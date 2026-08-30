extends MiniGame

## MG-01 Warung — the flagship mini-game (PLAN.md §8.1).
##
## The child runs a small shop. A customer asks for items, the child finds them,
## counts them out and hands them over. Counting 1-10, item recognition, and the
## vocabulary that comes from hearing every item named as it is picked up.
##
## The shape of a round is the design: there is no timer, no score that falls, and
## a wrong answer costs nothing at all. Getting it wrong three times does not fail
## the round — it makes the answer more and more obvious until it is impossible to
## miss (§3.2, §8.1.8).

const GAME_ID := "warung"

## Layout of the counter, in world units (1 unit = 1 metre, §11).
##
## Slot spacing is set by the touch rules in §3.3, not by taste: at this camera
## distance 0.85 units is what keeps neighbouring slots more than 40px apart on
## screen. The whole row also has to stay inside the frame, hence the cap.
const SLOT_SPACING := 0.85
const MAX_SHELF_SPAN := 4.1
const MAX_SHELF_SLOTS := 5
const SHELF_Z := 1.5
const SHELF_Y := 0.9
const COUNTER_TOP := 0.9
## Shop fittings. Absent files simply leave the shop bare (§10.5) — the game is
## unaffected, because none of this is playable.
## The gondola if it is here, otherwise the rack we built ourselves.
##
## The gondola came from outside the repository and its licence is unknown, so it
## is in .gitignore (see ASSETS.md) — which means a fresh clone does not have it.
## Preferring it and falling back means the shop is stocked either way: the
## checkout that has the file uses it, and the one that does not gets the
## procedural rack rather than an empty warung.
##
## A committed scene must never depend on an uncommitted asset.
const SHELF_MODELS: Array[String] = [
	"res://assets/models/shop/gondola.glb",
	"res://assets/models/shop/shelf_unit.glb",
]
const CRATE_MODEL := "res://assets/models/shop/crate.glb"
const SACK_MODEL := "res://assets/models/shop/sack_pile.glb"

const CUSTOMER_SPOT := Vector3(0.0, 0.0, -1.7)
const CUSTOMER_ENTRY := Vector3(-5.0, 0.0, -1.7)
const CUSTOMER_EXIT := Vector3(5.0, 0.0, -1.7)

## §8.1.8: the next customer arrives 1.5s after the last one is served.
const NEXT_CUSTOMER_DELAY := 1.5
const ORDER_VOICE_DELAY := 0.35

@onready var _camera: Camera3D = $Camera
@onready var _shelf: Node3D = $Shelf
@onready var _tray: CounterTray = $Counter/Tray
@onready var _drag: DragController = $DragController
@onready var _customer_root: Node3D = $CustomerRoot
@onready var _home_button: HomeButton = $UI/SafeArea/Screen/HomeButton
@onready var _order_card: OrderCard = $UI/SafeArea/Screen/OrderCard
@onready var _confirm_button: BigButton = $UI/SafeArea/Screen/ConfirmButton
@onready var _coin_display: CoinDisplay = $UI/SafeArea/Screen/CoinDisplay

var _level: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _slots: Dictionary = {}
var _shelf_item_ids: Array[String] = []

var _session_active: bool = false
var _coins_earned: int = 0
var _rounds_completed: int = 0
var _stock: Dictionary = {}
var _consumed: Dictionary = {}
var _last_customer_id: String = ""
var _current_customer: WarungCustomer = null
var _current_order: WarungOrder = null


func _ready() -> void:
	_rng.randomize()
	_drag.setup(_camera)
	_drag.set_enabled(false)
	_drag.picked.connect(_on_picked)
	_drag.dropped.connect(_on_dropped)

	_order_card.visible = false
	_order_card.replay_requested.connect(_on_replay_requested)

	_confirm_button.visible = false
	_confirm_button.icon_texture = PlaceholderFactory.build_glyph_icon("check", Palette.UI_PANEL, 128)
	_confirm_button.accent = Palette.CORRECT

	_home_button.home_confirmed.connect(_on_home_confirmed)
	SceneRouter.back_requested.connect(_home_button.request_exit)

	_coin_display.show_total(0)

	_build_counter()


func get_game_id() -> String:
	return GAME_ID


func get_intro_voice_id() -> String:
	return String(_level.get("intro_voice_id", ""))


func start_session(level: int) -> void:
	level_index = level
	_level = ContentDB.get_level(GAME_ID, level)
	if _level.is_empty():
		Log.e("Warung has no level data, leaving for the hub", "Warung")
		request_exit()
		return

	if bool(_level.get("money_enabled", false)):
		# Levels 4-5 are stretch scope (§16.5). The data is here so the design is
		# recorded, but a child must never be handed an unbuilt mechanic.
		Log.w("Level %d wants money, which is not built yet. Playing it without." % level, "Warung")

	_session_active = true
	_coins_earned = 0
	_rounds_completed = 0
	_consumed = {}
	_snapshot_stock()
	_stock_shelf()

	_run_session()


func pause_session() -> void:
	is_paused = true
	_drag.set_enabled(false)


func resume_session() -> void:
	is_paused = false
	if _session_active and _current_order != null:
		_drag.set_enabled(true)


# ---------------------------------------------------------------- session

func _run_session() -> void:
	var customers: int = maxi(1, int(_level.get("customers_per_session", 5)))

	for index: int in range(customers):
		if not _session_active:
			return
		await _run_round(index)

	if not _session_active:
		return

	_finish()


func _run_round(index: int) -> void:
	var customer: WarungCustomer = _spawn_customer()
	_current_customer = customer

	await customer.walk_in(CUSTOMER_ENTRY, CUSTOMER_SPOT)
	if not _session_active:
		return

	customer.speak_greeting()

	# The how-to-play line runs once per session, not once per customer (§8.1.2).
	if index == 0:
		var intro: String = get_intro_voice_id()
		if not intro.is_empty():
			VoiceBank.play(intro)

	var order: WarungOrder = WarungOrder.generate(_level, _shelf_item_ids, customer.voice_prefix, _rng)
	_current_order = order
	Log.d(order.describe(), "Warung")

	_order_card.set_order(order.to_card_entries())
	_order_card.visible = true

	await _wait(ORDER_VOICE_DELAY)
	if not _session_active:
		return
	customer.speak_order(order)

	_drag.set_enabled(true)
	_confirm_button.visible = true

	var attempts: int = 0
	while _session_active:
		await _confirm_button.pressed
		if not _session_active:
			return
		if order.is_satisfied_by(_tray.get_counts()):
			break
		attempts += 1
		_respond_to_wrong_answer(order, attempts, customer)

	if not _session_active:
		return

	await _complete_round(order, customer)


## Correct. Everything here is reward: coins, praise, a happy customer.
func _complete_round(order: WarungOrder, customer: WarungCustomer) -> void:
	_drag.set_enabled(false)
	_confirm_button.visible = false
	_clear_highlights()

	_record_sale(order)

	var reward: int = maxi(1, int(_level.get("coins_per_customer", 2)))
	_coins_earned += reward
	_rounds_completed += 1
	_coin_display.show_total(_coins_earned)

	SfxBank.play(SfxBank.COIN)
	customer.react_happy()
	VoiceBank.play("kanca_ui_benar")

	_order_card.visible = false
	_tray.clear()

	await _wait(0.6)
	if not _session_active:
		return

	customer.speak_farewell()
	await customer.walk_out(CUSTOMER_EXIT)
	customer.queue_free()
	_current_customer = null
	_current_order = null

	await _wait(NEXT_CUSTOMER_DELAY)


## Wrong. Nothing is lost and nothing is blocked — the help simply gets louder
## until the answer is visible on the shelf (§3.2, §8.1.8).
func _respond_to_wrong_answer(order: WarungOrder, attempts: int, customer: WarungCustomer) -> void:
	SfxBank.play(SfxBank.GENTLE)
	customer.react_confused()
	_order_card.pulse()

	var hint_threshold: int = maxi(1, int(_level.get("hint_after_attempts", 3)))

	if attempts == 1:
		return

	if attempts < hint_threshold:
		# Second try: point back at the order rather than at the answer.
		VoiceBank.play("kanca_hint_dengar")
		customer.repeat_order(order)
		return

	# Third try onwards: show them. A child who has tried three times has earned
	# the answer, and leaving them stuck is the one thing this design forbids.
	VoiceBank.play("kanca_hint_lihat")
	_highlight_answer(order)

	# A glowing shelf answers "which one", not "how many". A child holding one too
	# many already has the right item and needs pointing back at the count.
	if order.has_surplus(_tray.get_counts()):
		VoiceBank.play("kanca_hint_hitung")
		_order_card.pulse(3)


func _finish() -> void:
	_session_active = false
	_drag.set_enabled(false)
	_confirm_button.visible = false
	_order_card.visible = false

	var result: MiniGameResult = MiniGameResult.create(GAME_ID, level_index)
	result.rounds_completed = _rounds_completed
	result.coins_earned = _coins_earned
	result.items_consumed = _consumed.duplicate()

	finish_session(result)


func _on_home_confirmed() -> void:
	# Leaving early keeps whatever was earned. Nothing is taken away for stopping.
	_session_active = false
	_drag.set_enabled(false)

	if _rounds_completed > 0:
		var result: MiniGameResult = MiniGameResult.create(GAME_ID, level_index)
		result.rounds_completed = _rounds_completed
		result.coins_earned = _coins_earned
		result.items_consumed = _consumed.duplicate()
		finish_session(result)
		return

	request_exit()


# ---------------------------------------------------------------- shelf

## §8.4: produce grown in the Kebun should turn up here. The chain is a reward,
## never a gate — if the child has grown nothing, the shelf stocks itself from
## the level pool and play is unaffected.
func _stock_shelf() -> void:
	var pool: Array[String] = []
	for entry: Variant in (_level.get("item_pool", []) as Array):
		var item_id: String = String(entry)
		if ContentDB.has_item(item_id):
			pool.append(item_id)

	if pool.is_empty():
		Log.e("Level %d has no usable item pool, falling back" % level_index, "Warung")
		pool = ["pisang", "apel", "telur", "roti"]

	var requested: int = clampi(int(_level.get("shelf_item_types", 3)), 1, pool.size())
	var wanted: int = mini(requested, MAX_SHELF_SLOTS)
	if wanted < requested:
		# Never silently. More slots than this cannot be shown at the required
		# touch size without running off the edge of the frame.
		Log.w("Level %d asked for %d shelf types, showing %d - more will not fit the frame at the minimum touch size"
			% [level_index, requested, wanted], "Warung")

	var grown: Array[String] = []
	var rest: Array[String] = []
	for item_id: String in pool:
		if int(_stock.get(item_id, 0)) > 0:
			grown.append(item_id)
		else:
			rest.append(item_id)

	RngUtil.shuffle(grown, _rng)
	RngUtil.shuffle(rest, _rng)

	_shelf_item_ids = []
	for item_id: String in grown:
		if _shelf_item_ids.size() >= wanted:
			break
		_shelf_item_ids.append(item_id)
	for item_id: String in rest:
		if _shelf_item_ids.size() >= wanted:
			break
		_shelf_item_ids.append(item_id)

	_build_slots()


func _build_slots() -> void:
	for child: Node in _shelf.get_children():
		child.queue_free()
	_slots.clear()

	var count: int = _shelf_item_ids.size()
	var gaps: int = maxi(count - 1, 1)
	var step: float = minf(SLOT_SPACING, MAX_SHELF_SPAN / float(gaps))
	var start: float = -step * float(gaps) * 0.5 if count > 1 else 0.0

	for i: int in range(count):
		var item_id: String = _shelf_item_ids[i]
		var slot: ShelfSlot = ShelfSlot.new()
		_shelf.add_child(slot)
		slot.setup(item_id)
		slot.position = Vector3(start + step * float(i), SHELF_Y, SHELF_Z)
		_slots[item_id] = slot


## §8.1.8: "correct items on the shelf begin glowing". Every item in the order,
## not just the ones still short — the glow answers "which of these did she ask
## for", and that question has the same answer however the tray currently looks.
func _highlight_answer(order: WarungOrder) -> void:
	_clear_highlights()
	for item_id: String in order.get_item_ids():
		if _slots.has(item_id):
			(_slots[item_id] as ShelfSlot).set_highlighted(true)


func _clear_highlights() -> void:
	for item_id: String in _slots:
		(_slots[item_id] as ShelfSlot).set_highlighted(false)


# ---------------------------------------------------------------- inventory

func _snapshot_stock() -> void:
	_stock = {}
	for item_id: String in GameState.get_stocked_item_ids():
		_stock[item_id] = GameState.get_item_count(item_id)


## Sold items come out of the inventory when the child has them, and are simply
## conjured when they do not. §8.4 is explicit that the economy never blocks play.
func _record_sale(order: WarungOrder) -> void:
	for item_id: String in order.counts:
		var wanted: int = int(order.counts[item_id])
		var available: int = int(_stock.get(item_id, 0))
		var taken: int = mini(wanted, available)
		if taken <= 0:
			continue
		_stock[item_id] = available - taken
		_consumed[item_id] = int(_consumed.get(item_id, 0)) + taken


# ---------------------------------------------------------------- customers

func _spawn_customer() -> WarungCustomer:
	var roster: Array = ContentDB.get_level_data(GAME_ID, "customers", []) as Array
	if roster.is_empty():
		roster = [{"id": "anak", "voice_prefix": "cust_anak", "colour": "f28b82", "height": 0.95}]

	# §8.1: rotate randomly, never the same variant twice in a row.
	var choices: Array = []
	for entry: Variant in roster:
		if String((entry as Dictionary).get("id", "")) != _last_customer_id:
			choices.append(entry)
	if choices.is_empty():
		choices = roster

	var config: Dictionary = choices[_rng.randi_range(0, choices.size() - 1)] as Dictionary
	_last_customer_id = String(config.get("id", ""))

	var customer: WarungCustomer = WarungCustomer.new()
	_customer_root.add_child(customer)
	customer.setup(config)
	return customer


# ---------------------------------------------------------------- counter

## Placeholder set dressing. Replaced wholesale by the real warung model (§11).
func _build_counter() -> void:
	var counter: Node3D = $Counter

	counter.add_child(_build_counter_top())

	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var floor_box: BoxMesh = BoxMesh.new()
	floor_box.size = Vector3(14.0, 0.3, 14.0)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = PlaceholderFactory.get_flat_material(Palette.STONE)
	floor_mesh.position = Vector3(0.0, -0.15, -1.0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)

	var wall: MeshInstance3D = MeshInstance3D.new()
	wall.name = "BackWall"
	var wall_box: BoxMesh = BoxMesh.new()
	wall_box.size = Vector3(14.0, 4.0, 0.4)
	wall.mesh = wall_box
	wall.material_override = PlaceholderFactory.get_flat_material(Palette.CREAM.darkened(0.06))
	wall.position = Vector3(0.0, 2.0, -5.0)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)

	_build_stock()


## The first of `paths` that exists, or the last one so callers still have
## something to try and to log about.
static func _first_available(paths: Array[String]) -> String:
	for path: String in paths:
		if ResourceLoader.exists(path):
			return path
	return paths[paths.size() - 1]


## The shop behind the shop: racks of goods, crates and sacks (§8.1).
##
## None of it is playable, and none of it can be. §3.3 sets a 120×120px minimum
## touch target and a 40px gap, which at this camera distance caps what a child
## can pick up at five items — see MAX_SHELF_SLOTS. Five bananas on a counter is
## not a warung, so the shop is stocked behind the five: dozens of jars and
## packets that read as a well-stocked shop, standing behind items large enough
## for a small hand.
##
## The line matters in both directions. A tin that looks like the apple next to
## it but cannot be picked up teaches a child that touching things does not work,
## so the stock stays behind the counter, out of reach and visibly further away.
func _build_stock() -> void:
	var stock: Node3D = Node3D.new()
	stock.name = "Stock"
	add_child(stock)

	# Four racks along the back wall, with the middle pair parted so the customer
	# is never standing in front of a shelf.
	# Spacing follows the rack that is actually present: the gondola is a metre
	# wide and the timber rack is nearly twice that, so one layout cannot serve
	# both without either gaps or racks growing through each other.
	var shelf_path: String = _first_available(SHELF_MODELS)
	var narrow: bool = shelf_path.ends_with("gondola.glb")
	var spots: Array = ([-4.2, -3.1, -2.0, 2.0, 3.1, 4.2] if narrow
		else [-3.5, -1.6, 1.6, 3.5])

	for x: float in spots:
		var rack: Node3D = ModelKit.instantiate(shelf_path)
		if rack == null:
			break
		rack.position = Vector3(x, 0.0, -4.5)
		# Models face +Y in Blender, which is -Z here — the far side from the
		# camera. Without this the shop shows the backs of its own shelves.
		rack.rotation.y = PI
		stock.add_child(rack)

	# In the mid-ground between the counter and the racks, where there is clear
	# floor. Anything at the counter's own depth is hidden behind it.
	for spot: Vector3 in [Vector3(-2.9, 0.0, -3.3), Vector3(3.0, 0.0, -3.2),
			Vector3(-4.3, 0.0, -2.4)]:
		var crate: Node3D = ModelKit.instantiate(CRATE_MODEL)
		if crate == null:
			break
		crate.position = spot
		crate.rotation.y = 0.35 if spot.x < 0.0 else -0.28
		stock.add_child(crate)

	for spot: Vector3 in [Vector3(4.3, 0.0, -2.6), Vector3(-4.5, 0.0, -3.9)]:
		var sacks: Node3D = ModelKit.instantiate(SACK_MODEL)
		if sacks == null:
			break
		sacks.position = spot
		sacks.rotation.y = -0.4 if spot.x < 0.0 else 0.5
		stock.add_child(sacks)


## The counter, built as planks rather than one box.
##
## It fills the bottom half of the frame, which makes it the largest single
## surface in the game, and as one flat brown rectangle it read as exactly that —
## the same failure the village floor had. Planks cost nothing: the seams give
## the eye something to sit on and the slight difference in tone between boards
## does the rest.
func _build_counter_top() -> Node3D:
	const PLANKS := 7
	const WIDTH := 5.4
	const DEPTH := 2.6

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8412

	# The solid body stays. The planks are a skin laid over it, and without
	# something underneath, the groove between two boards is a hole you can see
	# the shop through — which is what the first version of this did.
	# A container, with the body and the plank skin as siblings. Parenting the
	# planks to the body would apply the body's offset to coordinates that are
	# already absolute, and the counter grows to fill the room.
	var group: Node3D = Node3D.new()
	group.name = "Surface"

	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(WIDTH, COUNTER_TOP, DEPTH)
	body.mesh = box
	body.material_override = PlaceholderFactory.get_flat_material(Palette.WOOD.darkened(0.34))
	body.position = Vector3(0.0, COUNTER_TOP * 0.5, 0.85)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var plank_depth: float = DEPTH / float(PLANKS)
	for index: int in range(PLANKS):
		var z0: float = 0.85 - DEPTH * 0.5 + plank_depth * float(index)
		# A groove between boards, and a tone per board. Both are needed: the
		# groove alone gives stripes, the tone alone gives a gradient.
		# The groove is the dark body showing through, not a hole. Keep it small:
		# a wide gap reads as a slatted deck rather than a counter.
		var inset: float = 0.010
		var tone: Color = Palette.WOOD.lerp(
			Palette.WOOD.darkened(0.09) if index % 2 == 0 else Palette.WOOD.lightened(0.05),
			rng.randf_range(0.30, 1.0))
		_add_plank(surface, Vector3(-WIDTH * 0.5, COUNTER_TOP + 0.003, z0 + inset),
			Vector3(WIDTH, 0.0, plank_depth - inset * 2.0), tone, true)

	surface.index()
	surface.generate_normals()

	var top: MeshInstance3D = MeshInstance3D.new()
	top.name = "Planks"
	top.mesh = surface.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	top.material_override = material
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	group.add_child(body)
	group.add_child(top)
	return group


## One flat quad. `size` gives its two spans; whichever component is zero is the
## direction it faces.
##
## Winding decides which side of that quad exists. With this vertex order the
## face that renders is the one facing `across × along`: for the counter's front
## panel — across +X, along +Y — that is +Z, towards the camera, which is right.
## For the top — across +X, along +Z — it is −Y, pointing at the floor, and the
## counter simply is not there. `flip` reverses it. This is not a detail that can
## be reasoned about once and trusted: the fascia rendered and the top did not,
## from the same function on the same call.
func _add_plank(surface: SurfaceTool, origin: Vector3, size: Vector3, colour: Color,
		flip: bool = false) -> void:
	var across: Vector3 = Vector3(size.x, 0.0, 0.0)
	var along: Vector3 = Vector3(0.0, size.y, size.z)
	surface.set_color(colour.srgb_to_linear())

	var order: Array[Vector3] = [origin, origin + along, origin + across + along,
		origin, origin + across + along, origin + across]
	if flip:
		order = [origin, origin + across, origin + across + along,
			origin, origin + across + along, origin + along]

	for corner: Vector3 in order:
		surface.add_vertex(corner)


# ---------------------------------------------------------------- reactions

## Every item names itself as it is picked up. This is passive vocabulary
## learning and §8.1.5 is explicit that it must never be skipped.
func _on_picked(item_id: String, source: Draggable) -> void:
	VoiceBank.play(ContentDB.get_item_voice_id(item_id))

	# Lifting something off the tray takes it off the tray. That is the undo
	# gesture, and undo must always be available (§8.1.6).
	var tray_item: TrayItem = source as TrayItem
	if tray_item != null:
		_tray.detach_item(tray_item)
		tray_item.queue_free()


func _on_dropped(item_id: String, target: DropTarget) -> void:
	if target != null and target == _tray.get_drop_zone():
		_tray.add_item(item_id)
		SfxBank.play(SfxBank.POP)


func _on_replay_requested() -> void:
	if _current_order == null or _current_customer == null:
		return
	_current_customer.repeat_order(_current_order)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
