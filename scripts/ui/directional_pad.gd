class_name DirectionalPad
extends MovementControl

## Hub movement controls (PLAN.md §3.3, §7.1).
##
## Directional buttons, not tap-to-move and not a free camera. A virtual joystick
## may be trialled later, but only after this works and only with real children
## (§16.3) — so this deliberately does not pretend to be a joystick.
##
## Size follows from the rules rather than from taste: four 120×120 targets in a
## cross, 40px apart, is 440×440 at the 1280×720 base resolution. That is a large
## share of the screen and it is supposed to be. Tune only with device data.

const BUTTON_SIZE := 120.0
const GAP := 40.0
const PAD_SPAN := BUTTON_SIZE * 3.0 + GAP * 2.0

## Screen-space directions. Y is negative for "away from the camera", matching
## the convention the player controller uses.
const DIRECTIONS: Dictionary = {
	"up": Vector2(0, -1),
	"down": Vector2(0, 1),
	"left": Vector2(-1, 0),
	"right": Vector2(1, 0),
}

@export var accent: Color = Palette.UI_PANEL
@export var arrow_colour: Color = Palette.UI_TEXT

var _buttons: Dictionary = {}
var _held: Dictionary = {}
var _direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Minimum size only — the parent scene owns where this sits on screen, and
	# assigning `size` here would fight its anchors.
	custom_minimum_size = Vector2(PAD_SPAN, PAD_SPAN)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slots: Dictionary = {
		"up": Vector2(BUTTON_SIZE + GAP, 0.0),
		"left": Vector2(0.0, BUTTON_SIZE + GAP),
		"right": Vector2((BUTTON_SIZE + GAP) * 2.0, BUTTON_SIZE + GAP),
		"down": Vector2(BUTTON_SIZE + GAP, (BUTTON_SIZE + GAP) * 2.0),
	}

	for key: String in slots:
		var button: BigButton = BigButton.new()
		button.name = key.capitalize()
		button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		button.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		button.position = slots[key]
		button.accent = accent
		button.icon_texture = PlaceholderFactory.build_arrow_icon(DIRECTIONS[key], arrow_colour, 96)
		# Holding a direction should not machine-gun the click sound.
		button.sfx_id = ""
		button.button_down.connect(_on_button_down.bind(key))
		button.button_up.connect(_on_button_up.bind(key))
		add_child(button)
		_buttons[key] = button
		_held[key] = false


## Current input as a screen-space vector. The player controller polls this each
## frame — movement input is the one thing §15 allows in _process.
func get_direction() -> Vector2:
	return _direction


func release_all() -> void:
	for key: String in _held:
		_held[key] = false
	_recalculate()


func _on_button_down(key: String) -> void:
	if not _held[key]:
		SfxBank.play(SfxBank.CLICK, 0.9)
	_held[key] = true
	_recalculate()


func _on_button_up(key: String) -> void:
	_held[key] = false
	_recalculate()


func _notification(what: int) -> void:
	# A finger that leaves the screen, or the app losing focus mid-hold, must not
	# leave the child walking into a fence forever.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()


func _recalculate() -> void:
	var next: Vector2 = Vector2.ZERO
	for key: String in _held:
		if _held[key]:
			next += DIRECTIONS[key] as Vector2

	if next.length() > 1.0:
		next = next.normalized()

	if next.is_equal_approx(_direction):
		return

	_direction = next
	direction_changed.emit(_direction)
