class_name VillageGround
extends RefCounted

## Builds the village floor as one vertex-coloured mesh (PLAN.md §7.1, §11).
##
## One mesh, not a green box with beige rectangles laid on top of it, and that is
## the whole point. Painting the paths into the ground rather than stacking them
## on it buys three things at once: no z-fighting, no strips left floating when
## the ground stops being flat, and edges that can be ragged instead of ruled.
## A path with a ruled edge reads as a decal; a path that frays into the grass
## reads as somewhere people have walked.
##
## It stays flat where it matters. The undulation is a tenth of a metre — enough
## for the light to find, far too little for a child to notice underfoot — and
## the collision body stays a plain box, so nothing about walking changes.

## Cells across the whole village. At forty metres across this is a corner every
## sixty centimetres, which is what the colour gradient is sampled at — fine
## enough that the lattice never shows, coarse enough to stay inside the triangle
## budget (§4.2) alongside everything standing on it.
const CELLS := 64

const UNDULATION := 0.22
const PATCH_SCALE := 0.16
const GRAIN_SCALE := 0.55
const EDGE_WOBBLE := 0.55

## How far a path frays out into the grass, in metres.
const EDGE_FEATHER := 0.45


## `paths` is an array of {"from": Vector2, "to": Vector2, "width": float}.
static func build(half_extent: float, plaza_centre: Vector2, plaza_radius: float,
		paths: Array, seed_value: int) -> MeshInstance3D:
	var span: float = half_extent * 2.0
	var step: float = span / float(CELLS)

	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for row: int in range(CELLS):
		for column: int in range(CELLS):
			var x0: float = -half_extent + float(column) * step
			var z0: float = -half_extent + float(row) * step
			var corners: Array[Vector2] = [
				Vector2(x0, z0), Vector2(x0 + step, z0),
				Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step),
			]
			# Two triangles, each with its own vertices: shared vertices would be
			# smooth-shaded, and the faceting is the look.
			_add_triangle(surface, corners[0], corners[1], corners[2],
				plaza_centre, plaza_radius, paths, seed_value)
			_add_triangle(surface, corners[0], corners[2], corners[3],
				plaza_centre, plaza_radius, paths, seed_value)

	# Weld first, then average the normals across the welded corners. Both halves
	# are needed: without index() every corner is its own vertex and there is
	# nothing to average, so the surface stays faceted whatever the smooth group
	# says.
	surface.index()
	surface.generate_normals()

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Ground"
	instance.mesh = surface.commit()
	instance.material_override = _ground_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _ground_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


static func _add_triangle(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2,
		plaza_centre: Vector2, plaza_radius: float, paths: Array, seed_value: int) -> void:
	# Colour per corner, so the hardware interpolates between them.
	#
	# The first version of this coloured each triangle as a whole, on the
	# reasoning that the art being chased is faceted. That was the wrong reading:
	# what is faceted in it is the *objects* — the rocks, the plants, the roofs.
	# The ground under them is smooth. A flat colour per triangle turns a meadow
	# into a chessboard, and the grid it is laid out on shows through every one
	# of them.
	for point: Vector2 in [a, b, c]:
		var dirt: float = dirt_at(point, plaza_centre, plaza_radius, paths, seed_value)
		# Vertex colours are used raw as a linear albedo multiplier, while every
		# colour in Palette is sRGB. Handing one to the other unconverted is what
		# turns a meadow into a neon lawn — the same mistake, in the same
		# direction, as feeding sRGB to a glTF baseColorFactor.
		surface.set_color(_colour_at(point, dirt, seed_value).srgb_to_linear())
		var lift: float = _noise(point * PATCH_SCALE, seed_value + 91) * UNDULATION
		surface.add_vertex(Vector3(point.x, lift * (1.0 - dirt), point.y))


## How much of this point is trodden path, 0 to 1. Public because the scatter
## reads it too — undergrowth must not grow in the middle of the road, and the
## only way to be sure it agrees with the painted ground is to ask the same
## function.
static func dirt_at(point: Vector2, plaza_centre: Vector2, plaza_radius: float,
		paths: Array, seed_value: int) -> float:
	# The wobble is what stops every edge being a ruled line. It is added to the
	# *distance*, not the colour, so the path itself changes shape.
	var wobble: float = _noise(point * GRAIN_SCALE, seed_value + 17) * EDGE_WOBBLE

	# A radius of zero means *no plaza*, not a plaza of no size. Without this
	# guard the distance to a zero-radius disc is just the distance to a point,
	# so anywhere near the origin comes out as trodden path — which is how the
	# Kebun, reusing this ground with no plaza at all, grew a patch of bare earth
	# in the middle of its lawn.
	var nearest: float = INF
	if plaza_radius > 0.0:
		nearest = point.distance_to(plaza_centre) - plaza_radius
	for entry: Dictionary in paths:
		var from: Vector2 = entry["from"] as Vector2
		var to: Vector2 = entry["to"] as Vector2
		var half_width: float = float(entry["width"]) * 0.5
		nearest = minf(nearest, _distance_to_segment(point, from, to) - half_width)

	return 1.0 - smoothstep(0.0, EDGE_FEATHER, nearest + wobble)


static func _colour_at(point: Vector2, dirt: float, seed_value: int) -> Color:
	# Three scales, added rather than chosen between.
	#
	# One scale is never enough. A single broad wave gives a field that is lighter
	# over there and darker over here and flat everywhere in between; a single
	# fine one gives speckle. What reads as ground is the sum: a slow drift for
	# the lie of the land, a middle wave for where the grass grows thicker, and a
	# small one so no two square metres match.
	#
	# All three are far coarser than the mesh, which is the point — the colour
	# has to change slowly enough that the lattice it is sampled on never shows.
	var drift: float = _noise(point * PATCH_SCALE, seed_value)
	var swell: float = _noise(point * PATCH_SCALE * 2.7, seed_value + 4)
	var grain: float = _noise(point * GRAIN_SCALE, seed_value + 11)
	var mixed: float = drift * 0.62 + swell * 0.28 + grain * 0.16

	var grass: Color = Palette.MEADOW
	if mixed > 0.0:
		grass = Palette.MEADOW.lerp(Palette.MEADOW_LIGHT, minf(mixed * 1.55, 1.0))
	else:
		grass = Palette.MEADOW.lerp(Palette.MEADOW_DARK, minf(-mixed * 1.45, 1.0))

	# Dry patches, sparse and warm, where the sun has got at the grass. Keyed off
	# a different octave so they do not simply follow the light areas.
	grass = grass.lerp(Palette.MEADOW_DRY, clampf((swell - 0.25) * 0.85, 0.0, 0.30))

	var earth: Color = Palette.DIRT.lerp(Palette.DIRT_DARK,
		clampf(grain * 0.75 + 0.4, 0.0, 1.0))
	earth = earth.lerp(Palette.DIRT.lightened(0.12), clampf(drift * 0.9, 0.0, 0.4))

	# A darker rim where earth meets grass. Trodden edges are always the darkest
	# part of a path, and without it the two colours just fade into each other and
	# the path loses its shape.
	var blended: Color = grass.lerp(earth, dirt)
	var rim: float = 1.0 - absf(dirt - 0.5) * 2.0
	return blended.lerp(blended.darkened(0.20), rim * 0.45)


static func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var axis: Vector2 = to - from
	var length_squared: float = axis.length_squared()
	if length_squared < 1e-6:
		return point.distance_to(from)
	var t: float = clampf((point - from).dot(axis) / length_squared, 0.0, 1.0)
	return point.distance_to(from + axis * t)


## Value noise in [-1, 1]. Deterministic from the seed, because §7.1 wants the
## village identical every launch — a child is learning where things are, and a
## field that reshapes itself overnight undoes that.
static func _noise(point: Vector2, seed_value: int) -> float:
	var x0: int = int(floorf(point.x))
	var y0: int = int(floorf(point.y))
	var fx: float = point.x - float(x0)
	var fy: float = point.y - float(y0)
	# Smoothstep the interpolation, or the lattice shows up as a grid.
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)

	var top: float = lerpf(_lattice(x0, y0, seed_value), _lattice(x0 + 1, y0, seed_value), fx)
	var bottom: float = lerpf(_lattice(x0, y0 + 1, seed_value),
		_lattice(x0 + 1, y0 + 1, seed_value), fx)
	return lerpf(top, bottom, fy)


static func _lattice(x: int, y: int, seed_value: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + seed_value * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 32767.5 - 1.0
