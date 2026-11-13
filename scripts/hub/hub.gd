extends Node3D

## Kampung Kanca — the village the child walks around between mini-games
## (PLAN.md §7).
##
## The hub owns two things nothing else does: it is the only consumer of
## MiniGameResult (§6.2), and it is the only place that decides what the child
## should try next. Everything about the buildings themselves comes from
## data/minigames.json, so a fourth mini-game needs no change here.
##
## The village is one model — ground, paths, fence, trees and all three buildings
## baked into a single mesh. It replaced a procedurally generated village on
## 2026-08-31; ASSETS.md records where it came from and what had to be repaired
## before it could be used.
##
## What that changes here is mostly deletion. The ground, the stepping stones,
## the undergrowth, the tree ring and the backdrop hills were each built in this
## file and are now painted into the model. What stays is everything the *game*
## needs and a picture cannot provide: where each building stands, how close the
## child has to be for its prompt, what is unlocked, and what to suggest next.
##
## Buildings are not separate objects in that mesh and do not need to be. A child
## never enters one from the village — they walk up, a prompt appears, and the
## router loads a different scene (§6.3, §7.1). `Building` therefore places a
## collider, a sign and a trigger at a position from data/minigames.json, and
## draws no model of its own.

## The model, and how big it is. §7.1 asks for roughly 40 × 40 units; this is 30,
## because the buildings are a fixed fraction of the tile and at forty they came
## out nearer ten metres across than the five to seven §11 asks for. A smaller
## village also suits a child who has to cross it on a phone.
const VILLAGE_MODEL := "res://assets/models/environment/village_market.glb"
const HALF_EXTENT := 15.0

## The fence, which is both what the child sees and what stops them. The inset is
## measured off the model's own line of posts, not chosen — see fence_line().
const FENCE_HEIGHT := 1.15
const FENCE_THICKNESS := 0.55
const FENCE_INSET := 0.9

const PLAYER_START := Vector2(0.0, 6.0)

## Undergrowth sown over the model's lawn.
##
## The village mesh is at its weakest exactly where the child spends the most
## time looking: the open middle is a flat expanse of pale green with nothing in
## it, because an atlas split across 3,844 islands has no resolution to spare for
## the biggest surface in the scene. Geometry is the cheap answer — the same
## vertex-coloured tufts, bushes and flowers the Kebun already scatters, which
## are crisp where the texture is soft and which match the child and Kanca rather
## than the backdrop.
##
## Each entry is how many, how big, how far from a building, and how much to
## favour the edges over the middle.
const SOWN: Array[Dictionary] = [
	{"id": "grass_tuft", "count": 340, "scale": Vector2(0.65, 1.20), "clearance": 2.6,
		"near_edge": 0.30},
	{"id": "flower_red", "count": 22, "scale": Vector2(0.85, 1.30), "clearance": 3.2,
		"near_edge": 0.45},
	{"id": "flower_purple", "count": 20, "scale": Vector2(0.85, 1.30), "clearance": 3.2,
		"near_edge": 0.45},
	{"id": "bush", "count": 14, "scale": Vector2(0.70, 1.20), "clearance": 4.0,
		"near_edge": 0.7},
]

## How far out the sown ground reaches. Short of the fence, because the model's
## own planting is already thick there and doubling it makes a hedge.
const SOWN_REACH := 11.5

## Above this, a spot is a roof, a stall or a crate rather than lawn. The village
## floor rolls by about a third of a metre; nothing is planted on anything higher.
const SOWN_MAX_HEIGHT := 0.42

const SOWN_SEED := 20260831

@onready var _world: Node3D = $World
@onready var _player: HubPlayer = $Player
@onready var _camera: HubCamera = $Camera
@onready var _kanca: MascotCompanion = $Kanca
@onready var _pad: MovementControl = $UI/SafeArea/Screen/Pad
@onready var _gestures: CameraGestures = $UI/SafeArea/Screen/Gestures
@onready var _zoom: ZoomControls = $UI/SafeArea/Screen/Zoom
@onready var _enter_prompt: BigButton = $UI/SafeArea/Screen/EnterPrompt
@onready var _celebration: CelebrationOverlay = $UI/Celebration

var _ground_height: VillageHeightField = null
var _buildings: Dictionary = {}
var _nearby_game_id: String = ""
var _pending_result: MiniGameResult = null


func _ready() -> void:
	_player.pad = _pad
	_player.camera = _camera
	_player.warp_to(PLAYER_START)
	_camera.target = _player
	# Kept inside the fence, so pulling back never puts a tree between the child
	# and the camera.
	_camera.limit = fence_line() - 1.5
	_zoom.camera = _camera
	_gestures.camera = _camera
	_kanca.target = _player

	_kanca.position = Vector3(PLAYER_START.x - 1.6, 0.0, PLAYER_START.y + 0.6)

	_enter_prompt.visible = false
	_enter_prompt.pressed.connect(_on_enter_pressed)

	_celebration.dismissed.connect(_on_celebration_dismissed)

	_build_ground()
	_build_boundary()
	_build_buildings()
	_sow_undergrowth()

	GameState.progress_changed.connect(_refresh_unlocks)
	SceneRouter.mini_game_finished.connect(_on_mini_game_finished)
	SceneRouter.transition_finished.connect(_on_transition_finished)

	# The hub is hidden rather than unloaded while a mini-game runs (§6.3), so it
	# has to take its camera back and drop any held direction when it returns.
	visibility_changed.connect(_on_visibility_changed)

	_refresh_unlocks()
	_kanca.greet()


func _on_visibility_changed() -> void:
	if visible:
		_camera.make_current()
		return
	_pad.release_all()
	_enter_prompt.visible = false
	_nearby_game_id = ""


# ---------------------------------------------------------------- village

## Where the fence stands, in world units from the centre. One function, because
## the colliders and the model's own line of posts have to agree, and a fence you
## can walk through is what happens when they do not. Measured off the model.
func fence_line() -> float:
	return HALF_EXTENT - FENCE_INSET


## The village: one mesh for what is seen, the same mesh again for what is walked
## on.
##
## The collider is the geometry rather than a flat box, which reverses what the
## procedural village did. That box existed because the ground it stood in for
## was decorative noise — a fifth of a metre of undulation nobody needed to walk
## over, and flattening it meant no terrain edit could ever put a lip under a
## four-year-old's feet. This ground is not that. It rises and falls by a third
## of a metre, it has stalls and rocks standing on it, and a flat box would bury
## the child's feet in exactly the way the old one was caught doing.
##
## The village casts real shadows. It carries some baked into its atlas, but they
## are faint enough not to fight, and without a real set the buildings sit on the
## grass like stickers — nothing in the scene tells you the Dapur is a solid
## object three metres tall. One extra shadow pass over ten thousand triangles is
## the cheapest depth available.
func _build_ground() -> void:
	var village: Node3D = ModelKit.instantiate(VILLAGE_MODEL)
	if village == null:
		# §10.5: a missing asset is never fatal. Without the mesh there is nothing
		# to see and nothing to stand on, so lay a flat floor and let the rest of
		# the village — buildings, signs, prompts, unlocking — still work.
		Log.w("No village model at %s — laying a bare floor instead" % VILLAGE_MODEL,
			"Hub")
		_add_flat_floor()
		return
	village.name = "Village"
	_world.add_child(village)
	var mesh: Mesh = ModelKit.load_mesh(VILLAGE_MODEL)
	if mesh == null:
		_add_flat_floor()
		return
	# Read once, into a grid, because the scatter below runs before the physics
	# server has a frame to answer rays in.
	_ground_height = VillageHeightField.new(mesh)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	_world.add_child(body)


## Hedges, not invisible walls. §7.1 is explicit: a child who walks into nothing
## and stops has no idea why, and will keep trying.
## The bamboo fence is the boundary, and it is solid (PLAN.md 7.1).
##
## There used to be a hedge here as well: a dark green wall standing behind the
## fence, carrying the collision while the fence was decoration. Two things wrong
## with that. It put a flat green slab across the horizon on every side, and the
## thing that actually stopped the child was not the thing they could see
## stopping them - the fence was walked through and the invisible surface half a
## metre behind it did the work, which is very close to the invisible wall 7.1
## exists to forbid.
##
## Now the fence is the wall. The colliders sit exactly on the line of posts.
func _build_boundary() -> void:
	var reach: float = fence_line()
	var span: float = reach * 2.0 + FENCE_THICKNESS

	var edges: Array = [
		{"position": Vector3(0.0, 0.0, -reach), "size": Vector3(span, FENCE_HEIGHT, FENCE_THICKNESS)},
		{"position": Vector3(0.0, 0.0, reach), "size": Vector3(span, FENCE_HEIGHT, FENCE_THICKNESS)},
		{"position": Vector3(-reach, 0.0, 0.0), "size": Vector3(FENCE_THICKNESS, FENCE_HEIGHT, span)},
		{"position": Vector3(reach, 0.0, 0.0), "size": Vector3(FENCE_THICKNESS, FENCE_HEIGHT, span)},
	]

	for index: int in range(edges.size()):
		var edge: Dictionary = edges[index]
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "FenceBody%d" % index
		body.collision_layer = 1
		body.collision_mask = 0

		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = edge["size"] as Vector3
		shape.shape = box
		body.add_child(shape)
		body.position = (edge["position"] as Vector3) + Vector3(0.0, FENCE_HEIGHT * 0.5, 0.0)
		_world.add_child(body)


## Scatters undergrowth across the model's lawn.
##
## Placed against the height field rather than at y=0: the ground is real
## geometry now and a plant dropped on the plane would be buried at one end of
## the village and hovering at the other. Rejection sampling, like the Kebun's —
## a tuft that cannot find anywhere legal is dropped rather than forced somewhere
## wrong, because one fewer tuft costs nothing and a bush growing through the
## Warung counter costs the whole illusion.
func _sow_undergrowth() -> void:
	if _ground_height == null or not _ground_height.is_ready():
		return

	# Buildings, and the patch of grass the child is standing on when the village
	# loads. A tuft in front of a door is untidy; a bush on top of the avatar the
	# first time a four-year-old sees themselves is not.
	var centres: Array[Vector2] = [PLAYER_START]
	for game_id: String in ContentDB.get_mini_game_ids():
		var raw: Array = ContentDB.get_mini_game(game_id).get("hub_position", [0.0, 0.0]) as Array
		centres.append(Vector2(float(raw[0]), float(raw[1])))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var sown: Node3D = Node3D.new()
	sown.name = "Undergrowth"
	_world.add_child(sown)

	for kind: Dictionary in SOWN:
		# A stream per type, so changing how many flowers there are does not
		# reshuffle every tuft in the village.
		rng.seed = SOWN_SEED + hash(kind["id"])
		var transforms: Array[Transform3D] = _sow_one(kind, centres, rng)
		var node: MultiMeshInstance3D = VillageScatter.instance_model(
			ModelKit.load_mesh("res://assets/models/environment/%s.glb" % kind["id"]),
			transforms, [], false)
		if node != null:
			node.name = String(kind["id"]).capitalize()
			sown.add_child(node)


func _sow_one(kind: Dictionary, centres: Array[Vector2],
		rng: RandomNumberGenerator) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var wanted: int = int(kind["count"])
	var clearance: float = float(kind["clearance"])
	var near_edge: float = float(kind["near_edge"])
	var scale_range: Vector2 = kind["scale"] as Vector2

	var attempts: int = 0
	var limit: int = wanted * 30
	while transforms.size() < wanted and attempts < limit:
		attempts += 1
		var point: Vector2 = Vector2(rng.randf_range(-SOWN_REACH, SOWN_REACH),
			rng.randf_range(-SOWN_REACH, SOWN_REACH))

		# Biasing outward is what leaves an open middle to walk in instead of an
		# even sprinkle that reads as wallpaper.
		if near_edge > 0.0:
			var pull: float = maxf(absf(point.x), absf(point.y)) / SOWN_REACH
			if rng.randf() > lerpf(1.0 - near_edge, 1.0, pull):
				continue

		var blocked: bool = false
		for centre: Vector2 in centres:
			if point.distance_to(centre) < clearance:
				blocked = true
				break
		if blocked:
			continue

		var height: float = _ground_height.height_at(point)
		if height > SOWN_MAX_HEIGHT:
			continue

		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y))
		# Sunk a centimetre: a plant whose base sits exactly on the surface shows
		# a hairline of ground through the gap between its lowest facets.
		transforms.append(Transform3D(basis, Vector3(point.x, height - 0.01, point.y)))

	return transforms


func _add_flat_floor() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(HALF_EXTENT * 2.0, 0.6, HALF_EXTENT * 2.0)
	shape.shape = box
	shape.position.y = -0.3
	body.add_child(shape)
	_world.add_child(body)


# ---------------------------------------------------------------- buildings

func _build_buildings() -> void:
	for game_id: String in ContentDB.get_mini_game_ids():
		var config: Dictionary = ContentDB.get_mini_game(game_id)
		var building: Building = Building.new()
		_world.add_child(building)
		building.setup(game_id, config, _is_playable(game_id))
		building.player_approached.connect(_on_building_approached)
		building.player_left.connect(_on_building_left)
		_buildings[game_id] = building


# ---------------------------------------------------------------- prompts

func _on_building_approached(game_id: String) -> void:
	_nearby_game_id = game_id
	var building: Building = _buildings[game_id] as Building

	_enter_prompt.icon_texture = building.get_icon()
	_enter_prompt.accent = Palette.SIGNATURE if building.is_unlocked else Palette.UI_DISABLED
	_enter_prompt.is_locked = not building.is_unlocked
	_enter_prompt.visible = true
	_enter_prompt.pulse(1)

	_kanca.clear_point()


func _on_building_left(game_id: String) -> void:
	if _nearby_game_id != game_id:
		return
	_nearby_game_id = ""
	_enter_prompt.visible = false
	_enter_prompt.stop_pulse()
	_point_at_recommendation()


## A single deliberate tap enters. §7.1 forbids entering on proximity alone.
func _on_enter_pressed() -> void:
	if _nearby_game_id.is_empty():
		return

	var building: Building = _buildings[_nearby_game_id] as Building
	if not building.is_unlocked:
		# Locked is "resting", not "denied". Kanca explains and points elsewhere.
		VoiceBank.play("kanca_locked")
		_point_at_recommendation()
		return

	VoiceBank.play("kanca_enter_building")
	SceneRouter.go_to_mini_game(_nearby_game_id)


# ---------------------------------------------------------------- progression

## A building opens when the child has earned it *and* the mini-game behind it
## exists. Both have to be true, and neither is the other's business: progress
## lives in GameState, existence in ContentDB.
func _is_playable(game_id: String) -> bool:
	return GameState.is_unlocked(game_id) and ContentDB.is_mini_game_available(game_id)


func _refresh_unlocks() -> void:
	for game_id: String in _buildings:
		var building: Building = _buildings[game_id] as Building
		building.set_unlocked(_is_playable(game_id))

	if not _nearby_game_id.is_empty():
		_on_building_approached(_nearby_game_id)
	else:
		_point_at_recommendation()


## What the child should try next: the first unlocked activity they have never
## played, otherwise whichever they have played least. Never a locked one — being
## pointed at something you cannot do is the definition of frustrating.
func _get_recommended_game_id() -> String:
	var best: String = ""
	var best_sessions: int = -1

	for game_id: String in ContentDB.get_mini_game_ids():
		if not _is_playable(game_id):
			continue
		var sessions: int = GameState.get_sessions_completed(game_id)
		if sessions == 0:
			return game_id
		if best_sessions < 0 or sessions < best_sessions:
			best = game_id
			best_sessions = sessions

	return best


func _point_at_recommendation() -> void:
	var game_id: String = _get_recommended_game_id()
	if game_id.is_empty() or not _buildings.has(game_id):
		_kanca.clear_point()
		return
	_kanca.point_at((_buildings[game_id] as Building).global_position)


# ---------------------------------------------------------------- results

## The hub is the only place a MiniGameResult is turned into progress (§6.2).
## The celebration waits for the transition to finish so it does not play behind
## the fade curtain.
func _on_mini_game_finished(game_id: String, result: MiniGameResult) -> void:
	Log.i("Session finished: %s" % result.describe(), "Hub")
	GameState.apply_result(result)
	_pending_result = result
	_kanca.pause_idle_chatter()


func _on_transition_finished() -> void:
	if _pending_result == null:
		return
	var result: MiniGameResult = _pending_result
	_pending_result = null
	# He cheers behind the overlay, so the village is already celebrating when it
	# is dismissed rather than snapping back to a companion standing still.
	_kanca.celebrate()
	_celebration.show_result(result)


func _on_celebration_dismissed() -> void:
	_kanca.resume_idle_chatter()
	_point_at_recommendation()
