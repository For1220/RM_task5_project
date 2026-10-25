extends CanvasLayer

## 比赛结束面板。
##
## 使用方式：
## 1. 把 scenes/GameOverPanel.tscn 实例化到 HUD 下；
## 2. 面板会自动连接 MatchState.phase_changed；
## 3. 当 MatchState 进入 ENDED 时自动显示；
## 4. 外部也可以直接调用 show_result()。
##
## 这个脚本不直接引用 MatchState 类标识符，而是通过 /root/MatchState
## 动态读取，避免 MatchState 暂时不可用时导致本面板也无法编译。

signal restart_requested

const TEAM_BLUE := 0
const TEAM_RED := 1
const WINNER_UNKNOWN := -2

@onready var result_label: Label = $Root/Center/Card/Margin/VBox/ResultLabel
@onready var winner_label: Label = $Root/Center/Card/Margin/VBox/WinnerLabel
@onready var reason_label: Label = $Root/Center/Card/Margin/VBox/ReasonLabel
@onready var perspective_label: Label = $Root/Center/Card/Margin/VBox/PerspectiveLabel
@onready var restart_button: Button = $Root/Center/Card/Margin/VBox/RestartButton
@onready var hint_label: Label = $Root/Center/Card/Margin/VBox/HintLabel

var _match_state: Node = null
var _is_result_visible := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_is_result_visible = false

	restart_button.pressed.connect(_on_restart_pressed)

	_match_state = get_tree().root.get_node_or_null("MatchState")
	if _match_state != null:
		if _match_state.has_signal("phase_changed"):
			var callable := Callable(self, "_on_phase_changed")
			if not _match_state.is_connected("phase_changed", callable):
				_match_state.connect("phase_changed", callable)

		# 如果面板是在比赛结束后才被实例化的，也要立即显示结果。
		_on_phase_changed(_get_phase_name())


func _on_phase_changed(phase: String) -> void:
	if phase == "ENDED":
		_show_result()
	else:
		visible = false
		_is_result_visible = false


## 外部直接调用入口。
## winner_team: 0=蓝方，1=红方，-1=平局
## view_team: 最后操纵视角，0=蓝方，1=红方
func show_result(winner_team: int = WINNER_UNKNOWN, view_team: int = WINNER_UNKNOWN, reason: String = "") -> void:
	if winner_team == WINNER_UNKNOWN:
		winner_team = _read_winner_from_match_state()

	if view_team == WINNER_UNKNOWN:
		view_team = _read_view_team_from_match_state()

	if reason.is_empty():
		reason = _read_reason_from_match_state()

	_apply_result(winner_team, view_team, reason)
	visible = true
	_is_result_visible = true
	restart_button.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_result() -> void:
	visible = false
	_is_result_visible = false


func _show_result() -> void:
	show_result()


func _read_winner_from_match_state() -> int:
	if _match_state == null:
		return -1

	var value = _match_state.get("winner_team")
	if value != null:
		return int(value)

	# 兼容尚未添加 winner_team 字段的旧 MatchState。
	if _match_state.has_method("determine_winner"):
		return int(_match_state.call("determine_winner"))

	return -1


func _read_view_team_from_match_state() -> int:
	if _match_state != null:
		var value = _match_state.get("last_controlled_team")
		if value != null:
			return int(value)

	var player := get_tree().get_first_node_in_group("Player")
	if player != null:
		var team_value = player.get("team")
		if team_value != null:
			return int(team_value)

	return TEAM_BLUE


func _read_reason_from_match_state() -> String:
	if _match_state == null:
		return ""
	var value = _match_state.get("result_reason")
	if value == null:
		return ""
	return str(value)


func _get_phase_name() -> String:
	if _match_state == null:
		return ""
	if _match_state.has_method("phase_name"):
		return str(_match_state.call("phase_name"))
	return ""


func _apply_result(winner_team: int, view_team: int, reason: String) -> void:
	var is_draw := winner_team == -1
	var is_victory := not is_draw and winner_team == view_team

	if is_draw:
		result_label.text = "DRAW"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.32))
		winner_label.text = "双方平局"
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	elif is_victory:
		result_label.text = "VICTORY"
		result_label.add_theme_color_override("font_color", Color(0.34, 1.0, 0.62))
		winner_label.text = "红方胜利" if winner_team == TEAM_RED else "蓝方胜利"
		winner_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.54, 0.62) if winner_team == TEAM_RED else Color(0.45, 0.78, 1.0)
		)
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.34, 0.4))
		winner_label.text = "红方胜利" if winner_team == TEAM_RED else "蓝方胜利"
		winner_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.54, 0.62) if winner_team == TEAM_RED else Color(0.45, 0.78, 1.0)
		)

	reason_label.text = _reason_text(reason)
	perspective_label.text = "最后操纵视角：%s" % ("红方" if view_team == TEAM_RED else "蓝方")
	hint_label.text = "点击重新开始 / CLICK TO RESTART"


func _reason_text(reason: String) -> String:
	match reason:
		"base_destroyed":
			return "比赛结束 · 基地被摧毁"
		"time_up":
			return "比赛结束 · 时间耗尽"
		"timeout":
			return "比赛结束 · 时间耗尽"
		_:
			return "比赛结束"


func _on_restart_pressed() -> void:
	restart_requested.emit()
	hide_result()

	# 优先复用现有 HUD 的重新开始流程：会重置机器人、基地、前哨站和能量机关。
	var hud := _find_hud()
	if hud != null and hud.has_method("_on_start_pressed"):
		hud.call("_on_start_pressed")
		return

	# 兜底：如果面板不是挂在 HUD 下，直接重新加载当前场景。
	var scene := get_tree().current_scene
	if scene != null:
		get_tree().reload_current_scene()


func _find_hud() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("_on_start_pressed"):
			return node
		node = node.get_parent()

	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("HUD")
