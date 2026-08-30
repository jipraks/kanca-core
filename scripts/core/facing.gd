class_name Facing
extends RefCounted

## Which way a character is turned.
##
## This exists as its own file because the convention is the thing everyone gets
## wrong, including me: in Godot a node's **forward is -Z**, so a model must be
## authored looking down -Z, and turning it to face a direction is *not*
## `atan2(x, z)`. That formula turns the model exactly backwards, which is subtle
## enough on a capsule to survive a headless test suite and obvious the moment a
## real character walks across a village.


## Y rotation that points a node's -Z axis along `direction`. Y is ignored.
static func angle_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Angle for a node at `from` to look at `to`.
static func angle_from_to(from: Vector3, to: Vector3) -> float:
	return angle_towards(to - from)
