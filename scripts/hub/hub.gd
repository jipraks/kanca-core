extends Node3D

## Kampung Kanca — the village the child walks around between mini-games
## (PLAN.md §7).
##
## The hub owns two things nothing else does: it is the only consumer of
## MiniGameResult (§6.2), and it is the only place that decides what the child
## should try next. Everything about the buildings themselves comes from
## data/minigames.json, so a fourth mini-game needs no change here.
##
## The village geometry below is generated placeholder art. When the real
## Kenney/Quaternius village arrives it becomes a scene instance and the rest of
## this file is unaffected (§11).

## §7.1 asks for roughly 40 × 40 world units.
const HALF_EXTENT := 20.0
## The fence, which is both what the child sees and what stops them.
const FENCE_HEIGHT := 1.15
const FENCE_THICKNESS := 0.55
const FENCE_INSET := 1.4

## How much clear ground a backdrop hill must leave outside the fence. A hill
## that reaches over it stops being scenery and becomes a wall.
const HILL_CLEARANCE := 6.0

## Trunk collision. Generous against the model's own trunk, because a child
## walking a diagonal into a tree should be turned aside rather than snagged on
## a cylinder narrower than the thing they can see.
const TRUNK_RADIUS := 0.42
const TRUNK_HEIGHT := 2.6
const TREE_COUNT := 14
const PLAYER_START := Vector2(0.0, 4.0)

## Where the paths meet. Sitting it between the player's starting spot and the
## buildings means the first thing a child sees is a junction with somewhere to
## go, rather than an empty field.
const PLAZA_CENTRE := Vector2(0.0, 1.5)
const PLAZA_RADIUS := 3.4
const PATH_WIDTH := 2.5

## One seed for everything the village scatters, so the whole place is identical
## every launch (§7.1) and any two parts of it that should agree, do.
const GROUND_SEED := 20260830
const STONE_SPACING := 1.9

const TREE_MODELS: Array[String] = [
	"res://assets/models/environment/tree_leafy.glb",
	"res://assets/models/environment/tree_banana.glb",
]

@onready var _world: Node3D = $World
@onready var _player: HubPlayer = $Player
@onready var _camera: HubCamera = $Camera
@onready var _kanca: MascotCompanion = $Kanca
@onready var _pad: MovementControl = $UI/SafeArea/Screen/Pad
@onready var _gestures: CameraGestures = $UI/SafeArea/Screen/Gestures
@onready var _zoom: ZoomControls = $UI/SafeArea/Screen/Zoom
@onready var _enter_prompt: BigButton = $UI/SafeArea/Screen/EnterPrompt
@onready var _celebration: CelebrationOverlay = $UI/Celebration

var _buildings: Dictionary = {}
var _nearby_game_id: String = ""
var _pending_result: MiniGameResult = null


func _ready() -> void:
	_player.pad = _pad
	_player.camera = _camera
	_player.warp_to(PLAYER_START)
	_camera.target = _player
	_zoom.camera = _camera
	_gestures.camera = _camera
	_kanca.target = _player
	_kanca.position = Vector3(PLAYER_START.x - 1.6, 0.0, PLAYER_START.y + 0.6)

	_enter_prompt.visible = false
	_enter_prompt.pressed.connect(_on_enter_pressed)

	_celebration.dismissed.connect(_on_celebration_dismissed)

	_build_ground()
	_build_boundary()
	_build_stepping_stones()
	_scatter_trees()
	_build_buildings()
	_scatter_undergrowth()
	_build_backdrop()

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
## the colliders, the fence panels and the scatter all have to agree about it and
## a fence you can walk through is what happens when two of them do not.
func fence_line() -> float:
	return HALF_EXTENT - FENCE_INSET


## Where the paths run, as line segments. Derived from hub_position rather than
## written down, so a fourth building gets a path to it for free — and the ground
## and the stepping stones both read this, so they cannot disagree about where
## the path is.
func _path_layout() -> Array:
	var layout: Array = []
	for game_id: String in ContentDB.get_mini_game_ids():
		var config: Dictionary = ContentDB.get_mini_game(game_id)
		var raw: Array = config.get("hub_position", [0.0, 0.0]) as Array
		var building: Vector2 = Vector2(float(raw[0]), float(raw[1]))
		var footprint: Array = config.get("building_size", [6.0, 3.0, 5.0]) as Array

		var towards_plaza: Vector2 = (PLAZA_CENTRE - building).normalized()
		# Stop at the building's front rather than under it, so the path reads as
		# arriving somewhere.
		var arrival: Vector2 = building + towards_plaza * (float(footprint[2]) * 0.5 + 0.3)
		if arrival.distance_to(PLAZA_CENTRE) < 0.5:
			continue
		layout.append({"from": PLAZA_CENTRE, "to": arrival, "width": PATH_WIDTH})
	return layout


func _build_ground() -> void:
	var ground: MeshInstance3D = VillageGround.build(
		HALF_EXTENT, PLAZA_CENTRE, PLAZA_RADIUS, _path_layout(), GROUND_SEED)
	_world.add_child(ground)

	# The visible ground rolls by a tenth of a metre; the one the child walks on
	# does not. Keeping the collider a flat box means no amount of fiddling with
	# the terrain can put a lip under a four-year-old's feet.
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


## Stepping stones along each path.
##
## The paths themselves are painted into the ground now, which makes them soft
## and a little vague — right for a worn track, but §7.1 leans on the paths for
## wayfinding, and a child who cannot read has nothing else telling them where to
## go. The stones put a hard, countable line back on top of the soft one.
func _build_stepping_stones() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = GROUND_SEED + 5

	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []

	for entry: Dictionary in _path_layout():
		var from: Vector2 = entry["from"] as Vector2
		var to: Vector2 = entry["to"] as Vector2
		var run: float = from.distance_to(to)
		var count: int = int(run / STONE_SPACING)
		var along: Vector2 = (to - from).normalized()
		var across: Vector2 = Vector2(-along.y, along.x)

		for index: int in range(1, count):
			var centre: Vector2 = from + along * (float(index) * STONE_SPACING)
			# Off the centre line, alternating, the way stones get placed by
			# someone walking rather than by a surveyor.
			centre += across * rng.randf_range(-0.55, 0.55)
			_add_stone(transforms, colours, centre, rng)

	# A few loose in the plaza. Deliberately not a ring -- evenly spaced stones
	# around a circle read as a fairy ring, which is a thing someone built, not a
	# place that got worn.
	for index: int in range(7):
		var angle: float = rng.randf_range(0.0, TAU)
		var reach: float = sqrt(rng.randf()) * (PLAZA_RADIUS - 0.6)
		_add_stone(transforms, colours, PLAZA_CENTRE + Vector2(cos(angle), sin(angle)) * reach, rng)

	var stones: MultiMeshInstance3D = VillageScatter.instance_model(
		_stone_mesh(), transforms, colours, false)
	if stones != null:
		stones.name = "SteppingStones"
		_world.add_child(stones)


## One flagstone mesh, reused. Five sides, not twenty: these are flagstones, not
## dinner plates, and forty-odd of them were forty-odd draw calls when each
## carried its own mesh and its own material.
func _stone_mesh() -> Mesh:
	var slab: CylinderMesh = CylinderMesh.new()
	slab.top_radius = 0.30
	slab.bottom_radius = 0.28
	slab.height = 0.07
	slab.radial_segments = 5
	slab.rings = 0
	slab.material = _stone_material()
	return slab


func _stone_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Per-instance colour carries the variation now, so the material itself is
	# white and every stone multiplies it down to its own grey.
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _add_stone(transforms: Array[Transform3D], colours: Array[Color], centre: Vector2,
		rng: RandomNumberGenerator) -> void:
	var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
	basis = basis.scaled(Vector3(rng.randf_range(0.78, 1.35), 1.0,
		rng.randf_range(0.70, 1.30)))
	transforms.append(Transform3D(basis, Vector3(centre.x, 0.03, centre.y)))

	# Muted and varied. A bright stone reads as a plate left on the grass.
	var tint: float = rng.randf_range(-0.16, 0.10)
	var base: Color = Palette.STONE.darkened(0.28)
	colours.append(base.lightened(maxf(tint, 0.0)).darkened(maxf(-tint, 0.0)))


## Hills and far trees beyond the boundary.
##
## Nothing here is reachable and nothing collides. It exists because the village
## ends at a hedge, and a hedge with empty sky above it tells a child exactly how
## big the world is. Something behind it -- anything -- turns a boundary into a
## horizon.
##
## Deliberately hazy and low-contrast. These sit behind everything the child can
## actually touch, and if they read as sharply as the Warung does they compete
## with it.
func _build_backdrop() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = GROUND_SEED + 77

	# A close ring of jungle, then hills behind it. Two distances rather than one,
	# because a single band reads as a painted wall.
	#
	# Leafy trees only, and no shadows. A banana palm is six times the triangles
	# of a leafy tree and none of that detail survives being thirty metres away;
	# the shadows fall outside the fence where nobody can see them, and paying for
	# them means drawing the whole backdrop a second time.
	var placements: Array[Array] = []
	for _index: int in range(TREE_MODELS.size()):
		placements.append([] as Array[Transform3D])

	for index: int in range(24):
		var angle: float = TAU * float(index) / 24.0 + rng.randf_range(-0.05, 0.05)
		var reach: float = HALF_EXTENT + rng.randf_range(2.2, 6.0)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(1.15, 1.85))
		(placements[0] as Array[Transform3D]).append(Transform3D(basis,
			Vector3(cos(angle) * reach, -0.4, sin(angle) * reach)))

	_plant(placements, [Palette.HILL_HAZE.lerp(Color.WHITE, 0.45)], false, "FarJungle")

	# Every hill into one mesh. Twenty-six cones is twenty-six draw calls for
	# something the child can never reach and never looks at directly.
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index: int in range(26):
		var angle: float = TAU * float(index) / 26.0 + rng.randf_range(-0.08, 0.08)
		var reach: float = HALF_EXTENT + rng.randf_range(20.0, 44.0)
		var height: float = rng.randf_range(6.0, 17.0)

		# A hill's radius has to stop short of the village, and nothing was
		# checking. At the old numbers a tall one could be 40 metres across and
		# 36 from the centre, which put its near slope *inside* the fence — an
		# unshaded, uncollidable wall of dark green that the child could walk
		# into and appear to sink through.
		var clearance: float = reach - HALF_EXTENT - HILL_CLEARANCE
		var radius: float = minf(rng.randf_range(height * 1.3, height * 2.4), clearance)
		if radius < 3.0:
			continue

		# The further away, the hazier -- one lerp, and it does the whole job of
		# making the distance read as distance.
		var haze: float = clampf((reach - HALF_EXTENT - 20.0) / 24.0, 0.0, 1.0)
		_add_hill(surface, Vector2(cos(angle) * reach, sin(angle) * reach), height,
			radius, Palette.HILL_FAR.lerp(Palette.HILL_HAZE, haze), rng)
	surface.generate_normals()

	var hills: MeshInstance3D = MeshInstance3D.new()
	hills.name = "Hills"
	hills.mesh = surface.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Unshaded: a hill lit by the same sun as the village competes with it, and
	# these are supposed to sit quietly behind everything.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hills.material_override = material
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(hills)


## A faceted cone written into a shared surface. Six or seven sides, so it reads
## as a low-poly hill rather than a smooth heap.
func _add_hill(surface: SurfaceTool, centre: Vector2, height: float, radius: float,
		colour: Color, rng: RandomNumberGenerator) -> void:
	var sides: int = rng.randi_range(6, 8)
	var base: Vector3 = Vector3(centre.x, 0.0, centre.y)
	var peak: Vector3 = base + Vector3(rng.randf_range(-0.2, 0.2) * radius, height,
		rng.randf_range(-0.2, 0.2) * radius)

	var rim: Array[Vector3] = []
	for index: int in range(sides):
		var angle: float = TAU * float(index) / float(sides)
		var wobble: float = rng.randf_range(0.78, 1.22)
		rim.append(base + Vector3(cos(angle) * radius * wobble, -1.5,
			sin(angle) * radius * wobble))

	for index: int in range(sides):
		var a: Vector3 = rim[index]
		var b: Vector3 = rim[(index + 1) % sides]
		# Sunlit faces lighter, shaded faces darker, decided by which way the
		# facet points rather than by the light -- these are unshaded, and too
		# far away for real shading to give them any shape.
		var facing: float = ((a + b) * 0.5 - peak).normalized().dot(Vector3(-0.4, 0.0, -0.9))
		var tint: Color = colour.lightened(clampf(facing, 0.0, 1.0) * 0.16)
		tint = tint.darkened(clampf(-facing, 0.0, 1.0) * 0.14)
		surface.set_color(tint.srgb_to_linear())
		surface.add_vertex(peak)
		surface.add_vertex(a)
		surface.add_vertex(b)


## Bushes, ferns, flowers, grass and stones, plus the bamboo fence.
##
## Runs after the buildings, because it needs to know where they stand: a fern
## growing through the Warung counter is the sort of thing that only shows up in
## a screenshot after the fact.
func _scatter_undergrowth() -> void:
	var blocked: Array = [{"centre": PLAYER_START, "radius": 2.2}]
	for game_id: String in ContentDB.get_mini_game_ids():
		var config: Dictionary = ContentDB.get_mini_game(game_id)
		var raw: Array = config.get("hub_position", [0.0, 0.0]) as Array
		var footprint: Array = config.get("building_size", [6.0, 3.0, 5.0]) as Array
		# Circle round the footprint's longest side. Generous rather than exact —
		# a gap of clear ground round a building reads as a swept yard.
		var reach: float = maxf(float(footprint[0]), float(footprint[2])) * 0.62 + 0.9
		blocked.append({"centre": Vector2(float(raw[0]), float(raw[1])), "radius": reach})

	_world.add_child(VillageScatter.build(HALF_EXTENT, FENCE_INSET,
		PLAZA_CENTRE, PLAZA_RADIUS, _path_layout(), blocked, GROUND_SEED))


## Deterministic scatter — the village looks the same every launch, which matters
## when a child is learning where things are.
func _scatter_trees() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = GROUND_SEED

	# Grouped by model rather than placed one at a time. Fourteen trees is not
	# many, but each carries a trunk and a canopy surface and each was its own
	# node -- and the same loop below plants thirty more in the backdrop.
	var placements: Array[Array] = []
	for _index: int in range(TREE_MODELS.size()):
		placements.append([] as Array[Transform3D])

	for i: int in range(TREE_COUNT):
		var x: float = rng.randf_range(-HALF_EXTENT + 3.0, HALF_EXTENT - 3.0)
		var z: float = rng.randf_range(-HALF_EXTENT + 3.0, HALF_EXTENT - 3.0)
		# Keep the middle clear so trees never sit on top of a building or the
		# path between them.
		if absf(x) < 13.0 and z < -2.0:
			continue
		if Vector2(x, z).distance_to(PLAYER_START) < 5.0:
			continue

		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(0.82, 1.18))
		var slot: int = i % TREE_MODELS.size()
		(placements[slot] as Array[Transform3D]).append(
			Transform3D(basis, Vector3(x, 0.0, z)))

	_plant(placements, [], true, "Trees", true)


## Turns per-model placement lists into MultiMesh nodes, falling back to the
## generated stand-in tree when a model is missing (10.5).
func _plant(placements: Array[Array], colours: Array[Color], casts_shadow: bool,
		group_name: String, solid: bool = false) -> void:
	var group: Node3D = Node3D.new()
	group.name = group_name
	_world.add_child(group)

	for slot: int in range(TREE_MODELS.size()):
		var transforms: Array[Transform3D] = placements[slot] as Array[Transform3D]
		if transforms.is_empty():
			continue

		var mesh: Mesh = ModelKit.load_mesh(TREE_MODELS[slot])
		if mesh != null:
			var tint: Array[Color] = []
			if not colours.is_empty():
				for _index: int in range(transforms.size()):
					tint.append(colours[0])
			var node: MultiMeshInstance3D = VillageScatter.instance_model(
				mesh, transforms, tint, casts_shadow)
			if node != null:
				node.name = "Model%d" % slot
				group.add_child(node)
			if solid:
				_add_trunk_colliders(group, transforms, slot)
			continue

		# No model: the stand-in is a node, so these go back to being one each.
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = GROUND_SEED + slot
		for transform: Transform3D in transforms:
			var tree: Node3D = _build_tree(slot, rng)
			tree.transform = transform
			group.add_child(tree)


## A trunk collider per tree.
##
## MultiMesh draws hundreds of copies from one mesh and carries no collision at
## all — which is why the village's trees could be walked straight through. The
## bodies have to be made separately, one per instance.
##
## Only the trunk, not the canopy. A child brushing past leaves should not be
## stopped by them, and a collider that matches the crown means being blocked by
## something a metre above your head.
func _add_trunk_colliders(group: Node3D, transforms: Array[Transform3D], slot: int) -> void:
	for index: int in range(transforms.size()):
		var transform: Transform3D = transforms[index]
		var scale: float = transform.basis.get_scale().x

		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Trunk%d_%d" % [slot, index]
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = transform.origin

		var shape: CollisionShape3D = CollisionShape3D.new()
		var cylinder: CylinderShape3D = CylinderShape3D.new()
		cylinder.radius = TRUNK_RADIUS * scale
		cylinder.height = TRUNK_HEIGHT * scale
		shape.shape = cylinder
		shape.position.y = cylinder.height * 0.5
		body.add_child(shape)
		group.add_child(body)


## The real tree if one exists, otherwise the old cylinder-and-sphere stand-in.
## Alternates the two types: twelve copies of one tree is what makes a place look
## generated rather than built.
func _build_tree(index: int, rng: RandomNumberGenerator) -> Node3D:
	var path: String = TREE_MODELS[index % TREE_MODELS.size()]
	var instance: Node3D = ModelKit.instantiate(path)
	if instance != null:
		return instance

	var tree: Node3D = Node3D.new()

	var trunk: MeshInstance3D = MeshInstance3D.new()
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 1.5
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 0
	trunk.mesh = trunk_mesh
	trunk.material_override = PlaceholderFactory.get_flat_material(Palette.WOOD)
	trunk.position.y = 0.75
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.add_child(trunk)

	var crown: MeshInstance3D = MeshInstance3D.new()
	var crown_mesh: SphereMesh = SphereMesh.new()
	crown_mesh.radius = 1.05
	crown_mesh.height = 1.9
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 4
	crown.mesh = crown_mesh
	crown.material_override = PlaceholderFactory.get_flat_material(Palette.GRASS_DARK)
	crown.position.y = 2.0
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree.add_child(crown)

	return tree


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
	_celebration.show_result(result)


func _on_celebration_dismissed() -> void:
	_kanca.resume_idle_chatter()
	_point_at_recommendation()
