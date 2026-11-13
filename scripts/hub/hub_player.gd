class_name HubPlayer
extends CharacterBody3D

## The child's avatar in the village (PLAN.md §7.1).
##
## Movement is camera-relative and comes from the on-screen pad. Keyboard input is
## accepted as well, purely so the village can be walked in the editor without a
## touchscreen — it is not a shipped control scheme.

## Brisk enough not to feel tedious to cross the village (§7.1).
const SPEED := 4.0
const ACCELERATION := 22.0
const DECELERATION := 26.0
const TURN_SHARPNESS := 12.0
const GRAVITY := 14.0

## The avatar's model. A single fixed thing rather than a data-driven one — there
## is exactly one child in this village, and inventing a registry for it would be
## more machinery than the problem has. Falls back to the placeholder capsule if
## the file is absent, like everything else (§10.5).
const MODEL := "res://assets/models/characters/player.glb"
const PLACEHOLDER_HEIGHT := 1.15

signal started_moving()
signal stopped_moving()

@export var pad: MovementControl = null
@export var camera: HubCamera = null

var _visual: Node3D = null
var _walk: WalkCycle = null
var _was_moving: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1

	_visual = _build_visual()
	_visual.name = "Visual"
	add_child(_visual)
	_walk = WalkCycle.new(_visual)



func _build_visual() -> Node3D:
	var instance: Node3D = ModelKit.instantiate(MODEL)
	if instance != null:
		return instance

	return PlaceholderFactory.build_character("player", Palette.SKY.darkened(0.1),
		PLACEHOLDER_HEIGHT)


func _physics_process(delta: float) -> void:
	var input: Vector2 = _read_input()
	var direction: Vector3 = Vector3(input.x, 0.0, input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	var target: Vector3 = direction * SPEED
	var rate: float = ACCELERATION if direction.length_squared() > 0.0 else DECELERATION
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	_face_travel_direction(delta)
	_step(delta)
	_report_movement()



## Swings the legs at whatever pace the child is actually moving, and plays a
## footfall as each foot lands.
##
## Driven by the horizontal velocity rather than by the stick, so a child walking
## into a fence stops stepping instead of jogging on the spot.
func _step(delta: float) -> void:
	if _walk == null:
		return
	var ground_speed: float = Vector2(velocity.x, velocity.z).length()
	if _walk.advance(delta, ground_speed):
		SfxBank.play(SfxBank.STEP, randf_range(0.94, 1.06))


## Places the avatar without the physics body fighting the teleport.
func warp_to(position_2d: Vector2) -> void:
	global_position = Vector3(position_2d.x, global_position.y, position_2d.y)
	velocity = Vector3.ZERO


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.1


func _read_input() -> Vector2:
	if pad != null:
		var from_pad: Vector2 = pad.get_direction()
		if from_pad != Vector2.ZERO:
			return from_pad
	return _read_keyboard()


## Editor convenience only. Harmless on a device, which has no keyboard.
func _read_keyboard() -> Vector2:
	var direction: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	return direction


func _face_travel_direction(delta: float) -> void:
	if _visual == null:
		return
	var flat: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.04:
		return
	var desired: float = Facing.angle_towards(flat)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, desired, 1.0 - exp(-TURN_SHARPNESS * delta))


func _report_movement() -> void:
	var moving: bool = is_moving()
	if moving == _was_moving:
		return
	_was_moving = moving
	if moving:
		started_moving.emit()
	else:
		stopped_moving.emit()
