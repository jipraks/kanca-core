class_name WateringCan
extends Draggable

## The watering can (PLAN.md §8.2).
##
## It never moves. Dragging spawns a temporary carried copy, exactly like the
## seed baskets, so the can is always where the child last saw it. A tool that
## wanders off is a tool a four-year-old cannot find again.

## Payload used for water. Prefixed so it can never collide with an item id from
## data/items.json.
const PAYLOAD := "tool:air"

## The touch box, not the basket. It is deliberately larger than the model — a
## child aiming at a seed basket is aiming at "the bananas over there", not at a
## piece of wickerwork.
##
## Shallower than it is wide since the camera moved off the top of the garden.
## Depth now costs screen height *and* pushes the near face towards the bottom
## edge of frame, and 1.15m of it put the front of the basket below the screen.
## The box still projects to well over the §3.3 minimum in both axes; the depth
## was slack, not headroom.
const TOUCH_SIZE := Vector3(1.4, 0.9, 0.9)

const CAN_MODEL := "res://assets/models/garden/watering_can.glb"

## Matched to the seed baskets beside it. Both are picked up by a small finger
## from a camera six metres up, and at model scale they were thirty pixels.
const CAN_SCALE := 1.55

var _display: Node3D = null


func setup() -> void:
	name = "WateringCan"
	add_touch_box(TOUCH_SIZE, Vector3(0.0, 0.24, 0.0))
	_display = _build_can()
	_display.name = "Display"
	add_child(_display)


func get_drag_payload() -> String:
	return PAYLOAD


func build_drag_visual() -> Node3D:
	return _build_can()


func on_drag_started() -> void:
	if _display == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_display, "rotation:z", deg_to_rad(-14.0), 0.08)
	tween.tween_property(_display, "rotation:z", 0.0, 0.14).set_trans(Tween.TRANS_BACK)


## Body, spout and handle. Crude, but the silhouette says "watering can" at a
## glance, which is the only thing that matters until real art arrives (§11).
func _build_can() -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.scale = Vector3.ONE * CAN_SCALE

	var can: Node3D = ModelKit.instantiate(CAN_MODEL)
	if can != null:
		holder.add_child(can)
		return holder

	var material: StandardMaterial3D = PlaceholderFactory.get_flat_material(
		Palette.SKY.darkened(0.15))

	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius = 0.17
	body_mesh.bottom_radius = 0.2
	body_mesh.height = 0.32
	body_mesh.radial_segments = 12
	body.mesh = body_mesh
	body.material_override = material
	body.position.y = 0.16
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(body)

	return holder
