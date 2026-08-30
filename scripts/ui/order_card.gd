class_name OrderCard
extends Control

## The persistent visual record of what the customer asked for (PLAN.md §8.1.4).
##
## A spoken order vanishes the moment it finishes. This card is what a child
## refers back to, and tapping it replays the line — so nobody is ever stuck
## because they missed a word.
##
## Each row is item icon + numeral. The counting dots §8.1 asks for are switched
## off here (see CountingRow) — the card read as cluttered with both. The numeral
## is enlarged to carry the quantity on its own.

signal replay_requested()

const ROW_ICON_SIZE := Vector2(96, 96)
## Narrower since the counting dots came off — a row is now an icon and a
## numeral, and the card was sized for a row three times as wide. Still tappable
## well past §3.3's floor, because the whole card replays the order.
const CARD_MIN_SIZE := Vector2(248, 190)

var _button: Button = null
var _rows: VBoxContainer = null
var _entries: Array = []


func _ready() -> void:
	custom_minimum_size = CARD_MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The whole card is the tap target, which makes it comfortably larger than
	# the 120px minimum without a separate replay button competing for space.
	_button = Button.new()
	_button.name = "TapToReplay"
	_button.focus_mode = Control.FOCUS_NONE
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.add_theme_stylebox_override("normal", _card_style(Palette.UI_PANEL))
	_button.add_theme_stylebox_override("hover", _card_style(Palette.UI_PANEL))
	_button.add_theme_stylebox_override("pressed", _card_style(Palette.UI_PANEL.darkened(0.06)))
	_button.add_theme_stylebox_override("focus", _card_style(Palette.UI_PANEL))
	_button.pressed.connect(_on_pressed)
	add_child(_button)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows.add_theme_constant_override("separation", 18)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.offset_left = 24
	_rows.offset_top = 20
	_rows.offset_right = -24
	_rows.offset_bottom = -20
	add_child(_rows)


## `entries` is [{ "item_id": String, "count": int }, ...] — the same shape the
## Warung builds its order from, so there is no translation layer.
func set_order(entries: Array) -> void:
	_entries = entries.duplicate(true)

	for child: Node in _rows.get_children():
		child.queue_free()

	for entry: Variant in _entries:
		var entry_dict: Dictionary = entry as Dictionary
		_rows.add_child(_build_row(String(entry_dict.get("item_id", "")), int(entry_dict.get("count", 0))))


func clear_order() -> void:
	set_order([])


## Called when the child gets it wrong: the card asks to be looked at again
## rather than the game saying "no" (§8.1.8).
func pulse(times: int = 2) -> void:
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	for i: int in range(maxi(times, 1)):
		tween.tween_property(self, "scale", Vector2.ONE * 1.06, 0.2).set_trans(Tween.TRANS_SINE)
		tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


func _build_row(item_id: String, count: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row_%s" % item_id
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.texture = PlaceholderFactory.build_item_icon(item_id, 128)
	icon.custom_minimum_size = ROW_ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Never stretched by the row. EXPAND_IGNORE_SIZE stops the *texture* deciding
	# the slot; this stops the *container* deciding it. Narrowing the card left
	# the box distributing spare height into the icon, which came out at 96×105 —
	# a square icon rendered as a rectangle, which the UI suite caught.
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var counting: CountingRow = CountingRow.new()
	counting.name = "Counting"
	# One colour for every row. Hashing the item id gave green dots next to a red
	# apple; the dots answer "how many", and the icon beside them answers "what".
	counting.dot_colour = Palette.SIGNATURE.darkened(0.08)
	counting.show_dots = false
	# Bigger, because it is now the only thing on the card that says how many.
	counting.numeral_font_size = 76
	row.add_child(counting)
	counting.set_count(count)

	return row


func _card_style(colour: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = colour
	style.corner_radius_top_left = 28
	style.corner_radius_top_right = 28
	style.corner_radius_bottom_left = 28
	style.corner_radius_bottom_right = 28
	style.border_width_bottom = 6
	style.border_color = Palette.UI_PANEL_EDGE
	return style


func _on_pressed() -> void:
	SfxBank.play(SfxBank.POP)
	replay_requested.emit()
