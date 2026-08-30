class_name TapTarget
extends Area3D

## Something a child taps rather than drags (PLAN.md §3.3).
##
## Rare on purpose. Drag is the primary interaction because it is more reliable
## for small hands; tapping is for the few places where dragging would be
## nonsense, such as picking a ripe plant off its stem.
##
## A tap is press and release on the same object. There is no double-tap, no
## long-press and no gesture anywhere in this game.

const INTERACTABLE_LAYER := 4


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	monitoring = false
	input_ray_pickable = true


func add_touch_box(size: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "TouchBox"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	add_child(shape)


## Switches the target in and out of reach without hiding it. A plant that is not
## ready yet stays visible and simply does not respond (§3.2).
func set_tappable(tappable: bool) -> void:
	collision_layer = INTERACTABLE_LAYER if tappable else 0
