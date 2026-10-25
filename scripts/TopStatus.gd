extends Control

const C_READY := Color("#4DDCFF")
const C_RUNNING := Color("#62E6A6")
const C_PAUSED := Color("#FFB454")
const C_ENDED := Color("#FF5E7A")
const C_TEXT := Color("#F4FBFF")

@onready var timer_label: Label = $VBox/TimerLabel
@onready var status_dot: Panel = $VBox/StatusRow/StatusDot
@onready var status_label: Label = $VBox/StatusRow/StatusLabel

var _dot_style: StyleBoxFlat


func _ready() -> void:
	_dot_style = StyleBoxFlat.new()
	_dot_style.set_corner_radius_all(4)
	_dot_style.shadow_size = 6
	status_dot.add_theme_stylebox_override("panel", _dot_style)

	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)


func _process(_delta: float) -> void:
	var snap := SnapshotHub.current
	if snap.is_empty():
		snap=MatchState.snapshot()
	
	var left := maxf(float(snap.time_left), 0.0)
	var seconds := ceili(left)
	var phase := String(snap.phase)

	timer_label.text = "%02d:%02d" % [
		floori(seconds / 60.0),
		seconds % 60
	]

	var status_color := C_READY
	match phase:
		"READY":
			status_color = C_READY
		"RUNNING":
			status_color = C_RUNNING
		"PAUSED":
			status_color = C_PAUSED
		"ENDED":
			status_color = C_ENDED

	status_label.text = phase
	status_label.add_theme_color_override("font_color", status_color)

	_dot_style.bg_color = status_color
	_dot_style.shadow_color = Color(
		status_color.r,
		status_color.g,
		status_color.b,
		0.35
	)

	# 时间颜色：正常冷白，最后 60 秒橙色，最后 10 秒红色
	var timer_color := C_TEXT
	if phase == "ENDED" or seconds <= 10:
		timer_color = C_ENDED
	elif seconds <= 60:
		timer_color = C_PAUSED
	elif phase == "PAUSED":
		timer_color = C_PAUSED

	timer_label.add_theme_color_override("font_color", timer_color)


func _apply_layout() -> void:
	var compact := get_viewport().get_visible_rect().size.x < 1500.0
	var half_width := 110.0 if compact else 120.0
	var top := 18.0 if compact else 24.0

	offset_left = -half_width
	offset_right = half_width
	offset_top = top
	offset_bottom = top + 72.0
