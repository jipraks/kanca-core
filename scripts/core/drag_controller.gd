class_name DragController
extends Node3D

## Pick up, carry, put down — shared by every mini-game (PLAN.md §3.3).
##
## Drag is the primary interaction for the whole game because it is far more
## reliable than tapping for small hands. Everything here is built around that:
## the pick box is generous, there is no double-tap, long-press or gesture
## anywhere, and a drop that lands nowhere useful simply lets go rather than
## doing something surprising.
##
## The controller knows nothing about shelves, trays or garden plots. It finds a
## `Draggable` on layer 3, carries its visual, finds a `DropTarget` on layer 4,
## and reports what happened. What that *means* is the mini-game's business.

## Emitted the moment something is picked up. `source` is still valid here, so a
## listener may detach or free it; nothing below touches it afterwards.
signal picked(payload: String, source: Draggable)

## Emitted on release. `target` is null when the drop landed on nothing.
signal dropped(payload: String, target: DropTarget)

## Press and release on the same non-draggable interactable.
signal tapped(target: TapTarget)

const INTERACTABLE_MASK := 4
const DROP_ZONE_MASK := 8
const RAY_LENGTH := 60.0
const CARRY_LIFT_SECONDS := 0.1
const CARRY_SCALE := 1.15

## Height the carried thing floats at while crossing the scene. Each mini-game
## sets this to sit comfortably above its own surface.
@export var carry_height: float = 1.35

var _camera: Camera3D = null
var _enabled: bool = false

var _held: Node3D = null
var _held_payload: String = ""
var _tap_candidate: TapTarget = null


func setup(camera: Camera3D) -> void:
	_camera = camera


## Dragging is switched off between rounds and during animations, so nothing can
## be shuffled around mid-transition.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		cancel()


func is_enabled() -> bool:
	return _enabled


func is_dragging() -> bool:
	return _held != null


## Drops whatever is being carried without counting it either way. Used when a
## round ends mid-drag, or the app loses focus with a finger down.
func cancel() -> void:
	_release_held()
	_tap_candidate = null


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or _camera == null:
		return

	# Touch arrives as mouse input: input_devices/pointing/emulate_mouse_from_touch
	# is on, and §3.3 rules out multi-touch anyway, so one pointer is all there is.
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_on_press(button.position)
		else:
			_on_release(button.position)
		return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _held != null:
		_held.global_position = _pointer_to_carry_position(motion.position)


func _on_press(screen_position: Vector2) -> void:
	if _held != null:
		return

	var hit: Dictionary = _raycast(screen_position, INTERACTABLE_MASK)
	if hit.is_empty():
		return

	var collider: Object = hit.get("collider")

	var source: Draggable = collider as Draggable
	if source != null:
		if not source.can_drag():
			return
		_begin_drag(source, screen_position)
		return

	# Not draggable, so it might be a tap. Confirmed on release.
	_tap_candidate = collider as TapTarget


func _on_release(screen_position: Vector2) -> void:
	if _held != null:
		_finish_drag(screen_position)
		return

	if _tap_candidate == null:
		return

	# A tap only counts if the finger came up on the same thing it went down on.
	# Sliding off is how a child changes their mind, and it must cost nothing.
	var hit: Dictionary = _raycast(screen_position, INTERACTABLE_MASK)
	var released_on: TapTarget = hit.get("collider") as TapTarget
	var candidate: TapTarget = _tap_candidate
	_tap_candidate = null

	if released_on != null and released_on == candidate:
		tapped.emit(candidate)


func _begin_drag(source: Draggable, screen_position: Vector2) -> void:
	_held_payload = source.get_drag_payload()

	var visual: Node3D = source.build_drag_visual()
	if visual == null:
		visual = PlaceholderFactory.build_item_visual(_held_payload)

	_held = visual
	_held.name = "Held"
	add_child(_held)
	_held.global_position = source.global_position

	# Lifts to carry height rather than snapping, so the child can see what they
	# picked up leave its place.
	var target: Vector3 = _pointer_to_carry_position(screen_position)
	var tween: Tween = create_tween()
	tween.tween_property(_held, "global_position", target, CARRY_LIFT_SECONDS).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_held, "scale", Vector3.ONE * CARRY_SCALE, CARRY_LIFT_SECONDS)

	SfxBank.play(SfxBank.CLICK)
	source.on_drag_started()

	# Emitted last, so a listener is free to detach or free the source.
	picked.emit(_held_payload, source)


func _finish_drag(screen_position: Vector2) -> void:
	var payload: String = _held_payload
	var hit: Dictionary = _raycast(screen_position, DROP_ZONE_MASK)
	var target: DropTarget = hit.get("collider") as DropTarget

	_release_held()

	if target != null and not target.can_accept(payload):
		target = null

	if target == null:
		SfxBank.play(SfxBank.WHOOSH)

	dropped.emit(payload, target)


func _release_held() -> void:
	if _held != null:
		_held.queue_free()
	_held = null
	_held_payload = ""


## Where the pointer lands on the horizontal plane things are carried along.
func _pointer_to_carry_position(screen_position: Vector2) -> Vector3:
	var from: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var plane: Plane = Plane(Vector3.UP, carry_height)
	var intersection: Variant = plane.intersects_ray(from, direction)
	if intersection == null:
		return from + direction * 3.0
	return intersection as Vector3


func _raycast(screen_position: Vector2, mask: int) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {}

	var from: Vector3 = _camera.project_ray_origin(screen_position)
	var to: Vector3 = from + _camera.project_ray_normal(screen_position) * RAY_LENGTH

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return space.intersect_ray(query)
