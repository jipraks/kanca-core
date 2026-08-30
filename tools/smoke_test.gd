extends Node

## Headless check of the core systems. Developer tool — never shipped.
##
##   godot --headless --path . res://tools/smoke_test.tscn
##
## Exits 0 when everything passes, 1 otherwise, so it drops straight into CI.
## It deliberately exercises the failure paths too: a corrupt save must reset
## cleanly rather than crash, because a crash loop in front of a child is the one
## outcome the design cannot tolerate (PLAN.md §6.1).

var _passed: int = 0
var _failed: int = 0
var _save_backup: String = ""
var _had_save: bool = false


func _ready() -> void:
	print("=== Kanca smoke test ===")
	_backup_save()

	_test_content_db()
	_test_game_state_arithmetic()
	_test_unlocking()
	_test_save_round_trip()
	_test_corrupt_save_recovery()
	_test_voice_bank()
	await _test_voice_queue()
	_test_hub_camera()
	_test_walk_cycle()

	_restore_save()

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------- tests

func _test_content_db() -> void:
	_check("items load", ContentDB.get_item_ids().size() == 15,
		"expected 15 items, got %d" % ContentDB.get_item_ids().size())
	_check("item lookup", ContentDB.get_item_display_name("pisang") == "Pisang",
		"got %s" % ContentDB.get_item_display_name("pisang"))
	_check("unknown item degrades", ContentDB.get_item("tidak_ada").has("display_name"),
		"unknown item returned an unusable dictionary")
	_check("growables", ContentDB.get_growable_item_ids().size() == 3,
		"expected 3 growable items, got %d" % ContentDB.get_growable_item_ids().size())

	_check("mini-games load", ContentDB.get_mini_game_ids().size() == 3,
		"got %s" % [ContentDB.get_mini_game_ids()])
	_check("mini-game order", ContentDB.get_mini_game_ids() == (["kebun", "warung", "dapur"] as Array[String]),
		"got %s" % [ContentDB.get_mini_game_ids()])

	_check("warung levels", ContentDB.get_level_count("warung") == 5,
		"got %d" % ContentDB.get_level_count("warung"))
	_check("stretch levels gated", ContentDB.get_max_playable_level("warung") == 3,
		"got %d" % ContentDB.get_max_playable_level("warung"))
	_check("level clamps high", int(ContentDB.get_level("warung", 99).get("index", 0)) == 5,
		"out-of-range level did not clamp")
	_check("level clamps low", int(ContentDB.get_level("warung", -3).get("index", 0)) == 1,
		"out-of-range level did not clamp")
	_check("unknown game has a fallback level", not ContentDB.get_level("tidak_ada", 1).is_empty(),
		"unknown game returned no level at all")


func _test_game_state_arithmetic() -> void:
	GameState.reset()

	GameState.add_coins(5)
	GameState.add_coins(-3)
	_check("coins never decrease from a negative add", GameState.coins == 5,
		"got %d" % GameState.coins)

	_check("cannot overspend", not GameState.try_spend_coins(99), "overspending was allowed")
	_check("balance intact after refusal", GameState.coins == 5, "got %d" % GameState.coins)
	_check("can spend what is there", GameState.try_spend_coins(5), "affordable spend refused")
	_check("balance after spend", GameState.coins == 0, "got %d" % GameState.coins)

	GameState.add_item("pisang", 3)
	_check("inventory add", GameState.get_item_count("pisang") == 3,
		"got %d" % GameState.get_item_count("pisang"))
	_check("cannot consume more than held", not GameState.try_consume_item("pisang", 4),
		"over-consumption was allowed")
	_check("consume", GameState.try_consume_item("pisang", 3), "valid consume refused")
	_check("empty entries are removed", not GameState.inventory.has("pisang"),
		"zero-count entry left behind")

	var result: MiniGameResult = MiniGameResult.create("warung", 1)
	result.coins_earned = 7
	result.rounds_completed = 5
	result.add_produced("apel", 2)
	GameState.add_item("telur", 4)
	result.add_consumed("telur", 1)
	GameState.apply_result(result)

	_check("result coins", GameState.coins == 7, "got %d" % GameState.coins)
	_check("result produced", GameState.get_item_count("apel") == 2,
		"got %d" % GameState.get_item_count("apel"))
	_check("result consumed", GameState.get_item_count("telur") == 3,
		"got %d" % GameState.get_item_count("telur"))
	_check("session recorded", GameState.get_sessions_completed("warung") == 1,
		"got %d" % GameState.get_sessions_completed("warung"))
	_check("level advanced", GameState.get_level("warung") == 2,
		"got %d" % GameState.get_level("warung"))

	# Levels 4-5 are stretch scope and must stay out of reach (§16.5).
	for i: int in range(10):
		GameState.record_session("warung")
	_check("level capped at the playable ceiling", GameState.get_level("warung") == 3,
		"got %d" % GameState.get_level("warung"))


func _test_unlocking() -> void:
	GameState.reset()
	_check("kebun open from the start", GameState.is_unlocked("kebun"), "kebun was locked")
	_check("warung starts locked", not GameState.is_unlocked("warung"), "warung was open")
	_check("dapur starts locked", not GameState.is_unlocked("dapur"), "dapur was open")

	GameState.record_session("kebun")
	_check("kebun session unlocks warung", GameState.is_unlocked("warung"), "warung still locked")
	_check("dapur still locked", not GameState.is_unlocked("dapur"), "dapur unlocked too early")

	GameState.record_session("warung")
	_check("warung session unlocks dapur", GameState.is_unlocked("dapur"), "dapur still locked")


func _test_save_round_trip() -> void:
	GameState.reset()
	GameState.add_coins(42)
	GameState.add_item("roti", 6)
	GameState.record_session("kebun")

	_check("save writes", SaveManager.save_game(), "save_game returned false")

	GameState.reset()
	_check("reset clears coins", GameState.coins == 0, "got %d" % GameState.coins)

	SaveManager.load_game()
	_check("coins survive a round trip", GameState.coins == 42, "got %d" % GameState.coins)
	_check("inventory survives", GameState.get_item_count("roti") == 6,
		"got %d" % GameState.get_item_count("roti"))
	_check("progress survives", GameState.get_sessions_completed("kebun") == 1,
		"got %d" % GameState.get_sessions_completed("kebun"))


func _test_corrupt_save_recovery() -> void:
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ this is not json at all ]]")
	file.close()

	SaveManager.load_game()
	_check("corrupt save resets instead of crashing", GameState.coins == 0,
		"got %d" % GameState.coins)

	# A structurally valid file with nonsense inside must survive too.
	JsonLoader.write_dict(SaveManager.SAVE_PATH, {"version": 1, "state": {"coins": "banyak", "inventory": [1, 2, 3]}})
	SaveManager.load_game()
	_check("nonsense fields are sanitised", GameState.coins == 0 and GameState.inventory.is_empty(),
		"coins=%s inventory=%s" % [GameState.coins, GameState.inventory])

	JsonLoader.write_dict(SaveManager.SAVE_PATH, {"version": 999, "state": {}})
	SaveManager.load_game()
	_check("future save version resets", GameState.coins == 0, "got %d" % GameState.coins)


func _test_voice_bank() -> void:
	var ids: Array[String] = VoiceBank.get_all_voice_ids()
	_check("manifest loads", ids.size() == 69, "expected 69 voice ids, got %d" % ids.size())

	_check("single-variant path", VoiceBank.resolve_path("num_3", 0).ends_with("/num_3.ogg"),
		"got %s" % VoiceBank.resolve_path("num_3", 0))
	_check("multi-variant path", VoiceBank.resolve_path("kanca_ui_benar", 2).ends_with("/kanca_ui_benar_03.ogg"),
		"got %s" % VoiceBank.resolve_path("kanca_ui_benar", 2))

	_check("unknown id has no entry", not VoiceBank.has_entry("tidak_ada"), "unknown id resolved")
	_check("every line is still unrecorded", VoiceBank.get_missing_recordings().size() == ids.size(),
		"got %d missing of %d" % [VoiceBank.get_missing_recordings().size(), ids.size()])

	# Variant rotation must never repeat back to back (§10.4).
	var previous: int = -1
	var repeats: int = 0
	for i: int in range(60):
		var variant: int = VoiceBank._next_variant("kanca_ui_benar")
		if variant == previous:
			repeats += 1
		previous = variant
	_check("variants never repeat back to back", repeats == 0, "%d immediate repeats" % repeats)

	var groups: Array = [["num_3", "item_pisang"], ["num_1", "item_roti"]]
	var joined: Array[String] = VoiceBank.join_groups(groups, "cust_ibu_and")
	_check("composed order inserts the connector",
		joined == (["num_3", "item_pisang", "cust_ibu_and", "num_1", "item_roti"] as Array[String]),
		"got %s" % [joined])


func _test_voice_queue() -> void:
	# Unrecorded lines still queue, still duck the music, still take real time.
	# That is what lets the whole game be built before a single line is recorded.
	AudioManager.clear_voice_queue()

	var started: Array[String] = []
	var finished: Array[String] = []
	var on_started: Callable = func(voice_id: String) -> void: started.append(voice_id)
	var on_finished: Callable = func(voice_id: String) -> void: finished.append(voice_id)
	AudioManager.voice_started.connect(on_started)
	AudioManager.voice_finished.connect(on_finished)

	AudioManager.enqueue_voice(null, "test_a", 0.05, 0.1)
	AudioManager.enqueue_voice(null, "test_b", 0.0, 0.1)
	_check("queue reports busy", AudioManager.is_voice_playing(), "queue said idle immediately")

	await AudioManager.voice_queue_emptied

	_check("both lines started", started == (["test_a", "test_b"] as Array[String]), "got %s" % [started])
	_check("both lines finished in order", finished == (["test_a", "test_b"] as Array[String]), "got %s" % [finished])
	_check("queue reports idle when drained", not AudioManager.is_voice_playing(), "queue still busy")

	# A cut mid-line must not strand the queue — the order card lets a child
	# re-trigger a line at any moment (§10.3).
	AudioManager.enqueue_voice(null, "test_c", 0.0, 5.0)
	await get_tree().process_frame
	AudioManager.clear_voice_queue()
	await get_tree().process_frame
	_check("clearing mid-line frees the queue", not AudioManager.is_voice_playing(),
		"queue stuck after a cut")

	AudioManager.enqueue_voice(null, "test_d", 0.0, 0.1)
	_check("queue accepts work after a cut", AudioManager.is_voice_playing(), "queue would not restart")
	await AudioManager.voice_queue_emptied

	AudioManager.voice_started.disconnect(on_started)
	AudioManager.voice_finished.disconnect(on_finished)


# ---------------------------------------------------------------- harness

func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s -- %s" % [label, detail])


## The village camera (§7.1). Pure arithmetic, so it needs no scene.
##
## The test that earns its keep is the last one. Movement is specified as
## relative to the camera, and now that the camera turns, a `screen_to_world`
## that ignores the heading means a child turns the village half a circle and
## then walks *towards* the screen when they push up. That failure is invisible
## in a screenshot and obvious to a four-year-old.
func _test_hub_camera() -> void:
	var camera: HubCamera = HubCamera.new()

	_check("the camera starts at the distance 7.1 was written against",
		is_equal_approx(camera.get_distance(), HubCamera.DEFAULT_DISTANCE),
		"got %.2f" % camera.get_distance())

	while camera.zoom_in():
		pass
	_check("zoom stops at the near limit rather than passing through the player",
		is_equal_approx(camera.get_distance(), HubCamera.MIN_DISTANCE),
		"got %.2f" % camera.get_distance())
	_check("a further zoom in reports that nothing moved", not camera.zoom_in(), "it claimed to")

	while camera.zoom_out():
		pass
	_check("zoom stops at the far limit rather than losing the village",
		is_equal_approx(camera.get_distance(), HubCamera.MAX_DISTANCE),
		"got %.2f" % camera.get_distance())
	_check("a further zoom out reports that nothing moved", not camera.zoom_out(), "it claimed to")

	# A pinch is a ratio, so the same spread of the fingers has to be worth the
	# same proportion of the distance wherever it starts.
	camera.reset_view()
	camera.zoom_by_ratio(2.0)
	_check("spreading the fingers twice as wide halves the distance",
		is_equal_approx(camera.get_distance(), HubCamera.DEFAULT_DISTANCE * 0.5),
		"got %.2f" % camera.get_distance())
	camera.zoom_by_ratio(0.5)
	_check("and pinching back returns to where it started",
		is_equal_approx(camera.get_distance(), HubCamera.DEFAULT_DISTANCE),
		"got %.2f" % camera.get_distance())
	_check("a nonsense ratio is refused rather than dividing by zero",
		not camera.zoom_by_ratio(0.0), "it accepted it")

	camera.reset_view()
	camera.turn_by(PI * 0.5)
	_check("turning moves the heading", is_equal_approx(camera.get_yaw(), PI * 0.5),
		"got %.3f" % camera.get_yaw())
	camera.turn_by(PI * 1.6)
	_check("heading wraps instead of winding up unboundedly",
		absf(camera.get_yaw()) <= PI + 0.001, "got %.3f" % camera.get_yaw())

	camera.reset_view()
	_check("reset returns the view to the opening shot",
		is_zero_approx(camera.get_yaw())
			and is_equal_approx(camera.get_distance(), HubCamera.DEFAULT_DISTANCE),
		"yaw %.3f, distance %.2f" % [camera.get_yaw(), camera.get_distance()])

	# Up on the stick is -Y, which is away from the camera.
	var away: Vector3 = camera.screen_to_world(Vector2(0.0, -1.0))
	_check("unturned, up on the stick walks away from the camera",
		away.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "got %s" % away)

	camera.turn_by(PI)
	var turned: Vector3 = camera.screen_to_world(Vector2(0.0, -1.0))
	_check("turned right around, up on the stick still walks away from the camera",
		turned.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "got %s" % turned)

	camera.reset_view()
	camera.turn_by(PI * 0.5)
	var quarter: Vector3 = camera.screen_to_world(Vector2(0.0, -1.0))
	_check("a quarter turn moves the walking direction by a quarter turn",
		quarter.is_equal_approx(Vector3(-1.0, 0.0, 0.0)), "got %s" % quarter)
	_check("turning never tilts the ground the child walks on",
		is_zero_approx(quarter.y), "got y %.3f" % quarter.y)

	camera.free()


## The walk cycle (§7.1). Pure arithmetic on two child nodes, so it needs no
## scene and no model.
##
## What is worth pinning here is the behaviour around *not* walking. A cycle that
## only works while moving is easy; one that leaves a child standing mid-stride
## the moment they lift their thumb is what people notice.
func _test_walk_cycle() -> void:
	var legless: Node3D = Node3D.new()
	var bare: WalkCycle = WalkCycle.new(legless)
	_check("a model with no legs is handled, not assumed away", not bare.has_legs(),
		"it claimed to have legs")
	_check("advancing a legless cycle is a no-op", not bare.advance(0.1, 4.0),
		"it reported a footstep")
	legless.free()

	var body: Node3D = Node3D.new()
	var left: Node3D = Node3D.new()
	left.name = "player_leg_l"
	var right: Node3D = Node3D.new()
	right.name = "player_leg_r"
	body.add_child(left)
	body.add_child(right)

	var walk: WalkCycle = WalkCycle.new(body)
	_check("legs are found by name", walk.has_legs(), "not found")
	if not walk.has_legs():
		body.free()
		return

	var steps: int = 0
	for frame: int in range(120):
		if walk.advance(1.0 / 60.0, 4.0):
			steps += 1

	_check("the legs swing", absf(left.rotation.x) > 0.01 or absf(right.rotation.x) > 0.01,
		"both legs stayed at rest")
	_check("the legs swing in opposition, not together",
		signf(left.rotation.x) != signf(right.rotation.x)
			or is_zero_approx(left.rotation.x),
		"left %.3f, right %.3f" % [left.rotation.x, right.rotation.x])
	_check("the swing stays within a walk", absf(left.rotation.x) <= WalkCycle.MAX_SWING + 0.01,
		"swung %.3f radians" % left.rotation.x)

	# Two seconds at walking pace. The cadence is per stride and a stride is two
	# footfalls, so the count should be near four times the cadence.
	var expected: int = int(round(WalkCycle.CADENCE * 2.0 * 2.0))
	_check("a footstep lands roughly twice per stride",
		absi(steps - expected) <= 2, "got %d steps, expected about %d" % [steps, expected])

	_check("the body rises as it walks", body.position.y > 0.001,
		"stayed at %.4f" % body.position.y)

	for frame: int in range(90):
		walk.advance(1.0 / 60.0, 0.0)
	_check("stopping eases the legs back to standing",
		absf(left.rotation.x) < 0.02 and absf(right.rotation.x) < 0.02,
		"left %.3f, right %.3f" % [left.rotation.x, right.rotation.x])
	_check("and puts the body back down", absf(body.position.y) < 0.002,
		"left at %.4f" % body.position.y)

	body.free()


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if not _had_save:
		return
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	if file != null:
		_save_backup = file.get_as_text()
		file.close()


func _restore_save() -> void:
	if not _had_save:
		if FileAccess.file_exists(SaveManager.SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))
		return
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(_save_backup)
		file.close()
