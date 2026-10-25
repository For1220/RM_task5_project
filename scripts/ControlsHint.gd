extends Control

@export var compact_width: float = 1500.0
@export var compact_scale: float = 0.72
@export var compact_shift: float = 40.0

const BASE_HALF_WIDTH := 470.0


func _ready() -> void:
	get_viewport().size_changed.connect(_apply_scale)
	call_deferred("_apply_scale")


func _process(_delta: float) -> void:
	var hud := get_parent()
	if hud == null:
		return

	var start_panel := hud.get_node_or_null("StartPanel") as Control
	if is_instance_valid(start_panel):
		visible = not start_panel.visible


func _apply_scale() -> void:
	var compact := get_viewport().get_visible_rect().size.x < compact_width

	scale = Vector2.ONE * (compact_scale if compact else 1.0)

	var shift := compact_shift if compact else 0.0
	offset_left = -BASE_HALF_WIDTH + shift
	offset_right = BASE_HALF_WIDTH + shift

	pivot_offset = Vector2(size.x * 0.5, size.y)
