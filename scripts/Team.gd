
class_name Team

enum Id{
	BLUE,
	RED,
}

static func side_name(team_id:int)->String:
	return "blue" if team_id==Id.BLUE else "red"
static func team_group(team_id:int)->StringName:
	return StringName("team_"+side_name(team_id))
static func object_group(team_id:int,kind:String)->StringName:
	return StringName(side_name(team_id)+"_"+kind)
static func is_enemy(a:int,b:int)->bool:
	return a!=b
