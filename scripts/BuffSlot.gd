extends Panel

const SLOT_CORNER_RADIUS := 9
const SHADE_COLOR := Color(0.42, 0.46, 0.52, 0.76)
const TRACK_COLOR := Color("#061019")

@onready var icon:TextureRect=$IconClip/Icon
@onready var shade:ColorRect=$IconClip/Shade
@onready var time_label:Label=$TimeLabel

var _style:StyleBoxFlat
var _accent:Color=Color.TRANSPARENT

func _ready()->void:
	_ensure_style()
	mouse_filter=Control.MOUSE_FILTER_PASS
	clear()
	
func set_state(texture:Texture2D,remaining:float,total:float,accent:Color,tooltip:String="")->void:
	if texture==null:
		clear()
		return
	if remaining<=0.0:
		clear()
		return
	visible=true
	icon.texture=texture
	icon.modulate=Color.WHITE
	time_label.visible=true
	
	var dura:=maxf(maxf(total,remaining),0.001)
	var ratio:=clampf(remaining/dura,0.0,1.0)
	var elapsed_ratio:=1.0-ratio
	_update_shade(elapsed_ratio)
	time_label.text=_format_time(remaining)
	_set_accent(accent)
	if tooltip.is_empty():
		tooltip_text="剩余 %s"%_format_time(remaining)
	else :
		tooltip_text=tooltip

func clear()->void:
	visible=false
	shade.visible=false
	time_label.text=""
	time_label.visible=false
	tooltip_text=""
	
func _ensure_style() -> void:
	if _style != null:
		return
	_style = StyleBoxFlat.new()
	_style.bg_color = TRACK_COLOR
	_style.border_width_left = 1
	_style.border_width_top = 1
	_style.border_width_right = 1
	_style.border_width_bottom = 1
	_style.set_corner_radius_all(SLOT_CORNER_RADIUS)
	_style.shadow_size = 5
	_style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", _style)
func _update_shade(elapsed_ratio: float) -> void:
	elapsed_ratio = clampf(elapsed_ratio, 0.0, 1.0)
	shade.visible = elapsed_ratio > 0.001
	shade.color = SHADE_COLOR

	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.0
	shade.anchor_bottom = elapsed_ratio
	shade.offset_left = 0.0
	shade.offset_top = 0.0
	shade.offset_right = 0.0
	shade.offset_bottom = 0.0
func _set_accent(accent: Color) -> void:
	if _style == null:
		_ensure_style()
	if accent == _accent:
		return

	_accent = accent
	_style.border_color = accent
	_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.24)
func _format_time(seconds: float) -> String:
	var total_seconds := int(ceil(maxf(seconds, 0.0)))
	if total_seconds >= 60:
		var minutes := int(total_seconds / 60.0)
		var rest := total_seconds % 60
		return "%d:%02d" % [minutes, rest]
	return "%ds" % total_seconds	
