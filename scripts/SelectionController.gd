extends Node

@export var allow_enemy_selection: bool = true
@export var panel_path:NodePath=^"../HUD/SelectionPanel"
@onready var panel:Control=get_node_or_null(panel_path)

# 行节点的引用和选择
@onready var blue_row:PanelContainer=panel.get_node_or_null(
	"Center/Card/Margin/VBox/BlueRow"
) if panel else null
@onready var red_row:PanelContainer=panel.get_node_or_null(
	"Center/Card/Margin/VBox/RedRow"
) if panel else null
var menu_open:bool=false
var previous_mouse_mode:int=Input.MOUSE_MODE_VISIBLE

func _ready()->void:
	add_to_group("selection_controller")
	process_mode=Node.PROCESS_MODE_ALWAYS
	if panel: panel.visible=false
	if blue_row:
		blue_row.gui_input.connect( _on_row_gui_input.bind(Team.Id.BLUE) )
	if red_row:
		red_row.gui_input.connect( _on_row_gui_input.bind(Team.Id.RED) )

func _on_row_gui_input(event:InputEvent,team_id:int)->void:
	if not menu_open: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			_select_team(team_id)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if event.physical_keycode==KEY_C:
		if MatchState.phase_name()=="RUNNING":
			_toggle_menu()
			get_viewport().set_input_as_handled()
		return
	if not menu_open:return
	if event.physical_keycode==KEY_1:
		_select_team(Team.Id.BLUE)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_2:
		_select_team(Team.Id.RED)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_ESCAPE:
		_set_menu_open(false)
		get_viewport().set_input_as_handled()
func _toggle_menu()->void:
	_set_menu_open(not menu_open)
func _set_menu_open(value:bool)->void:
	menu_open=value
	if panel: panel.visible=value
	if value:
		previous_mouse_mode=Input.mouse_mode
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		get_tree().paused=true
		_refresh_panel()
	else :
		get_tree().paused=false
		Input.mouse_mode=previous_mouse_mode
	
func _select_team(team_id: int) -> void:
	if MatchState.phase_name() != "RUNNING":
		return

	var target := _find_team_infantry(team_id)
	if target == null:
		print("[选择] 没有找到队伍 ", Team.side_name(team_id), " 的步兵")
		return

	if not allow_enemy_selection and team_id != Team.Id.BLUE:
		return
	MatchState.last_controlled_team = team_id
	for unit in get_tree().get_nodes_in_group("infantry"):
		if unit.has_method("set_controlled"):
			unit.set_controlled(unit == target)

	print("[选择] 当前控制：", target.name,
		" | team=", Team.side_name(team_id))
	_set_menu_open(false)
func _refresh_panel()->void:
	var current:=get_tree().get_first_node_in_group("Player")
	var current_team:=-1
	if current:
		current_team=int(current.get("team"))
	var blue:=_find_team_infantry(Team.Id.BLUE)
	_update_row(Team.Id.BLUE,blue,current_team==Team.Id.BLUE)
	var red:=_find_team_infantry(Team.Id.RED)
	_update_row(Team.Id.RED,red,current_team==Team.Id.RED)
	
func _find_alive_infantry(team_id: int) -> Node:
	for unit in get_tree().get_nodes_in_group("infantry"):
		if int(unit.get("team")) != team_id:
			continue

		var hp = unit.get("hp")
		if hp != null and int(hp) <= 0:
			continue

		return unit

	return null
func _find_team_infantry(team_id:int)->Node:
	for unit in get_tree().get_nodes_in_group("infantry"):
		if int(unit.get("team"))==team_id:
			return unit
	return null
func _update_row(team_id:int,unit:Node,is_current:bool)->void:
	if panel==null: return
	var prefix:="Blue" if team_id==Team.Id.BLUE else "Red"
	var row:=panel.get_node_or_null("Center/Card/Margin/VBox/%sRow"%prefix) as PanelContainer
	if row == null :return
	var status:=row.get_node_or_null(
		"%sMargin/HBox/%sInfo/Status"%[prefix,prefix]
	)as Label
	var current_label:=row.get_node_or_null(
		"%sMargin/HBox/%sCurrent"%[prefix,prefix]
	)as Label
	if status==null or current_label==null: return
	if unit==null:
		print("未找到")
		row.modulate=Color(0.45,0.45,0.45,1.0)
		current_label.visible = false
		return
	var hp=unit.get("hp")
	if hp!=null and int(hp)<=0:
		status.text="阵亡"
		row.modulate=Color(0.45, 0.45, 0.45, 1.0)
	else :
		status.text="存活"
		row.modulate=Color.WHITE
	if is_current and hp!=null and int(hp)>0:
		row.modulate=Color(1.0,1.0,1.0,1.0)
func open_menu()->void:
	if MatchState.phase_name()!="RUNNING":return
	_set_menu_open(true)
