extends Node
const LEVEL_XP:Array[int]=[
	0,550,1100,1650,2200,
	2750,3300,3850,4400,5000
]

var small_bonus_end :={
	Team.Id.BLUE:0.0,
	Team.Id.RED:0.0,
}
var small_bonus_remaining:={
	Team.Id.BLUE:0.0,
	Team.Id.RED:0.0,
}

func level_for_exp(total_exp:float)->int:
	for i in range(LEVEL_XP.size()-1,-1,-1):
		if total_exp>=LEVEL_XP[i]:
			return i+1
	return 1

func level_start_exp(level:int)->float:
	level=clampi(level,1,LEVEL_XP.size())
	return float(LEVEL_XP[level-1])
func level_next_exp(level:int)->float:
	if level >= LEVEL_XP.size():
		return float(LEVEL_XP[LEVEL_XP.size()-1])
	return float(LEVEL_XP[level])
func kill_exp(killer_level:int,victim_level:int)->float:
	var diff:=maxi(victim_level-killer_level,0)
	return roundf(50.0*victim_level*(1.0+0.2*diff))

func start_small_rune_bonus(team_id:int,dura:float=45.0)->void:
	small_bonus_end[team_id]=MatchState.elapsed+dura
	small_bonus_remaining[team_id]=1200.0
func consume_small_bonus(team_id:int,base_exp:float)->float:
	if base_exp<=0.0: return 0.0
	if MatchState.elapsed>small_bonus_end.get(team_id,0.0):
		return 0.0
	var remaining:float=small_bonus_remaining.get(team_id,0.0)
	if remaining<=0.0: return 0.0
	var extra:float=minf(base_exp,remaining)
	small_bonus_remaining[team_id]=remaining-extra
	return extra
func award_large_rune_exp(team_id:int,total_exp:float=750.0)->void:
	var targets:Array[Node]=[]
	for unit in get_tree().get_nodes_in_group("infantry"):
		if int(unit.get("team"))==team_id and not bool(unit.get("is_dead")):
			targets.append(unit)
	if targets.is_empty():return
	var send_exp:float=total_exp/float(targets.size())
	for unit in targets:
		if unit.has_method("exp_gain"):
			unit.exp_gain(send_exp)
func reset_for_match()->void:
	for team_id in [Team.Id.BLUE,Team.Id.RED]:
		small_bonus_end[team_id]=0.0
		small_bonus_remaining[team_id]=0.0
	
