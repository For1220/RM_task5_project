extends Structure

@export var target_rot_speed:float = 0.8 * PI
@export var acceleration_time:float=5.0
@export var stop_rot_time:float=180.0
@export var recover_rot_time:float=10.0
@export var recover_hp: float=750.0

var current_rot_speed:float=0.0
var is_rot:bool = false
var is_recover:bool = false
var ever_destroyed:bool=false

#灯光部件
var guide_on_nodes:Array=[]
var guide_off_nodes:Array=[]

@onready var rot_part=find_child("*ROTATE*",true,false)

func _ready()->void:
	structure_kind=&"outpost"
	destroyed.connect(_on_destroyed)
	super._ready()
	# 子节点原来的初始化
	add_to_group("outpost")
	_connect_armor_signals(self)
	_cache_guide_lights()
	reset_outpost()
	print("前哨站初始化完成，血量：",current_hp)
	
func _connect_armor_signals(node:Node):
	for child in node.get_children() :
		if child is Area3D and "ARMOR" in child.name:
			child.area_entered.connect(_on_armor_hit)
		_connect_armor_signals(child)
func _cache_guide_lights()->void:
	guide_on_nodes=find_children("GUIDE_LIGHT_ON_*","MeshInstance3D",true,false)
	guide_off_nodes=find_children("GUIDE_LIGHT_OFF_*","MeshInstance3D",true,false)
	if(guide_on_nodes.is_empty()) : print("[前哨站]未找到")
func _set_guide_light(on:bool)->void:
	for n in guide_on_nodes: n.visible=on
	for n in guide_off_nodes: n.visible=not on
	print("[前哨站] 引导灯 ", "ON" if on else "OFF")
	
func _physics_process(delta:float)->void:
	if is_destroyed: return
	if MatchState.phase!=MatchState.Phase.RUNNING:return
	if is_rot:
		if current_rot_speed<target_rot_speed:
			current_rot_speed = move_toward(current_rot_speed,target_rot_speed,
			target_rot_speed/acceleration_time*delta)
	if rot_part:
		rot_part.rotate_y(current_rot_speed*delta)
	if MatchState.elapsed>=stop_rot_time :
		_stop_rot()
	if buff_time_left > 0.0:
		buff_time_left-=delta
		if buff_time_left<=0.0: _buff_clear()

func _stop_rot():
	if not is_rot:
		return
	is_rot=false
	print("停止旋转，时间：",MatchState.elapsed)
	if rot_part:
		var tween=create_tween()
		var current_y=rot_part.rotation.y
		var target_y=0.0
		tween.tween_property(rot_part,"rotation:y",target_y,recover_rot_time)

func take_damage(amount:int,source_team:int=-1,source:Node=null)->int:
	if is_destroyed:return 0
	if source_team==team:return 0
	return super.take_damage(amount,source_team,source)

func _on_armor_hit(area:Area3D):
	if area.has_method("get_damage") or "damage" in area:
		var source_team:=int(area.get_source_team())
		var dmg = area.damage if "damage" in area else 20
		take_damage(dmg,source_team,area)
		area.queue_free()

# 摧毁与重建代码模块
func _on_destroyed(_team_id:int=-1) ->void:
	super.destroy_structure()
	ever_destroyed=true
	is_rot=false
	current_rot_speed=0.0
	_set_guide_light(false)
	print("前哨站被摧毁，基地无敌解除")
	get_tree().call_group("notification_feed", "push_notification",
	"[OUTPOST] 前哨站已被摧毁")
	var base:=get_tree().get_first_node_in_group(Team.object_group(team,"base"))
	if base and base.has_method("set_invincible"):
		base.call("set_invincible",false)
	if base and base.has_method("set_base_guide_light"):
		base.call("set_base_guide_light", true)
func try_rebuild(team_id: int) -> bool:
	if not is_destroyed:
		return false
	if team_id != team:
		return false
	if MatchState.phase_name() != "RUNNING":
		return false

	# 比赛开始 5 分钟后不能重建
	if MatchState.elapsed >= 300.0:
		return false

	var base := get_tree().get_first_node_in_group(
		Team.object_group(team, "base")
	)
	if base == null:
		return false
	if bool(base.get("is_destroyed")):
		return false
	if not base.has_method("consume_rebuild_chance"):
		return false
	if not bool(base.call("consume_rebuild_chance")):
		return false

	is_destroyed = false
	current_hp = int(recover_hp)   # 750
	current_rot_speed = 0.0
	is_rot = false

	_set_guide_light(true)

	if base.has_method("set_invincible"):
		base.call("set_invincible", true)
	if base.has_method("set_base_guide_light"):
		base.call("set_base_guide_light", false)
	hp_changed.emit(current_hp, max_hp)

	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[OUTPOST] 前哨站重建完成，恢复 750 点血量"
	)
	return true
# 增益状态
func _buff_clear()->void:
	defense_buff=0.0
func _apply_buff(def:float,dura:float,source_team:int)->void:
	super.apply_buff(def,dura,source_team)
	print("[增益]前哨站获得增益")
	
# 重置代码
func reset_outpost()->void:
	ever_destroyed=false
	is_destroyed=false
	current_hp=max_hp
	is_rot=true	
	current_rot_speed=0.0
	_set_guide_light(true)
	if rot_part: rot_part.rotation.y=0.0
	var base:=get_tree().get_first_node_in_group(Team.object_group(team,"base"))
	if base and base.has_method("set_invincible"):
		base.call("set_invincible", true)
	if base and base.has_method("set_base_guide_light"):
		base.call("set_base_guide_light", false)
# 接基地判定
func stop_rotation() -> void:
	_stop_rot()
