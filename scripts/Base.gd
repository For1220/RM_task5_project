extends Structure

signal armor_opened(reason:String)

@export var base_max_hp: int = 5000
@export var shield_max: int = 150
@export var open_animation: StringName = &"open"

@export var own_outpost_path: NodePath
@export var enemy_outpost_path: NodePath

var shield_hp: int = 0
var is_shielded: bool = true
var armor_open: bool = false

var _base_guide_on: MeshInstance3D
var _base_guide_off: MeshInstance3D

# 堡垒占领计时
const FORTRESS_REQUIRED := 20.0
const CAPTURE_GRACE := 3.0
var fortress_capture_time: float = 0.0
var fortress_capture_team: int = -1
var fortress_grace: float = 0.0

# 飞镖累计
var dart_mode: String = ""
var dart_hits: int = 0

#是否摧毁
var destoryed:bool=false
#是否无敌
var is_invincible:bool=true
func set_invincible(value: bool) -> void:
	is_invincible = value
# 前哨站重建
var rebuild_chances: int = 0
var _base_hp_loss_total: int = 0
var _rebuild_chances_used: int = 0


@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var map_anchor: Node3D = get_node_or_null("0010_1")

func _ready() -> void:
	structure_kind = &"base"
	max_hp = base_max_hp

	super._ready()

	add_to_group("base")
	destroyed.connect(_on_destroyed)

	shield_hp = shield_max
	is_shielded = shield_hp > 0
	armor_open = false
	fortress_capture_time = 0.0
	fortress_capture_team = -1
	fortress_grace = 0.0
	dart_mode = ""
	dart_hits = 0
	
	_base_guide_on = get_node_or_null("DART_GUIDE_LIGHT") as MeshInstance3D
	_base_guide_off = get_node_or_null("DART_GUIDE_LIGHT_OFF") as MeshInstance3D
	set_base_guide_light(false)
	_reset_armor_animation()
func set_base_guide_light(on: bool) -> void:
	if _base_guide_on != null:
		_base_guide_on.visible = on
	if _base_guide_off != null:
		_base_guide_off.visible = not on
	
func _active_animation() -> AnimationPlayer:
	return animation_player

func _reset_armor_animation() -> void:
	var ap := _active_animation()
	if ap == null:
		return
	ap.play(open_animation)
	ap.seek(0.0, true)
	ap.pause()
func open_armor(reason: String = "") -> void:
	if armor_open or is_destroyed:
		return

	armor_open = true

	var ap := _active_animation()
	if ap:
		ap.play(open_animation)

	armor_opened.emit(reason)

	var reason_text: String = {
		"dart_moving": "飞镖命中（移动）",
		"dart_fixed": "飞镖命中（固定）",
		"fortress_capture": "堡垒占领",
	}.get(reason, reason)
	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[BASE] 基地护甲展开：%s" % reason_text
	)

	_stop_enemy_outpost_rotation()
func _stop_enemy_outpost_rotation() -> void:
	var enemy_team := Team.Id.RED if team == Team.Id.BLUE else Team.Id.BLUE
	var enemy_outpost: Node3D = null

	if not enemy_outpost_path.is_empty():
		enemy_outpost = get_node_or_null(enemy_outpost_path) as Node3D

	if enemy_outpost == null:
		var path := "Teams/TeamBlue/OutpostBlue" if enemy_team == Team.Id.BLUE else "Teams/TeamRed/OutpostRed"
		var scene := get_tree().current_scene
		enemy_outpost = scene.get_node_or_null(path) as Node3D

	if enemy_outpost and enemy_outpost.has_method("stop_rotation"):
		enemy_outpost.stop_rotation()
func tick_fortress_capture(attacker_team: int, delta: float) -> void:
	if armor_open or is_destroyed:
		return
	if MatchState.phase_name() != "RUNNING":
		return
	if MatchState.elapsed < 180.0:
		return
	if attacker_team == team:
		return
	if not _own_outpost_destroyed():
		return

	if fortress_capture_team != attacker_team:
		fortress_capture_team = attacker_team
		fortress_capture_time = 0.0

	fortress_capture_time += delta
	fortress_grace = CAPTURE_GRACE

	if fortress_capture_time >= FORTRESS_REQUIRED:
		open_armor("fortress_capture")
func release_fortress_capture(attacker_team: int) -> void:
	if attacker_team == fortress_capture_team:
		fortress_grace = CAPTURE_GRACE

func _process(delta: float) -> void:
	if armor_open or is_destroyed:
		return
	if fortress_capture_team < 0:
		return

	fortress_grace -= delta
	if fortress_grace <= 0.0:
		fortress_capture_team = -1
		fortress_capture_time = 0.0
func _own_outpost_destroyed() -> bool:
	var outpost: Node3D = null

	if not own_outpost_path.is_empty():
		outpost = get_node_or_null(own_outpost_path) as Node3D

	if outpost == null:
		var path := "Teams/TeamBlue/OutpostBlue" if team == Team.Id.BLUE else "Teams/TeamRed/OutpostRed"
		var scene := get_tree().current_scene
		outpost = scene.get_node_or_null(path) as Node3D

	return outpost != null and bool(outpost.get("is_destroyed"))
func on_dart_hit(mode: String, hit_base: bool = true) -> void:
	if armor_open or is_destroyed or not hit_base:
		return

	mode = mode.strip_edges()

	if "随机移动" in mode or "末端移动" in mode:
		open_armor("dart_moving")
		return

	if "固定" in mode:
		if dart_mode != mode:
			dart_mode = mode
			dart_hits = 0

		dart_hits += 1
		if dart_hits >= 4:
			open_armor("dart_fixed")
func take_damage(amount: int, source_team: int = -1, source: Node = null) -> int:
	if is_destroyed or source_team == team: return 0
	if is_invincible:return 0
	var remaining := maxi(amount, 0)
	var applied_damage := 0

	if shield_hp > 0:
		var absorbed := mini(shield_hp, remaining)
		shield_hp -= absorbed
		remaining -= absorbed
		applied_damage += absorbed
		MatchState.record_damage(source_team,absorbed)
		is_shielded = shield_hp > 0

		# 护盾吸收也要让 HUD 知道
		hp_changed.emit(current_hp, max_hp)

	if remaining <= 0:
		return applied_damage
	var hp_before := current_hp
	var actual := super.take_damage(remaining, source_team, source)
	var hp_loss := hp_before - current_hp
	if hp_loss>0: _register_base_hp_loss(hp_loss)
	return applied_damage + actual
func _register_base_hp_loss(amount: int) -> void:
	if amount <= 0:
		return

	_base_hp_loss_total += amount

	var earned := int(_base_hp_loss_total / 1000.0)
	var available := earned - _rebuild_chances_used

	if available > rebuild_chances:
		var gained := available - rebuild_chances
		rebuild_chances = available

		get_tree().call_group(
			"notification_feed",
			"push_notification",
			"[BASE] 获得 %d 次重建前哨站机会" % gained
		)
func consume_rebuild_chance() -> bool: #重建前哨站
	if rebuild_chances <= 0:
		return false

	rebuild_chances -= 1
	_rebuild_chances_used += 1
	return true

func reset_base() -> void:
	current_hp = max_hp
	is_destroyed = false
	shield_hp = shield_max
	is_shielded = shield_hp > 0
	armor_open = false
	is_invincible=true
	
	fortress_capture_time = 0.0
	fortress_capture_team = -1
	fortress_grace = 0.0
	dart_mode = ""
	dart_hits = 0
	
	rebuild_chances = 0
	_base_hp_loss_total = 0
	_rebuild_chances_used = 0

	_reset_armor_animation()
	
	set_base_guide_light(false)
func _on_destroyed(_team_id:int=-1) -> void:
	MatchState.finish_match("base_destroyed")
	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[BASE] 基地已被摧毁"
	)
# 小地图映射
func get_map_position() -> Vector3:
	if map_anchor:
		return map_anchor.global_position
	return global_position
