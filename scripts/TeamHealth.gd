extends Control

@onready var blue_base_bar: ProgressBar = $BlueGroup/BlueBaseRow/Bar
@onready var blue_base_value: Label = $BlueGroup/BlueBaseRow/Bar/Value
@onready var blue_base_icon: TextureRect = $BlueGroup/BlueBaseRow/Icon

@onready var blue_outpost_bar: ProgressBar = $BlueGroup/BlueOutpostRow/Bar
@onready var blue_outpost_value: Label = $BlueGroup/BlueOutpostRow/Bar/Value
@onready var blue_outpost_icon: TextureRect = $BlueGroup/BlueOutpostRow/Icon

@onready var red_base_bar: ProgressBar = $RedGroup/RedBaseRow/Bar
@onready var red_base_value: Label = $RedGroup/RedBaseRow/Bar/Value
@onready var red_base_icon: TextureRect = $RedGroup/RedBaseRow/Icon

@onready var red_outpost_bar: ProgressBar = $RedGroup/RedOutpostRow/Bar
@onready var red_outpost_value: Label = $RedGroup/RedOutpostRow/Bar/Value
@onready var red_outpost_icon: TextureRect = $RedGroup/RedOutpostRow/Icon

# 在 Inspector 里指定四个节点路径
@export var blue_base_path: NodePath
@export var blue_outpost_path: NodePath
@export var red_base_path: NodePath
@export var red_outpost_path: NodePath


func _process(_delta: float) -> void:
	if not SnapshotHub.current.is_empty():
		apply_snapshot(SnapshotHub.current)
	else:
		_update_all()
func apply_snapshot(s: Dictionary) -> void:
	var entities: Array = s.get("entities", [])

	var blue_outpost := _find_entity(entities, "blue", "outpost")
	var red_outpost := _find_entity(entities, "red", "outpost")
	var blue_base := _find_entity(entities, "blue", "base")
	var red_base := _find_entity(entities, "red", "base")

	_update_outpost_entity(blue_outpost, blue_outpost_bar, blue_outpost_value, blue_outpost_icon)
	_update_outpost_entity(red_outpost, red_outpost_bar, red_outpost_value, red_outpost_icon)
	_update_base_entity(blue_base, blue_base_bar, blue_base_value, blue_base_icon)
	_update_base_entity(red_base, red_base_bar, red_base_value, red_base_icon)
func _find_entity(entities: Array, team: String, kind: String) -> Dictionary:
	for e in entities:
		if String(e.get("team", "")) == team and String(e.get("kind", "")) == kind:
			return e
	return {}
func _update_outpost_entity(
	e: Dictionary,
	bar: ProgressBar,
	value: Label,
	icon: TextureRect
) -> void:
	if e.is_empty():
		_set_empty(bar, value, icon)
		return

	var current_hp := int(e.get("hp", 0))
	var max_hp := maxi(int(e.get("max_hp", 1)), 1)
	var destroyed := not bool(e.get("alive", true))
	var rotating := bool(e.get("is_rot", false))

	_set_bar(bar, value, current_hp, max_hp)

	if destroyed:
		icon.modulate = Color(0.38, 0.43, 0.48, 1)
		bar.modulate = Color(0.48, 0.52, 0.56, 1)
	elif not rotating:
		icon.modulate = Color(0.50, 0.56, 0.62, 1)
		bar.modulate = Color(0.58, 0.62, 0.66, 1)
	else:
		icon.modulate = Color.WHITE
		bar.modulate = Color.WHITE
func _update_base_entity(
	e: Dictionary,
	bar: ProgressBar,
	value: Label,
	icon: TextureRect
) -> void:
	if e.is_empty():
		_set_empty(bar, value, icon)
		return

	var current_hp := int(e.get("hp", 0))
	var max_hp := maxi(int(e.get("max_hp", 1)), 1)
	var shielded := bool(e.get("is_shielded", false))

	var armor_open := bool(e.get("armor_open", false))
	var shield_hp := int(e.get("shield_hp", 0))

	_set_bar(bar, value, current_hp, max_hp)

	value.text = "%d/%d" % [current_hp, max_hp]
	if shield_hp > 0:
		value.text += " | SHIELD %d" % shield_hp
	if armor_open:
		value.text += " | ARMOR OPEN"
	var invincible:=bool(e.get("is_invincible",false))
	if invincible:
		value.text+=" | INVINCIBLE"
	icon.modulate = Color(1.0, 0.7, 0.3, 1.0) if armor_open else Color.WHITE
	bar.modulate = Color(1, 1, 1, 0.76) if shielded else Color.WHITE
	
	


func _update_all() -> void:
	_update_outpost(
		get_node_or_null(blue_outpost_path),
		blue_outpost_bar,
		blue_outpost_value,
		blue_outpost_icon
	)
	_update_outpost(
		get_node_or_null(red_outpost_path),
		red_outpost_bar,
		red_outpost_value,
		red_outpost_icon
	)
	_update_base(
		get_node_or_null(blue_base_path),
		blue_base_bar,
		blue_base_value,
		blue_base_icon
	)
	_update_base(
		get_node_or_null(red_base_path),
		red_base_bar,
		red_base_value,
		red_base_icon
	)


func _update_outpost(
	outpost: Node,
	bar: ProgressBar,
	value: Label,
	icon: TextureRect
) -> void:
	if outpost == null:
		_set_empty(bar, value, icon)
		return

	var current_hp := int(outpost.get("current_hp"))
	var max_hp := maxi(int(outpost.get("max_hp")), 1)
	var destroyed := bool(outpost.get("is_destroyed"))
	var rotating := bool(outpost.get("is_rot"))

	_set_bar(bar, value, current_hp, max_hp)

	if destroyed:
		icon.modulate = Color(0.38, 0.43, 0.48, 1)
		bar.modulate = Color(0.48, 0.52, 0.56, 1)
	elif not rotating:
		icon.modulate = Color(0.50, 0.56, 0.62, 1)
		bar.modulate = Color(0.58, 0.62, 0.66, 1)
	else:
		icon.modulate = Color.WHITE
		bar.modulate = Color.WHITE


func _update_base(
	base: Node,
	bar: ProgressBar,
	value: Label,
	icon: TextureRect
) -> void:
	if base == null:
		_set_empty(bar, value, icon)
		return

	var current_hp := int(base.get("current_hp"))
	var max_hp := maxi(int(base.get("max_hp")), 1)
	var shielded := bool(base.get("is_shielded")) if base.get("is_shielded") != null else false

	_set_bar(bar, value, current_hp, max_hp)
	icon.modulate = Color.WHITE

	# 护盾存在时基地条稍微变淡；没有护盾时恢复不透明
	bar.modulate = Color(1, 1, 1, 0.76) if shielded else Color.WHITE


func _set_bar(
	bar: ProgressBar,
	value: Label,
	current_hp: int,
	max_hp: int
) -> void:
	current_hp = clampi(current_hp, 0, max_hp)
	bar.max_value = float(max_hp)
	bar.value = float(current_hp)
	value.text = "%d/%d" % [current_hp, max_hp]


func _set_empty(
	bar: ProgressBar,
	value: Label,
	icon: TextureRect
) -> void:
	bar.max_value = 1.0
	bar.value = 0.0
	value.text = "--/--"
	icon.modulate = Color(0.35, 0.40, 0.45, 1)
