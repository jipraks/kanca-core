class_name CameraGestures
extends Control

## Drag to turn the village, pinch to zoom it (PLAN.md §3.3, §7.1).
##
## A full-screen Control sitting *underneath* the rest of the hub UI, which is
## what stops a finger on the joystick from also spinning the camera: Godot
## offers a touch to the topmost control first, so the stick and the buttons take
## their own presses and only what lands on open village reaches here.
##
## Rotation reads the mouse rather than the touch, deliberately. The project runs
## with `emulate_mouse_from_touch` on (it is load-bearing for the mini-game drag
## system), so every finger arrives twice — once as a touch and once as a mouse
## event. Handling both would turn the village at double speed. The mouse copy is
## the one that respects which control was actually hit, so that is the copy this
## uses, and it makes the same gesture work with a mouse on desktop for free.
##
## Pinch has no mouse equivalent, so it is the one thing read from raw touches.

## About one and a half screen-widths of drag for a full turn. Slow enough that a
## child brushing the screen does not spin the village, fast enough to get all
## the way round without lifting a finger twice.
const ROTATE_RADIANS_PER_PIXEL := 0.0030

## One mouse-wheel notch. Desktop only — there is no wheel on a phone, this is
## for testing the village in the editor.
const WHEEL_RATIO := 1.12

## Two fingers have to move this far apart, in pixels, before it counts as a
## pinch. Fingers resting on glass jitter by a pixel or two.
const PINCH_DEADZONE := 6.0

@export var camera: HubCamera = null

var _dragging: bool = false
var _touches: Dictionary = {}
var _spread: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if camera == null:
		return

	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom_by_ratio(WHEEL_RATIO)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_by_ratio(1.0 / WHEEL_RATIO)
			accept_event()
		return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		# A second finger means the gesture is a pinch, and the emulated mouse is
		# still following finger zero. Turning at the same time makes the village
		# lurch sideways every time a child zooms.
		if _touches.size() < 2:
			camera.turn_by(motion.relative.x * ROTATE_RADIANS_PER_PIXEL)
		accept_event()


## Raw touches, for the pinch only. Read here rather than in _gui_input because
## a pinch is defined by two fingers at once, which the GUI system has no notion
## of — it routes one pointer.
func _input(event: InputEvent) -> void:
	if camera == null:
		return

	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		# Reset on every change of finger count: the spread across a *different*
		# pair of fingers is not a continuation of the previous pinch, and using
		# it as one snaps the zoom.
		_spread = 0.0
		if _touches.size() < 2:
			return
		_spread = _current_spread()
		return

	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag == null or not _touches.has(drag.index):
		return

	_touches[drag.index] = drag.position
	if _touches.size() < 2:
		return

	var spread: float = _current_spread()
	if _spread < PINCH_DEADZONE or spread < PINCH_DEADZONE:
		_spread = spread
		return

	camera.zoom_by_ratio(spread / _spread)
	_spread = spread


func _notification(what: int) -> void:
	# A finger that leaves the screen, or the app losing focus mid-gesture, must
	# not leave the village stuck mid-turn.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false
		_touches.clear()
		_spread = 0.0


## Distance between the two lowest-indexed fingers. Two is all a pinch needs, and
## picking a stable pair stops a third finger landing from changing the ratio.
func _current_spread() -> float:
	var indices: Array = _touches.keys()
	indices.sort()
	var first: Vector2 = _touches[indices[0]] as Vector2
	var second: Vector2 = _touches[indices[1]] as Vector2
	return first.distance_to(second)
