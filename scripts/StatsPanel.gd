extends VBoxContainer

const LOW_HP_RATIO := 0.25

const C_TEXT := Color("#F4FBFF")
const C_DANGER_TEXT := Color("#FFD7DE")
const C_HP := Color("#62E6A6")
const C_AMMO := Color("#4DDCFF")
const C_HEAT := Color("#FFB454")
const C_DANGER := Color("#FF5E7A")
const C_TRACK := Color("#061019")

@onready var hp_bar: ProgressBar = $HPRow/HPBar
@onready var hp_status: Label = $HPRow/HPBar/StatusLabel
@onready var hp_value: Label = $HPRow/HPBar/ValueLabel

@onready var ammo_bar: ProgressBar = $AmmoRow/AmmoBar
@onready var ammo_status: Label = $AmmoRow/AmmoBar/StatusLabel
@onready var ammo_value: Label = $AmmoRow/AmmoBar/ValueLabel

@onready var heat_bar: ProgressBar = $HeatRow/HeatBar
@onready var heat_status: Label = $HeatRow/HeatBar/StatusLabel
@onready var heat_value: Label = $HeatRow/HeatBar/ValueLabel

@onready var live_dot:Panel=$Header/LiveBox/LiveDot
@onready var live_label:Label=$Header/LiveBox/LiveLabel
const C_LIVE:=Color("#62E6A6")
const C_DEAD:=Color("#FF5E7A")
var _live_style:StyleBoxFlat

# exp
@onready var exp_bar:ProgressBar=$ExpRow/XPBAR
@onready var exp_value:Label=$ExpRow/XPBar/ValueLabel
@onready var level_label:Label=$Header/LevelLabel

var _hp_fill: StyleBoxFlat
var _ammo_fill: StyleBoxFlat
var _heat_fill: StyleBoxFlat
var _danger_fill: StyleBoxFlat


func _ready() -> void:
	_hp_fill = _make_fill(C_HP)
	_ammo_fill = _make_fill(C_AMMO)
	_heat_fill = _make_fill(C_HEAT)
	_danger_fill = _make_fill(C_DANGER)

	_setup_bar(hp_bar, _hp_fill)
	_setup_bar(ammo_bar, _ammo_fill)
	_setup_bar(heat_bar, _heat_fill)

	_style_label(hp_status, 8)
	_style_label(ammo_status, 8)
	_style_label(heat_status, 8)
	_style_label(hp_value, 11)
	_style_label(ammo_value, 11)
	_style_label(heat_value, 11)

	_setup_live_dot()

	alignment = BoxContainer.ALIGNMENT_END
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()


func _setup_bar(bar: ProgressBar, fill: StyleBoxFlat) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = C_TRACK
	track.border_color = Color(1, 1, 1, 0.055)
	track.set_border_width_all(1)
	track.set_corner_radius_all(7)

	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	bar.show_percentage = false
	bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_fill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	return box


func _style_label(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.72))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_live_dot() -> void:
	var dot := get_node_or_null("Header/LiveBox/LiveDot") as Panel
	if dot == null:
		return
	_live_style=StyleBoxFlat.new()
	_live_style.bg_color=C_LIVE
	_live_style.set_corner_radius_all(4)
	_live_style.shadow_color=Color(0.38,0.90,0.65,0.35)
	_live_style.shadow_size=6
	live_dot.add_theme_stylebox_override("panel",_live_style)


func apply_snapshot(s:Dictionary) -> void:
	# 血量
	var hp_max := maxi(int(s.get("max_hp", 1)), 1)
	var hp := clampi(int(s.get("hp", 0)), 0, hp_max)
	hp_bar.max_value = float(hp_max)
	hp_bar.value = float(hp)
	hp_value.text = "%d/%d" % [hp, hp_max]
	_set_warning(
		hp_bar,
		hp_status,
		hp_value,
		hp <= int(round(float(hp_max) * LOW_HP_RATIO)),
		"LOW HP",
		_hp_fill
	)

	# 弹药
	var ammo_max := maxi(int(s.get("max_ammo", 1)), 1)
	var ammo := clampi(int(s.get("ammo", 0)), 0, ammo_max)
	ammo_bar.max_value = float(ammo_max)
	ammo_bar.value = float(ammo)
	ammo_value.text = "%d/%d" % [ammo, ammo_max]
	_set_warning(
		ammo_bar,
		ammo_status,
		ammo_value,
		ammo <= 0,
		"EMPTY",
		_ammo_fill
	)

	# 热量
	var heat_max := maxf(float(s.get("heat_limit", 1.0)), 1.0)
	var heat_raw := float(s.get("heat", 0.0))
	var locked := bool(s.get("is_locked", false))
	var heat := clampf(heat_raw, 0.0, heat_max)
	if locked:
		heat = heat_max

	heat_bar.max_value = heat_max
	heat_bar.value = heat
	heat_value.text = "%d/%d" % [int(round(heat)), int(round(heat_max))]

	var overheated := bool(s.get("is_overheated", false)) or heat_raw >= heat_max
	var heat_text := "LOCKED" if locked else ("OVERHEAT" if overheated else "")
	_set_warning(
		heat_bar,
		heat_status,
		heat_value,
		heat_text != "",
		heat_text,
		_heat_fill
	)
	# 阵亡
	var dead := bool(s.get("is_dead", false))
	_update_live_state(not dead)
	# exp
	var level := int(s.get("level", 1))
	var total_exp := float(s.get("total_exp", 0.0))
	var start_exp := ExpSystem.level_start_exp(level)
	var next_exp := ExpSystem.level_next_exp(level)

	level_label.text = "LV.%d" % level
	if level >= 10:
		exp_bar.max_value = 1.0
		exp_bar.value = 1.0
		exp_value.text = "MAX"
	else:
		exp_bar.max_value = next_exp - start_exp
		exp_bar.value = total_exp - start_exp
		exp_value.text = "%d/%d" % [
			int(total_exp - start_exp),
			int(next_exp - start_exp)
		]
func _update_live_state(alive:bool)->void:
	if live_label:
		live_label.text="LIVE" if alive else "DEAD"
		live_label.add_theme_color_override(
			"font_color",
			C_LIVE if alive else C_DEAD
		)
	if _live_style:
		_live_style.bg_color=C_LIVE if alive else C_DEAD
		_live_style.shadow_color=(
			Color(0.38,0.90,0.65,0.35)
			if alive
			else Color(1.0,0.37,0.48,0.42)
		)

func _set_warning(
	bar: ProgressBar,
	status: Label,
	value: Label,
	active: bool,
	text: String,
	normal_fill: StyleBoxFlat
) -> void:
	status.visible = active
	status.text = text if active else ""
	status.add_theme_color_override("font_color", C_DANGER_TEXT if active else C_TEXT)
	value.add_theme_color_override("font_color", C_DANGER_TEXT if active else C_TEXT)
	bar.add_theme_stylebox_override("fill", _danger_fill if active else normal_fill)


func _apply_layout() -> void:
	var compact := get_viewport().get_visible_rect().size.x < 1500.0
	var width := 280.0 if compact else 320.0
	var margin := 24.0 if compact else 32.0

	offset_left = -width - margin
	offset_right = -margin
	offset_top = -170.0 if compact else -190.0
	offset_bottom = -margin

	
