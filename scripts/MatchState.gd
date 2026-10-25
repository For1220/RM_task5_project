extends Node

signal phase_changed(phase:String)
signal match_ended()

enum Phase{ READY,RUNNING,PAUSED,ENDED }

@export var duration_s:float=420.0
var time_left:float=duration_s
var elapsed:float=0.0
var phase:Phase=Phase.READY
var running:bool=false
var paused:bool=false
var team_damage={
	Team.Id.BLUE:0,
	Team.Id.RED:0
}
var winner_team: int = -1
var result_reason: String = ""
var last_controlled_team: int = Team.Id.BLUE

func _ready()->void:
	add_to_group("match_state")
	reset_match()

func _physics_process(delta:float)->void:
	if not running or paused or phase != Phase.RUNNING:
		return
	time_left=maxf(time_left-delta,0.0)
	elapsed+=delta
	if time_left<=0.0: finish_match("time_up")
func reset_match()->void:
	time_left=duration_s
	elapsed=0.0

	winner_team = -1
	result_reason = ""
	team_damage[Team.Id.BLUE] = 0.0
	team_damage[Team.Id.RED] = 0.0

	phase=Phase.READY
	running=false
	paused=false
	phase_changed.emit(phase_name())
	
func begin_match()->void:
	reset_match()
	running=true
	paused=false
	phase=Phase.RUNNING
	phase_changed.emit(phase_name())

func pause_match()->void:
	if phase != Phase.RUNNING: return
	paused=true
	phase=Phase.PAUSED
	phase_changed.emit(phase_name())
func resume_match()->void:
	if phase!=Phase.PAUSED: return
	paused=false
	phase=Phase.RUNNING
	phase_changed.emit(phase_name())

func record_damage(team_id: int, amount: float) -> void:
	if amount <= 0.0:
		return
	if team_id != Team.Id.BLUE and team_id != Team.Id.RED:
		return
	team_damage[team_id] += amount

func phase_name()->String:
	match phase:
		Phase.READY: return "READY"
		Phase.RUNNING: return "RUNNING"
		Phase.PAUSED: return "PAUSED"
		Phase.ENDED: return "ENDED"
	return "READY"

func snapshot()->Dictionary:
	return {
		"schema_version":1,
		"phase":phase_name(),
		"time_left":time_left,
		"elapsed":elapsed,
		"winner_team": winner_team,
		"result_reason": result_reason,
		"last_controlled_team": last_controlled_team
	}
	
func _get_base(team_id: int) -> Node:
	return get_tree().get_first_node_in_group(
		Team.object_group(team_id, "base")
	)

func _get_outpost(team_id: int) -> Node:
	return get_tree().get_first_node_in_group(
		Team.object_group(team_id, "outpost")
	)

func _team_robot_hp(team_id: int) -> int:
	var total := 0
	for unit in get_tree().get_nodes_in_group("infantry"):
		if int(unit.get("team")) == team_id:
			total += maxi(int(unit.get("hp")), 0)
	return total
func determine_winner() -> int:
	var blue_base := _get_base(Team.Id.BLUE)
	var red_base := _get_base(Team.Id.RED)

	var blue_base_hp := int(blue_base.get("current_hp")) if blue_base else 0
	var red_base_hp := int(red_base.get("current_hp")) if red_base else 0

	# 1. 基地血量
	if blue_base_hp > red_base_hp:
		return Team.Id.BLUE
	if red_base_hp > blue_base_hp:
		return Team.Id.RED

	var blue_outpost := _get_outpost(Team.Id.BLUE)
	var red_outpost := _get_outpost(Team.Id.RED)

	var blue_out_hp := int(blue_outpost.get("current_hp")) if blue_outpost else 0
	var red_out_hp := int(red_outpost.get("current_hp")) if red_outpost else 0

	var blue_ever := bool(blue_outpost.get("ever_destroyed")) if blue_outpost else true
	var red_ever := bool(red_outpost.get("ever_destroyed")) if red_outpost else true

	# 2. 双方前哨站都未被击毁
	if not blue_ever and not red_ever:
		if blue_out_hp > red_out_hp:
			return Team.Id.BLUE
		if red_out_hp > blue_out_hp:
			return Team.Id.RED

	# 3. 只有一方前哨站被击毁过
	if blue_ever != red_ever:
		return Team.Id.BLUE if not blue_ever else Team.Id.RED

	# 4. 全队攻击伤害
	var blue_damage := float(team_damage[Team.Id.BLUE])
	var red_damage := float(team_damage[Team.Id.RED])
	if blue_damage > red_damage:
		return Team.Id.BLUE
	if red_damage > blue_damage:
		return Team.Id.RED

	# 5. 全队总剩余血量
	var blue_hp := _team_robot_hp(Team.Id.BLUE)
	var red_hp := _team_robot_hp(Team.Id.RED)
	if blue_hp > red_hp:
		return Team.Id.BLUE
	if red_hp > blue_hp:
		return Team.Id.RED

	# 6. 平局
	return -1
func finish_match(reason: String) -> void:
	if phase == Phase.ENDED:
		return

	winner_team = determine_winner()
	result_reason = reason

	running = false
	paused = false
	phase = Phase.ENDED

	phase_changed.emit(phase_name())
	match_ended.emit()
