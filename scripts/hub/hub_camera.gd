class_name HubCamera
extends Camera3D

## Follow camera for the village (PLAN.md §7.1).
##
## The child steers this: a drag turns it, a pinch or the zoom buttons push it in
## and out. Two things stay welded shut, and they are the two that matter — the
## pitch is fixed at 35° and the camera always looks at the player. Between them
## there is no input that ends with a child staring at the sky or hunting for an
## avatar that has left the frame, which is what the original fixed camera was
## defending against.
##
## Heading is free and unclamped. A village you can walk all the way around is
## worth more than a heading limit that stops the child mid-turn for no reason
## they can see.

## Third-person, elevated, looking down (§7.1). Not adjustable.
const PITCH_DEGREES := -35.0

const MIN_DISTANCE := 6.5
const MAX_DISTANCE := 22.0
const DEFAULT_DISTANCE := 13.0

## What one press of a zoom button is worth. Big enough that a press is visibly
## worth making, small enough that the range takes several to cross.
const BUTTON_STEP := 3.5

## Higher is snappier. Low enough that the village does not judder, high enough
## that the player never outruns the frame.
const FOLLOW_SHARPNESS := 7.0

## Zoom and turn ease rather than snap, so the village reads as being moved
## rather than cut to. Turning is quicker than zooming because a drag is a
## continuous gesture and lag under the finger feels like a fault.
const ZOOM_SHARPNESS := 9.0
const YAW_SHARPNESS := 16.0

signal view_changed()

@export var target: Node3D = null

var _yaw: float = 0.0
var _shown_yaw: float = 0.0
var _distance: float = DEFAULT_DISTANCE
var _shown_distance: float = DEFAULT_DISTANCE
var _pitch: float = 0.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 55.0
	_pitch = deg_to_rad(-PITCH_DEGREES)
	rotation = Vector3(deg_to_rad(PITCH_DEGREES), _shown_yaw, 0.0)

	if target != null:
		global_position = target.global_position + _offset(_shown_yaw, _shown_distance)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	# Shortest way round, so dragging past due north does not unwind the long way.
	var yaw_weight: float = 1.0 - exp(-YAW_SHARPNESS * delta)
	_shown_yaw = _shown_yaw + wrapf(_yaw - _shown_yaw, -PI, PI) * yaw_weight
	_shown_distance = lerpf(_shown_distance, _distance, 1.0 - exp(-ZOOM_SHARPNESS * delta))

	rotation = Vector3(deg_to_rad(PITCH_DEGREES), _shown_yaw, 0.0)

	# Follows on X and Z only; the ground is flat and a bobbing camera would
	# make the village feel unstable.
	var offset: Vector3 = _offset(_shown_yaw, _shown_distance)
	var desired: Vector3 = target.global_position + offset
	desired.y = offset.y
	var weight: float = 1.0 - exp(-FOLLOW_SHARPNESS * delta)
	global_position = global_position.lerp(desired, weight)


# ---------------------------------------------------------------- zoom

## One button press nearer. Returns false at the near end, so the button can grey
## itself out rather than silently doing nothing — a control that answers a press
## by not moving is how a child learns to stop pressing.
func zoom_in() -> bool:
	return set_distance(_distance - BUTTON_STEP)


func zoom_out() -> bool:
	return set_distance(_distance + BUTTON_STEP)


## Pinch. A ratio rather than a delta, because the gesture is a ratio: spreading
## the fingers twice as far apart should halve the distance wherever it started,
## and subtracting a fixed number would make the same pinch feel different at
## each end of the range.
func zoom_by_ratio(ratio: float) -> bool:
	if ratio <= 0.0:
		return false
	return set_distance(_distance / ratio)


func set_distance(value: float) -> bool:
	var clamped: float = clampf(value, MIN_DISTANCE, MAX_DISTANCE)
	if is_equal_approx(clamped, _distance):
		return false
	_distance = clamped
	view_changed.emit()
	return true


func get_distance() -> float:
	return _distance


func can_zoom_in() -> bool:
	return _distance > MIN_DISTANCE + 0.01


func can_zoom_out() -> bool:
	return _distance < MAX_DISTANCE - 0.01


# ---------------------------------------------------------------- heading

func turn_by(radians: float) -> void:
	if is_zero_approx(radians):
		return
	_yaw = wrapf(_yaw + radians, -PI, PI)
	view_changed.emit()


func get_yaw() -> float:
	return _yaw


## Back to the view every session opens on. Snaps rather than eases: used when
## the hub is first shown, where there is no previous frame to glide from.
func reset_view() -> void:
	_yaw = 0.0
	_shown_yaw = 0.0
	_distance = DEFAULT_DISTANCE
	_shown_distance = DEFAULT_DISTANCE
	view_changed.emit()


func _offset(yaw: float, distance: float) -> Vector3:
	var flat: Vector3 = Vector3(0.0, sin(_pitch) * distance, cos(_pitch) * distance)
	return flat.rotated(Vector3.UP, yaw)


## Screen-space input to world movement (§7.1: "relative to the camera, not the
## character"). Now that the camera turns, that has to mean its *current*
## heading — otherwise the child turns the village a half-circle and up on the
## stick starts walking them towards the screen.
func screen_to_world(direction: Vector2) -> Vector3:
	return Vector3(direction.x, 0.0, direction.y).rotated(Vector3.UP, _yaw)
