class_name BigButton
extends Button

## The only button type in the game (PLAN.md §12).
##
## Icon-driven by construction: there is no text property to set, because §3.1
## forbids any UI element whose meaning depends on reading. If a button needs
## explaining, it needs a voice line, not a label.
##
## Enforces the 120×120 minimum from §3.3 rather than trusting each caller to
## remember it.

## §3.3. Far above the adult 48dp guideline, deliberately.
const MIN_TOUCH_SIZE := Vector2(120, 120)

## §3.4 caps transitions at 400ms; a press must feel instant, so this is far under.
const PRESS_ANIMATION_SECONDS := 0.08
const PRESSED_SCALE := 0.92

@export var icon_texture: Texture2D = null:
	set(value):
		icon_texture = value
		if is_inside_tree():
			_apply_icon()

@export var accent: Color = Palette.SIGNATURE:
	set(value):
		accent = value
		if is_inside_tree():
			_apply_style()

## Played when the child presses this button. Optional (§12).
@export var voice_id: String = ""

@export var sfx_id: String = SfxBank.CLICK

## Locked controls stay visible and tappable — tapping one should explain itself,
## not do nothing. Never draw them as a padlock (§7.2).
## Shrinks the drawn panel inside the control without shrinking the control.
##
## §3.3's 120×120 is a floor on the *touch target*, not on the paint. A button
## drawn a little smaller than it can be pressed is forgiving — a finger landing
## just outside still works. The reverse would not be: paint wider than the hit
## area and a child presses the picture and nothing happens.
@export var visual_inset: float = 0.0:
	set(value):
		visual_inset = value
		if is_inside_tree():
			_apply_style()

@export var is_locked: bool = false:
	set(value):
		is_locked = value
		if is_inside_tree():
			_apply_style()

var _scale_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(MIN_TOUCH_SIZE)
	focus_mode = Control.FOCUS_NONE
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	text = ""
	clip_contents = false

	resized.connect(_recentre_pivot)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)

	_recentre_pivot()
	_apply_style()
	_apply_icon()


## Draws attention without nagging. Used when a hint escalates (§8.1.8) and when
## the order card wants to be looked at again.
func pulse(times: int = 3) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	for i: int in range(maxi(times, 1)):
		_pulse_tween.tween_property(self, "scale", Vector2.ONE * 1.12, 0.18).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)


func stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	scale = Vector2.ONE


func _recentre_pivot() -> void:
	pivot_offset = size * 0.5


func _apply_icon() -> void:
	icon = icon_texture


func _apply_style() -> void:
	var base: Color = Palette.UI_DISABLED if is_locked else accent
	add_theme_stylebox_override("normal", _make_style(base, 0.0))
	add_theme_stylebox_override("hover", _make_style(base.lightened(0.08), 0.0))
	add_theme_stylebox_override("pressed", _make_style(base.darkened(0.12), 2.0))
	add_theme_stylebox_override("disabled", _make_style(Palette.UI_DISABLED, 0.0))
	add_theme_stylebox_override("focus", _make_style(base, 0.0))


func _make_style(colour: Color, top_offset: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = colour
	style.corner_radius_top_left = 28
	style.corner_radius_top_right = 28
	style.corner_radius_bottom_left = 28
	style.corner_radius_bottom_right = 28
	style.border_width_bottom = 6
	style.border_color = colour.darkened(0.22)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18 + top_offset
	style.content_margin_bottom = 18 - top_offset

	# Negative expand margins pull the painted box inwards. The Control keeps its
	# full rect, so the touch target is untouched.
	if visual_inset > 0.0:
		style.expand_margin_left = -visual_inset
		style.expand_margin_right = -visual_inset
		style.expand_margin_top = -visual_inset
		style.expand_margin_bottom = -visual_inset
	return style


func _on_button_down() -> void:
	_animate_scale(PRESSED_SCALE)


func _on_button_up() -> void:
	_animate_scale(1.0)


func _on_pressed() -> void:
	# Visual, audio, and voice all inside 100ms (§3.3).
	if not sfx_id.is_empty():
		SfxBank.play(sfx_id)
	if not voice_id.is_empty():
		VoiceBank.play(voice_id)


func _animate_scale(target: float) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, PRESS_ANIMATION_SECONDS)
