extends Node3D

# ============================================================
# 大小能量机关
#
# 规则依据：RoboMaster 2026 规则手册 V2.2.0 5.5.2
# ============================================================

@onready var face_1: Node3D = $FACE_1
@onready var face_2: Node3D = $FACE_2

# 小能量机关转速：π/3 rad/s
# 大能量机关非激活状态：π/3 rad/s
@export var spin_speed_rad: float = PI/3.0
@export var large_idle_speed_rad: float = PI / 3.0
const ck_point: float = 180.0

var pivot_point := Vector3(0, 2.447, 0)
var fixed_axis := Vector3(1, 0, 1).normalized()
var init_transform_1: Transform3D
var init_transform_2: Transform3D
var angle_1: float = 0.0
var angle_2: float = 0.0
var spin_direction: int = 1

# 小能量机关：0:00、1:30
var small_rune_times: Array = [0.0, 90.0]
# 大能量机关：3:00、4:15、5:30
var large_rune_times: Array = [ck_point, 255.0, 330.0]

# 双方独立的机会数量
var small_chance := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}
var large_chance := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}

# 大能量机关累计成功激活次数
var large_activation_count := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}

# 当前正在激活的是否为大能量机关
var activation_is_large := {
	Team.Id.BLUE: false,
	Team.Id.RED: false,
}

# 每个时间点是否已经发过机会
var small_gain := {
	Team.Id.BLUE: [false, false],
	Team.Id.RED: [false, false],
}
var large_gain := {
	Team.Id.BLUE: [false, false, false],
	Team.Id.RED: [false, false, false],
}

# 状态：未激活 / 正在激活 / 已激活
enum RuneState { IDLE, ACTIVATING, ACTIVATED }

var current_state := {
	Team.Id.BLUE: RuneState.IDLE,
	Team.Id.RED: RuneState.IDLE,
}

# 已激活状态（Buff 期间）的结束时间
var buff_end_at := {
	Team.Id.BLUE: 0.0,
	Team.Id.RED: 0.0,
}

# 激活令牌，用于取消旧协程
var activation_id := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}

# 进入正在激活状态的时间
var activation_started_at := {
	Team.Id.BLUE: 0.0,
	Team.Id.RED: 0.0,
}

# 大能量机关激活中的旋转参数
var large_motion_started_at := {
	Team.Id.BLUE: 0.0,
	Team.Id.RED: 0.0,
}
var large_motion_a := {
	Team.Id.BLUE: 0.780,
	Team.Id.RED: 0.780,
}
var large_motion_omega := {
	Team.Id.BLUE: 1.884,
	Team.Id.RED: 1.884,
}

# 单次命中状态
var is_target_hit := {
	Team.Id.BLUE: false,
	Team.Id.RED: false,
}
var is_failed := {
	Team.Id.BLUE: false,
	Team.Id.RED: false,
}
var first_hit_name := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}
var hit_legal := {
	Team.Id.BLUE: [false, false, false, false, false, false],
	Team.Id.RED: [false, false, false, false, false, false],
}
var hit_cnt := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}
var tot_hit := {
	Team.Id.BLUE: 0,
	Team.Id.RED: 0,
}
var target_hited := {
	Team.Id.BLUE: "",
	Team.Id.RED: "",
}

# 灯效缓存
var face_1_tar: Array = []
var face_2_tar: Array = []
var face_1_leg: Array = []
var face_2_leg: Array = []

const SHOT_LIMIT := 2.5
const SECOND_SHOT_LIMIT := 1.0
const ACTIVATION_TIMEOUT := 20.0


func _ready() -> void:
	add_to_group("power_rune")
	init_transform_1 = face_1.global_transform
	init_transform_2 = face_2.global_transform
	_init_all_lights()
	reset_rune()


func _physics_process(delta: float) -> void:
	if MatchState.phase != MatchState.Phase.RUNNING:
		return

	for team_id in [Team.Id.BLUE, Team.Id.RED]:
		opportunities_gain(team_id)

	var base_speed: float = spin_speed_rad
	if base_speed <= 0.0:
		base_speed = PI /3.0

	if MatchState.elapsed >= ck_point:
		base_speed = large_idle_speed_rad
		if base_speed <= 0.0:
			base_speed = PI / 3.0

	var speed_1: float = base_speed * spin_direction
	var speed_2: float = -base_speed * spin_direction

	if MatchState.elapsed >= ck_point:
		if current_state[Team.Id.RED] == RuneState.ACTIVATING:
			speed_1 = _large_speed(Team.Id.RED) * spin_direction
		if current_state[Team.Id.BLUE] == RuneState.ACTIVATING:
			speed_2 = _large_speed(Team.Id.BLUE) * -spin_direction

	angle_1 = wrapf(angle_1 + speed_1 * delta, 0.0, TAU)
	angle_2 = wrapf(angle_2 + speed_2 * delta, 0.0, TAU)

	if face_1:
		apply_rotation(face_1, init_transform_1, angle_1)
	if face_2:
		apply_rotation(face_2, init_transform_2, angle_2)


func _process(_delta: float) -> void:
	# Buff 结束后，能量机关从“已激活”回到“未激活”
	for team_id in [Team.Id.BLUE, Team.Id.RED]:
		if current_state[team_id] == RuneState.ACTIVATED:
			if MatchState.elapsed >= buff_end_at[team_id]:
				current_state[team_id] = RuneState.IDLE
				_set_idle_state(team_id)


func opportunities_gain(team_id: int) -> void:
	for i in range(small_rune_times.size()):
		if MatchState.elapsed >= float(small_rune_times[i]) and not small_gain[team_id][i]:
			small_gain[team_id][i] = true
			small_chance[team_id] += 1
			print("[RUNE] %s获得小能量机关激活机会，当前：%d" % [
				_team_name(team_id), small_chance[team_id]
			])

	for i in range(large_rune_times.size()):
		if MatchState.elapsed >= float(large_rune_times[i]) and not large_gain[team_id][i]:
			large_gain[team_id][i] = true
			large_chance[team_id] += 1
			print("[RUNE] %s获得大能量机关激活机会，当前：%d" % [
				_team_name(team_id), large_chance[team_id]
			])


func _large_speed(team_id: int) -> float:
	var t: float = maxf(MatchState.elapsed - large_motion_started_at[team_id], 0.0)
	var a: float = large_motion_a[team_id]
	var omega: float = large_motion_omega[team_id]
	var b: float = 2.090 - a
	return a * sin(omega * t) + b


func _begin_large_motion(team_id: int) -> void:
	large_motion_started_at[team_id] = MatchState.elapsed
	large_motion_a[team_id] = randf_range(0.780, 1.045)
	large_motion_omega[team_id] = randf_range(1.884, 2.000)


func apply_rotation(node: Node3D, init_transform: Transform3D, angle: float) -> void:
	var rot_basis := Basis(fixed_axis, angle)
	var offset := init_transform.origin - pivot_point
	node.global_transform.basis = rot_basis * init_transform.basis
	node.global_position = pivot_point + rot_basis * offset


func request_activation(team_id: int) -> void:
	if MatchState.phase_name() != "RUNNING":
		return
	if team_id != Team.Id.BLUE and team_id != Team.Id.RED:
		return
	if current_state[team_id] != RuneState.IDLE:
		print("[RUNE] %s能量机关尚未恢复未激活状态" % _team_name(team_id))
		return

	if MatchState.elapsed < ck_point:
		if small_chance[team_id] <= 0:
			print("[RUNE] %s没有小能量机关激活机会" % _team_name(team_id))
			return

		small_chance[team_id] -= 1
		current_state[team_id] = RuneState.ACTIVATING
		activation_is_large[team_id] = false
		activation_id[team_id] += 1
		activation_started_at[team_id] = MatchState.elapsed
		_small_act(team_id)
	else:
		if large_chance[team_id] <= 0:
			print("[RUNE] %s没有大能量机关激活机会" % _team_name(team_id))
			return

		large_chance[team_id] -= 1
		current_state[team_id] = RuneState.ACTIVATING
		activation_is_large[team_id] = true
		activation_id[team_id] += 1
		activation_started_at[team_id] = MatchState.elapsed
		_begin_large_motion(team_id)
		_large_act(team_id)


func _init_all_lights() -> void:
	for i in range(6):
		face_1_tar.append([])
		face_2_tar.append([])
		face_1_leg.append([])
		face_2_leg.append([])

	for i in range(1, 6):
		for child in face_1.get_children():
			if child.name.begins_with("FACE_1_TARGET_%d_" % i):
				face_1_tar[i].append(child)

		for child in face_2.get_children():
			if child.name.begins_with("FACE_2_TARGET_%d_" % i):
				face_2_tar[i].append(child)

	for i in range(1, 6):
		for s in range(1, 6):
			var n1: Node = face_1.find_child("TARGET_%d_SEG_%d" % [i, s], true, false)
			if n1:
				face_1_leg[i].append(n1)

			var n2: Node = face_2.find_child("TARGET_%d_SEG_%d" % [i, s], true, false)
			if n2:
				face_2_leg[i].append(n2)

		if face_1_leg[i].is_empty():
			for s in range(1, 4):
				var f1: Node = face_1.find_child("FACE_1_TARGET_%d_LEGGING_%d" % [i, s], true, false)
				if f1:
					face_1_leg[i].append(f1)

		if face_2_leg[i].is_empty():
			for s in range(1, 4):
				var f2: Node = face_2.find_child("FACE_2_TARGET_%d_LEGGING_%d" % [i, s], true, false)
				if f2:
					face_2_leg[i].append(f2)

	_set_idle_state(Team.Id.BLUE)
	_set_idle_state(Team.Id.RED)


func _face_for_team(team_id: int) -> Node3D:
	return face_1 if team_id == Team.Id.RED else face_2


func _face_prefix(team_id: int) -> String:
	return "FACE_1" if team_id == Team.Id.RED else "FACE_2"


func _targets_for_team(team_id: int) -> Array:
	return face_1_tar if team_id == Team.Id.RED else face_2_tar


func _legs_for_team(team_id: int) -> Array:
	return face_1_leg if team_id == Team.Id.RED else face_2_leg


func _team_name(team_id: int) -> String:
	return "红方" if team_id == Team.Id.RED else "蓝方"


# 供 bullet.gd 查询：当前队伍是否正在激活
func is_team_activating(team_id: int) -> bool:
	return current_state.get(team_id, RuneState.IDLE) == RuneState.ACTIVATING


func _set_powered(team_id: int, visible: bool) -> void:
	var face := _face_for_team(team_id)
	if face == null:
		return

	# 能量核心亮起 / 变暗
	var powered := face.get_node_or_null("%s_R_POWERED" % _face_prefix(team_id))
	if powered:
		powered.visible = visible

	var unpowered := face.get_node_or_null("%s_R_UNPOWERED" % _face_prefix(team_id))
	if unpowered:
		unpowered.visible = not visible


func _set_idle_state(team_id: int) -> void:
	_set_powered(team_id, false)

	var targets := _targets_for_team(team_id)
	var legs := _legs_for_team(team_id)

	for i in range(1, 6):
		_hide_target(targets[i])
		_hide_target(legs[i])


func _hide_target(targets: Array) -> void:
	for target in targets:
		if target is Node3D:
			target.visible = false


func _show_lit_target(team_id: int, i: int) -> void:
	for target in _targets_for_team(team_id)[i]:
		if target is Node3D and (
			target.name.ends_with("ACTIVE") or
			target.name.ends_with("PROGRESSING")
		):
			target.visible = true


func _hide_lit_target(team_id: int, i: int) -> void:
	for target in _targets_for_team(team_id)[i]:
		if target is Node3D and (
			target.name.ends_with("ACTIVE") or
			target.name.ends_with("PROGRESSING")
		):
			target.visible = false


func _show_legging_progress(team_id: int, i: int, progress: int) -> void:
	var legs: Array = _legs_for_team(team_id)[i]
	if legs.is_empty():
		return

	var show_count: int = int(round(float(progress) / 5.0 * float(legs.size())))
	for s in range(legs.size()):
		if legs[s] is Node3D:
			legs[s].visible = s < show_count


func _hide_legging_progress(team_id: int, i: int) -> void:
	for node in _legs_for_team(team_id)[i]:
		if node is Node3D:
			node.visible = false


func _show_final(team_id: int, i: int) -> void:
	_show_target_suffix(team_id, i, "PADDING")


func _hide_final(team_id: int, i: int) -> void:
	_hide_target_suffix(team_id, i, "PADDING")


func _show_pre(team_id: int, i: int) -> void:
	_show_target_suffix(team_id, i, "ACTIVATED")


func _hide_pre(team_id: int, i: int) -> void:
	_hide_target_suffix(team_id, i, "ACTIVATED")


func _show_target_suffix(team_id: int, i: int, suffix: String) -> void:
	var prefix := "%s_TARGET_%d_" % [_face_prefix(team_id), i]
	for target in _targets_for_team(team_id)[i]:
		if target is Node3D and target.name.begins_with(prefix) and target.name.ends_with(suffix):
			target.visible = true


func _hide_target_suffix(team_id: int, i: int, suffix: String) -> void:
	var prefix := "%s_TARGET_%d_" % [_face_prefix(team_id), i]
	for target in _targets_for_team(team_id)[i]:
		if target is Node3D and target.name.begins_with(prefix) and target.name.ends_with(suffix):
			target.visible = false


func _activation_timed_out(team_id: int) -> bool:
	return MatchState.elapsed - activation_started_at[team_id] >= ACTIVATION_TIMEOUT


# ============================================================
# 小能量机关
# ============================================================

func _small_act(team_id: int) -> void:
	# 20 秒激活窗口内，允许反复重新开始 5 个标靶
	var my_id: int = activation_id[team_id]

	while current_state[team_id] == RuneState.ACTIVATING:
		if _activation_timed_out(team_id):
			_finish_activation(team_id, false)
			return

		var ok: bool = await _small_attempt(team_id, my_id)
		if my_id != activation_id[team_id]:
			return

		if ok:
			for i in range(1, 6):
				_show_legging_progress(team_id, i, 5)
				_show_final(team_id, i)

			_send_buff(0.25, 1.0, 1.0, 45.0, 0.25, team_id)
			ExpSystem.start_small_rune_bonus(team_id, 45.0)

			get_tree().call_group(
				"notification_feed",
				"push_notification",
				"[RUNE] %s小能量机关激活成功" % _team_name(team_id)
			)
			_finish_activation(team_id, true, 45.0)
			return

		# 单次 5 标靶失败，重新开始 5 个标靶
		if _activation_timed_out(team_id):
			_finish_activation(team_id, false)
			return

		_clear_small_attempt(team_id)


func _small_attempt(team_id: int, my_id: int) -> bool:
	var is_lighted: Array = [false, false, false, false, false, false]

	_set_powered(team_id, true)

	for i in range(1, 6):
		if _activation_timed_out(team_id):
			return false

		var idx: int = randi_range(1, 5)
		while is_lighted[idx]:
			idx = randi_range(1, 5)

		print("[小能量机关] %s请激活标靶：%d" % [_team_name(team_id), idx])
		hit_legal[team_id][idx] = true
		_show_lit_target(team_id, idx)

		is_target_hit[team_id] = false
		is_failed[team_id] = false

		var result: bool = await _wait_for_hit(SHOT_LIMIT, my_id, team_id)
		if my_id != activation_id[team_id]:
			return false

		hit_legal[team_id][idx] = false

		if is_failed[team_id] or not result:
			return false

		is_lighted[idx] = true
		_hide_lit_target(team_id, idx)
		_show_legging_progress(team_id, idx, 5)
		_show_pre(team_id, idx)

	return true


func _clear_small_attempt(team_id: int) -> void:
	is_target_hit[team_id] = false
	is_failed[team_id] = false
	hit_legal[team_id] = [false, false, false, false, false, false]
	_set_idle_state(team_id)


# ============================================================
# 大能量机关
# ============================================================

func _large_act(team_id: int) -> void:
	# 20 秒窗口内，允许反复重新开始完整 5 组
	var my_id: int = activation_id[team_id]

	while current_state[team_id] == RuneState.ACTIVATING:
		if _activation_timed_out(team_id):
			_finish_activation(team_id, false)
			return

		_reset_large_attempt(team_id)
		var ok: bool = await _large_attempt(team_id, my_id)
		if my_id != activation_id[team_id]:
			return

		if ok:
			for i in range(1, 6):
				_show_legging_progress(team_id, i, 5)
				_show_final(team_id, i)

			var buff_duration: float = _apply_large_reward(team_id)
			large_activation_count[team_id] += 1
			_finish_activation(team_id, true, buff_duration)
			return

		if _activation_timed_out(team_id):
			_finish_activation(team_id, false)
			return

		_clear_large_attempt(team_id)


func _large_attempt(team_id: int, my_id: int) -> bool:
	_set_powered(team_id, true)

	for i in range(1, 6):
		if _activation_timed_out(team_id):
			return false

		var t1: int = randi_range(1, 5)
		var t2: int = randi_range(1, 5)
		while t1 == t2:
			t2 = randi_range(1, 5)

		is_target_hit[team_id] = false
		is_failed[team_id] = false
		first_hit_name[team_id] = 0

		for j in range(1, 6):
			hit_legal[team_id][j] = false
			_hide_lit_target(team_id,j)
		for j in range(1, 6):
			if j == t1 or j == t2:
				_hide_legging_progress(team_id,j)
				_show_lit_target(team_id, j)
				hit_legal[team_id][j] = true
				print("[大能量机关] %s请激活标靶：%d" % [_team_name(team_id), j])
			else:
				_show_legging_progress(team_id, j, i - 1)

		var first_ok: bool = await _wait_for_hit(SHOT_LIMIT, my_id, team_id)
		if my_id != activation_id[team_id]:
			return false

		if is_failed[team_id] or not first_ok:
			return false

		var first_arm: int = first_hit_name[team_id]
		if first_arm != 0:
			_hide_lit_target(team_id, first_arm)
			hit_legal[team_id][first_arm] = false
			for j in range(1,6):
				if (j==t1 and j!=first_arm) or (j==t2 and j!=first_arm):
					continue
				_show_legging_progress(team_id,j,i)
			print("[大能量机关] 已激活灯臂：%d" % first_arm)

		# 第一发命中后本组完成；第二发只是可选加分
		is_target_hit[team_id] = false
		is_failed[team_id] = false

		var second_ok: bool = await _wait_for_hit(SECOND_SHOT_LIMIT, my_id, team_id)
		if my_id != activation_id[team_id]:
			return false

		if _activation_timed_out(team_id):
			if i == 5:
				for j in range(1, 6):
					_hide_lit_target(team_id, j)
				return true

			# 第 1~4 组尚未完成全部 5 组，20 秒到期仍然失败
			return false


		if is_failed[team_id]:
			# 第二发打中错误标靶：重新开始 5 组
			return false

		for j in range(1, 6):
			if j == t1 or j == t2:
				_hide_lit_target(team_id, j)
			else:
				_hide_legging_progress(team_id, j)

	return true


func _reset_large_attempt(team_id: int) -> void:
	is_target_hit[team_id] = false
	is_failed[team_id] = false
	first_hit_name[team_id] = 0
	hit_cnt[team_id] = 0
	tot_hit[team_id] = 0
	hit_legal[team_id] = [false, false, false, false, false, false]
	_set_idle_state(team_id)


func _clear_large_attempt(team_id: int) -> void:
	is_target_hit[team_id] = false
	is_failed[team_id] = false
	first_hit_name[team_id] = 0
	hit_legal[team_id] = [false, false, false, false, false, false]
	_set_idle_state(team_id)


func _apply_large_reward(team_id: int) -> float:
	var avg: float = float(tot_hit[team_id]) / float(max(hit_cnt[team_id], 1))
	var hits: int = clampi(hit_cnt[team_id], 5, 10)
	var duration: float = 30.0
	if hits >= 10:
		duration = 60.0
	else:
		duration = 30.0 + 5.0 * float(hits - 5)

	var atk: float = 1.0
	var defense: float = 0.0
	var cool: float = 1.0

	if avg >= 9.0:
		atk = 3.0
		defense = 0.5
		cool = 5.0
	elif avg > 8.0:
		atk = 2.0
		defense = 0.25
		cool = 3.0
	elif avg > 7.0:
		atk = 2.0
		defense = 0.25
		cool = 2.0
	elif avg > 3.0:
		atk = 1.5
		defense = 0.25
		cool = 2.0
	elif avg >= 1.0:
		atk = 1.5
		defense = 0.25
		cool = 1.0

	_send_buff(defense, atk, cool, duration, defense, team_id)
	ExpSystem.award_large_rune_exp(team_id, 750.0)

	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[RUNE]%s大能量机关激活成功，环数：%.2f，命中数：%d" % [
			_team_name(team_id), avg, hit_cnt[team_id]
		]
	)

	print("[大能量机关] %s激活成功，平均环数：%.2f，命中数：%d，持续时间：%.0f" % [
		_team_name(team_id), avg, hit_cnt[team_id], duration
	])

	return duration


func _wait_for_hit(timeout_sec: float, my_id: int, team_id: int) -> bool:
	var deadline: float = MatchState.elapsed + timeout_sec

	while not is_target_hit[team_id] and not is_failed[team_id]:
		if my_id != activation_id[team_id]:
			return false

		var phase: String = MatchState.phase_name()
		if phase == "READY" or phase == "ENDED" or phase == "PAUSED":
			return false

		if MatchState.elapsed - activation_started_at[team_id] >= ACTIVATION_TIMEOUT:
			return false

		if MatchState.elapsed >= deadline:
			break

		await get_tree().process_frame

	if is_failed[team_id]:
		return false

	if is_target_hit[team_id]:
		hit_cnt[team_id] += 1
		return true

	return false


func _finish_activation(team_id: int, success: bool, buff_duration: float = 0.0) -> void:
	hit_legal[team_id] = [false, false, false, false, false, false]

	if success:
		# 成功激活后进入“已激活”状态，Buff 持续期间不能再激活
		current_state[team_id] = RuneState.ACTIVATED
		buff_end_at[team_id] = MatchState.elapsed + buff_duration
		_set_powered(team_id, true)
	else:
		# 20 秒窗口内没有完成，进入未激活状态
		current_state[team_id] = RuneState.IDLE
		_set_idle_state(team_id)


func on_target_hit(hit_tar_name: String, hit_pos: Vector3) -> bool:
	var team_id: int = Team.Id.RED if hit_tar_name.begins_with("FACE_1") else Team.Id.BLUE

	if current_state[team_id] != RuneState.ACTIVATING:
		return false
	if is_target_hit[team_id]:
		return false

	var face := _face_for_team(team_id)
	var prefix := _face_prefix(team_id)

	for i in range(1, 6):
		var expected_name: String = "%s_TARGET_%d" % [prefix, i]
		if not hit_tar_name.begins_with(expected_name):
			continue

		var target_node := face.get_node_or_null(hit_tar_name) as Node3D
		if target_node == null:
			return false

		var ring: int = calculate_ring(hit_pos, target_node)
		if ring <= 0:
			return false

		# 大能量机关：累计激活后只检测内侧环数
		if activation_is_large[team_id] and ring < _min_large_ring(team_id):
			print("[RUNE] %s命中有效区域外，环数：%d，最低要求：%d" % [
				_team_name(team_id), ring, _min_large_ring(team_id)
			])
			return false

		if not hit_legal[team_id][i]:
			print("[RUNE] %s打中了非点亮标靶：%s" % [
				_team_name(team_id), hit_tar_name
			])
			is_failed[team_id] = true
			return false

		target_hited[team_id] = hit_tar_name
		tot_hit[team_id] += ring
		is_target_hit[team_id] = true
		first_hit_name[team_id] = i

		print("[RUNE] %s命中标靶：%s，环数：%d" % [
			_team_name(team_id), hit_tar_name, ring
		])
		return true

	return false


func _min_large_ring(team_id: int) -> int:
	var count: int = int(large_activation_count.get(team_id, 0))
	if count <= 0:
		return 1
	if count == 1:
		return 4
	return 7


func calculate_ring(hit_pos: Vector3, target_node: Node3D) -> int:
	if target_node == null:
		return 0

	var center: Vector3 = target_node.global_position
	var normal: Vector3 = fixed_axis.normalized()
	var v: Vector3 = hit_pos - center
	var projection_vec: Vector3 = v - normal * v.dot(normal)
	var distance_to_center: float = projection_vec.length()

	var max_radius: float = 0.15
	var ring_width: float = max_radius / 10.0

	if distance_to_center >= max_radius:
		return 0

	var ring: int = 10 - int(distance_to_center / ring_width)
	return clampi(ring, 1, 10)


func _send_buff(
	def_i: float,
	atk: float,
	cool: float,
	duration: float,
	def_o: float,
	team_id: int
) -> void:
	for bot in get_tree().get_nodes_in_group("infantry"):
		if int(bot.get("team")) == team_id and bot.has_method("apply_buff"):
			bot.apply_buff(def_i, atk, cool, duration, team_id)

	for structure in get_tree().get_nodes_in_group("structure"):
		if int(structure.get("team")) != team_id:
			continue
		if structure.has_method("apply_buff"):
			structure.apply_buff(def_o, duration, team_id)


func reset_rune() -> void:
	for team_id in [Team.Id.BLUE, Team.Id.RED]:
		activation_id[team_id] += 1
		current_state[team_id] = RuneState.IDLE
		activation_started_at[team_id] = 0.0
		buff_end_at[team_id] = 0.0
		large_motion_started_at[team_id] = 0.0
		large_motion_a[team_id] = 0.780
		large_motion_omega[team_id] = 1.884
		is_target_hit[team_id] = false
		is_failed[team_id] = false
		first_hit_name[team_id] = 0
		hit_cnt[team_id] = 0
		tot_hit[team_id] = 0
		target_hited[team_id] = ""
		hit_legal[team_id] = [false, false, false, false, false, false]
		large_activation_count[team_id] = 0
		activation_is_large[team_id] = false

		for i in range(small_gain[team_id].size()):
			small_gain[team_id][i] = false
		for i in range(large_gain[team_id].size()):
			large_gain[team_id][i] = false

		small_chance[team_id] = 0
		large_chance[team_id] = 0

		_set_idle_state(team_id)

	spin_direction = 1 if randi() % 2 == 0 else -1
	angle_1 = 0.0
	angle_2 = 0.0
	if face_1:
		apply_rotation(face_1, init_transform_1, 0.0)
	if face_2:
		apply_rotation(face_2, init_transform_2, 0.0)
