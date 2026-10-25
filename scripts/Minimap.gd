extends Control

const MAP_MIN := Vector2(-14.0, -7.5)
const MAP_MAX := Vector2(14.0, 7.5)
const ENEMY_DOT_COUNT := 8

@export var blue_base_path: NodePath
@export var blue_outpost_path: NodePath
@export var red_base_path: NodePath
@export var red_outpost_path: NodePath

@onready var map_view: Control = $MapView
@onready var player_marker: Control = $MapView/PlayerMarker
@onready var enemy_dots_root: Control = $MapView/EnemyDots
@onready var blue_base_marker: TextureRect = $MapView/BlueBaseMarker
@onready var blue_outpost_marker: TextureRect = $MapView/BlueOutpostMarker
@onready var red_base_marker: TextureRect = $MapView/RedBaseMarker
@onready var red_outpost_marker: TextureRect = $MapView/RedOutpostMarker
@onready var rune_marker: Control = $MapView/RuneMarker
@onready var coords_label: Label = $MapView/Legend/HBox/Coords

var enemy_dots: Array[Panel] = []


func _ready() -> void:
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	_create_enemy_dots()


func _process(_delta: float) -> void:
	if not SnapshotHub.current.is_empty():
		apply_snapshot(SnapshotHub.current)
	else :
		_update_player()
		_update_buildings()
		_update_enemy_dots()
func apply_snapshot(s: Dictionary) -> void:
	var pose: Dictionary = s.get("pose", {})
	if pose.is_empty():
		player_marker.visible = false
		return

	player_marker.visible = true
	var p := Vector3(
		float(pose.get("x", 0.0)),
		0.0,
		float(pose.get("z", 0.0))
	)
	player_marker.position = world_to_map(p) - player_marker.size * 0.5

	# 世界 yaw 到小地图旋转
	player_marker.rotation =  float(pose.get("camera_yaw",-float(pose.get("gimbal_yaw", pose.get("yaw", 0.0)))))

	coords_label.text = "X %.1f  Z %.1f" % [
		float(pose.get("x", 0.0)),
		float(pose.get("z", 0.0))
	]

	var entities: Array = s.get("entities", [])
	_set_building_entity(blue_base_marker, _find_entity(entities, "blue", "base"))
	_set_building_entity(blue_outpost_marker, _find_entity(entities, "blue", "outpost"))
	_set_building_entity(red_base_marker, _find_entity(entities, "red", "base"))
	_set_building_entity(red_outpost_marker, _find_entity(entities, "red", "outpost"))
	rune_marker.position=map_view.size*0.5-rune_marker.size*0.5
	_update_enemy_dots_from_snapshot(s)
func _find_entity(entities: Array, team: String, kind: String) -> Dictionary:
	for e in entities:
		if not (e is Dictionary):
			continue
		if String(e.get("team", "")) == team and String(e.get("kind", "")) == kind:
			return e
	return {}
func _update_enemy_dots_from_snapshot(s: Dictionary) -> void:
	var own_team := String(s.get("team", ""))
	var used := 0

	for e in s.get("entities", []):
		if String(e.get("kind", "")) != "infantry":
			continue
		if String(e.get("team", "")) == own_team:
			continue
		if not bool(e.get("alive", true)):
			continue
		if e.has("visible") and not bool(e.get("visible", true)):
			continue
		if used >= enemy_dots.size():
			break

		var dot := enemy_dots[used]
		dot.visible = true
		var p := Vector3(
			float(e.get("x", 0.0)),
			0.0,
			float(e.get("z", 0.0))
		)
		dot.position = world_to_map(p) - dot.size * 0.5
		used += 1

	_hide_enemy_dots(used)
func _set_building_entity(marker: TextureRect, e: Dictionary) -> void:
	if e.is_empty() or not bool(e.get("alive", true)):
		marker.visible = false
		return

	marker.visible = true
	var p := Vector3(float(e.get("x", 0.0)), 0.0, float(e.get("z", 0.0)))
	marker.position = world_to_map(p) - marker.size * 0.5
	marker.modulate = Color(0.4, 0.4, 0.4, 1.0)

func _apply_layout() -> void:
	var compact := get_viewport().get_visible_rect().size.x < 1500.0
	var w := 320.0 if compact else 368.0
	var h := 171.0 if compact else 197.0
	var margin := 18.0 if compact else 30.0
	var bottom := 18.0 if compact else 26.0

	offset_left = margin
	offset_right = margin + w
	offset_top = -bottom - h
	offset_bottom = -bottom


func world_to_map(world_pos: Vector3) -> Vector2:
	var uv := Vector2(
		(world_pos.x - MAP_MIN.x) / (MAP_MAX.x - MAP_MIN.x),
		(world_pos.z - MAP_MIN.y) / (MAP_MAX.y - MAP_MIN.y)
	)
	uv.x = clampf(uv.x, 0.0, 1.0)
	uv.y = clampf(uv.y, 0.0, 1.0)
	return uv * map_view.size


func _update_player() -> void:
	var player := get_tree().get_first_node_in_group("Player")
	if player == null:
		player_marker.visible = false
		return

	player_marker.visible = true
	player_marker.position = world_to_map(player.global_position) - player_marker.size * 0.5

	var camera := player.get_node_or_null(
		"GimbalYaw/GimbalPitch/Camera3D"
	) as Camera3D

	if camera:
		var forward := -camera.global_transform.basis.z
		var direction := Vector2(forward.x, forward.z)

		if direction.length_squared() > 0.0001:
			direction = direction.normalized()
			player_marker.rotation = atan2(direction.x, -direction.y)

	coords_label.text = "X %.1f  Z %.1f" % [
		player.global_position.x,
		player.global_position.z
	]


func _update_buildings() -> void:
	_set_building(
		blue_base_marker,
		_find_node(blue_base_path, "blue_base")
	)
	_set_building(
		blue_outpost_marker,
		_find_node(blue_outpost_path, "blue_outpost")
	)
	_set_building(
		red_base_marker,
		_find_node(red_base_path, "red_base")
	)
	_set_building(
		red_outpost_marker,
		_find_node(red_outpost_path, "red_outpost")
	)

	rune_marker.position = map_view.size * 0.5 - rune_marker.size * 0.5


func _find_node(path: NodePath, group: StringName) -> Node3D:
	if not path.is_empty():
		return get_node_or_null(path) as Node3D
	return get_tree().get_first_node_in_group(group) as Node3D


func _set_building(marker: TextureRect, building: Node3D) -> void:
	if building == null:
		marker.visible = false
		return
	if bool(building.get("is_destroyed")):
		marker.visible=false
		return
	marker.visible = true
	marker.modulate = Color(0.4, 0.4, 0.4, 1.0)
	marker.position = world_to_map(building.global_position) - marker.size * 0.5


func _create_enemy_dots() -> void:
	for i in range(ENEMY_DOT_COUNT):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size = Vector2(7, 7)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var style := StyleBoxFlat.new()
		style.bg_color = Color("#FF5E7A")
		style.set_corner_radius_all(4)
		style.shadow_color = Color(1.0, 0.37, 0.48, 0.45)
		style.shadow_size = 6
		dot.add_theme_stylebox_override("panel", style)

		enemy_dots_root.add_child(dot)
		dot.visible = false
		enemy_dots.append(dot)


func _update_enemy_dots() -> void:
	var player := get_tree().get_first_node_in_group("Player")
	if player == null:
		_hide_enemy_dots(0)
		return

	var camera := player.get_node_or_null(
		"GimbalYaw/GimbalPitch/Camera3D"
	) as Camera3D
	if camera == null:
		_hide_enemy_dots(0)
		return

	var used := 0
	for node in get_tree().get_nodes_in_group("Enemy"):
		var enemy := node as Node3D
		if enemy == null or not _can_see_enemy(enemy, camera):
			continue
		if used >= enemy_dots.size():
			break

		var dot := enemy_dots[used]
		dot.visible = true
		dot.position = world_to_map(enemy.global_position) - dot.size * 0.5
		used += 1

	_hide_enemy_dots(used)


func _hide_enemy_dots(from_index: int) -> void:
	for i in range(from_index, enemy_dots.size()):
		enemy_dots[i].visible = false


func _can_see_enemy(enemy: Node3D, camera: Camera3D) -> bool:
	if enemy == null or camera == null:
		return false
	if not enemy.is_visible_in_tree():
		return false

	var hp_value = enemy.get("hp")
	if hp_value != null and int(hp_value) <= 0:
		return false

	var target := enemy.global_position + Vector3.UP * 0.8
	if not camera.is_position_in_frustum(target):
		return false

	var player := get_tree().get_first_node_in_group("Player")
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		target
	)
	query.exclude = [player]
	query.collide_with_areas = true

	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var hit_node: Node = hit.get("collider") as Node
	while hit_node != null:
		if hit_node == enemy:
			return true
		hit_node = hit_node.get_parent()

	return false
