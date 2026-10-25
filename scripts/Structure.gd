class_name Structure
extends Node3D

signal hp_changed(current_hp:int,max_hp:int)
signal destroyed(team_id:int)
signal rebuilt(team_id:int)

@export_enum("Blue","Red") var team:int=Team.Id.BLUE
@export var structure_kind:StringName=&"outpost"
@export var max_hp:int=1500

var current_hp:int
var defense_buff:float=0.0
var buff_time_left:float=0.0
var is_destroyed:bool=false

func _ready()->void:
	current_hp=max_hp
	add_to_group("structure")
	add_to_group(Team.team_group(team))
	add_to_group(Team.object_group(team,String(structure_kind)))
	
func tick_buff(delta:float)->void:
	if buff_time_left<=0.0: return
	buff_time_left-=delta
	if buff_time_left<=0.0: defense_buff=0.0

func take_damage(amount:int,source_team:int=-1,source:Node=null)->int:
	if is_destroyed: return 0
	if source_team==team:return 0
	var before:=current_hp
	var actual:=int(amount*(1.0-defense_buff))
	current_hp=maxi(current_hp-actual,0)
	hp_changed.emit(current_hp,max_hp)
	var actual_damage:=before-current_hp
	MatchState.record_damage(source_team,actual_damage)
	if current_hp<=0: destroy_structure()
	return before-current_hp

func apply_buff(defense:float,dura:float,source_team:int)->void:
	if source_team!=team: return
	defense_buff=maxf(defense_buff,defense)
	buff_time_left=maxf(buff_time_left,dura)

func destroy_structure()->void:
	if is_destroyed: return
	is_destroyed=true
	current_hp=0
	destroyed.emit(team)
func reset_structure()->void:
	is_destroyed=false
	current_hp=max_hp
	defense_buff=0.0
	buff_time_left=0.0
