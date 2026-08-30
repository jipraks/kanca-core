class_name ZoomControls
extends Control

## The village's zoom buttons (PLAN.md §3.3, §7.1).
##
## Buttons rather than a pinch, because §3.3 rules out multi-touch outright:
## "No double-tap, long-press, swipe, pinch, or multi-touch gestures anywhere."
## That is not a limitation to work around here — a pinch needs two fingers held
## at once on a screen a small hand is also gripping, and it has no discoverable
## affordance. Two targets you press do.
##
## Sizes come from §3.3 and not from taste: 120×120 each, 40 apart, so the pair
## is 120 wide and 280 tall at the 1280×720 base.

const BUTTON_SIZE := 120.0
const GAP := 40.0
const SPAN := Vector2(BUTTON_SIZE, BUTTON_SIZE * 2.0 + GAP)

@export var accent: Color = Color(Palette.UI_PANEL, 0.88)
@export var icon_colour: Color = Palette.UI_TEXT

## Set by the hub, the same way the player's pad and camera are.
var camera: HubCamera = null:
	set(value):
		if camera != null and camera.view_changed.is_connected(_on_view_changed):
			camera.view_changed.disconnect(_on_view_changed)
		camera = value
		if camera != null:
			camera.view_changed.connect(_on_view_changed)
		_refresh()

var _in_button: BigButton = null
var _out_button: BigButton = null


func _ready() -> void:
	custom_minimum_size = SPAN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_in_button = _make_button("ZoomIn", true, Vector2.ZERO)
	_out_button = _make_button("ZoomOut", false, Vector2(0.0, BUTTON_SIZE + GAP))
	_refresh()


func _make_button(node_name: String, zoom_in: bool, offset: Vector2) -> BigButton:
	var button: BigButton = BigButton.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.position = offset
	button.accent = accent
	# The 120 stays: §3.3 sets it as a floor and these are at it, so they cannot
	# get smaller. What can change is how much of that they paint — the panel is
	# drawn at 96 inside a 120 target, which keeps the press forgiving and stops
	# two white slabs dominating the right-hand edge of the village.
	button.visual_inset = 12.0
	button.icon_texture = PlaceholderFactory.build_zoom_icon(zoom_in, icon_colour, 78)
	button.pressed.connect(_on_pressed.bind(zoom_in))
	add_child(button)
	return button


func _on_pressed(zoom_in: bool) -> void:
	if camera == null:
		return
	# The camera reports whether the step actually moved. It cannot here — the
	# button is locked at the end of the range — but relying on that would make
	# this correct by coincidence.
	if zoom_in:
		camera.zoom_in()
	else:
		camera.zoom_out()


func _on_view_changed() -> void:
	_refresh()


## A button at the end of its range is locked, not hidden. §3.2 forbids anything
## that reads as a penalty, and a control that vanishes under the finger is
## worse than one that visibly has nothing left to give — the child loses the
## thing they were aiming at mid-press.
func _refresh() -> void:
	if _in_button == null or _out_button == null:
		return
	_in_button.is_locked = camera == null or not camera.can_zoom_in()
	_out_button.is_locked = camera == null or not camera.can_zoom_out()
