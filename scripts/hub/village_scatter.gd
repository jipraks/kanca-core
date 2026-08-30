class_name VillageScatter
extends RefCounted

## Fills the village floor with undergrowth (PLAN.md §7.1, §11).
##
## Nothing here is worth looking at on its own, and that is what it is for. A
## green field with three good buildings on it still reads as a green field; what
## makes somewhere look like a place is a few hundred bushes, ferns and stones
## nobody ever looks at directly.
##
## Every type is drawn as one MultiMeshInstance3D, so a hundred and forty tufts
## of grass cost one draw call rather than a hundred and forty. On the
## Compatibility renderer that difference matters far more than the triangles do.
##
## Placement is deterministic from a seed, because §7.1 wants the village
## identical every launch — a child learning where things are should not find the
## bushes rearranged overnight.

const MODEL_DIR := "res://assets/models/environment/"

## Each entry: how many, how big, and how far from a path it has to stay.
## Grass dominates by an order of magnitude — it is the cheapest model here and
## the one that does the most, because it is what covers the seams.
const KINDS: Array[Dictionary] = [
	{"id": "grass_tuft", "count": 145, "scale": Vector2(1.05, 1.85), "clearance": 0.35,
		"near_edge": 0.0},
	{"id": "bush", "count": 40, "scale": Vector2(0.75, 1.45), "clearance": 1.1,
		"near_edge": 0.55},
	{"id": "fern", "count": 24, "scale": Vector2(0.65, 1.15), "clearance": 1.0,
		"near_edge": 0.65},
	{"id": "flower_red", "count": 18, "scale": Vector2(0.85, 1.35), "clearance": 0.7,
		"near_edge": 0.0},
	{"id": "flower_purple", "count": 17, "scale": Vector2(0.85, 1.35), "clearance": 0.7,
		"near_edge": 0.0},
	{"id": "rock", "count": 22, "scale": Vector2(0.55, 1.20), "clearance": 0.6,
		"near_edge": 0.0},
]

const FENCE_MODEL := MODEL_DIR + "bamboo_fence.glb"
const FENCE_PANEL := 3.3


## `blocked` is an array of {"centre": Vector2, "radius": float} the scatter must
## keep out of — buildings, and wherever the child starts.
static func build(half_extent: float, fence_inset: float, plaza_centre: Vector2,
		plaza_radius: float, paths: Array, blocked: Array, seed_value: int) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Scatter"

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	for kind: Dictionary in KINDS:
		# A separate stream per type, so changing how many ferns there are does
		# not reshuffle every bush in the village.
		rng.seed = seed_value + hash(kind["id"])
		var transforms: Array[Transform3D] = _place(
			kind, half_extent, plaza_centre, plaza_radius, paths, blocked, rng, seed_value)
		var node: MultiMeshInstance3D = _multi_mesh(
			MODEL_DIR + "%s.glb" % kind["id"], transforms)
		if node != null:
			node.name = String(kind["id"]).capitalize()
			root.add_child(node)

	var fence: MultiMeshInstance3D = _multi_mesh(FENCE_MODEL,
		_fence_ring(half_extent - fence_inset))
	if fence != null:
		fence.name = "Fence"
		root.add_child(fence)

	return root


static func _place(kind: Dictionary, half_extent: float, plaza_centre: Vector2,
		plaza_radius: float, paths: Array, blocked: Array,
		rng: RandomNumberGenerator, seed_value: int) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var wanted: int = int(kind["count"])
	var clearance: float = float(kind["clearance"])
	var near_edge: float = float(kind["near_edge"])
	var scale_range: Vector2 = kind["scale"] as Vector2

	# Rejection sampling with a hard ceiling. A plant that cannot find anywhere
	# legal is dropped rather than forced somewhere wrong — a fern in the middle
	# of the path is worse than one fern fewer.
	var attempts: int = 0
	var limit: int = wanted * 24
	while transforms.size() < wanted and attempts < limit:
		attempts += 1
		var reach: float = half_extent - 1.2
		var point: Vector2 = Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))

		# Some things belong at the edges. Biasing outward is what gives the
		# village a thick, overgrown boundary and an open middle to walk in,
		# instead of an even sprinkle that reads as wallpaper.
		if near_edge > 0.0:
			var pull: float = maxf(absf(point.x), absf(point.y)) / reach
			if rng.randf() > lerpf(1.0 - near_edge, 1.0, pull):
				continue

		if VillageGround.dirt_at(point, plaza_centre, plaza_radius, paths, seed_value) > 0.08:
			continue
		if _distance_to_path(point, plaza_centre, plaza_radius, paths) < clearance:
			continue

		var rejected: bool = false
		for area: Dictionary in blocked:
			if point.distance_to(area["centre"] as Vector2) < float(area["radius"]):
				rejected = true
				break
		if rejected:
			continue

		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y))
		transforms.append(Transform3D(basis, Vector3(point.x, 0.0, point.y)))

	return transforms


## Panels end to end round the boundary, on the line the colliders use.
##
## `inset` comes from Hub.fence_line(), not from a number chosen here. The panels
## and the thing that stops the child have to be in the same place, and the
## surest way to get that is for neither to own the figure.
static func _fence_ring(inset: float) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var per_side: int = int(ceilf(inset * 2.0 / FENCE_PANEL))
	var step: float = inset * 2.0 / float(per_side)

	# The panel is built lying along X, so a run down the Z edges is turned a
	# quarter turn. Corners overlap by half a post, which is what a real fence
	# does and what stops a gap of daylight at each corner.
	for side: int in range(4):
		var turn: float = TAU * 0.25 * float(side)
		for index: int in range(per_side):
			var along: float = -inset + step * (float(index) + 0.5)
			var local: Vector2 = Vector2(along, -inset)
			var placed: Vector2 = local.rotated(turn)
			transforms.append(Transform3D(Basis(Vector3.UP, -turn),
				Vector3(placed.x, 0.0, placed.y)))

	return transforms


## Pulls the mesh out of a .glb and hands it to a MultiMesh.
##
## Returns null when the model is missing, and the caller simply gets no
## undergrowth of that kind — the same failure mode as every other asset here
## (§10.5). A village with no ferns still works; a village that will not load
## does not.
static func _multi_mesh(model_path: String, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	# Undergrowth casting shadows costs a second pass over every instance and
	# buys almost nothing at this size — the shadow lands under the plant.
	return instance_model(ModelKit.load_mesh(model_path), transforms, [], false)


## One MultiMeshInstance3D from a mesh and a list of placements.
##
## Public because the village needs this for more than undergrowth. Every tree,
## every stepping stone and every backdrop palm was its own node once, and the
## village measured 355 draw calls against a budget of 100 — not because any of
## them was expensive, but because there were three hundred of them.
##
## `colours` may be empty, or one entry per transform. Per-instance colour is how
## the backdrop gets hazed without giving every distant tree its own material.
static func instance_model(mesh: Mesh, transforms: Array[Transform3D],
		colours: Array[Color], casts_shadow: bool) -> MultiMeshInstance3D:
	if mesh == null or transforms.is_empty():
		return null

	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colours.is_empty()
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multi.set_instance_transform(index, transforms[index])
		if not colours.is_empty():
			# Instance colour multiplies the baked vertex gradient rather than
			# replacing it, so a hazed tree keeps its own light and shade.
			multi.set_instance_color(index, colours[index].srgb_to_linear())

	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = multi
	node.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	return node


static func _distance_to_path(point: Vector2, plaza_centre: Vector2, plaza_radius: float,
		paths: Array) -> float:
	# Zero radius means no plaza — the same trap the ground had. Left as it was,
	# every plant near the origin is rejected for standing too close to a plaza
	# that does not exist.
	var nearest: float = INF
	if plaza_radius > 0.0:
		nearest = point.distance_to(plaza_centre) - plaza_radius
	for entry: Dictionary in paths:
		var from: Vector2 = entry["from"] as Vector2
		var to: Vector2 = entry["to"] as Vector2
		var axis: Vector2 = to - from
		var length_squared: float = axis.length_squared()
		var t: float = 0.0
		if length_squared > 1e-6:
			t = clampf((point - from).dot(axis) / length_squared, 0.0, 1.0)
		nearest = minf(nearest, point.distance_to(from + axis * t) - float(entry["width"]) * 0.5)
	return nearest
