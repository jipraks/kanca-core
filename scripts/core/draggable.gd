class_name Draggable
extends Area3D

## Something a child can pick up and carry (PLAN.md §3.3).
##
## Drag is the primary interaction for every mini-game, so what it means to be
## draggable belongs here rather than being re-invented per game. A shelf slot, a
## tray item, a seed packet and a watering can are all this.
##
## Subclasses override the three hooks below. `DragController` never needs to know
## which kind it picked up.

## Physics layer 3, "interactable" — what a pick raycast looks for.
const INTERACTABLE_LAYER := 4

## Generous compared to the model inside. Small hands miss (§3.3), and the
## touch-target audits measure this box rather than the mesh.
const DEFAULT_TOUCH_SIZE := Vector3(0.5, 0.5, 0.3)


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	# Nothing here needs overlap detection; picking is done by raycast.
	monitoring = false
	input_ray_pickable = true


## Builds the pick box. Call from a subclass's setup, not from _ready, so the
## size can depend on what the subclass is representing.
func add_touch_box(size: Vector3 = DEFAULT_TOUCH_SIZE, offset: Vector3 = Vector3(0.0, 0.22, 0.0)) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "TouchBox"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	add_child(shape)


## What is being carried: an item id from data/items.json, or a tool id.
func get_drag_payload() -> String:
	return ""


## The thing that follows the pointer. Defaults to the payload's own visual.
func build_drag_visual() -> Node3D:
	return PlaceholderFactory.build_item_visual(get_drag_payload())


## Feedback the instant it is touched, inside the 100ms §3.3 asks for — before
## the carried visual has even started moving.
func on_drag_started() -> void:
	pass


## False while this source is temporarily unavailable. It stays visible and
## tappable either way; nothing in this app disappears to say "no" (§3.2).
func can_drag() -> bool:
	return true
