extends Area3D

## 前哨站增益点 / 重建点。
##
## 这个脚本只负责“检测自己的机器人是否连续停留在范围内”，并维护每台机器人独立的计时。
## 默认优先调用 Outpost.try_rebuild(team_id)；如果当前项目还没有该方法，
## 可以通过 legacy_rebuild_fallback 兼容旧的 Outpost.rebuild()。
##
## 规则依据：
## - 英雄 / 步兵 / 哨兵连续检测 10 秒
## - 工程机器人连续检测 5 秒
## - 不同机器人独立计时
## - 比赛开始 5 分钟后不能重建

signal progress_changed(team_id: int, progress: float, required: float)
signal occupancy_changed(team_id: int, occupied: bool)
signal rebuild_requested(team_id: int)
signal rebuild_completed(team_id: int)

@export var team: int = 0
@export var outpost_path: NodePath
@export var base_path: NodePath

@export var normal_required: float = 10.0
@export var engineer_required: float = 5.0

## 当前项目还没有 Base.rebuild_chances 时，这个检查会自动跳过。
@export var require_base_rebuild_chance: bool = true

## 到达计时后是否直接尝试重建。
@export var auto_trigger_rebuild: bool = true

## 如果 Outpost 没有 try_rebuild，是否兼容调用旧的 rebuild()。
## 旧 rebuild() 没有校验重建机会，严格按规则时应保持 false。
@export var legacy_rebuild_fallback: bool = false

var _timers: Dictionary = {}
var _last_occupied := false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2


func _physics_process(delta: float) -> void:
	var phase := MatchState.phase_name()

	# 暂停时不累计，但保留已有进度。
	if phase == "PAUSED":
		return

	if phase != "RUNNING":
		_clear_timers()
		return

	var outpost := _get_outpost()
	if outpost == null:
		_clear_timers()
		return

	if not bool(outpost.get("is_destroyed")):
		_clear_timers()
		return

	if MatchState.elapsed >= 300.0:
		_clear_timers()
		return

	var base := _get_base()
	if _base_has_no_chance(base):
		_clear_timers()
		return

	var present: Dictionary = {}
	var max_progress := 0.0
	var max_required := normal_required

	for body in get_overlapping_bodies():
		if body == null:
			continue
		if not body.is_in_group("infantry"):
			continue
		if int(body.get("team")) != team:
			continue
		if bool(body.get("is_dead")):
			continue

		present[body] = true
		var required := _required_time_for(body)
		var current := float(_timers.get(body, 0.0)) + delta
		_timers[body] = current

		if current > max_progress:
			max_progress = current
			max_required = required

		if current >= required:
			rebuild_requested.emit(team)

			if auto_trigger_rebuild:
				if _request_rebuild(outpost):
					rebuild_completed.emit(team)

			_timers.clear()
			_emit_progress(0.0, required)
			return

	# 离开范围或已经死亡的机器人，进度清零，不和其他机器人合并。
	for body in _timers.keys():
		if not present.has(body) or not is_instance_valid(body):
			_timers.erase(body)

	var occupied := not _timers.is_empty()
	if occupied != _last_occupied:
		_last_occupied = occupied
		occupancy_changed.emit(team, occupied)

	_emit_progress(max_progress, max_required)


func _get_outpost() -> Node:
	if outpost_path.is_empty():
		return get_parent()
	return get_node_or_null(outpost_path)


func _get_base() -> Node:
	if not base_path.is_empty():
		var direct := get_node_or_null(base_path)
		if direct != null:
			return direct

	return get_tree().get_first_node_in_group(
		Team.object_group(team, "base")
	)


func _base_has_no_chance(base: Node) -> bool:
	if base == null or not require_base_rebuild_chance:
		return false

	# 当前项目 Base 还没有 rebuild_chances 时 get() 返回 null，此时不拦截。
	var value = base.get("rebuild_chances")
	if value == null:
		return false

	return int(value) <= 0


func _required_time_for(body: Node) -> float:
	if body.is_in_group("engineer"):
		return engineer_required

	var role = body.get("robot_role")
	if role != null and str(role) == "engineer":
		return engineer_required

	return normal_required


func _request_rebuild(outpost: Node) -> bool:
	if outpost.has_method("try_rebuild"):
		return bool(outpost.call("try_rebuild", team))

	if legacy_rebuild_fallback and outpost.has_method("rebuild"):
		outpost.call("rebuild")
		return true

	return false


func _clear_timers() -> void:
	_timers.clear()
	if _last_occupied:
		_last_occupied = false
		occupancy_changed.emit(team, false)
	_emit_progress(0.0, normal_required)


func _emit_progress(progress: float, required: float) -> void:
	progress_changed.emit(team, progress, required)


func get_progress() -> float:
	var max_progress := 0.0
	for value in _timers.values():
		max_progress = maxf(max_progress, float(value))
	return max_progress


func get_occupied_robots() -> Array:
	return _timers.keys()
