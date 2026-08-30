class_name CountingRow
extends HBoxContainer

## A quantity, shown as a numeral and optionally as countable dots (§3.1, §8.1).
##
## The dots were the point of this class. §8.1 step 4 specifies "item icon + a
## row of counting dots + the numeral", and §3.1 forbids UI that needs reading:
## for a three-year-old who does not yet know that the shape "3" means three, the
## dots are the *only* thing on the card that answers "how many", and the numeral
## is the reading aid beside them.
##
## `show_dots` was added on 2026-08-30 at the project owner's request — the card
## was judged cluttered, and the dots and numeral do compete at this size. The
## trade is real and it is not free: with them off, quantity becomes literate-only
## and the youngest players in the target range lose the ability to read the
## order. Worth putting in front of children before it is settled (§14).

const DOT_SIZE := 40
const MAX_DOTS := 10

## Off means the numeral carries the quantity alone. See the note above.
@export var show_dots: bool = true:
	set(value):
		show_dots = value
		if _dot_box != null:
			_dot_box.visible = value

@export var dot_colour: Color = Palette.SIGNATURE
@export var numeral_colour: Color = Palette.UI_TEXT
@export var numeral_font_size: int = 56

var _numeral: Label = null
var _dot_box: HBoxContainer = null
var _count: int = 0


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dot_box = HBoxContainer.new()
	_dot_box.name = "Dots"
	_dot_box.add_theme_constant_override("separation", 10)
	_dot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot_box.visible = show_dots
	add_child(_dot_box)

	_numeral = Label.new()
	_numeral.name = "Numeral"
	_numeral.add_theme_font_size_override("font_size", numeral_font_size)
	_numeral.add_theme_color_override("font_color", numeral_colour)
	_numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_numeral)

	set_count(_count)


func set_count(value: int) -> void:
	_count = maxi(value, 0)
	if _dot_box == null:
		return

	for child: Node in _dot_box.get_children():
		child.queue_free()

	# Counting past ten is not a v1.0 learning goal (§8.1), and a row of twenty
	# dots stops being countable anyway.
	var drawn: int = mini(_count, MAX_DOTS)
	for i: int in range(drawn):
		var dot: TextureRect = TextureRect.new()
		dot.texture = PlaceholderFactory.build_dot_icon(dot_colour, DOT_SIZE * 2)
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dot_box.add_child(dot)

	_numeral.text = str(_count)


func get_count() -> int:
	return _count
