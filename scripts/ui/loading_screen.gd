class_name LoadingScreen
extends Control

## Shown while a scene loads (PLAN.md §12).
##
## "Never a bare progress bar" — a child who cannot read has no idea what a bar
## means. Kanca bounces, and three dots fill up one at a time, so the screen says
## "something is happening, wait a moment" without a word.
##
## Content is built in code rather than laid out in the scene file because the
## mascot here is still a still picture. When he is rigged (§11.1) this becomes
## an AnimatedSprite or a subviewport of the model itself, and there is nothing
## worth hand-placing until then.

const DOT_COUNT := 3
const DOT_SIZE := 28.0
const DOT_SPACING := 46.0
const BOUNCE_HEIGHT := 26.0
const BOUNCE_SECONDS := 0.55
const MASCOT_HEIGHT := 260

var _mascot: TextureRect = null
var _dots: Array[TextureRect] = []
var _progress: float = 0.0
var _elapsed: float = 0.0
var _mascot_home_y: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.color = Palette.CREAM
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var centre: CenterContainer = CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 36)
	centre.add_child(column)

	_mascot = TextureRect.new()
	_mascot.name = "Mascot"
	_mascot.texture = PlaceholderFactory.build_mascot_portrait(MASCOT_HEIGHT)
	# Sized by height, not by a square. Kanca is 2.4 heads tall and half as wide
	# as he is high; a 160-square box that fitted the placeholder swatch exactly
	# gives him 74 pixels of width and leaves him looking lost on the screen.
	_mascot.custom_minimum_size = Vector2(MASCOT_HEIGHT * 0.6, MASCOT_HEIGHT)
	_mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_mascot)

	var dot_row: HBoxContainer = HBoxContainer.new()
	dot_row.name = "Dots"
	dot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dot_row.add_theme_constant_override("separation", int(DOT_SPACING - DOT_SIZE))
	column.add_child(dot_row)

	for i: int in range(DOT_COUNT):
		var dot: TextureRect = TextureRect.new()
		dot.name = "Dot%d" % i
		dot.texture = PlaceholderFactory.build_dot_icon(Palette.SIGNATURE, 64)
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.modulate.a = 0.25
		dot_row.add_child(dot)
		_dots.append(dot)

	set_progress(0.0)


func _process(delta: float) -> void:
	if _mascot == null:
		return
	_elapsed += delta
	var phase: float = fmod(_elapsed, BOUNCE_SECONDS) / BOUNCE_SECONDS
	# A simple arc: up on the first half, down on the second.
	var height: float = sin(phase * PI) * BOUNCE_HEIGHT
	_mascot.position.y = _mascot_home_y - height


func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	for i: int in range(_dots.size()):
		var threshold: float = float(i + 1) / float(_dots.size())
		var lit: bool = _progress >= threshold - 0.001
		_dots[i].modulate.a = 1.0 if lit else 0.25


func get_progress() -> float:
	return _progress
