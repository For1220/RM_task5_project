extends Control

const ITEM_SCENE = preload("res://scenes/NotificationItem.tscn")
const MAX_ITEMS := 20

const TYPE_COLORS := {
	"ENEMY": Color("#62E6A6"),
	"RUNE": Color("#FFB454"),
	"OUTPOST": Color("#FF5E7A"),
	"SYSTEM": Color("#9AB1C2"),
	"INFO": Color("#4DDCFF"),
	"WARN": Color("#FFB454"),
	"ERROR": Color("#FF5E7A"),
	"NET": Color("#4D9DFF"),
	"DEBUG": Color("#6D879B"),
}

@export var clear_on_idle := false

@onready var feed: ScrollContainer = $Feed
@onready var list: VBoxContainer = $Feed/List
@onready var idle_timer: Timer = $IdleTimer

var _type_regex := RegEx.new()
var _feed_tween: Tween


func _ready() -> void:
	add_to_group("notification_feed")

	_type_regex.compile("^\\[([A-Za-z0-9_]+)\\]\\s*(.*)$")

	idle_timer.one_shot = true
	idle_timer.wait_time = 10.0
	idle_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	idle_timer.timeout.connect(_on_idle_timeout)

	feed.visible = false
	feed.modulate.a = 0.0


func push_notification(raw: String) -> void:
	var notif_type := "INFO"
	var body := raw

	var m := _type_regex.search(raw)
	if m:
		notif_type = m.get_string(1).to_upper()
		body = m.get_string(2)

	var color: Color = TYPE_COLORS.get(notif_type, Color("#9AB1C2"))

	var item := ITEM_SCENE.instantiate()
	var tag: Label = item.get_node("Row/Tag")
	var message: Label = item.get_node("Row/Message")
	var time_label: Label = item.get_node("Row/Time")

	tag.text = "[%s]" % notif_type
	tag.add_theme_color_override(
		"font_color",
		Color(color.r, color.g, color.b, 0.92)
	)
	message.text = body
	message.add_theme_color_override(
		"font_color",
		Color(0.90, 0.96, 1.0, 0.82)
	)

	var sec := int(MatchState.elapsed)
	time_label.text = "%02d:%02d" % [sec / 60, sec % 60]

	list.add_child(item)
	list.move_child(item, 0)

	while list.get_child_count() > MAX_ITEMS:
		var oldest := list.get_child(list.get_child_count() - 1)
		list.remove_child(oldest)
		oldest.queue_free()

	_show_feed()
	idle_timer.start()

	await get_tree().process_frame
	feed.scroll_vertical = 0


func _show_feed() -> void:
	if _feed_tween:
		_feed_tween.kill()

	if not feed.visible:
		feed.visible = true
		feed.modulate.a = 0.0

	_feed_tween = create_tween()
	_feed_tween.tween_property(feed, "modulate:a", 1.0, 0.2)


func _on_idle_timeout() -> void:
	if not feed.visible:
		return

	if clear_on_idle:
		for child in list.get_children():
			child.queue_free()

	if _feed_tween:
		_feed_tween.kill()

	_feed_tween = create_tween()
	_feed_tween.tween_property(feed, "modulate:a", 0.0, 0.25)
	_feed_tween.tween_callback(func() -> void: feed.visible = false)
