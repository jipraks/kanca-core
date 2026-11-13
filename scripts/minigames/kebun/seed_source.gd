class_name SeedSource
extends Draggable

## A basket of one kind of seed (PLAN.md §8.2).
##
## Endless, like the warung shelf: a child who runs out of seeds halfway through
## the garden has hit a failure state, and there are none of those (§3.2).

## Sized from the measured projection, not from the basket mesh: at the Kebun
## camera distance this is what clears the 120px floor in §3.3.
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

const BASKET_MODEL := "res://assets/models/garden/seed_basket.glb"

## The camera looks down from six metres at an orthographic width of eight, so a
## thirty-centimetre basket is thirty pixels of screen. These are the two things
## the child picks up; they have to be as big as the plots they are dragged to.
const BASKET_SCALE := 1.55

var item_id: String = ""

var _display: Node3D = null
var _label: Sprite3D = null


func setup(id: String) -> void:
	item_id = id
	name = "Seed_%s" % id

	add_touch_box(TOUCH_SIZE, Vector3(0.0, 0.2, 0.0))
	_build_basket()

	# The seed itself is tiny, so the basket carries the item's own icon. A child
	# picks by picture, never by reading (§3.1).
	_label = Sprite3D.new()
	_label.name = "Label"
	_label.texture = PlaceholderFactory.build_item_icon(item_id, 128)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.shaded = false
	_label.pixel_size = 0.0035
	_label.position.y = 0.46
	add_child(_label)


## What comes out of the basket is the produce it grows into, so the child sees
## the connection between the picture on the basket and the thing they harvest.
func get_drag_payload() -> String:
	return item_id


func on_drag_started() -> void:
	if _display == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_display, "scale", Vector3(1.12, 0.88, 1.12), 0.06)
	tween.tween_property(_display, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK)


func _build_basket() -> void:
	_display = Node3D.new()
	_display.name = "Display"
	_display.scale = Vector3.ONE * BASKET_SCALE
	add_child(_display)

	var basket: Node3D = ModelKit.instantiate(BASKET_MODEL)
	if basket == null:
		basket = _build_placeholder_basket()
	basket.name = "Basket"
	_display.add_child(basket)

	# The seed on top is tinted to the crop it holds, so two baskets side by side
	# are told apart by colour before the child reads the label above them.
	var seeds: MeshInstance3D = MeshInstance3D.new()
	var seed_mesh: SphereMesh = SphereMesh.new()
	seed_mesh.radius = 0.20
	seed_mesh.height = 0.13
	seed_mesh.radial_segments = 10
	seed_mesh.rings = 4
	seeds.mesh = seed_mesh
	seeds.material_override = PlaceholderFactory.get_flat_material(
		Palette.for_key(item_id).darkened(0.24))
	seeds.position.y = 0.245
	seeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_display.add_child(seeds)


func _build_placeholder_basket() -> Node3D:
	var basket: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.16
	mesh.height = 0.28
	mesh.radial_segments = 10
	mesh.rings = 0
	basket.mesh = mesh
	basket.material_override = PlaceholderFactory.get_flat_material(Palette.WOOD)
	basket.position.y = 0.14
	basket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return basket

