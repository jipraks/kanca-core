class_name CounterTray
extends Node3D

## The counter tray the child assembles the order on (PLAN.md §8.1.5-6).
##
## Owns what is on it and where each thing sits. The Warung asks it "what do you
## hold" at validation time and never tracks a parallel list of its own.

signal contents_changed()

const SURFACE_HEIGHT := 0.06
const COLUMN_SPACING := 0.34
const ROW_SPACING := 0.34
const ITEMS_PER_ROW := 5
const DROP_ZONE_SIZE := Vector3(2.0, 0.9, 0.95)

var _items: Array[TrayItem] = []
var _drop_zone: DropTarget = null


func _ready() -> void:
	_build_surface()
	_build_drop_zone()


## Adds an item and re-flows the layout. Returns the new tray item.
func add_item(item_id: String) -> TrayItem:
	var item: TrayItem = TrayItem.new()
	add_child(item)
	item.setup(item_id)
	_items.append(item)
	item.position = _slot_position(_items.size() - 1)
	item.play_drop()
	_reflow()
	contents_changed.emit()
	return item


## Takes an item off the tray without freeing it — the drag controller keeps
## holding it, which is what makes "drag it back off" the undo gesture.
func detach_item(item: TrayItem) -> void:
	var index: int = _items.find(item)
	if index < 0:
		return
	_items.remove_at(index)
	remove_child(item)
	_reflow()
	contents_changed.emit()


func clear() -> void:
	for item: TrayItem in _items:
		item.queue_free()
	_items.clear()
	contents_changed.emit()


## item_id -> count, the shape WarungOrder validates against.
func get_counts() -> Dictionary:
	var counts: Dictionary = {}
	for item: TrayItem in _items:
		counts[item.item_id] = int(counts.get(item.item_id, 0)) + 1
	return counts


func get_items() -> Array[TrayItem]:
	return _items.duplicate()


func is_empty() -> bool:
	return _items.is_empty()


## Where a dropped item should land, in tray-local space.
func get_next_slot_position() -> Vector3:
	return _slot_position(_items.size())


func get_drop_zone() -> DropTarget:
	return _drop_zone


func _slot_position(index: int) -> Vector3:
	var row: int = index / ITEMS_PER_ROW
	var column: int = index % ITEMS_PER_ROW
	var row_count: int = mini(_items.size() - row * ITEMS_PER_ROW, ITEMS_PER_ROW)
	if row_count <= 0:
		row_count = 1
	var span: float = float(mini(maxi(row_count, 1), ITEMS_PER_ROW) - 1) * COLUMN_SPACING
	return Vector3(
		float(column) * COLUMN_SPACING - span * 0.5,
		SURFACE_HEIGHT,
		float(row) * ROW_SPACING - ROW_SPACING * 0.5)


## Keeps the items centred as the count changes, so five bananas read as a row of
## five rather than drifting off one edge.
func _reflow() -> void:
	for i: int in range(_items.size()):
		_items[i].move_to(_slot_position(i))


func _build_surface() -> void:
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = "Surface"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(DROP_ZONE_SIZE.x, 0.06, DROP_ZONE_SIZE.z)
	surface.mesh = box
	surface.material_override = PlaceholderFactory.get_flat_material(Palette.CREAM.darkened(0.08))
	surface.position.y = 0.03
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)


func _build_drop_zone() -> void:
	_drop_zone = DropTarget.new()
	_drop_zone.name = "DropZone"
	add_child(_drop_zone)
	_drop_zone.add_zone_box(DROP_ZONE_SIZE, Vector3(0.0, DROP_ZONE_SIZE.y * 0.5, 0.0))
