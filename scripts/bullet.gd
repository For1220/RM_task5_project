extends Area3D

var shooter : Node=null
signal hit(target:Object,point:Vector3,normal:Vector3)
var shooter_team:int=-1

@export var speed:float =25.0
@export var g : float=9.8
@export var damage:int =20

# 释放子弹内存
@export var life_time:float=2.5
var life_left:float=2.5

var velocity: Vector3 = Vector3.ZERO
var last_position:Vector3

func get_source_team()->int: return shooter_team

# 准备+初始位置
func _ready() -> void:
	add_to_group("bullet")
	velocity = -global_basis.z*speed
	last_position=global_position
	life_left=life_time
	
# 物理运动
func _physics_process(delta:float) ->void:
	if MatchState.phase_name()!="RUNNING":return
	life_left-=delta
	if life_left<=0.0:
		queue_free()
		return
	velocity.y-=g * delta
	var tar_pos=global_position + velocity*delta
	var space_state=get_world_3d().direct_space_state
	var query=PhysicsRayQueryParameters3D.create(last_position,tar_pos)
	query.collision_mask=collision_mask
	query.exclude=[self,shooter]
	query.collide_with_areas=true
	
	var result=space_state.intersect_ray(query)
	if result:
		_handle_hit(result.collider,result.position,result.normal)
		return
	global_position=tar_pos
	last_position=global_position
# 命中判定
func _handle_hit(collider:Object,hit_point:Vector3,normal:Vector3):
	var n : Node = collider as Node
	while n != null :
		if n== shooter: 
			queue_free() 
			return
		n=n.get_parent()
	
	# 通信
	var collider_name:=String(collider.name)
	#队伍判定
	var target=collider
	
	if "TARGET" in collider.name and "COL" in collider.name:
		var power_rune = get_tree().current_scene.get_node_or_null("POWER_COL/ROOT")

		# 根据碰到的靶面决定查看哪个队伍的能量机关状态
		var rune_team: int = Team.Id.RED if String(collider.name).begins_with("FACE_1") else Team.Id.BLUE

		if power_rune and power_rune.has_method("on_target_hit"):
			if _is_rune_activating(power_rune, rune_team):
				var accepted: bool = power_rune.on_target_hit(collider.name, hit_point)
				if accepted:
					_notify("[RUNE] 标靶命中")

		hit.emit(collider, hit_point, normal)
		queue_free()
		return
	
	while target and not target.has_method("take_damage") :
		target=target.get_parent()
	if target == null:
		queue_free()
		return
	var target_team := int(target.get("team"))
	
	if not Team.is_enemy(shooter_team, target_team):
		queue_free()
		return
	if target and target.has_method("take_damage"):
		if _is_enemy_unit(target):
			if _is_enemy_alive(target):
				var actual_damage:int=target.take_damage(damage,shooter_team,shooter)
				exp_from_bullet(actual_damage,shooter,target)
				_notify("[ENEMY] 命中，伤害 %d 点，%s"%[actual_damage,_remaining_hp(target)])
		elif _is_outpost(target):
			if _is_outpost_alive(target):
				var actual_damage:int=target.take_damage(damage,shooter_team,shooter)
				exp_from_bullet(actual_damage,shooter,target)
				_notify("[OUTPOST] 命中，伤害 %d 点，%s"%[actual_damage,_remaining_hp(target)])
		elif _is_base(target):
			if _is_base_alive(target):
				var invincible:=false
				if target.get("is_invincible")!=null:
					invincible=bool(target.get("is_invincible"))
				if invincible:
					_notify("[BASE] 基地无敌，无法造成伤害")
					hit.emit(collider, hit_point, normal)
					queue_free()
					return
				var actual_damage:=int(target.take_damage(damage,shooter_team,shooter))
				exp_from_bullet(actual_damage,shooter,target)
				_notify("[BASE]命中，伤害%d点，%s"%[actual_damage,_remaining_hp(target)])
	hit.emit(collider,hit_point,normal)
	queue_free()	
	
#经验机制
func exp_from_bullet(ac_damage:int,now_shooter:Node,tar:Node)->void:
	if ac_damage >0 and now_shooter and now_shooter.has_method("exp_gain"):
		if tar.is_in_group("infantry"):
			now_shooter.exp_gain(ac_damage*4.0)
		elif tar.is_in_group("outpost"):
			now_shooter.exp_gain(ac_damage*2.0)
		elif tar.is_in_group("base"):
			now_shooter.exp_gain(ac_damage/2.0)
		

func _notify(text:String)->void:
	get_tree().call_group("notification_feed","push_notification",text)
func _is_outpost(target:Node)->bool:
	return target!=null and target.is_in_group("outpost")
func _is_base(target:Node)->bool:
	return target!=null and target.is_in_group("base")
func _is_structure(target:Node)->bool:
	return target!=null and target.is_in_group("structure")
func _is_enemy_unit(target:Node)->bool:
	if target == null:return false
	if not target.is_in_group("infantry"): return false
	var target_team:=int(target.get("team"))
	return Team.is_enemy(shooter_team,target_team)
func _remaining_hp(target:Node)->String:
	if target==null: return "剩余 HP --"
	if _is_outpost(target):
		var current:=int(target.get("current_hp"))
		var maximum:=int(target.get("max_hp"))
		return "剩余 HP %d/%d"%[current,maximum]
	if _is_base(target):
		var current:=int(target.get("current_hp"))
		var maximum:=int(target.get("max_hp"))
		return "剩余 HP %d/%d"%[current,maximum]
	if _is_enemy_unit(target):
		var current:=int(target.get("hp"))
		var maximum:=int(target.get("max_hp"))
		return "剩余 HP %d/%d"%[current,maximum]
	
	return "剩余 HP --"
func _is_rune_activating(rune:Node,team_id:int)->bool:
	if rune==null:return false
	var state=rune.get("current_state")
	if state==null: return false
	if state is Dictionary:
		if not state.has(team_id):return false
	return int(state[team_id])==1
func _is_enemy_alive(target:Node)->bool:
	var target_hp=target.get("hp")
	if target_hp==null: return false
	return int(target_hp)>0
func _is_outpost_alive(target:Node)->bool:
	if target==null: return false
	return not bool(target.get("is_destroyed"))
func _is_base_alive(target:Node)->bool:
	if target==null: return false
	return not bool(target.get("is_destroyed"))
	
