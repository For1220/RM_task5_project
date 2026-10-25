extends HBoxContainer

## BuffDisplay
## 显示当前受控步兵的伤害、防御、热量冷却和经验加成。
## 每个子节点必须是 BuffSlot.tscn 的实例：
##   Damage / Defense / Heat / Exp

const ICON_DAMAGE := preload("res://assets/ui/buffs/icon_buff_damage.png")
const ICON_DEFENSE := preload("res://assets/ui/buffs/icon_buff_defense.png")
const ICON_HEAT := preload("res://assets/ui/buffs/icon_buff_heat.png")
const ICON_EXP := preload("res://assets/ui/buffs/icon_buff_exp.png")

const ACCENT_DAMAGE := Color("#FF7B61")
const ACCENT_DEFENSE := Color("#64D8FF")
const ACCENT_HEAT := Color("#FFC45C")
const ACCENT_EXP := Color("#FFD166")

# 小能量机关经验 Buff 的持续时间。
const XP_BUFF_DURATION := 45.0

@onready var slots: Dictionary = {
	"damage": $Damage,
	"defense": $Defense,
	"heat": $Heat,
	"exp": $Exp,
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_refresh")


func _process(_delta: float) -> void:
	_refresh()
	_layout()


## 读取当前受控步兵和团队状态，更新四个 Buff 槽位。
func _refresh() -> void:
	var active: Dictionary = {}
	var player := get_tree().get_first_node_in_group("Player")

	if is_instance_valid(player) and not bool(player.get("is_dead")):
		var remaining := maxf(float(player.get("buff_time_left")), 0.0)
		var total := maxf(float(player.get("buff_time_total")), remaining)
		if total <= 0.0:
			total = remaining

		if float(player.get("attack_multiplier")) > 1.001:
			active["damage"] = [
				remaining,
				total,
				ICON_DAMAGE,
				ACCENT_DAMAGE,
				"伤害 ×%.2f" % float(player.get("attack_multiplier"))
			]

		if float(player.get("defense_buff")) > 0.001:
			active["defense"] = [
				remaining,
				total,
				ICON_DEFENSE,
				ACCENT_DEFENSE,
				"减伤 %.0f%%" % (float(player.get("defense_buff")) * 100.0)
			]

		if float(player.get("cool_multiplier")) > 1.001:
			active["heat"] = [
				remaining,
				total,
				ICON_HEAT,
				ACCENT_HEAT,
				"热量冷却 ×%.2f" % float(player.get("cool_multiplier"))
			]

		var team := int(player.get("team"))
		var xp_remaining := maxf(
			float(ExpSystem.small_bonus_end.get(team, 0.0)) - MatchState.elapsed,
			0.0
		)
		var xp_pool := float(ExpSystem.small_bonus_remaining.get(team, 0.0))

		if xp_remaining > 0.0 and xp_pool > 0.0:
			active["exp"] = [
				xp_remaining,
				XP_BUFF_DURATION,
				ICON_EXP,
				ACCENT_EXP,
				"经验 +100%%，剩余池 %d" % int(xp_pool)
			]

	for key in slots:
		var slot = slots[key]
		if active.has(key):
			var data: Array = active[key]
			slot.set_state(data[2], data[0], data[1], data[3], data[4])
		else:
			slot.clear()

	var hint := _get_hint()
	visible = not active.is_empty() and hint != null and hint.visible


## 把 BuffDisplay 放在 ControlsHint 正上方并居中。
func _layout() -> void:
	if not visible:
		return

	var hint := _get_hint()
	if hint == null:
		return

	var target_size := get_combined_minimum_size()
	size = target_size

	var hint_rect := hint.get_global_rect()
	global_position = Vector2(
		round(hint_rect.position.x + (hint_rect.size.x - target_size.x) * 0.5),
		round(hint_rect.position.y - target_size.y - 10.0)
	)


## BuffDisplay 必须是 HUD 的直接子节点，和 ControlsHint 同级。
func _get_hint() -> Control:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("ControlsHint") as Control
