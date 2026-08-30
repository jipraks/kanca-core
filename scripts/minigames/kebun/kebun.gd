extends MiniGame

## MG-02 Kebun — the garden (PLAN.md §8.2).
##
## Plant a seed, water it, watch it grow through three stages, pick the fruit.
## The learning is the life cycle and the order it happens in: cause and effect a
## child can see, and sequencing they have to get right.
##
## What is harvested here stocks the Warung shelf next session. That chain is
## what makes this feel like one world rather than a bag of unrelated games
## (§8.2) — and it is deliberately loose, because §8.4 forbids the economy ever
## blocking play.
##
## There is no round loop and no failure. The session ends when all six plots
## have been picked, in whatever order the child likes.

const GAME_ID := "kebun"

## Layout in world units (1 unit = 1 metre, §11).
##
## The camera is orthographic (see kebun.tscn), which is what makes this tractable:
## every plot projects to exactly the same size no matter which row it is in, so
## no plot is harder for a child to hit than another. One world unit is 90px, and
## the depth axis foreshortens by 0.866, so the §3.3 minimums translate directly
## into the spacings below. tools/kebun_test.tscn measures the result.
const PLOT_SPACING_X := 2.0
const PLOT_SPACING_Z := 2.2
const PLOTS_PER_ROW := 3
const PLOT_ORIGIN_Z := -1.0
const SEED_ROW_Z := 2.3
const SEED_SPACING := 2.0

## The garden's own patch of ground. Smaller than the village and centred behind
## the plots, so the fence sits at the edge of frame rather than across it.
const GARDEN_EXTENT := 9.0
const FENCE_INSET := 0.8
const SCENERY_CENTRE_Z := -1.0
const GARDEN_SEED := 30260830

@onready var _camera: Camera3D = $Camera
@onready var _plots_root: Node3D = $Plots
@onready var _seeds_root: Node3D = $Seeds
@onready var _drag: DragController = $DragController
@onready var _home_button: HomeButton = $UI/SafeArea/Screen/HomeButton
@onready var _coin_display: CoinDisplay = $UI/SafeArea/Screen/CoinDisplay

var _level: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _plots: Array[GardenPlot] = []
var _seed_pool: Array[String] = []
var _can: WateringCan = null

var _session_active: bool = false
var _harvested: Dictionary = {}
var _harvest_count: int = 0

## Each coaching line plays once. Repeating it every plot would turn a helpful
## companion into a nag (§7.1 rate-limits Kanca for the same reason).
var _said_plant: bool = false
var _said_water: bool = false
var _said_harvest: bool = false


func _ready() -> void:
	_rng.randomize()

	_drag.setup(_camera)
	_drag.carry_height = 1.1
	_drag.set_enabled(false)
	_drag.picked.connect(_on_picked)
	_drag.dropped.connect(_on_dropped)
	_drag.tapped.connect(_on_tapped)

	_home_button.home_confirmed.connect(_on_home_confirmed)
	SceneRouter.back_requested.connect(_home_button.request_exit)

	_coin_display.show_total(0)

	_build_scenery()


func get_game_id() -> String:
	return GAME_ID


func get_intro_voice_id() -> String:
	return String(_level.get("intro_voice_id", ""))


func start_session(level: int) -> void:
	level_index = level
	_level = ContentDB.get_level(GAME_ID, level)
	if _level.is_empty():
		Log.e("Kebun has no level data, leaving for the hub", "Kebun")
		request_exit()
		return

	_session_active = true
	_harvested = {}
	_harvest_count = 0
	_said_plant = false
	_said_water = false
	_said_harvest = false

	_resolve_seed_pool()
	_build_plots()
	_build_seed_sources()

	var intro: String = get_intro_voice_id()
	if not intro.is_empty():
		VoiceBank.play(intro)

	_drag.set_enabled(true)


func pause_session() -> void:
	is_paused = true
	_drag.set_enabled(false)


func resume_session() -> void:
	is_paused = false
	if _session_active:
		_drag.set_enabled(true)


# ---------------------------------------------------------------- interaction

func _on_picked(payload: String, _source: Draggable) -> void:
	if payload == WateringCan.PAYLOAD:
		VoiceBank.play("kanca_kebun_air")
		return
	# Naming each seed as it is picked up is the same passive vocabulary learning
	# the Warung relies on (§8.1.5).
	VoiceBank.play(ContentDB.get_item_voice_id(payload))


func _on_dropped(payload: String, target: DropTarget) -> void:
	if not _session_active or target == null:
		return

	var plot: GardenPlot = target.get_parent() as GardenPlot
	if plot == null:
		return

	if payload == WateringCan.PAYLOAD:
		_try_water(plot)
		return

	_try_plant(plot, payload)


func _try_plant(plot: GardenPlot, item_id: String) -> void:
	if not plot.can_plant():
		# Already growing, or already picked. Nothing is undone (§3.2).
		plot.nudge()
		VoiceBank.play("kanca_ui_belum_waktunya")
		return

	if not plot.accepts_seed(item_id):
		# Level 3 only: this plot is labelled for a different seed (§8.2).
		plot.nudge()
		SfxBank.play(SfxBank.GENTLE)
		VoiceBank.play("kanca_ui_coba_lagi")
		return

	plot.plant(item_id)

	if not _said_water:
		_said_water = true
		VoiceBank.play("kanca_kebun_siram")


func _try_water(plot: GardenPlot) -> void:
	if not plot.needs_water():
		plot.nudge()
		if plot.can_plant():
			# Water before a seed. Point at what comes first, gently.
			VoiceBank.play("kanca_kebun_tanam")
		else:
			VoiceBank.play("kanca_ui_belum_waktunya")
		return

	plot.water()


func _on_tapped(target: TapTarget) -> void:
	if not _session_active:
		return

	var plot: GardenPlot = target.get_parent() as GardenPlot
	if plot == null or not plot.is_ready():
		return

	var item_id: String = plot.harvest()
	if item_id.is_empty():
		return

	_harvested[item_id] = int(_harvested.get(item_id, 0)) + int(_level.get("harvest_per_plot", 1))
	_harvest_count += 1

	VoiceBank.play(ContentDB.get_item_voice_id(item_id))
	VoiceBank.play("kanca_ui_benar")

	if _harvest_count >= _plots.size():
		_finish()


func _on_plot_ready(_plot: GardenPlot) -> void:
	if _said_harvest:
		return
	_said_harvest = true
	VoiceBank.play("kanca_kebun_panen")


# ---------------------------------------------------------------- session end

func _finish() -> void:
	_session_active = false
	_drag.set_enabled(false)

	var coins: int = maxi(1, int(_level.get("coins_per_session", 3)))
	_coin_display.show_total(coins)
	SfxBank.play(SfxBank.COIN)

	finish_session(_build_result(coins))


func _on_home_confirmed() -> void:
	# Leaving early keeps whatever was picked. Stopping costs nothing (§3.2).
	_session_active = false
	_drag.set_enabled(false)

	if _harvest_count > 0:
		var share: int = int(round(float(_level.get("coins_per_session", 3)) * float(_harvest_count) / float(maxi(_plots.size(), 1))))
		finish_session(_build_result(maxi(share, 1)))
		return

	request_exit()


func _build_result(coins: int) -> MiniGameResult:
	var result: MiniGameResult = MiniGameResult.create(GAME_ID, level_index)
	result.rounds_completed = _harvest_count
	result.coins_earned = coins
	result.items_produced = _harvested.duplicate()
	return result


# ---------------------------------------------------------------- construction

func _resolve_seed_pool() -> void:
	_seed_pool = []
	for entry: Variant in (_level.get("seed_pool", []) as Array):
		var item_id: String = String(entry)
		if ContentDB.has_item(item_id):
			_seed_pool.append(item_id)

	if _seed_pool.is_empty():
		Log.e("Level %d has no usable seed pool, falling back to pisang" % level_index, "Kebun")
		_seed_pool = ["pisang"]


func _build_plots() -> void:
	for child: Node in _plots_root.get_children():
		child.queue_free()
	_plots = []

	var count: int = maxi(1, int(_level.get("plots", 6)))
	var grow_seconds: float = float(_level.get("grow_seconds", 6.0))
	var stages: int = int(_level.get("grow_stages", 3))
	var matched: bool = bool(_level.get("match_seed_to_plot", false))

	# Written out rather than as a ternary: the empty-array branch of a ternary is
	# untyped, which fails the Array[String] assignment at runtime and silently
	# leaves the garden with no plots at all.
	var requirements: Array[String] = []
	if matched:
		requirements = _build_requirements(count)

	var rows: int = int(ceil(float(count) / float(PLOTS_PER_ROW)))
	for i: int in range(count):
		var row: int = i / PLOTS_PER_ROW
		var column: int = i % PLOTS_PER_ROW
		var columns_in_row: int = mini(count - row * PLOTS_PER_ROW, PLOTS_PER_ROW)

		var plot: GardenPlot = GardenPlot.new()
		_plots_root.add_child(plot)
		plot.setup(i, grow_seconds, stages, requirements[i] if i < requirements.size() else "")
		plot.position = Vector3(
			(float(column) - float(columns_in_row - 1) * 0.5) * PLOT_SPACING_X,
			0.0,
			PLOT_ORIGIN_Z + (float(row) - float(rows - 1) * 0.5) * PLOT_SPACING_Z)
		plot.became_ready.connect(_on_plot_ready)
		_plots.append(plot)


## Spreads the required seeds evenly across the plots, then shuffles, so level 3
## never asks for six of the same thing and never lands them in a tidy block.
func _build_requirements(count: int) -> Array[String]:
	var requirements: Array[String] = []
	for i: int in range(count):
		requirements.append(_seed_pool[i % _seed_pool.size()])
	RngUtil.shuffle(requirements, _rng)
	return requirements


## Baskets and the watering can share one evenly-spaced row. Placing the can
## separately meant its gap to the nearest basket depended on how many seeds the
## level happened to use, and at level 3 that gap fell under the §3.3 minimum.
func _build_seed_sources() -> void:
	for child: Node in _seeds_root.get_children():
		child.queue_free()

	var slots: int = _seed_pool.size() + 1
	for i: int in range(_seed_pool.size()):
		var source: SeedSource = SeedSource.new()
		_seeds_root.add_child(source)
		source.setup(_seed_pool[i])
		source.position = Vector3(_row_x(i, slots), 0.0, SEED_ROW_Z)

	_can.position = Vector3(_row_x(slots - 1, slots), 0.0, SEED_ROW_Z)


func _row_x(index_in_row: int, slots: int) -> float:
	return (float(index_in_row) - float(slots - 1) * 0.5) * SEED_SPACING


## Placeholder set dressing, replaced wholesale by the real garden model (§11).
## The garden's surroundings, built from the same pieces as the village.
##
## Reused rather than rebuilt: the same vertex-coloured ground, the same bamboo
## fence, the same bushes and grass. §8.4 says the Kebun and the Warung are one
## world and the produce chain is what proves it — a garden with its own flat
## green floor and its own brown plank fence would say the opposite before the
## child has planted anything.
func _build_scenery() -> void:
	var ground: MeshInstance3D = VillageGround.build(
		GARDEN_EXTENT, Vector2.ZERO, 0.0, [], GARDEN_SEED)
	ground.position.z = SCENERY_CENTRE_Z
	add_child(ground)

	var blocked: Array = [{"centre": Vector2(0.0, 0.0), "radius": 5.2}]
	var scatter: Node3D = VillageScatter.build(GARDEN_EXTENT, FENCE_INSET,
		Vector2.ZERO, 0.0, [], blocked, GARDEN_SEED)
	scatter.position.z = SCENERY_CENTRE_Z
	add_child(scatter)

	_can = WateringCan.new()
	add_child(_can)
	_can.setup()
