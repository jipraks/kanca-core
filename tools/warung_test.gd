extends Node

## End-to-end check of the Warung. Developer tool — never shipped.
##
##   godot --headless --path . res://tools/warung_test.tscn
##
## This is the M2 "done when" from PLAN.md §14, run by machine: a full
## five-customer session completes, and both correct and incorrect answers behave
## the way §8.1 says they must. It also projects the 3D shelf into screen space
## and checks the §3.3 touch rules there, which is the part that cannot be
## verified by looking at the UI layer alone.

const MIN_TOUCH := 120.0
const MIN_GAP := 40.0
const WARUNG_SCENE := "res://scenes/minigames/warung/warung.tscn"

## The game is hosted in a SubViewport pinned to the base resolution from
## PLAN.md §4.1. Headless has no window, so the default viewport comes out square
## and every screen-space measurement below would be against a resolution no
## phone has. Pinning it means the touch audit measures what a child actually
## sees at 1280×720.
const BASE_RESOLUTION := Vector2i(1280, 720)

var _passed: int = 0
var _failed: int = 0
var _viewport: SubViewport = null
var _warung: MiniGame = null
var _requested_voices: Array[String] = []


func _ready() -> void:
	print("=== Kanca warung test ===")
	# Animations and the 1.5s gap between customers are real design decisions but
	# make a headless run take half a minute. Time scale keeps the sequencing
	# honest while getting the answer back quickly.
	Engine.time_scale = 6.0

	GameState.reset()
	VoiceBank.voice_requested.connect(func(voice_id: String) -> void: _requested_voices.append(voice_id))

	await _run()

	Engine.time_scale = 1.0
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _run() -> void:
	var packed: PackedScene = load(WARUNG_SCENE) as PackedScene
	if not _check("warung scene loads", packed != null, "missing or unreadable"):
		return

	_warung = packed.instantiate() as MiniGame
	if not _check("warung extends MiniGame", _warung != null, "the router would refuse it"):
		return

	_viewport = SubViewport.new()
	_viewport.size = BASE_RESOLUTION
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_viewport.add_child(_warung)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("test runs at the base resolution",
		_warung._camera.get_viewport().get_visible_rect().size == Vector2(BASE_RESOLUTION),
		"got %s" % _warung._camera.get_viewport().get_visible_rect().size)

	_check("game id matches the registry", _warung.get_game_id() == "warung",
		"got %s" % _warung.get_game_id())

	var finished: Array[MiniGameResult] = []
	_warung.session_completed.connect(func(result: MiniGameResult) -> void: finished.append(result))

	_warung.start_session(1)
	await get_tree().process_frame

	await _test_shelf_layout()
	_test_stock_is_scenery()
	await _test_first_round_by_dragging()
	await _test_wrong_answers_and_hints()
	await _test_remaining_rounds(finished)


# ---------------------------------------------------------------- tests

func _test_shelf_layout() -> void:
	var level: Dictionary = ContentDB.get_level("warung", 1)
	var slots: Array = _warung._shelf.get_children()
	_check("shelf stocked from the level", slots.size() == int(level.get("shelf_item_types", 3)),
		"got %d slots" % slots.size())

	var camera: Camera3D = _warung._camera
	var rects: Array[Rect2] = []

	for child: Node in slots:
		var slot: ShelfSlot = child as ShelfSlot
		var rect: Rect2 = _project_slot(camera, slot)
		rects.append(rect)
		_check("shelf %s is at least 120x120 on screen" % slot.item_id,
			rect.size.x >= MIN_TOUCH and rect.size.y >= MIN_TOUCH,
			"projected to %.0fx%.0f px" % [rect.size.x, rect.size.y])
		var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(BASE_RESOLUTION))
		_check("shelf %s is fully on screen" % slot.item_id, screen.encloses(rect),
			"projected to %s, screen is %s" % [rect, screen])

	for i: int in range(rects.size()):
		for j: int in range(i + 1, rects.size()):
			var gap: float = _gap_between(rects[i], rects[j])
			_check("shelf slots %d and %d are at least 40px apart" % [i, j], gap >= MIN_GAP,
				"gap was %.1fpx" % gap)


## The first customer is served with real pointer input through the viewport, so
## the whole picking, carrying and dropping path is exercised rather than the
## tray being filled behind its back.
## The shop's stock is scenery and must stay scenery (§3.3, §8.1).
##
## The racks hold dozens of jars because five items on a counter is not a shop.
## But §3.3's 120×120 minimum caps what a child can actually pick up at five, so
## everything on the racks is out of reach by design.
##
## That boundary is worth a test because breaking it is silent and the damage is
## the wrong kind. A tin that looks like the apple beside it and does not respond
## to a small hand does not just fail once — it teaches a child that touching
## things is not how this works, which is the opposite of what every other screen
## in the game is trying to teach.
func _test_stock_is_scenery() -> void:
	var stock: Node3D = _warung.get_node_or_null("Stock") as Node3D
	if not _check("the shop has stock behind the counter", stock != null, "none built"):
		return

	var meshes: int = 0
	var reachable: Array[String] = []
	_survey_stock(stock, meshes, reachable)

	_check("the racks are actually stocked", _count_meshes(stock) >= 4,
		"only %d mesh instances" % _count_meshes(stock))
	_check("nothing in the shop's stock can be picked up", reachable.is_empty(),
		"these respond to touch: %s" % ", ".join(reachable))


func _count_meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		total += _count_meshes(child)
	return total


## Anything draggable, tappable, or sitting on the interactable collision layer
## counts as reachable — those are the three ways something becomes touchable
## here, and a new one would want adding.
func _survey_stock(node: Node, meshes: int, reachable: Array[String]) -> void:
	if node is Draggable or node is TapTarget:
		reachable.append(node.name)
	var body: CollisionObject3D = node as CollisionObject3D
	if body != null and (body.collision_layer & 4) != 0:
		reachable.append("%s (interactable layer)" % node.name)
	for child: Node in node.get_children():
		_survey_stock(child, meshes, reachable)


func _test_first_round_by_dragging() -> void:
	var arrived: bool = await _await_until(
		func() -> bool: return _warung._current_order != null and _warung._drag._enabled,
		12.0)
	if not _check("first customer arrives and dragging opens", arrived, "timed out"):
		return

	var order: WarungOrder = _warung._current_order
	_check("order card shows the order", _warung._order_card.visible, "card was hidden")
	_check("order only asks for stocked items",
		order.get_item_ids().all(func(id: String) -> bool: return _warung._slots.has(id)),
		"order wanted something not on the shelf: %s" % order.describe())

	var item_id: String = order.get_item_ids()[0]
	_requested_voices.clear()

	await _drag_from_shelf_to_tray(item_id)
	_check("dragging from the shelf puts one on the tray",
		int(_warung._tray.get_counts().get(item_id, 0)) == 1,
		"tray holds %s" % _warung._tray.get_counts())

	# §8.1.5: every item names itself as it is picked up. This is the vocabulary
	# learning, and it is explicitly not optional.
	_check("picking an item speaks its name",
		_requested_voices.has(ContentDB.get_item_voice_id(item_id)),
		"voices requested: %s" % [_requested_voices])

	# §8.1.6: undo must always be available.
	await _drag_from_tray_to_nowhere(item_id)
	_check("dragging a tray item off again undoes it",
		int(_warung._tray.get_counts().get(item_id, 0)) == 0,
		"tray holds %s" % _warung._tray.get_counts())


func _test_wrong_answers_and_hints() -> void:
	var order: WarungOrder = _warung._current_order
	if order == null:
		_check("an order is in progress", false, "none")
		return

	var wanted_item: String = order.get_item_ids()[0]
	var rounds_before: int = _warung._rounds_completed

	# Deliberately one too many. §3.2: this must cost nothing at all. Over rather
	# than under, so the tray still holds something even when the order is a
	# single item of quantity one.
	_fill_tray(order.counts, wanted_item, 1)
	_warung._confirm_button.pressed.emit()
	await get_tree().process_frame

	_check("a wrong answer does not complete the round",
		_warung._rounds_completed == rounds_before, "round counter moved")
	_check("a wrong answer earns nothing and loses nothing", _warung._coins_earned == 0,
		"coins were %d" % _warung._coins_earned)
	_check("the order card stays up after a wrong answer", _warung._order_card.visible,
		"the card vanished, leaving nothing to refer back to")
	_check("items stay on the tray for adjusting", not _warung._tray.is_empty(),
		"the tray was cleared, discarding the child's work")
	_check("no shelf glow on the first mistake", not _any_slot_highlighted(),
		"the answer was given away immediately")

	_warung._confirm_button.pressed.emit()
	await get_tree().process_frame
	_check("still no glow on the second mistake", not _any_slot_highlighted(), "too early")

	# §8.1.8: after three attempts the correct items begin glowing.
	_requested_voices.clear()
	_warung._confirm_button.pressed.emit()
	await get_tree().process_frame
	_check("the shelf glows after three attempts", _any_slot_highlighted(),
		"a child who has tried three times is still stuck")
	var expected: Array[String] = order.get_item_ids()
	expected.sort()
	_check("every correct item glows, and only those", _highlighted_item_ids() == expected,
		"glowing %s, expected %s" % [_highlighted_item_ids(), expected])
	_check("Kanca offers the strongest hint", _requested_voices.has("kanca_hint_lihat"),
		"voices requested: %s" % [_requested_voices])
	# The tray is deliberately one over, so the hint must also address the count.
	_check("an overcount is nudged towards counting again",
		_requested_voices.has("kanca_hint_hitung"),
		"voices requested: %s" % [_requested_voices])

	# Now get it right.
	_fill_tray(order.counts, "", 0)
	_warung._confirm_button.pressed.emit()

	var completed: bool = await _await_until(
		func() -> bool: return _warung._rounds_completed == rounds_before + 1, 12.0)
	_check("a correct answer completes the round", completed, "timed out")
	_check("a correct answer pays out", _warung._coins_earned > 0, "no coins")
	_check("the glow clears once it is right", not _any_slot_highlighted(), "still glowing")
	_check("the tray is cleared for the next customer", _warung._tray.is_empty(),
		"tray holds %s" % _warung._tray.get_counts())


func _test_remaining_rounds(finished: Array[MiniGameResult]) -> void:
	var level: Dictionary = ContentDB.get_level("warung", 1)
	var target: int = int(level.get("customers_per_session", 5))

	var done: bool = await _await_until(func() -> bool: return not finished.is_empty(), 90.0,
		func() -> void: _auto_serve())

	if not _check("the full session completes", done, "timed out after %d rounds"
			% _warung._rounds_completed):
		return

	var result: MiniGameResult = finished[0]
	_check("every customer was served", result.rounds_completed == target,
		"served %d of %d" % [result.rounds_completed, target])
	_check("coins match the level payout",
		result.coins_earned == target * int(level.get("coins_per_customer", 2)),
		"earned %d" % result.coins_earned)
	_check("the result is tagged with the game and level",
		result.game_id == "warung" and result.level_index == 1,
		"got %s L%d" % [result.game_id, result.level_index])

	# §8.4: the economy is a reward, never a gate. With an empty inventory the
	# shop still runs and simply consumes nothing.
	_check("nothing was consumed from an empty inventory", result.items_consumed.is_empty(),
		"consumed %s" % result.items_consumed)


# ---------------------------------------------------------------- helpers

## Fills the tray to match `counts`, optionally miscounting one item by `delta`.
func _fill_tray(counts: Dictionary, wrong_item: String, delta: int) -> void:
	_warung._tray.clear()
	for item_id: String in counts:
		var wanted: int = int(counts[item_id])
		if item_id == wrong_item:
			wanted = maxi(wanted + delta, 0)
		for i: int in range(wanted):
			_warung._tray.add_item(item_id)


## Serves whatever customer is currently waiting, correctly.
func _auto_serve() -> void:
	var order: WarungOrder = _warung._current_order
	if order == null or not _warung._drag._enabled:
		return
	if order.is_satisfied_by(_warung._tray.get_counts()):
		return
	_fill_tray(order.counts, "", 0)
	_warung._confirm_button.pressed.emit()


func _drag_from_shelf_to_tray(item_id: String) -> void:
	var camera: Camera3D = _warung._camera
	var slot: ShelfSlot = _warung._slots[item_id] as ShelfSlot
	var from: Vector2 = camera.unproject_position(slot.global_position + Vector3(0.0, 0.2, 0.0))
	var to: Vector2 = camera.unproject_position(_warung._tray.global_position + Vector3(0.0, 0.3, 0.0))
	await _pointer_drag(from, to)


func _drag_from_tray_to_nowhere(item_id: String) -> void:
	var camera: Camera3D = _warung._camera
	var items: Array[TrayItem] = _warung._tray.get_items()
	if items.is_empty():
		return
	var from: Vector2 = camera.unproject_position(items[0].global_position + Vector3(0.0, 0.15, 0.0))
	# Off to the side of the counter, where there is no drop zone at all.
	var to: Vector2 = camera.unproject_position(Vector3(-3.4, 1.3, 1.2))
	await _pointer_drag(from, to)


func _pointer_drag(from: Vector2, to: Vector2) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	_viewport.push_input(press)
	await get_tree().process_frame

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	_viewport.push_input(motion)
	await get_tree().process_frame

	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	_viewport.push_input(release)
	await get_tree().process_frame
	await get_tree().process_frame


## Screen-space footprint of a shelf slot's collision box — what a finger has to
## hit, not what the mesh happens to look like.
func _project_slot(camera: Camera3D, slot: ShelfSlot) -> Rect2:
	var shape: CollisionShape3D = null
	for child: Node in slot.get_children():
		if child is CollisionShape3D:
			shape = child as CollisionShape3D
			break
	if shape == null:
		return Rect2()

	var box: BoxShape3D = shape.shape as BoxShape3D
	var half: Vector3 = box.size * 0.5
	var centre: Vector3 = slot.global_position + shape.position

	var min_point: Vector2 = Vector2.INF
	var max_point: Vector2 = -Vector2.INF
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var corner: Vector3 = centre + Vector3(half.x * sx, half.y * sy, half.z * sz)
				var projected: Vector2 = camera.unproject_position(corner)
				min_point = min_point.min(projected)
				max_point = max_point.max(projected)

	return Rect2(min_point, max_point - min_point)


func _gap_between(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var dy: float = maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	return maxf(dx, dy)


func _any_slot_highlighted() -> bool:
	return not _highlighted_item_ids().is_empty()


func _highlighted_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for child: Node in _warung._shelf.get_children():
		var slot: ShelfSlot = child as ShelfSlot
		if slot == null:
			continue
		var glow: MeshInstance3D = slot.get_node_or_null("Glow") as MeshInstance3D
		if glow != null and glow.visible:
			ids.append(slot.item_id)
	ids.sort()
	return ids


func _await_until(predicate: Callable, timeout_seconds: float, each_frame: Callable = Callable()) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		if each_frame.is_valid():
			each_frame.call()
		await get_tree().process_frame
	return false


func _check(label: String, condition: bool, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s -- %s" % [label, detail])
	return condition
