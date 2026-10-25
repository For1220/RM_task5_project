extends CharacterBody3D

#队伍状态
@export_enum("Blue","Red")var team:int=Team.Id.BLUE
@export var is_controlled:bool=false

@export var speed : float=4.0
@export var jump_speed : float=2.5
@export var sensitivity: float=0.01
@export var bullet_scene:PackedScene
@export var max_hp:int = 200
@export var max_ammo:int=500
@export var max_heat:float =100.0
@export var cool_heat:float=20.0
@export var base_damage=20.0

#射击：过热和冷却变量
var current_ammo:int = max_ammo
var is_overheated:bool = false
var current_heat:float = 0.0
var heat_per_shot:float=10.0
var is_locked:bool = false

var ignore_fire_until_release:bool=false

#过热的颜色
var heat_normal:StyleBoxFlat
var heat_over:StyleBoxFlat

# HUD
var hud_panel:Control

#初始位置
var spawn_transform:Transform3D

var hp :int
var G :float=9.8
@onready var camera = $GimbalYaw/GimbalPitch/Camera3D
@onready var yaw = $GimbalYaw
@onready var pitch = $GimbalYaw/GimbalPitch

# 是否存活
signal died(unit:Node)
signal respawned(unit:Node)
var is_dead:bool=false
var respawn_end_time:float=0.0
func get_respawn_time()->float:
	return 10.0+(420.0-MatchState.time_left)/10.0

# buff状态
var defense_buff:float=0.0
var attack_multiplier:float=1.0
var cool_multiplier:float=1.0
var buff_time_left:float=0.0
var buff_time_total:float=0.0

# exp 机制
@export var level:int=1
var total_exp:float=0.0

func set_controlled(value:bool)->void:
	is_controlled=value
	if value:
		add_to_group("Player")
		camera.current=true
		ignore_fire_until_release=Input.is_action_pressed("fire")
	else :
		remove_from_group("Player")
		camera.current=false

#准备+摄像机就绪
func _ready()->void:
	add_to_group("infantry")
	add_to_group(Team.team_group(team))
	spawn_transform=global_transform
	hp = max_hp
	if is_controlled:
		add_to_group("Player")
		camera.current=true
		MatchState.last_controlled_team=team
	print("[系统]",name,"就绪，初始血量：",hp)
	print("Infantry ready")
	
	# 状态条画出来
	var current_scene=get_tree().current_scene
	if current_scene:
		hud_panel=current_scene.get_node_or_null("HUD/StatusPanel")
	if hud_panel:
		var ammo_bar = hud_panel.get_node_or_null("VBoxContainer/AmmoBar")
		if ammo_bar:
			#ammo_bar.custom_minimum_size = Vector2(300, 20)
			var ammo_style = StyleBoxFlat.new()
			ammo_style.bg_color = Color(0.2, 0.6, 1.0) # 蓝色
			ammo_bar.add_theme_stylebox_override("fill", ammo_style)
			
		var heat_bar = hud_panel.get_node_or_null("VBoxContainer/HeatBar")
		if heat_bar:
			#heat_bar.custom_minimum_size = Vector2(300, 20)
			heat_normal=StyleBoxFlat.new()
			heat_normal.bg_color=Color(1.0, 0.4, 0.0)
			heat_over=StyleBoxFlat.new()
			heat_over.bg_color=Color(1.0,0.0,0.0)
			heat_bar.add_theme_stylebox_override("fill", heat_normal)

# 扣血计算
func take_damage(amount:int,source_team:int=-1,source:Node=null)->int:
	if source_team==team:return 0
	if is_dead:return 0
	var before:=hp
	var actual_demage=int(amount*(1.0-defense_buff))
	hp=max(hp - actual_demage,0)
	print("[受击] ", name, " 受到 ", actual_demage, " 点伤害！")
	print("[状态] ", name, " 剩余血量: ", hp, " / ", max_hp)
	if hp<=0:
		print("[阵亡] ", name, " 已被击毁！")
		_die()
		if source and source.has_method("exp_gain"):
			var exp:=ExpSystem.kill_exp(
				int(source.get("level")),
				level
			)
			source.exp_gain(exp)
	MatchState.record_damage(source_team, actual_demage)
	return before-hp
func _die()->void:
	if is_dead: return
	is_dead=true
	hp=0
	respawn_end_time=MatchState.elapsed+get_respawn_time()
	velocity=Vector3.ZERO
	if fire_timer: fire_timer.stop()
	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[INFANTRY] %s步兵阵亡，%.1f 秒后复活" % [
			"红方" if team == Team.Id.RED else "蓝方",
			get_respawn_time()
		]
	)
	died.emit(self)
# 物理运动
func _physics_process(delta:float) -> void:
	if MatchState.phase_name()=="PAUSED" or MatchState.phase_name()=="ENDED":
		return
	if is_dead:
		if MatchState.elapsed>=respawn_end_time:
			_respawn()
		return
	if hp<=0:
		velocity.x=0.0
		velocity.z=0.
		if not is_on_floor() :
			velocity.y -=G*delta
		move_and_slide()
		return
	var input_2d=Vector2.ZERO
	if is_controlled: 
		input_2d=Input.get_vector("move_left","move_right","move_forward","move_back")
	var cam=$GimbalYaw/GimbalPitch/Camera3D
	var cam_basis=cam.global_transform.basis
	
	var forward=-cam_basis.z
	var right=cam_basis.x
	forward.y=0
	right.y=0
	forward=forward.normalized()
	right=right.normalized()
	
	var direction=(forward*-input_2d.y)+(right*input_2d.x)
	
	velocity.x=direction.x*speed
	velocity.z=direction.z*speed
	if not is_on_floor() :
		velocity.y -=G*delta
	elif is_controlled and Input.is_action_just_pressed("jump") and hp>0:
		velocity.y = jump_speed
	move_and_slide()
	
	# 冷却完成否
	if current_heat>0:
		current_heat=maxf(current_heat-cool_heat*cool_multiplier*delta,0.0)
		if current_heat<=0.0 and is_overheated:
			is_overheated= false
			print("冷却完毕")
	var fire_held:=Input.is_action_pressed("fire")
	if not fire_held:
		ignore_fire_until_release=false
	if is_controlled and Input.is_action_pressed("fire") and hp>0 and fire_held and not ignore_fire_until_release:
		shoot()
		exp_gain(1.0)
	if buff_time_left > 0.0:
			buff_time_left=maxf(buff_time_left-delta,0.0)
			if buff_time_left <=0.0: _clear_buffs()

func _clear_buffs()->void:
	defense_buff=0.0
	attack_multiplier=1.0
	cool_multiplier=1.0
	buff_time_total=0.0
	print("[增益已结束]")

@onready var muzzle = $GimbalYaw/GimbalPitch/Muzzle
@onready var fire_timer = $FireTimer	


func _process(delta:float)->void:
	var main_cam=$GimbalYaw/GimbalPitch/Camera3D
	var vis_cam= $GimbalYaw/GimbalPitch/VisionViewport/VisionCamera
	if main_cam and vis_cam:
		vis_cam.global_transform=main_cam.global_transform
		vis_cam.fov=main_cam.fov
		vis_cam.near=main_cam.near
		vis_cam.far=main_cam.far
	
	if not is_controlled:
		return
	if hud_panel:
		var ammo_bar=hud_panel.get_node_or_null("VBoxContainer/AmmoBar")
		if ammo_bar:
			ammo_bar.value=current_ammo
			var lbl = ammo_bar.get_node_or_null("Label")
			if lbl: 
				lbl.text="弹药"+str(current_ammo)+"/"+str(max_ammo)
		var heat_bar=hud_panel.get_node_or_null("VBoxContainer/HeatBar")
		if heat_bar:
			heat_bar.value=current_heat
			var lbl = heat_bar.get_node_or_null("Label")
			if lbl: 
				lbl.text="热量"+str(int(current_heat))+"/"+str(int(max_heat))
			if is_overheated:
				heat_bar.add_theme_stylebox_override("fill",heat_over)
			else :
				heat_bar.add_theme_stylebox_override("fill",heat_normal)

# 视角运动
func _unhandled_input(event:InputEvent) -> void:
	if not is_in_group("Player") or MatchState.phase_name()!="RUNNING":
		return
	#鼠标移动视角转动
	if event is InputEventMouseMotion:
		yaw.rotate_y(-event.relative.x*sensitivity)
		pitch.rotation.x=clampf( pitch.rotation.x+event.relative.y*sensitivity,deg_to_rad(-60),deg_to_rad(30) )
	#做能量机关开启的按键检测
	if is_controlled and Input.is_action_just_pressed("trigger_rune"):
		var power_rune=get_tree().current_scene.get_node_or_null("POWER_COL/ROOT")
		if power_rune and power_rune.has_method("request_activation"):
			power_rune.request_activation(team)
# 射击模块（弹道计算+子弹发射）
func shoot():
	#非法开火逻辑检测
	if not fire_timer.is_stopped(): return
	if bullet_scene == null: return
	if hp<=0 and is_dead: return
	if is_locked:
		print("发射机构已永久锁死")
		return
	if is_overheated:
		print("过热中")
		return
	if current_ammo<=0:
		print("弹药耗尽")
		return
	if MatchState.phase_name()!="RUNNING": return
	
	fire_timer.start()
	# 弹药和热量模块
	current_ammo -=1
	current_heat +=heat_per_shot
	if current_heat>max_heat+100.0:
		is_locked=true
		print("永久锁死")
	elif current_heat>max_heat:
		is_overheated = true
		print("过热，请冷却")
	print("[开火]剩余弹药：",current_ammo,"|当前热量：",current_heat)	
	
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.last_position=bullet.global_position
	bullet.shooter=self # 无视自己的碰撞
	bullet.shooter_team=team
	bullet.damage=int(base_damage*attack_multiplier)
	print("active bullets=", get_tree().get_nodes_in_group("bullet").size())
	
	# 1. 获取准星瞄准的初步目标点（物理射线）
	var cam = $GimbalYaw/GimbalPitch/Camera3D
	var ray_start = cam.global_position
	var ray_end = ray_start + -cam.global_basis.z * 100.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	# 排除自身和自身的全部碰撞体，避免准星射线打到自己的装甲板
	var exclude: Array[RID] = []
	if self is CollisionObject3D:
		exclude.append((self as CollisionObject3D).get_rid())
	for child in find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			exclude.append((child as CollisionObject3D).get_rid())
	query.exclude = exclude
	query.collide_with_areas = true
	
	var result = space_state.intersect_ray(query)
	var target_point = ray_end
	if result:
		target_point = result.position
	
	# ==========================================
	# 2. 精准弹道解算（恒定重力低伸解）
	# ==========================================
	var origin: Vector3 = bullet.global_position
	var delta: Vector3 = target_point - origin
	var horizontal_distance: float = Vector2(delta.x, delta.z).length()
	var bullet_speed: float = bullet.speed
	var bullet_gravity: float = bullet.g

	if horizontal_distance > 0.001 and bullet_gravity > 0.0:
		var speed_sq: float = bullet_speed * bullet_speed
		var discriminant: float = (
			speed_sq * speed_sq
			- bullet_gravity * (
				bullet_gravity * horizontal_distance * horizontal_distance
				+ 2.0 * delta.y * speed_sq
			)
		)

		if discriminant >= 0.0:
			# 低伸弹道对应的发射角
			var tan_theta: float = (
				speed_sq - sqrt(discriminant)
			) / (bullet_gravity * horizontal_distance)
			var aim_dir := Vector3(
				delta.x / horizontal_distance,
				tan_theta,
				delta.z / horizontal_distance
			).normalized()
			bullet.look_at(origin + aim_dir, Vector3.UP)
		else:
			# 当前初速无法到达该点，保持直射方向
			bullet.look_at(target_point, Vector3.UP)
	else:
		bullet.look_at(target_point, Vector3.UP)

	bullet.velocity = -bullet.global_basis.z * bullet.speed

# 状态增益：
func apply_buff(def:float,atk:float,cool:float,duration:float,source_team:int)->void:
	if source_team!=team:return
	defense_buff=max(defense_buff,def)
	attack_multiplier=max(attack_multiplier,atk)
	cool_multiplier=max(cool_multiplier,cool)
	buff_time_left=max(buff_time_left,duration)
	buff_time_total=max(buff_time_total,duration)
	print(name,"获得增益成功！")

# 存活与否
func is_alive()->bool: return hp>0
#我重生了，这一世......
func _respawn()->void:
	if not is_dead: return
	is_dead=false
	hp=max_hp
	global_transform=spawn_transform
	velocity=Vector3.ZERO
	current_ammo=max_ammo
	current_heat=0.0
	is_overheated=false
	is_locked=false
	
	#exp
	
	defense_buff=0.0
	attack_multiplier=1.0
	cool_multiplier=1.0
	buff_time_left=0.0
	buff_time_total=0.0
	respawn_end_time=0.0
	if fire_timer:fire_timer.stop()
	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[INFANTRY] %s步兵已复活" % (
			"红方" if team == Team.Id.RED else "蓝方"
		)
	)
	respawned.emit(self)

# exp 机制的实现
func exp_gain(amount:float,allow_small_bonus:bool=true)->void:
	if amount<=0.0: return
	if is_dead:return
	var extra:=0.0
	if allow_small_bonus:
		extra=ExpSystem.consume_small_bonus(team,amount)
	total_exp+=amount+extra
	_update_level()	
func _update_level()->void:
	var new_level:int=ExpSystem.level_for_exp(total_exp)
	if new_level>level:
		var old_level:=level
		level=new_level
		_on_level_up(old_level,level)
func _on_level_up(old_level:int,new_level:int)->void:
	var old_max_hp:=max_hp
	# 待加入

# 重置比赛的代码
func reset_robot()->void:
	is_dead=false
	respawn_end_time=0.0
	global_transform=spawn_transform
	velocity=Vector3.ZERO
	hp=max_hp
	current_ammo=max_ammo
	current_heat=0.0
	is_overheated=false
	is_locked=false
	yaw.rotation=Vector3.ZERO
	pitch.rotation=Vector3.ZERO
	if fire_timer:fire_timer.stop()
	defense_buff = 0.0
	attack_multiplier = 1.0
	cool_multiplier = 1.0
	buff_time_left = 0.0
	buff_time_total = 0.0
	
