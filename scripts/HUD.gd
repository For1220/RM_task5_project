extends CanvasLayer

@onready var timer_label:Label=$Left_up/TimerLabel
@onready var minimap_panel:Panel=$Left_up/MiniMapPanel
@onready var player_icon:ColorRect=$Left_up/MiniMapPanel/PlayerIcon
@onready var start_panel:Control=$StartPanel
@onready var title_label: Label = $StartPanel/CenterContainer/VBoxContainer/Title
@onready var hint_label: Label = $StartPanel/CenterContainer/VBoxContainer/Hint
@onready var con_label:Label=$StartPanel/CenterContainer/VBoxContainer/Condition
@onready var start_button:Button=$StartPanel/CenterContainer/VBoxContainer/StartButton
@onready var resume_button:Button=$StartPanel/CenterContainer/VBoxContainer/ResumeButton
@onready var reset_button:Button=$StartPanel/CenterContainer/VBoxContainer/ResetButton

@onready var death_overlay:Control=$DeathOverlay
@onready var respawn_label:Label=$DeathOverlay/Center/VBox/RespawnLabel

#显示 发送 状态
@onready var net_label:Label=get_node_or_null("NetStatus")
var _net_state: int = 0
var _net_fps: float = 0.0
var _net_dropped: int = 0
var _net_errors: int = 0
var _net_bound: bool = false

# 第二版HUD
@onready var stats_panel:VBoxContainer=$StatsPanel

# 前哨站重建提示
@onready var rebuild_panel:PanelContainer=$RebuildPanel
@onready var blue_rebuild_status:Label=$RebuildPanel/Margin/VBox/BlueRow/BlueHeader/BlueStatus
@onready var blue_rebuild_chance:Label=$RebuildPanel/Margin/VBox/BlueRow/BlueHeader/BlueChance
@onready var blue_rebuild_bar:ProgressBar=$RebuildPanel/Margin/VBox/BlueRow/BlueBar
@onready var red_rebuild_status:Label=$RebuildPanel/Margin/VBox/RedRow/RedHeader/RedStatus
@onready var red_rebuild_chance:Label=$RebuildPanel/Margin/VBox/RedRow/RedHeader/RedChance
@onready var red_rebuild_bar:ProgressBar=$RebuildPanel/Margin/VBox/RedRow/RedBar

var _rebuild_bound := false
var _blue_buff_area:Node = null
var _red_buff_area:Node = null
var _blue_outpost:Node = null
var _red_outpost:Node = null
var _blue_base:Node = null
var _red_base:Node = null

var map_min=Vector2(-14.0,-7.5)
var map_max=Vector2( 14.0, 7.5)

func _ready()->void:
	start_button.pressed.connect(_on_start_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	MatchState.phase_changed.connect(_on_phase_changed)
	start_button.grab_focus()
	_refresh_menu_ui()
	call_deferred("_bind_net_source")
	call_deferred("_bind_rebuild_sources")
func _on_start_pressed()->void:
	if MatchState.phase_name()=="ENDED": _reset_game()
	MatchState.begin_match()
	_refresh_menu_ui()
	var selector := get_tree().get_first_node_in_group("selection_controller")
	if selector and selector.has_method("open_menu"):
		selector.call("open_menu")
func _on_resume_pressed()->void:
	MatchState.resume_match()
	_refresh_menu_ui()
func _on_reset_pressed()->void:
	_reset_game()
	MatchState.reset_match()
	_refresh_menu_ui()
func _on_phase_changed(_phase:String)->void:
	_refresh_menu_ui()
	_update_rebuild_ui()
func _refresh_menu_ui()->void:
	var phase:=MatchState.phase_name()
	var is_ready:=phase=="READY"
	var is_paused:=phase=="PAUSED"
	var is_ended:=phase=="ENDED"
	start_panel.visible=is_ready or is_paused
	con_label.text="Are u ready?" if is_ready else "比赛暂停"
	start_button.visible=is_ready
	resume_button.visible=is_paused
	reset_button.visible=is_paused
	if is_ready:
		hint_label.text="点击开始比赛/Enter"
		start_button.text="开始比赛"
		start_button.grab_focus()
	elif is_paused:
		hint_label.text="点击以继续"
		resume_button.grab_focus()
	elif is_ended:
		con_label.text="比赛结束"
		start_button.text="再来一局/one more"
		hint_label.text="点击重新开始"
		var panel := get_node_or_null("GameOverPanel")
		if panel != null and panel.has_method("focus_restart"):
			panel.call("focus_restart")
	if start_panel.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
# 大头：重置游戏状态：
func _reset_game()->void:
	ExpSystem.reset_for_match()
	for player in get_tree().get_nodes_in_group("infantry"):
		if player and player.has_method("reset_robot"):
			player.call("reset_robot")
	for outpost in get_tree().get_nodes_in_group("outpost"):
		if outpost and outpost.has_method("reset_outpost"):
			outpost.call("reset_outpost")
	for rune in get_tree().get_nodes_in_group("power_rune"):
		if rune and rune.has_method("reset_rune"):
			rune.call("reset_rune")
	for base in get_tree().get_nodes_in_group("base"):
		if base and base.has_method("reset_base"):
			base.call("reset_base")
	for b in get_tree().get_nodes_in_group("bullet"):
		if is_instance_valid(b): b.queue_free()


# 暂停处理
func _unhandled_input(event:InputEvent)->void:
	if event.is_action_pressed("reset"):
		match MatchState.phase_name():
			"RUNNING": MatchState.pause_match()
			"PAUSED": MatchState.resume_match()
		get_viewport().set_input_as_handled()
		_refresh_menu_ui()

func _process(delta:float) ->void:
	var snap:=SnapshotHub.current
	if snap.is_empty():snap=MatchState.snapshot()
	apply_state(snap)
	_update_death_overlay(snap)
	_update_rebuild_ui()
func apply_state(snapshot:Dictionary)->void:
	var left=maxf(float(snapshot.get("time_left",0.0)),0.0)
	var seconds=ceili(left)
	timer_label.text="%02d:%02d"%[floori(seconds/60.0),seconds%60]
	if stats_panel and stats_panel.has_method("apply_snapshot") and snapshot.has("hp"):
		stats_panel.apply_snapshot(snapshot)
	
func _update_minimap():
	var target_infantry=get_tree().get_first_node_in_group("Player")
	if not target_infantry or not player_icon:
		return
	var map_pos=world_to_map(target_infantry.global_position)
	player_icon.position=map_pos-Vector2(player_icon.size.x/2,player_icon.size.y/2)

func world_to_map(p:Vector3)->Vector2:
	var uv=(Vector2(p.x,p.z)-map_min)/(map_max-map_min)
	uv.x=clampf(uv.x,0.0,1.0)
	uv.y=clampf(uv.y,0.0,1.0)
	return uv*minimap_panel.size
	
# 更新阵亡灰幕
func _update_death_overlay(snapshot:Dictionary)->void:
	var dead:=bool(snapshot.get("is_dead",false))
	var show_overlay:=dead and not start_panel.visible
	death_overlay.visible=show_overlay
	if not show_overlay:return
	var left:=maxf(
		float(snapshot.get("respawn_end_time",0.0))
		-float(snapshot.get("elapsed",0.0)),0.0)
	respawn_label.text="复活倒计时：%d s"%ceili(left)	

func _bind_rebuild_sources() -> void:
	if _rebuild_bound:
		return

	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	if root == null:
		return

	_blue_buff_area = root.get_node_or_null(
		"Teams/TeamBlue/OutpostBlue/OutpostBuffPointBlue"
	)
	_red_buff_area = root.get_node_or_null(
		"Teams/TeamRed/OutpostRed/OutpostBuffPointRed"
	)
	_blue_outpost = root.get_node_or_null("Teams/TeamBlue/OutpostBlue")
	_red_outpost = root.get_node_or_null("Teams/TeamRed/OutpostRed")
	_blue_base = root.get_node_or_null("Teams/TeamBlue/BaseBlue")
	_red_base = root.get_node_or_null("Teams/TeamRed/BaseRed")

	_rebuild_bound = true
	_update_rebuild_ui()

func _update_rebuild_ui() -> void:
	if not _rebuild_bound:
		_bind_rebuild_sources()
		if not _rebuild_bound:
			return

	if rebuild_panel == null:
		return

	var phase := MatchState.phase_name()
	var visible_now := phase == "RUNNING" or phase == "PAUSED"
	# READY/ENDED 不显示；GameOverPanel 自己会显示比赛结果。
	rebuild_panel.visible = visible_now
	if not visible_now:
		return

	_update_rebuild_row(
		_blue_buff_area, _blue_outpost, _blue_base,
		blue_rebuild_status, blue_rebuild_chance, blue_rebuild_bar
	)
	_update_rebuild_row(
		_red_buff_area, _red_outpost, _red_base,
		red_rebuild_status, red_rebuild_chance, red_rebuild_bar
	)

func _update_rebuild_row(
	area: Node,
	outpost: Node,
	base: Node,
	status_label: Label,
	chance_label: Label,
	bar: ProgressBar
) -> void:
	var chances := _get_rebuild_chances(base)
	var progress := 0.0
	var required := 10.0

	if area != null:
		if area.has_method("get_progress"):
			progress = float(area.call("get_progress"))
		var normal_value = area.get("normal_required")
		if normal_value != null:
			required = maxf(float(normal_value), 0.1)

	bar.max_value = required
	bar.value = clampf(progress, 0.0, required)
	chance_label.text = "机会 ×%d" % chances

	if outpost == null:
		status_label.text = "前哨站未绑定"
		return

	var destroyed := bool(outpost.get("is_destroyed"))
	if not destroyed:
		status_label.text = "前哨站在线"
		return

	if MatchState.elapsed >= 300.0:
		status_label.text = "重建已截止"
		return

	if chances <= 0:
		status_label.text = "无重建机会"
		return

	if area == null:
		status_label.text = "增益点未绑定"
		return

	if progress > 0.01:
		status_label.text = "重建中 %.1f/%.1fs" % [progress, required]
	else:
		status_label.text = "可重建"

func _get_rebuild_chances(base: Node) -> int:
	if base == null:
		return 0
	var value = base.get("rebuild_chances")
	if value == null:
		return 0
	return int(value)

# net 发送
func _bind_net_source() -> void:
	if _net_bound:
		return
	var sender := get_tree().get_first_node_in_group("frame_sender")
	if sender == null:
		await get_tree().process_frame
		sender = get_tree().get_first_node_in_group("frame_sender")
	if sender == null:
		return
	_net_bound = true
	sender.link_changed.connect(_on_net_link_changed)
	sender.net_stats.connect(_on_net_stats)
	if sender.has_method("get_image_link_state"):
		_net_state = int(sender.call("get_image_link_state"))
	_refresh_net_label()
func _on_net_link_changed(channel: String, state: int) -> void:
	if channel != "image":
		return
	_net_state = state
	_refresh_net_label()
func _on_net_stats(fps: float, dropped: int, errors: int) -> void:
	_net_fps = fps
	_net_dropped = dropped
	_net_errors = errors
	_refresh_net_label()
func _refresh_net_label() -> void:
	if net_label == null:
		return
	var names := ["DOWN", "CONNECTING", "UP"]
	var idx := clampi(_net_state, 0, 2)
	var color := Color("#FF5E7A")
	if idx == 1:
		color = Color("#FFB454")
	elif idx == 2:
		color = Color("#62E6A6")
	net_label.text = "NET ● %s | TX %.1f fps | drop %d | err %d" % [
		names[idx], _net_fps, _net_dropped, _net_errors
	]
	net_label.add_theme_color_override("font_color", color)	
