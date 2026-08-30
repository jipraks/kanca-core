class_name ShelfSlot
extends Draggable

## One item type on the warung shelf (PLAN.md §8.1.5).
##
## A slot is an endless supply of one item rather than a finite stack: dragging
## from it spawns a fresh item. Counting out five bananas should never stop
## because the shelf ran out, and running out would be a failure state (§3.2).

const HIGHLIGHT_PULSE_SECONDS := 0.9

var item_id: String = ""

var _display: Node3D = null
var _glow: MeshInstance3D = null
var _glow_tween: Tween = null


func setup(id: String) -> void:
	item_id = id
	name = "Slot_%s" % id

	add_touch_box()

	_display = PlaceholderFactory.build_item_visual(item_id)
	_display.name = "Display"
	add_child(_display)

	_build_glow()


# ---------------------------------------------------------------- Draggable

func get_drag_payload() -> String:
	return item_id


## Small squash when something is taken, so the shelf acknowledges the touch
## inside 100ms even before the item starts moving (§3.3).
func on_drag_started() -> void:
	if _display == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_display, "scale", Vector3(1.15, 0.85, 1.15), 0.06)
	tween.tween_property(_display, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK)


# ---------------------------------------------------------------- hints

## Turns on when hints escalate to showing the answer (§8.1.8). It is an
## invitation, not a correction — the child has lost nothing by getting here.
func set_highlighted(highlighted: bool) -> void:
	if _glow == null:
		return

	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()

	_glow.visible = highlighted
	if not highlighted:
		return

	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(_glow, "scale", Vector3.ONE * 1.18, HIGHLIGHT_PULSE_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(_glow, "scale", Vector3.ONE, HIGHLIGHT_PULSE_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)


func _build_glow() -> void:
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 10
	sphere.rings = 5
	_glow.mesh = sphere
	_glow.material_override = PlaceholderFactory.get_unshaded_material(Color(Palette.HINT_GLOW, 0.45), true)
	_glow.position.y = 0.2
	_glow.visible = false
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
