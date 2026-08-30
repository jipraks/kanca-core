class_name AnalogStick
extends MovementControl

## Analogue steering for the village (PLAN.md §7.1, §16.3).
##
## Wraps Godot 4.7's built-in VirtualJoystick rather than re-implementing one.
## §16.3 names that node specifically, and the engine's version already handles
## touch cancellation, dead zones and clamping better than a hand-rolled Control
## would. This class exists only to give it the same surface the directional pad
## has, so swapping the two for a session with children is a one-line change in
## hub.tscn.
##
## Three settings here are about four-year-olds rather than about joysticks:
##
## **Fixed, not dynamic.** The stick is always in the same corner. One that
## appears wherever you touch is more forgiving for an adult and baffling for a
## child still learning that the control lives somewhere.
##
## **Always visible.** A control that only appears once you touch it cannot be
## found by a child who does not yet know it is there.
##
## **Generous dead zone.** A finger resting near the centre means "stop", not
## "creep slowly". Drift is how a child ends up in a hedge without touching
## anything.

const ACTION_LEFT := &"hub_move_left"
const ACTION_RIGHT := &"hub_move_right"
const ACTION_UP := &"hub_move_up"
const ACTION_DOWN := &"hub_move_down"

## Comfortably past the 120px minimum in §3.3 — this is a resting place for a
## thumb, not a button. Reduced from 300 on 2026-08-30: at that size it covered
## almost a quarter of the screen's width and the village was playing second
## fiddle to its own controls. Still nearly twice the floor.
const STICK_SIZE := 220.0
const TIP_SIZE := 104.0
const DEAD_ZONE := 0.20
const CLAMP_ZONE := 0.78

var _joystick: VirtualJoystick = null


func _ready() -> void:
	custom_minimum_size = Vector2(STICK_SIZE, STICK_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_joystick = VirtualJoystick.new()
	_joystick.name = "Stick"
	_joystick.joystick_mode = VirtualJoystick.JOYSTICK_FIXED
	_joystick.visibility_mode = VirtualJoystick.VISIBILITY_ALWAYS
	_joystick.joystick_size = STICK_SIZE
	_joystick.tip_size = TIP_SIZE
	_joystick.deadzone_ratio = DEAD_ZONE
	_joystick.clampzone_ratio = CLAMP_ZONE
	_joystick.action_left = ACTION_LEFT
	_joystick.action_right = ACTION_RIGHT
	_joystick.action_up = ACTION_UP
	_joystick.action_down = ACTION_DOWN
	_joystick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_style(_joystick)
	add_child(_joystick)

	_joystick.pressed.connect(_on_pressed)


## The joystick drives InputMap actions rather than reporting a vector, so the
## direction is read back from them. Y is negated because the actions are named
## for the screen while §7.1's convention has -Y meaning away from the camera.
func get_direction() -> Vector2:
	var vector: Vector2 = Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	return Vector2(vector.x, vector.y)


func release_all() -> void:
	for action: StringName in [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	direction_changed.emit(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()


## The engine ships a grey placeholder look. These four styleboxes are the only
## way in, so the palette goes on through them.
func _style(joystick: VirtualJoystick) -> void:
	joystick.add_theme_stylebox_override("normal_joystick",
		_circle(Color(Palette.UI_PANEL, 0.50), Palette.UI_PANEL_EDGE, 6))
	joystick.add_theme_stylebox_override("pressed_joystick",
		_circle(Color(Palette.UI_PANEL, 0.68), Palette.UI_PANEL_EDGE, 6))
	joystick.add_theme_stylebox_override("normal_tip",
		_circle(Palette.SIGNATURE, Palette.SIGNATURE_DARK, 8))
	joystick.add_theme_stylebox_override("pressed_tip",
		_circle(Palette.SIGNATURE_LIGHT, Palette.SIGNATURE_DARK, 8))


func _circle(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	# Corner radius past half the box makes a circle at any size.
	style.corner_radius_top_left = 512
	style.corner_radius_top_right = 512
	style.corner_radius_bottom_left = 512
	style.corner_radius_bottom_right = 512
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	return style


func _on_pressed() -> void:
	# Every touch gets audible feedback inside 100ms (§3.3).
	SfxBank.play(SfxBank.CLICK, 0.9)
