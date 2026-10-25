extends Control

@onready var mode_fixed: Button = $Center/Card/Margin/VBox/ModeFixed
@onready var mode_random_fixed: Button = $Center/Card/Margin/VBox/ModeRandomFixed
@onready var mode_random_moving: Button = $Center/Card/Margin/VBox/ModeRandomMoving
@onready var mode_end_moving: Button = $Center/Card/Margin/VBox/ModeEndMoving
@onready var hint: Label = $Center/Card/Margin/VBox/Hint

var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	mode_fixed.pressed.connect(_on_mode.bind("固定目标"))
	mode_random_fixed.pressed.connect(_on_mode.bind("随机固定目标"))
	mode_random_moving.pressed.connect(_on_mode.bind("随机移动目标"))
	mode_end_moving.pressed.connect(_on_mode.bind("末端移动目标"))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	if event.is_action_pressed("dart_launch"):
		if visible:
			_close()
		elif MatchState.phase_name() == "RUNNING" and not get_tree().paused:
			_open()
		get_viewport().set_input_as_handled()
		return

	if visible and event.physical_keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _open() -> void:
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	get_tree().paused = true
	mode_fixed.grab_focus()

func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _previous_mouse_mode

func _on_mode(mode: String) -> void:
	_fire(mode)
	_close()

func _fire(mode: String) -> void:
	var target := _enemy_base()
	if target == null:
		get_tree().call_group(
			"notification_feed",
			"push_notification",
			"[DART] 未找到敌方基地"
		)
		return

	if mode in ["固定目标", "随机固定目标"]:
		# 固定类方案：模拟 4 发飞镖全部命中
		for i in range(4):
			if target.has_method("on_dart_hit"):
				target.call("on_dart_hit", mode, true)
	else:
		# 移动类方案：任意一发命中
		if target.has_method("on_dart_hit"):
			target.call("on_dart_hit", mode, true)

	get_tree().call_group(
		"notification_feed",
		"push_notification",
		"[DART] %s 命中敌方基地" % mode
	)

func _enemy_base() -> Node:
	var player := get_tree().get_first_node_in_group("Player")
	if player == null:
		return null

	var own_team := int(player.get("team"))
	var enemy_team := Team.Id.RED if own_team == Team.Id.BLUE else Team.Id.BLUE

	var path := "Teams/TeamBlue/BaseBlue" if enemy_team == Team.Id.BLUE else "Teams/TeamRed/BaseRed"
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(path)
