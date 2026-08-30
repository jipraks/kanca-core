extends Node

## Boot to hub to mini-game and back, through the real router. Developer tool.
##
##   godot --headless --path . res://tools/integration_test.tscn
##
## This is the M1 "done when" from PLAN.md §14 — enter a mini-game, leave it, and
## have progress survive — plus the parts of §6.3, §7.2 and §8.2 that only show up
## once the pieces are wired together: the hub stays loaded rather than reloading,
## unlocking cascades, the celebration lands after the fade rather than behind it,
## and what is grown in the garden turns up as inventory the shop stocks from.

const WARUNG_LEVEL_COINS := 2
const PLAYER_START_FOR_TESTS := Vector2(0.0, 4.0)

var _passed: int = 0
var _failed: int = 0
var _hub: Node3D = null


func _ready() -> void:
	print("=== Kanca integration test ===")
	Engine.time_scale = 6.0
	GameState.reset()

	await _run()

	Engine.time_scale = 1.0
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _run() -> void:
	# Fresh save: the Kebun is where a new player starts, and it is the only thing
	# open to them (§7.2).
	_check("a fresh player has earned the Kebun", GameState.is_unlocked("kebun"), "locked")
	_check("a fresh player has not earned the Warung", not GameState.is_unlocked("warung"), "open")
	_check("the Kebun is built", ContentDB.is_mini_game_available("kebun"), "scene missing")
	_check("the Warung is built", ContentDB.is_mini_game_available("warung"), "scene missing")
	_check("the Dapur is not built yet", not ContentDB.is_mini_game_available("dapur"),
		"a dapur scene exists now, this expectation is stale")

	# The router frees whatever the current scene is when it takes over from boot,
	# and here that would be this harness. Detaching first leaves the harness in
	# the tree as a plain child of root, watching the real flow from the outside.
	get_tree().current_scene = null

	SceneRouter.go_to_hub()
	var loaded: bool = await _await_until(func() -> bool: return _find_hub() != null, 20.0)
	if not _check("the router loads the hub", loaded, "timed out"):
		return
	_hub = _find_hub()

	await _await_until(func() -> bool: return not SceneRouter.is_transitioning(), 20.0)

	_check("the hub is the current scene", get_tree().current_scene == _hub,
		"got %s" % get_tree().current_scene)
	_check("all three buildings are in the village", _hub._buildings.size() == 3,
		"got %d" % _hub._buildings.size())

	_check_player_model()
	_check_camera_controls()
	await _check_the_world_is_solid()

	# §7.2: a locked building is visible and resting, never a padlock, and an
	# unbuilt one is under construction rather than a door that leads nowhere.
	_check("the Kebun is open on a fresh save",
		(_hub._buildings["kebun"] as Building).is_unlocked, "it was shut")
	_check("the Warung shows as not ready", not (_hub._buildings["warung"] as Building).is_unlocked,
		"it was open before the Kebun was played")
	_check("the Kebun is what a new player is pointed at",
		_hub._get_recommended_game_id() == "kebun",
		"recommended %s" % _hub._get_recommended_game_id())

	await _test_kebun_unlocks_warung()
	await _test_no_auto_enter()
	await _test_warung_round_trip()
	await _test_progress_survives_a_restart()


## The fence stops the child, and the trees do too (§7.1).
##
## §7.1 forbids invisible walls a child can walk into and get stuck against. The
## inverse is just as bad and is what this catches: scenery that looks solid and
## is not. A fence that can be walked through is not a boundary, it is a
## decoration the child learns to ignore — and a tree they pass through teaches
## the same thing about everything else in the village.
func _check_the_world_is_solid() -> void:
	var player: HubPlayer = _hub._player
	var limit: float = _hub.fence_line()

	# Counted against the trees that are actually there, not against a number
	# written here. The scatter rejects any tree that would land on a path, a
	# building or the child's starting spot, so how many get planted is not
	# knowable from TREE_COUNT — and a test that hard-codes it passes for the
	# wrong reason the day someone moves a building.
	var trees: Node3D = _hub._world.get_node_or_null("Trees") as Node3D
	var planted: int = 0
	var trunks: int = 0
	if trees != null:
		for child: Node in trees.get_children():
			if child is StaticBody3D:
				trunks += 1
			var multi: MultiMeshInstance3D = child as MultiMeshInstance3D
			if multi != null and multi.multimesh != null:
				planted += multi.multimesh.instance_count

	_check("the village has trees in it", planted > 0, "none were planted")
	_check("every planted tree has a trunk collider", trunks == planted,
		"%d trees, %d trunk bodies" % [planted, trunks])

	# Walk at the fence for two seconds of game time and see where it stops.
	player.warp_to(Vector2(0.0, limit - 3.0))
	await get_tree().physics_frame
	Input.action_press(&"hub_move_down", 1.0)
	for _frame: int in range(140):
		await get_tree().physics_frame
	Input.action_release(&"hub_move_down")

	var stopped_at: float = player.global_position.z
	_check("walking into the fence stops the child",
		stopped_at < limit + 0.2, "walked to z %.2f, fence is at %.2f" % [stopped_at, limit])
	_check("and the child is stopped by the fence, not before it",
		stopped_at > limit - 2.0,
		"stopped %.2f metres short of the fence" % (limit - stopped_at))

	player.warp_to(PLAYER_START_FOR_TESTS)


## The camera controls have to be wired, and the gesture layer has to sit at the
## bottom of the UI stack (§3.3, §7.1).
##
## The ordering is the whole test. Godot offers a touch to the topmost control
## first, so a full-screen gesture catcher placed above the joystick would
## swallow every press and spin the village whenever the child tried to walk.
## Nothing about the scene looks wrong when that happens — it only shows up under
## a finger.
func _check_camera_controls() -> void:
	var camera: HubCamera = _hub._camera
	var gestures: CameraGestures = _hub._gestures
	var zoom: ZoomControls = _hub._zoom

	if not _check("the hub has gesture and zoom controls",
			gestures != null and zoom != null, "one is missing"):
		return

	_check("the gesture layer drives the camera", gestures.camera == camera, "not wired")
	_check("the zoom buttons drive the same camera", zoom.camera == camera, "not wired")

	var screen: Control = gestures.get_parent() as Control
	_check("the gesture layer is beneath every other control",
		screen != null and screen.get_child(0) == gestures,
		"it is at index %d" % gestures.get_index())
	_check("the gesture layer covers the whole screen",
		gestures.size.x > 600.0 and gestures.size.y > 300.0, "only %s" % gestures.size)

	# A drag turns the view and a pinch resizes it, and neither may move the child.
	var before: Vector3 = _hub._player.global_position
	camera.turn_by(0.9)
	camera.zoom_by_ratio(1.4)
	_check("steering the camera does not move the avatar",
		_hub._player.global_position.is_equal_approx(before),
		"the player slid to %s" % _hub._player.global_position)
	_check("the view actually changed", not is_zero_approx(camera.get_yaw())
		and not is_equal_approx(camera.get_distance(), HubCamera.DEFAULT_DISTANCE),
		"yaw %.2f, distance %.2f" % [camera.get_yaw(), camera.get_distance()])

	camera.reset_view()


## The avatar has to be the built model, standing on the ground, facing forward.
##
## Two failures this catches. A model whose origin is not at the feet sinks into
## the path or floats above it, and the mistake is invisible in Blender — the
## build script places the origin, so nothing on the Godot side would notice if
## that ever stopped happening. And a broken import falls back silently to the
## placeholder capsule, which still moves and still collides: the game plays
## correctly and looks wrong, which is the worst kind of regression to spot.
func _check_player_model() -> void:
	var player: HubPlayer = _hub._player
	var visual: Node3D = player._visual

	if not _check("the player has a visual", visual != null, "none"):
		return

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(visual, meshes)
	if not _check("the player's visual has geometry", not meshes.is_empty(), "no meshes"):
		return

	_check("the player uses the built model, not the placeholder capsule",
		ResourceLoader.exists(HubPlayer.MODEL) == (visual.scene_file_path == HubPlayer.MODEL),
		"scene_file_path %s" % visual.scene_file_path)

	# Feet on the floor. The visual sits at the body's origin, so the lowest
	# vertex of its combined bounds is how far it sinks.
	var lowest: float = INF
	var highest: float = -INF
	for mesh: MeshInstance3D in meshes:
		var bounds: AABB = mesh.get_aabb()
		var offset: float = (mesh.global_position - player.global_position).y
		lowest = minf(lowest, bounds.position.y + offset)
		highest = maxf(highest, bounds.end.y + offset)

	_check("the player stands on the ground rather than in it",
		absf(lowest) < 0.05, "feet at %.3f" % lowest)
	_check("the player is roughly child-height",
		highest > 0.9 and highest < 1.4, "%.2f m tall" % highest)


func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		into.append(mesh)
	for child: Node in node.get_children():
		_collect_meshes(child, into)


## §7.2 and §8.2 together: a new player is sent to the garden, and what they grow
## there both opens the shop and stocks it.
func _test_kebun_unlocks_warung() -> void:
	SceneRouter.go_to_mini_game("kebun")
	var entered: bool = await _await_until(_is_kebun_running, 25.0)
	if not _check("the router enters the Kebun", entered, "timed out"):
		return

	var played: bool = await _await_until(_hub_is_back, 150.0, _auto_play)
	if not _check("a Kebun session completes and returns to the hub", played, "timed out"):
		return

	_check("the Kebun session was recorded", GameState.get_sessions_completed("kebun") == 1,
		"got %d" % GameState.get_sessions_completed("kebun"))
	_check("playing the Kebun opens the Warung",
		(_hub._buildings["warung"] as Building).is_unlocked, "still shut")
	_check("the Warung becomes the recommendation", _hub._get_recommended_game_id() == "warung",
		"recommended %s" % _hub._get_recommended_game_id())

	# §8.2: produce grown in the garden has to reach the inventory, because that
	# is what the Warung stocks its shelf from next session.
	_check("the garden filled the inventory", GameState.has_any_stock(),
		"inventory is %s" % GameState.inventory)

	# Clear the celebration so it is not sitting over the next transition.
	_hub._celebration._dismiss()
	await get_tree().process_frame


## §7.1 is explicit: approaching a building shows a prompt, and entering takes a
## deliberate tap. A child who walks past a door and gets teleported inside learns
## to avoid the door.
func _test_no_auto_enter() -> void:
	# Stand well inside the Warung trigger, without touching anything.
	_hub._player.warp_to(Vector2(0.0, -6.0))
	await _await_until(func() -> bool: return _hub._nearby_game_id == "warung", 5.0)

	_check("standing at a building raises its prompt", _hub._enter_prompt.visible,
		"nothing appeared to tap")
	_check("the prompt is for the building being stood at", _hub._nearby_game_id == "warung",
		"got %s" % _hub._nearby_game_id)

	# Loiter. Proximity alone must never open anything.
	for i: int in range(60):
		await get_tree().process_frame

	_check("standing there does not enter the building",
		SceneRouter.get_current_mini_game_id().is_empty(),
		"walked straight into %s" % SceneRouter.get_current_mini_game_id())
	_check("the hub is still what is on screen", _hub.visible, "the hub was hidden")

	_hub._player.warp_to(Vector2(0.0, 4.0))
	await _await_until(func() -> bool: return _hub._nearby_game_id.is_empty(), 5.0)
	_check("walking away clears the prompt", not _hub._enter_prompt.visible,
		"the prompt stayed up after leaving")


func _test_warung_round_trip() -> void:
	var hub_before: Node3D = _hub
	var stocked: Array[String] = GameState.get_stocked_item_ids()

	SceneRouter.go_to_mini_game("warung")
	var entered: bool = await _await_until(_is_warung_running, 25.0)
	if not _check("the router enters the Warung", entered, "timed out"):
		return

	# §6.3: the hub is hidden, never unloaded, so coming back is instant.
	_check("the hub survives the trip", is_instance_valid(hub_before) and hub_before == _hub,
		"the hub was reloaded")
	_check("the hub is hidden while the mini-game runs", not _hub.visible, "still visible")
	_check("the hub stops processing while hidden",
		_hub.process_mode == Node.PROCESS_MODE_DISABLED, "got %d" % _hub.process_mode)

	var warung: MiniGame = SceneRouter._current_mini_game
	if not _check("the mini-game instance is live", warung != null, "none"):
		return
	_check("the session started at the earned level", warung.level_index == 1,
		"got %d" % warung.level_index)

	# §8.4: the shelf prefers what the child grew. Not something the shop enforces
	# — an empty inventory is filled from the level pool instead — but when there
	# is produce, it should be on the shelf.
	var on_shelf: bool = false
	for item_id: String in stocked:
		if warung._shelf_item_ids.has(item_id):
			on_shelf = true
			break
	_check("what was grown turns up on the warung shelf", on_shelf,
		"grew %s, shelf has %s" % [stocked, warung._shelf_item_ids])

	var coins_before: int = GameState.coins
	var served: bool = await _await_until(_hub_is_back, 150.0, _auto_play)
	if not _check("the session completes and returns to the hub", served, "timed out"):
		return

	var customers: int = int(ContentDB.get_level("warung", 1).get("customers_per_session", 5))
	_check("the Warung paid out on top of the garden",
		GameState.coins == coins_before + customers * WARUNG_LEVEL_COINS,
		"had %d, now %d" % [coins_before, GameState.coins])
	_check("the Warung session was recorded", GameState.get_sessions_completed("warung") == 1,
		"got %d" % GameState.get_sessions_completed("warung"))
	_check("serving the Warung opens the Dapur", GameState.is_unlocked("dapur"), "still shut")
	_check("the unbuilt Dapur still shows as not ready",
		not (_hub._buildings["dapur"] as Building).is_unlocked,
		"the village offered a door with nothing behind it")
	_check("the level advanced for next time", GameState.get_level("warung") == 2,
		"got %d" % GameState.get_level("warung"))

	# §8.1.9: the celebration is part of coming back, and it must not play behind
	# the fade curtain.
	_check("the celebration is showing after the return", _hub._celebration.visible,
		"the session ended with no acknowledgement")
	_check("the hub has its camera back", _hub._camera.current, "a mini-game camera is still live")


func _test_progress_survives_a_restart() -> void:
	SaveManager.flush()
	SaveManager.save_game()

	var coins: int = GameState.coins
	var sessions: int = GameState.get_sessions_completed("warung")
	var inventory: Dictionary = GameState.inventory.duplicate()

	# Stand-in for a force-close: wipe memory, reload from disk.
	GameState.reset()
	SaveManager.load_game()

	_check("coins survive a restart", GameState.coins == coins,
		"had %d, reloaded %d" % [coins, GameState.coins])
	_check("sessions survive a restart", GameState.get_sessions_completed("warung") == sessions,
		"had %d, reloaded %d" % [sessions, GameState.get_sessions_completed("warung")])
	_check("the inventory survives a restart", GameState.inventory == inventory,
		"had %s, reloaded %s" % [inventory, GameState.inventory])
	_check("unlocking survives a restart", GameState.is_unlocked("dapur"), "the Dapur re-locked")


# ---------------------------------------------------------------- helpers

## Plays whichever mini-game is currently running. Looks it up each tick rather
## than holding a reference: the router frees it the moment the session ends, and
## a bound argument pointing at a freed node throws before the loop can notice.
func _auto_play() -> void:
	var game: MiniGame = SceneRouter._current_mini_game
	if game == null or not is_instance_valid(game):
		return
	match game.get_game_id():
		"warung":
			_auto_serve(game)
		"kebun":
			_auto_tend(game)


func _auto_serve(warung: MiniGame) -> void:
	var order: WarungOrder = warung._current_order
	if order == null or not warung._drag.is_enabled():
		return
	if order.is_satisfied_by(warung._tray.get_counts()):
		return
	warung._tray.clear()
	for item_id: String in order.counts:
		for i: int in range(int(order.counts[item_id])):
			warung._tray.add_item(item_id)
	warung._confirm_button.pressed.emit()


func _auto_tend(kebun: MiniGame) -> void:
	if not kebun._drag.is_enabled():
		return
	for child: Node in kebun._plots_root.get_children():
		var plot: GardenPlot = child as GardenPlot
		if plot == null:
			continue
		if plot.is_ready():
			kebun._on_tapped(plot.get_harvest_target())
			return
		if plot.can_plant():
			var basket: SeedSource = kebun._seeds_root.get_child(0) as SeedSource
			if basket != null:
				kebun._on_dropped(basket.item_id, plot.get_drop_zone())
			return
		if plot.needs_water():
			kebun._on_dropped(WateringCan.PAYLOAD, plot.get_drop_zone())
			return


## A single-expression lambda cannot wrap across lines in GDScript, so multi-part
## conditions live in named predicates.
func _is_kebun_running() -> bool:
	return SceneRouter.get_current_mini_game_id() == "kebun" and not SceneRouter.is_transitioning()


func _is_warung_running() -> bool:
	return SceneRouter.get_current_mini_game_id() == "warung" and not SceneRouter.is_transitioning()


func _hub_is_back() -> bool:
	return _hub.visible and not SceneRouter.is_transitioning()


func _find_hub() -> Node3D:
	for child: Node in get_tree().root.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("hub.gd"):
			return child as Node3D
	return null


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
