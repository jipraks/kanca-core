class_name DropTarget
extends Area3D

## Somewhere a carried thing can be let go (PLAN.md §3.3, §8.1.6).
##
## A drop that lands anywhere else is never an error — it puts the item back, or
## takes it off the tray, depending on what the mini-game wants. Nothing about
## missing a target may cost the child anything.

## Physics layer 4, "drop_zone" — what a release raycast looks for.
const DROP_ZONE_LAYER := 8


func _ready() -> void:
	collision_layer = DROP_ZONE_LAYER
	collision_mask = 0
	monitoring = false
	input_ray_pickable = true


func add_zone_box(size: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "ZoneBox"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	add_child(shape)


## Whether this target wants that payload right now. A refusal is the mini-game's
## cue to respond gently, not the controller's cue to do nothing.
func can_accept(_payload: String) -> bool:
	return true
