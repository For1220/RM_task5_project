extends Node

signal link_changed(channel:String,state:int)
signal net_stats(tx_fps:float,dropped:int,errors:int)

const SERVER_IP: String="127.0.0.1"
const PORT_IMAGE: int=9000
const PORT_STATE: int=9001
const SEND_HZ: float=30.0
const MAGIC: String="RMV1"

var image_server=StreamPeerTCP.new()
var state_server=StreamPeerTCP.new()

var frame_timer=0.0
var sequence=0
var _state_seq:int=0
#非阻塞
var send_buffer:PackedByteArray = PackedByteArray()
var send_offset:int=0
var is_sending:bool=false
var _state_buffer:PackedByteArray = PackedByteArray()
var _state_offset:int = 0
var _state_busy:bool = false
var _state_pending:PackedByteArray = PackedByteArray()

@onready var viewport: SubViewport = $Teams/TeamBlue/InfantryBlue/GimbalYaw/GimbalPitch/VisionViewport

func _ready() :
	add_to_group("frame_sender")
	var err=image_server.connect_to_host(SERVER_IP,PORT_IMAGE)
	if err!=OK:
		_errors+=1
		print("[网络] 无法连接到图像通道 127.0.0.1:", PORT_IMAGE)
	err=state_server.connect_to_host(SERVER_IP,PORT_STATE)
	if err!=OK:
		_errors+=1
		print("[网络] 无法连接到状态通道 127.0.0.1:", PORT_STATE)
	get_tree().call_group("notification_feed", "push_notification",
	"[NET]视觉链路连接中")

# update:加入重联机制：
var _image_retry:=0.0
var _state_retry:=0.0

# 发送包
# HUD 连接状态统计
var _last_image_status: int = -1
var _stats_timer: float = 0.0
var _frames_sent: int = 0
var _dropped: int = 0
var _errors: int = 0

func _process(delta:float):
	image_server.poll()
	state_server.poll()
	#连接状态发送
	var st:=image_server.get_status()
	if st!=_last_image_status:
		_last_image_status=st
		link_changed.emit("image",_link_state_from_status(st))
		if st==StreamPeerTCP.STATUS_CONNECTED:
			get_tree().call_group("notification_feed","push_notification","[NET]图像通道已连接")
		elif st==StreamPeerTCP.STATUS_ERROR: _errors+=1			
	
	# 把当前连接状态和每秒统计发给 HUD

	_stats_timer+=delta
	if _stats_timer>=1.0:
		net_stats.emit(float(_frames_sent)/_stats_timer, _dropped, _errors)
		_stats_timer=0.0
	
	# 重联
	_image_retry -= delta
	if image_server.get_status() != StreamPeerTCP.STATUS_CONNECTED \
	and image_server.get_status() != StreamPeerTCP.STATUS_CONNECTING \
	and _image_retry <= 0.0:
		_image_retry = 1.0
		image_server = StreamPeerTCP.new()
		image_server.connect_to_host(SERVER_IP, PORT_IMAGE)

	_state_retry -= delta
	if state_server.get_status() != StreamPeerTCP.STATUS_CONNECTED \
	and state_server.get_status() != StreamPeerTCP.STATUS_CONNECTING \
	and _state_retry <= 0.0:
		_state_retry = 1.0
		state_server = StreamPeerTCP.new()
		state_server.connect_to_host(SERVER_IP, PORT_STATE)
	_send_state_snapshot()
	_flush_state()
	
	if is_sending:
		_flush_send_buffer()
		return
	frame_timer+=delta
	if frame_timer>=1.0/SEND_HZ:
		frame_timer=0.0
		_send_image_frame()

var _capturing := false # 一个采集锁，
func _send_image_frame():
	if _capturing:
		_dropped+=1
		return
	if image_server.get_status()!=StreamPeerTCP.STATUS_CONNECTED:
		return
	var now_viewp:=_get_viewport()
	if now_viewp==null:return
	var cam=now_viewp.get_node_or_null("VisionCamera")
	if cam==null:return
	
	_capturing=true
	await RenderingServer.frame_post_draw
	var image=now_viewp.get_texture().get_image()
	if image == null or image.is_empty():
		_capturing=false
		_dropped+=1
		return
	var jpeg_data=image.save_jpg_to_buffer(0.8)
	_capturing=false
	if jpeg_data.is_empty():
		_errors+=1
		return
		
	var timestamp = int(Time.get_unix_time_from_system()*1_000_000.0)
	# 1. 打包头部
	var header_buffer = StreamPeerBuffer.new()
	header_buffer.big_endian = true
	header_buffer.put_data(MAGIC.to_ascii_buffer()) # 4 字节: "RMV1"
	header_buffer.put_u32(sequence)                 # 4 字节: 序列号
	header_buffer.put_u64(timestamp)                # 8 字节: 时间戳
	header_buffer.put_u32(jpeg_data.size())         # 4 字节: JPEG 长度
	
	# 2. 把完整的一帧（头+JPEG）存入发送缓冲区，准备断点续传
	send_buffer = header_buffer.data_array + jpeg_data
	send_offset = 0
	is_sending = true
	sequence += 1
	
	# 3. 立刻尝试发送第一波（不是一次性发完！）
	_flush_send_buffer()
func _flush_send_buffer():
	if not is_sending:return
	if image_server.get_status()!=StreamPeerTCP.STATUS_CONNECTED:
		is_sending=false
		return
	var bytes_to_send=send_buffer.slice(send_offset)
	var result=image_server.put_partial_data(bytes_to_send)
	var err=result[0]
	var bytes_sent=result[1]
	
	if err!=OK:
		_errors+=1
		print("发送失败：",err)
		is_sending=false
		return
	send_offset+=bytes_sent
	
	if send_offset>=send_buffer.size():
		is_sending=false
		_frames_sent+=1

func _send_state_snapshot() -> void:
	var infantry := _get_infantry()
	if infantry == null: return

	var state :=_build_snapshot(infantry)
	SnapshotHub.publish(state)
	if state_server.get_status()!=StreamPeerTCP.STATUS_CONNECTED:
		return

	_state_seq += 1

	var json_str := JSON.stringify(state) + "\n"
	_queue_state(json_str.to_utf8_buffer())
# 状态通道非阻塞发送：当前消息发完后，只保留最新一条等待消息
func _queue_state(line: PackedByteArray) -> void:
	if _state_busy:
		_state_pending = line
		return
	_start_state_tx(line)

func _start_state_tx(line: PackedByteArray) -> void:
	_state_buffer = line
	_state_offset = 0
	_state_busy = true
	_flush_state()

func _flush_state() -> void:
	if not _state_busy:
		return
	if state_server.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_state_busy = false
		_state_pending.clear()
		return

	var result := state_server.put_partial_data(_state_buffer.slice(_state_offset))
	if result[0] != OK:
		_errors += 1
		_state_busy = false
		_state_pending.clear()
		return

	_state_offset += int(result[1])
	if _state_offset < _state_buffer.size():
		return

	_state_busy = false
	if not _state_pending.is_empty():
		var next := _state_pending
		_state_pending.clear()
		_start_state_tx(next)
# 加入切换选择
func _get_infantry()->Node3D:
	var n:=get_tree().get_first_node_in_group("Player")
	if n == null:
		n = get_tree().get_first_node_in_group("team_blue")
	if n == null:
		n = get_tree().get_first_node_in_group("infantry")
	if n == null or not is_instance_valid(n):
		return null
	return n as Node3D
func _get_viewport()->SubViewport:
	var inf:=_get_infantry()
	if inf == null:return null
	return inf.get_node_or_null("GimbalYaw/GimbalPitch/VisionViewport")as SubViewport
func _now_usec()->int:
	return int(Time.get_unix_time_from_system()*1_000_000.0)
func _link_state_from_status(status:int)->int:
	if status==StreamPeerTCP.STATUS_CONNECTED: return 2
	if status==StreamPeerTCP.STATUS_CONNECTING: return 1
	return 0
func get_image_link_state()->int:
	return _link_state_from_status(image_server.get_status())	



func _collect_entities(inf: Node3D) -> Array:
	var out: Array = []

	# 己方/当前控制的步兵
	var team_name := "blue" if int(inf.get("team")) == int(Team.Id.BLUE) else "red"
	out.append({
		"id": str(inf.name),
		"team": team_name,
		"kind": "infantry",
		"x": inf.global_position.x,
		"z": inf.global_position.z,
		"yaw": inf.global_rotation.y,
		"hp": int(inf.get("hp")),
		"max_hp": int(inf.get("max_hp")),
		"alive": not bool(inf.get("is_dead")),
	})
	# 敌方步兵：用于小地图红点
	for unit in get_tree().get_nodes_in_group("infantry"):
		var enemy := unit as Node3D
		if enemy == null or enemy == inf:
			continue
		if int(enemy.get("team")) == int(inf.get("team")):
			continue
		if bool(enemy.get("is_dead")):
			continue

		out.append({
			"id": str(enemy.name),
			"team": "blue" if int(enemy.get("team")) == int(Team.Id.BLUE) else "red",
			"kind": "infantry",
			"x": enemy.global_position.x,
			"z": enemy.global_position.z,
			"yaw": enemy.global_rotation.y,
			"hp": int(enemy.get("hp")),
			"max_hp": int(enemy.get("max_hp")),
			"alive": true,
			"visible": true
		})
	# 双方基地/前哨站
	var structure_paths := {
		"blue_outpost": ^"Teams/TeamBlue/OutpostBlue",
		"red_outpost": ^"Teams/TeamRed/OutpostRed",
		"blue_base":^"Teams/TeamBlue/BaseBlue",
		"red_base":^"Teams/TeamRed/BaseRed"
	}
	for id in structure_paths:
		var n := get_node_or_null(structure_paths[id]) as Node3D
		if n == null or not (n is Node3D):
			continue

		var node3d := n as Node3D
		var parts := String(id).split("_")
		var map_pos:=node3d.global_position
		if n.has_method("get_map_position"):
			map_pos=n.call("get_map_position")
		out.append({
			"id": id,
			"team": parts[0],
			"kind": parts[1],
			"x": map_pos.x,
			"z": map_pos.z,
			"yaw": node3d.global_rotation.y,
			"hp": int(n.get("current_hp")),
			"max_hp": int(n.get("max_hp")),
			"alive": not bool(n.get("is_destroyed")),
			"is_rot": bool(n.get("is_rot")) if n.get("is_rot") != null else false,
			"is_shielded": bool(n.get("is_shielded")) if n.get("is_shielded") != null else false,
			"armor_open": bool(n.get("armor_open")) if n.get("armor_open") != null else false,
			"shield_hp": int(n.get("shield_hp")) if n.get("shield_hp") != null else 0,
			"is_invincible": bool(n.get("is_invincible")) if n.get("is_invincible") != null else false
		})

	return out		
func _build_snapshot(infantry: Node3D) -> Dictionary:
	var snap := MatchState.snapshot()
	var yaw_node := infantry.get_node_or_null("GimbalYaw") as Node3D
	var pitch_node := infantry.get_node_or_null("GimbalYaw/GimbalPitch") as Node3D
	var vp := _get_viewport()
	var cam := infantry.get_node_or_null("GimbalYaw/GimbalPitch/Camera3D") as Camera3D
	var cam_forward := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	var camera_yaw := atan2(cam_forward.x, -cam_forward.z)	
	var team_id := int(infantry.get("team"))

	return {
		"schema_version": 1,
		"seq": _state_seq,
		"ts_us": _now_usec(),
		"phase": snap["phase"],
		"time_left": snap["time_left"],
		"elapsed": snap["elapsed"],
		"team": "blue" if team_id == int(Team.Id.BLUE) else "red",

		"hp": int(infantry.get("hp")),
		"max_hp": int(infantry.get("max_hp")),
		"ammo": int(infantry.get("current_ammo")),
		"max_ammo": int(infantry.get("max_ammo")),
		"heat": float(infantry.get("current_heat")),
		"heat_limit": float(infantry.get("max_heat")),
		"is_dead": bool(infantry.get("is_dead")),
		"is_overheated": bool(infantry.get("is_overheated")),
		"is_locked": bool(infantry.get("is_locked")),
		"respawn_end_time": float(infantry.get("respawn_end_time")),

		"level": int(infantry.get("level")),
		"total_exp": float(infantry.get("total_exp")),

		"buffs": {
			"attack": float(infantry.get("attack_multiplier")),
			"defense": float(infantry.get("defense_buff")),
			"cool": float(infantry.get("cool_multiplier")),
			"time_left": float(infantry.get("buff_time_left")),
			"time_total": float(infantry.get("buff_time_total"))
		},

		"pose": {
			"x": infantry.global_position.x,
			"y": infantry.global_position.y,
			"z": infantry.global_position.z,
			"yaw": infantry.global_rotation.y,
			"gimbal_yaw": yaw_node.global_rotation.y if yaw_node else 0.0,
			"gimbal_pitch": pitch_node.rotation.x if pitch_node else 0.0,
			"camera_yaw": camera_yaw
		},

		"camera": {
			"width": vp.size.x if vp else 0,
			"height": vp.size.y if vp else 0,
			"fov_deg": cam.fov if cam else 0.0,
			"near": cam.near if cam else 0.0,
			"far": cam.far if cam else 0.0
		},

		"entities": _collect_entities(infantry)
	}
