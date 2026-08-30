extends Node

## End-to-end check of the Kebun. Developer tool — never shipped.
##
##   godot --headless --path . res://tools/kebun_test.tscn
##
## Covers the life cycle from PLAN.md §8.2 — seed, water, three visible stages,
## harvest — the out-of-order responses that must never punish, and the same
## screen-space touch audit the Warung gets, because plots and seed baskets are
## 3D objects and §3.3 applies to them too.

const MIN_TOUCH := 120.0
const MIN_GAP := 40.0
const KEBUN_SCENE := "res://scenes/minigames/kebun/kebun.tscn"
const BASE_RESOLUTION := Vector2i(1280, 720)

var _passed: int = 0
var _failed: int = 0
var _viewport: SubViewport = null
var _kebun: MiniGame = null
var _requested_voices: Array[String] = []


func _ready() -> void:
	print("=== Kanca kebun test ===")
	Engine.time_scale = 6.0
	GameState.reset()
	VoiceBank.voice_requested.connect(func(voice_id: String) -> void: _requested_voices.append(voice_id))

	await _run()

	Engine.time_scale = 1.0
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _run() -> void:
	var packed: PackedScene = load(KEBUN_SCENE) as PackedScene
	if not _check("kebun scene loads", packed != null, "missing or unreadable"):
		return

	_kebun = packed.instantiate() as MiniGame
	if not _check("kebun extends MiniGame", _kebun != null, "the router would refuse it"):
		return

	_viewport = SubViewport.new()
	_viewport.size = BASE_RESOLUTION
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.add_child(_kebun)

	await get_tree().process_frame
	await get_tree().process_frame

	_check("game id matches the registry", _kebun.get_game_id() == "kebun",
		"got %s" % _kebun.get_game_id())
	_check("the Kebun is registered as available now",
		ContentDB.is_mini_game_available("kebun"), "the hub would still show it unbuilt")

	var finished: Array[MiniGameResult] = []
	_kebun.session_completed.connect(func(result: MiniGameResult) -> void: finished.append(result))

	_kebun.start_session(1)
	await get_tree().process_frame

	await _test_layout()
	await _test_life_cycle()
	await _test_out_of_order()
	await _test_full_session(finished)
	await _test_matched_plots()


# ---------------------------------------------------------------- tests

func _test_layout() -> void:
	var level: Dictionary = ContentDB.get_level("kebun", 1)
	_check("six plots, as §8.2 specifies", _plots().size() == int(level.get("plots", 6)),
		"got %d" % _plots().size())
	_check("growth is six seconds, never longer",
		float(level.get("grow_seconds", 0.0)) <= 6.0 and float(level.get("grow_seconds", 0.0)) > 0.0,
		"got %s" % level.get("grow_seconds"))
	_check("three visible stages", int(level.get("grow_stages", 0)) == 3,
		"got %s" % level.get("grow_stages"))

	var camera: Camera3D = _kebun._camera
	var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(BASE_RESOLUTION))

	# Plots are both drop targets and, once ripe, tap targets. The audit measures
	# the drop zone, which is the larger of the two.
	var plot_rects: Array[Rect2] = []
	for plot: GardenPlot in _plots():
		var rect: Rect2 = _project_area(camera, plot.get_drop_zone())
		plot_rects.append(rect)
		_check("plot %d is at least 120x120 on screen" % plot.index,
			rect.size.x >= MIN_TOUCH and rect.size.y >= MIN_TOUCH,
			"projected to %.0fx%.0f px" % [rect.size.x, rect.size.y])
		_check("plot %d is fully on screen" % plot.index, screen.encloses(rect),
			"projected to %s" % rect)

	_check_gaps(plot_rects, "plots")

	var source_rects: Array[Rect2] = []
	var labels: Array[String] = []
	for source: SeedSource in _seed_sources():
		source_rects.append(_project_area(camera, source))
		labels.append(source.item_id)
	source_rects.append(_project_area(camera, _kebun._can))
	labels.append("watering can")

	for i: int in range(source_rects.size()):
		_check("%s is at least 120x120 on screen" % labels[i],
			source_rects[i].size.x >= MIN_TOUCH and source_rects[i].size.y >= MIN_TOUCH,
			"projected to %.0fx%.0f px" % [source_rects[i].size.x, source_rects[i].size.y])
		_check("%s is fully on screen" % labels[i], screen.encloses(source_rects[i]),
			"projected to %s" % source_rects[i])

	_check_gaps(source_rects, "seed row")


func _test_life_cycle() -> void:
	var plot: GardenPlot = _plots()[0]
	var seed_id: String = _seed_sources()[0].item_id

	_check("a fresh plot is empty", plot.can_plant(), "state %d" % plot.get_state())
	_check("a fresh plot cannot be harvested", not plot.is_ready(), "it was ripe already")

	_requested_voices.clear()
	await _drag_to_plot(_seed_sources()[0], plot)
	_check("dropping a seed plants it", plot.needs_water(), "state %d" % plot.get_state())
	_check("picking a seed speaks its name",
		_requested_voices.has(ContentDB.get_item_voice_id(seed_id)),
		"voices: %s" % [_requested_voices])
	_check("Kanca says what comes next", _requested_voices.has("kanca_kebun_siram"),
		"voices: %s" % [_requested_voices])

	# §8.2: three visible stages, then fruit. Watch it actually progress rather
	# than trusting the end state.
	_requested_voices.clear()
	await _drag_to_plot(_kebun._can, plot)
	_check("watering starts growth", plot.get_state() == GardenPlot.State.GROWING,
		"state %d" % plot.get_state())
	_check("picking up water is announced", _requested_voices.has("kanca_kebun_air"),
		"voices: %s" % [_requested_voices])

	var grew: bool = await _await_until(func() -> bool: return plot.is_ready(), 25.0)
	_check("the plant ripens", grew, "timed out waiting for growth")
	_check("a ripe plot offers something to tap",
		plot.get_harvest_target().collision_layer == TapTarget.INTERACTABLE_LAYER,
		"the harvest target was not switched on")

	_requested_voices.clear()
	await _tap(plot.get_harvest_target())
	_check("tapping a ripe plot harvests it", plot.is_finished(), "state %d" % plot.get_state())
	_check("harvesting names what was picked",
		_requested_voices.has(ContentDB.get_item_voice_id(seed_id)),
		"voices: %s" % [_requested_voices])


func _test_out_of_order() -> void:
	var plot: GardenPlot = _plots()[1]

	# Water before seed. §3.2: gentle, and nothing changes.
	_requested_voices.clear()
	await _drag_to_plot(_kebun._can, plot)
	_check("watering bare soil does nothing", plot.can_plant(), "state %d" % plot.get_state())
	_check("watering bare soil is answered gently",
		_requested_voices.has("kanca_kebun_tanam"), "voices: %s" % [_requested_voices])

	# Harvesting an unripe plot must be inert, not punished.
	var before: int = _kebun._harvest_count
	await _tap(plot.get_harvest_target())
	_check("an unripe plot cannot be harvested", _kebun._harvest_count == before,
		"harvest count moved to %d" % _kebun._harvest_count)

	# Seeding twice.
	await _drag_to_plot(_seed_sources()[0], plot)
	_requested_voices.clear()
	await _drag_to_plot(_seed_sources()[0], plot)
	_check("a second seed on the same plot is refused gently",
		_requested_voices.has("kanca_ui_belum_waktunya"), "voices: %s" % [_requested_voices])
	_check("the first seed is still there", plot.needs_water(), "state %d" % plot.get_state())


func _test_full_session(finished: Array[MiniGameResult]) -> void:
	var done: bool = await _await_until(func() -> bool: return not finished.is_empty(), 120.0,
		_tend_garden)
	if not _check("the whole garden can be worked through", done,
			"harvested %d of %d" % [_kebun._harvest_count, _plots().size()]):
		return

	var result: MiniGameResult = finished[0]
	var level: Dictionary = ContentDB.get_level("kebun", 1)

	_check("every plot was harvested", result.rounds_completed == _plots().size(),
		"got %d" % result.rounds_completed)
	_check("the session pays out", result.coins_earned == int(level.get("coins_per_session", 3)),
		"got %d" % result.coins_earned)

	# §8.2: this is the chain. Produce grown here has to reach the inventory, or
	# the Warung shelf will never know about it.
	var produced: int = 0
	for item_id: String in result.items_produced:
		produced += int(result.items_produced[item_id])
	_check("harvested produce comes back as inventory", produced == _plots().size(),
		"produced %s" % result.items_produced)

	GameState.apply_result(result)
	_check("the inventory actually receives it", GameState.has_any_stock(),
		"inventory is %s" % GameState.inventory)


## Level 3 labels each plot with the seed it wants (§8.2). Wrong seed, gentle no.
func _test_matched_plots() -> void:
	_kebun.start_session(3)
	await get_tree().process_frame

	var level: Dictionary = ContentDB.get_level("kebun", 3)
	_check("level 3 asks for matching", bool(level.get("match_seed_to_plot", false)),
		"the level data says otherwise")

	var plot: GardenPlot = _plots()[0]
	_check("a matched plot states what it wants", not plot.required_item_id.is_empty(),
		"no requirement was assigned")

	var wrong: SeedSource = null
	for source: SeedSource in _seed_sources():
		if source.item_id != plot.required_item_id:
			wrong = source
			break
	if not _check("there is a wrong seed to try", wrong != null, "only one seed type"):
		return

	_requested_voices.clear()
	await _drag_to_plot(wrong, plot)
	_check("the wrong seed is refused", plot.can_plant(), "it was planted anyway")
	_check("the refusal is gentle, never a rebuke",
		_requested_voices.has("kanca_ui_coba_lagi"), "voices: %s" % [_requested_voices])

	var right: SeedSource = null
	for source: SeedSource in _seed_sources():
		if source.item_id == plot.required_item_id:
			right = source
			break
	await _drag_to_plot(right, plot)
	_check("the right seed is accepted", plot.needs_water(), "state %d" % plot.get_state())

	# Level 3 puts three baskets in the row. If the seed row is ever going to
	# crowd, it crowds here, not at level 1 where there is only one.
	var camera: Camera3D = _kebun._camera
	var rects: Array[Rect2] = []
	for source: SeedSource in _seed_sources():
		rects.append(_project_area(camera, source))
	rects.append(_project_area(camera, _kebun._can))
	_check("level 3 has a full seed row", rects.size() >= 4, "only %d sources" % rects.size())
	_check_gaps(rects, "level 3 seed row")


# ---------------------------------------------------------------- helpers

## Plants, waters and picks whatever is ready, one action per tick.
func _tend_garden() -> void:
	if not _kebun._session_active:
		return
	for plot: GardenPlot in _plots():
		if plot.is_ready():
			_kebun._on_tapped(plot.get_harvest_target())
			return
		if plot.can_plant():
			_kebun._on_dropped(_seed_sources()[0].item_id, plot.get_drop_zone())
			return
		if plot.needs_water():
			_kebun._on_dropped(WateringCan.PAYLOAD, plot.get_drop_zone())
			return


func _plots() -> Array[GardenPlot]:
	var result: Array[GardenPlot] = []
	for child: Node in _kebun._plots_root.get_children():
		var plot: GardenPlot = child as GardenPlot
		if plot != null and not plot.is_queued_for_deletion():
			result.append(plot)
	return result


func _seed_sources() -> Array[SeedSource]:
	var result: Array[SeedSource] = []
	for child: Node in _kebun._seeds_root.get_children():
		var source: SeedSource = child as SeedSource
		if source != null and not source.is_queued_for_deletion():
			result.append(source)
	return result


func _drag_to_plot(source: Draggable, plot: GardenPlot) -> void:
	var camera: Camera3D = _kebun._camera
	var from: Vector2 = camera.unproject_position(source.global_position + Vector3(0.0, 0.2, 0.0))
	var to: Vector2 = camera.unproject_position(plot.global_position + Vector3(0.0, 0.25, 0.0))
	await _pointer_drag(from, to)


func _tap(target: TapTarget) -> void:
	var camera: Camera3D = _kebun._camera
	var at: Vector2 = camera.unproject_position(target.global_position + Vector3(0.0, 0.55, 0.0))
	await _pointer_drag(at, at)


func _pointer_drag(from: Vector2, to: Vector2) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	_viewport.push_input(press)
	await get_tree().process_frame

	if not from.is_equal_approx(to):
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


## Screen-space footprint of an area's collision box — what a finger has to hit.
func _project_area(camera: Camera3D, area: Area3D) -> Rect2:
	var shape: CollisionShape3D = null
	for child: Node in area.get_children():
		if child is CollisionShape3D:
			shape = child as CollisionShape3D
			break
	if shape == null:
		return Rect2()

	var box: BoxShape3D = shape.shape as BoxShape3D
	if box == null:
		return Rect2()

	var half: Vector3 = box.size * 0.5
	var centre: Vector3 = area.global_position + shape.position

	var min_point: Vector2 = Vector2.INF
	var max_point: Vector2 = -Vector2.INF
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var projected: Vector2 = camera.unproject_position(
					centre + Vector3(half.x * sx, half.y * sy, half.z * sz))
				min_point = min_point.min(projected)
				max_point = max_point.max(projected)

	return Rect2(min_point, max_point - min_point)


func _check_gaps(rects: Array[Rect2], label: String) -> void:
	for i: int in range(rects.size()):
		for j: int in range(i + 1, rects.size()):
			var dx: float = maxf(rects[i].position.x - rects[j].end.x, rects[j].position.x - rects[i].end.x)
			var dy: float = maxf(rects[i].position.y - rects[j].end.y, rects[j].position.y - rects[i].end.y)
			var gap: float = maxf(dx, dy)
			_check("%s %d and %d are at least 40px apart" % [label, i, j], gap >= MIN_GAP,
				"gap was %.1fpx" % gap)


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
