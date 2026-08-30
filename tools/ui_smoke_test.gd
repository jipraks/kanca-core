extends Control

## Headless check of the UI components. Developer tool — never shipped.
##
##   godot --headless --path . res://tools/ui_smoke_test.tscn
##
## The interesting part is not that the scenes instantiate — it is the touch
## target audit at the end. PLAN.md §3.3 sets a 120×120 minimum and a 40px gap,
## and §17 asks for that to be verified before every commit. Checking it by eye
## on a phone does not scale; checking it here does.

const MIN_TOUCH := 120.0
const MIN_GAP := 40.0

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	print("=== Kanca UI smoke test ===")

	await _test_placeholder_factory()
	await _test_sfx_bank()
	await _test_big_button()
	await _test_directional_pad()
	await _test_analog_stick()
	await _test_zoom_controls()
	await _test_counting_row()
	await _test_order_card()
	await _test_celebration_overlay()
	await _test_parental_gate()
	await _test_confirm_dialog()
	await _test_loading_screen()

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------- tests

func _test_placeholder_factory() -> void:
	# Real icons exist now, so build_item_icon returns them at their own size -
	# the `size` argument only ever governed the generated fallback.
	var icon: Texture2D = PlaceholderFactory.build_item_icon("pisang")
	_check("item icon resolves", icon != null and icon.get_width() > 0, "got %s" % icon)
	_check("the real icon is preferred over a generated one",
		icon.resource_path.ends_with("pisang.png"),
		"got %s, which means the art on disk is being ignored" % icon.resource_path)
	_check("two items differ", PlaceholderFactory.build_item_icon("apel") != icon,
		"apel and pisang produced the same texture")

	var swatch: Texture2D = PlaceholderFactory.build_swatch_icon("no_such_item", Palette.GRASS, 64)
	_check("generated swatch honours its size", swatch != null and swatch.get_width() == 64,
		"got %s" % swatch)
	_check("swatch cache returns the same texture",
		PlaceholderFactory.build_swatch_icon("no_such_item", Palette.GRASS, 64) == swatch,
		"cache missed")

	for glyph: String in ["check", "home", "star", "coin", "play", "sleep", "construction"]:
		var glyph_icon: Texture2D = PlaceholderFactory.build_glyph_icon(glyph, Palette.UI_TEXT, 64)
		_check("glyph %s" % glyph, glyph_icon != null and glyph_icon.get_width() == 64, "missing")

	# Three tiers: real .glb, then a billboard of the 2D icon, then a primitive.
	# No art exists yet, so build_item_visual must be landing on the last one.
	var visual: Node3D = PlaceholderFactory.build_item_visual("pisang")
	_check("item visual has something in it", visual != null and visual.get_child_count() > 0,
		"no children")
	_check("with no art on disk it falls through to a primitive",
		visual.get_child(0) is MeshInstance3D,
		"got %s, so a tier above claimed it unexpectedly" % visual.get_child(0))
	visual.free()

	# The middle tier, exercised directly since dropping a real PNG into res://
	# mid-test is not possible.
	var texture: Texture2D = PlaceholderFactory.build_swatch_icon("tier_test", Palette.GRASS, 128)
	var sprite_visual: Node3D = PlaceholderFactory.build_sprite_visual(texture, PlaceholderFactory.ITEM_SIZE)
	var sprite: Sprite3D = sprite_visual.get_child(0) as Sprite3D
	_check("a 2D icon can stand in as a 3D item", sprite != null, "no Sprite3D was built")
	if sprite != null:
		_check("the sprite faces the camera", sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
			"got %d" % sprite.billboard)
		_check("the sprite writes depth so tray items stack correctly",
			sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "got %d" % sprite.alpha_cut)
		_check("the sprite stands on the ground rather than through it",
			sprite.position.y > 0.0, "origin at y=%f" % sprite.position.y)
		var width: float = float(texture.get_width()) * sprite.pixel_size
		_check("the sprite is about item-sized",
			absf(width - PlaceholderFactory.ITEM_SIZE * PlaceholderFactory.SPRITE_SIZE_BOOST) < 0.01,
			"%.3f m across" % width)
	sprite_visual.free()

	var character: Node3D = PlaceholderFactory.build_character("kanca", Palette.SIGNATURE)
	_check("character placeholder built", character != null and character.get_child_count() == 3,
		"expected body, head, nose")

	# A model's forward is -Z. Turning it with atan2(x, z) points it exactly
	# backwards, which a capsule hides and a real character does not - the
	# player walked across the whole village in reverse before this was caught.
	add_child(character)
	var nose: Node3D = character.get_child(2) as Node3D
	for travel: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		character.rotation.y = Facing.angle_towards(travel)
		var pointing: Vector3 = nose.global_position - character.global_position
		pointing.y = 0.0
		_check("a character turned towards %s actually faces it" % travel,
			pointing.normalized().dot(travel) > 0.9,
			"it faces %s instead" % pointing.normalized())
	remove_child(character)
	character.free()

	var material_a: StandardMaterial3D = PlaceholderFactory.get_flat_material(Palette.GRASS)
	var material_b: StandardMaterial3D = PlaceholderFactory.get_flat_material(Palette.GRASS)
	_check("materials are shared per colour", material_a == material_b,
		"a fresh material per call would blow the 25-material budget")


func _test_sfx_bank() -> void:
	for sfx_id: String in SfxBank.get_all_ids():
		var stream: AudioStream = SfxBank.get_stream(sfx_id)
		_check("sfx %s synthesised" % sfx_id, stream != null and stream.get_length() > 0.0,
			"got %s" % stream)
	_check("everything is still a placeholder", SfxBank.is_placeholder(SfxBank.CLICK),
		"a real click.ogg exists, update this expectation")


func _test_big_button() -> void:
	var button: BigButton = await _spawn("res://scenes/ui/big_button.tscn") as BigButton
	_check("big button loaded", button != null, "scene did not instantiate as BigButton")
	if button == null:
		return
	_check("big button meets the touch minimum",
		button.size.x >= MIN_TOUCH and button.size.y >= MIN_TOUCH,
		"got %s" % button.size)
	_check("big button carries no text", button.text.is_empty(),
		"text would make meaning depend on reading")
	button.queue_free()


func _test_directional_pad() -> void:
	var pad: DirectionalPad = await _spawn("res://scenes/ui/directional_pad.tscn") as DirectionalPad
	_check("pad loaded", pad != null, "scene did not instantiate as DirectionalPad")
	if pad == null:
		return

	_check("pad starts neutral", pad.get_direction() == Vector2.ZERO, "got %s" % pad.get_direction())

	var emitted: Array[Vector2] = []
	pad.direction_changed.connect(func(direction: Vector2) -> void: emitted.append(direction))

	var up: BigButton = pad.get_node("Up") as BigButton
	up.button_down.emit()
	_check("pressing up moves away from the camera", pad.get_direction() == Vector2(0, -1),
		"got %s" % pad.get_direction())
	up.button_up.emit()
	_check("releasing stops movement", pad.get_direction() == Vector2.ZERO,
		"got %s" % pad.get_direction())
	_check("direction changes were emitted", emitted.size() == 2, "got %d" % emitted.size())

	up.button_down.emit()
	pad.release_all()
	_check("release_all clears a stuck hold", pad.get_direction() == Vector2.ZERO,
		"got %s" % pad.get_direction())

	await _audit(pad, "directional pad")
	pad.queue_free()


## §16.3 leaves movement controls open, so both implementations have to keep
## satisfying the same surface — otherwise swapping them for a session with
## children stops being a one-line change.
func _test_analog_stick() -> void:
	var stick: AnalogStick = await _spawn("res://scenes/ui/analog_stick.tscn") as AnalogStick
	if not _check("analog stick loaded", stick != null, "did not instantiate"):
		return

	_check("the stick is a MovementControl, like the pad it replaces",
		stick is MovementControl, "the hub could not swap between them")
	_check("the stick starts neutral", stick.get_direction() == Vector2.ZERO,
		"got %s" % stick.get_direction())

	var native: VirtualJoystick = stick.get_node("Stick") as VirtualJoystick
	if not _check("it wraps the engine's own joystick", native != null, "no VirtualJoystick child"):
		return

	# Fixed and always visible, both for the same reason: a child is still
	# learning that the control lives somewhere.
	_check("the stick stays in one place",
		native.joystick_mode == VirtualJoystick.JOYSTICK_FIXED, "got %d" % native.joystick_mode)
	_check("the stick is visible before it is touched",
		native.visibility_mode == VirtualJoystick.VISIBILITY_ALWAYS,
		"got %d" % native.visibility_mode)
	_check("the stick clears the 120px minimum",
		native.joystick_size >= MIN_TOUCH and native.tip_size >= MIN_TOUCH * 0.5,
		"base %.0f, tip %.0f" % [native.joystick_size, native.tip_size])
	_check("a resting finger means stop, not drift", native.deadzone_ratio >= 0.15,
		"dead zone is only %.2f" % native.deadzone_ratio)

	stick.release_all()
	_check("release clears any held direction", stick.get_direction() == Vector2.ZERO,
		"got %s" % stick.get_direction())
	stick.queue_free()


## The village zoom buttons (§3.3, §7.1). They exist alongside the pinch rather
## than instead of it: a pinch has no affordance, and a child who never discovers
## it would otherwise be stuck at one distance forever.
func _test_zoom_controls() -> void:
	var zoom: ZoomControls = await _spawn("res://scenes/ui/zoom_controls.tscn") as ZoomControls
	if not _check("zoom controls loaded", zoom != null, "did not instantiate"):
		return

	var in_button: BigButton = zoom.get_node("ZoomIn") as BigButton
	var out_button: BigButton = zoom.get_node("ZoomOut") as BigButton
	if not _check("it has both buttons", in_button != null and out_button != null, "missing one"):
		zoom.queue_free()
		return

	_check("both buttons clear the 120px minimum",
		in_button.size.x >= MIN_TOUCH and in_button.size.y >= MIN_TOUCH
			and out_button.size.x >= MIN_TOUCH and out_button.size.y >= MIN_TOUCH,
		"in %s, out %s" % [in_button.size, out_button.size])

	var gap: float = out_button.position.y - (in_button.position.y + in_button.size.y)
	_check("they are 40px apart", gap >= MIN_GAP, "only %.0f px" % gap)

	_check("the icons carry the meaning, not text (3.1)",
		in_button.text.is_empty() and in_button.icon_texture != null
			and out_button.icon_texture != null, "a button is relying on a label")
	_check("the two icons are not the same picture",
		in_button.icon_texture != out_button.icon_texture,
		"zoom in and zoom out look identical")

	# Without a camera there is nothing to zoom, so both must read as unavailable
	# rather than sitting there looking pressable.
	_check("both lock when nothing is wired up",
		in_button.is_locked and out_button.is_locked, "a button looked live")

	var camera: HubCamera = HubCamera.new()
	add_child(camera)
	zoom.camera = camera
	_check("both unlock at the default distance",
		not in_button.is_locked and not out_button.is_locked, "a button stayed locked")

	while camera.zoom_in():
		pass
	_check("zooming all the way in locks the in button", in_button.is_locked, "still live")
	_check("and leaves the out button available", not out_button.is_locked, "it locked too")

	while camera.zoom_out():
		pass
	_check("zooming all the way out locks the out button", out_button.is_locked, "still live")
	_check("and leaves the in button available", not in_button.is_locked, "it locked too")

	camera.queue_free()
	zoom.queue_free()


func _test_counting_row() -> void:
	var row: CountingRow = await _spawn("res://scenes/ui/counting_row.tscn") as CountingRow
	if not _check("counting row loaded", row != null, "did not instantiate"):
		return

	row.set_count(3)
	await get_tree().process_frame
	var dots: Control = row.get_node("Dots") as Control
	_check("three dots for three", dots.get_child_count() == 3, "got %d" % dots.get_child_count())
	var numeral: Label = row.get_node("Numeral") as Label
	_check("numeral matches the dots", numeral.text == "3", "got %s" % numeral.text)

	row.set_count(14)
	await get_tree().process_frame
	_check("dots cap at ten", dots.get_child_count() == CountingRow.MAX_DOTS,
		"got %d" % dots.get_child_count())
	row.queue_free()


func _test_order_card() -> void:
	var card: OrderCard = await _spawn("res://scenes/ui/order_card.tscn") as OrderCard
	if not _check("order card loaded", card != null, "did not instantiate"):
		return

	card.set_order([
		{"item_id": "pisang", "count": 3},
		{"item_id": "roti", "count": 1},
	])
	await get_tree().process_frame
	var rows: Control = card.get_node("Rows") as Control
	_check("one row per item type", rows.get_child_count() == 2, "got %d" % rows.get_child_count())

	var replayed: Array[bool] = []
	card.replay_requested.connect(func() -> void: replayed.append(true))
	(card.get_node("TapToReplay") as Button).pressed.emit()
	_check("tapping the card asks for a replay", replayed.size() == 1,
		"a child who missed the order must be able to hear it again")

	# A TextureRect defaults to taking its minimum size from the texture. Real
	# item icons are 256px, and that blew the order card clean off the screen the
	# first time one arrived - invisible for as long as every icon was a small
	# generated swatch.
	var row_icon: TextureRect = rows.get_child(0).get_node("Icon") as TextureRect
	_check("a real icon does not decide how big the card is",
		row_icon.size.x <= OrderCard.ROW_ICON_SIZE.x + 1.0
			and row_icon.size.y <= OrderCard.ROW_ICON_SIZE.y + 1.0,
		"icon rendered at %s against a %s slot" % [row_icon.size, OrderCard.ROW_ICON_SIZE])
	_check("the card fits on screen", card.size.x <= 640.0,
		"card is %.0fpx wide" % card.size.x)

	card.clear_order()
	await get_tree().process_frame
	_check("card clears", rows.get_child_count() == 0, "got %d" % rows.get_child_count())
	card.queue_free()


func _test_celebration_overlay() -> void:
	var overlay: CelebrationOverlay = await _spawn("res://scenes/ui/celebration_overlay.tscn") as CelebrationOverlay
	if not _check("celebration overlay loaded", overlay != null, "did not instantiate"):
		return

	_check("overlay starts hidden", not overlay.visible, "it was visible before a session ended")

	var result: MiniGameResult = MiniGameResult.create("warung", 1)
	result.rounds_completed = 5
	result.coins_earned = 10
	overlay.show_result(result)
	await get_tree().process_frame

	_check("overlay shows", overlay.visible, "show_result left it hidden")
	var stars: Control = overlay.get_node("Centre/Column/Stars") as Control
	_check("one star per round", stars.get_child_count() == 5, "got %d" % stars.get_child_count())

	var dismissed: Array[bool] = []
	overlay.dismissed.connect(func() -> void: dismissed.append(true))
	(overlay.get_node("Centre/Column/Continue") as BigButton).pressed.emit()
	_check("continue dismisses", dismissed.size() == 1 and not overlay.visible, "still on screen")

	await _audit(overlay, "celebration overlay")
	overlay.queue_free()


func _test_parental_gate() -> void:
	var gate: ParentalGate = await _spawn("res://scenes/ui/parental_gate.tscn") as ParentalGate
	if not _check("parental gate loaded", gate != null, "did not instantiate"):
		return

	gate.open()
	await get_tree().process_frame

	var choices: Control = gate.get_node("Centre/Panel/Column/Choices") as Control
	_check("three numerals offered", choices.get_child_count() == ParentalGate.CHOICE_COUNT,
		"got %d" % choices.get_child_count())

	var values: Array[int] = []
	for child: Node in choices.get_children():
		values.append(int((child as Button).text))
	_check("numerals are two digits", values.all(func(v: int) -> bool: return v >= 10 and v <= 99),
		"got %s" % [values])
	_check("no two share a digit position",
		_all_distinct_digits(values), "distractors were too similar: %s" % [values])

	# A wrong tap must draw a completely new challenge, so repeated guessing
	# never narrows the answer down (§3.6).
	var wrong: Button = _find_wrong_choice(choices, gate)
	var passed_count: Array[bool] = []
	gate.passed.connect(func() -> void: passed_count.append(true))
	wrong.pressed.emit()
	await get_tree().process_frame
	_check("a wrong tap does not pass the gate", passed_count.is_empty(), "the gate opened")
	_check("the gate stays up after a wrong tap", gate.visible, "it closed")

	var new_values: Array[int] = []
	for child: Node in (gate.get_node("Centre/Panel/Column/Choices") as Control).get_children():
		new_values.append(int((child as Button).text))
	_check("a wrong tap reshuffles the challenge", new_values != values,
		"the same three numbers came back, which makes it guessable")

	await _audit(gate, "parental gate")
	gate.queue_free()


func _test_confirm_dialog() -> void:
	var dialog: IconConfirmDialog = await _spawn("res://scenes/ui/icon_confirm_dialog.tscn") as IconConfirmDialog
	if not _check("confirm dialog loaded", dialog != null, "did not instantiate"):
		return

	dialog.open(PlaceholderFactory.build_glyph_icon("home", Palette.SIGNATURE, 96))
	await get_tree().process_frame
	_check("dialog opens", dialog.visible, "open left it hidden")

	var confirmed: Array[bool] = []
	dialog.confirmed.connect(func() -> void: confirmed.append(true))
	(dialog.get_node("Centre/Panel/Column/Choices/Confirm") as BigButton).pressed.emit()
	_check("confirm closes and reports", confirmed.size() == 1 and not dialog.visible, "no")

	await _audit(dialog, "confirm dialog")
	dialog.queue_free()


func _test_loading_screen() -> void:
	var screen: LoadingScreen = await _spawn("res://scenes/ui/loading_screen.tscn") as LoadingScreen
	if not _check("loading screen loaded", screen != null, "did not instantiate"):
		return

	screen.set_progress(0.5)
	_check("progress is stored", is_equal_approx(screen.get_progress(), 0.5),
		"got %f" % screen.get_progress())
	screen.set_progress(4.0)
	_check("progress clamps", is_equal_approx(screen.get_progress(), 1.0),
		"got %f" % screen.get_progress())
	screen.queue_free()


# ---------------------------------------------------------------- audit

## Walks a component and enforces the two touch rules from §3.3 on every button
## it finds. This is the check §17 asks for, done by machine instead of by eye.
func _audit(root: Control, label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var buttons: Array[Control] = []
	_collect_buttons(root, buttons)
	_check("%s: has interactive elements" % label, not buttons.is_empty(), "found none to audit")

	for button: Control in buttons:
		var size: Vector2 = button.size
		_check("%s: %s is at least 120x120" % [label, button.name],
			size.x >= MIN_TOUCH and size.y >= MIN_TOUCH, "got %s" % size)

	for i: int in range(buttons.size()):
		for j: int in range(i + 1, buttons.size()):
			var gap: float = _gap_between(buttons[i].get_global_rect(), buttons[j].get_global_rect())
			_check("%s: %s and %s are at least 40px apart" % [label, buttons[i].name, buttons[j].name],
				gap >= MIN_GAP, "gap was %.1fpx" % gap)


func _collect_buttons(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Button and (child as Control).visible:
			into.append(child as Control)
		_collect_buttons(child, into)


## Separation between two rects: negative on the axes where they overlap, so the
## larger of the two axes is the real gap. Overlapping rects give a negative gap.
func _gap_between(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var dy: float = maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	return maxf(dx, dy)


# ---------------------------------------------------------------- harness

func _spawn(scene_path: String) -> Control:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_check("load %s" % scene_path, false, "scene missing or unreadable")
		return null
	var instance: Control = packed.instantiate() as Control
	add_child(instance)
	await get_tree().process_frame
	return instance


func _all_distinct_digits(values: Array[int]) -> bool:
	for i: int in range(values.size()):
		for j: int in range(i + 1, values.size()):
			if values[i] / 10 == values[j] / 10 or values[i] % 10 == values[j] % 10:
				return false
	return true


func _find_wrong_choice(choices: Control, gate: ParentalGate) -> Button:
	var target: int = gate._target
	for child: Node in choices.get_children():
		var button: Button = child as Button
		if int(button.text) != target:
			return button
	return choices.get_child(0) as Button


func _check(label: String, condition: bool, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s -- %s" % [label, detail])
	return condition
