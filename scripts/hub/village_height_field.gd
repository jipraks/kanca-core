class_name VillageHeightField
extends RefCounted

## Where the surface of a mesh is, asked by world position.
##
## The procedural village could answer this from the noise function that drew it
## (`VillageGround.Sampler`). The village is a supplied mesh now, and the only
## thing that knows where its ground is, is the mesh — but asking it per query
## means a ray per plant per frame, and the physics server is not even up when
## the hub scatters.
##
## So the mesh is rasterised once into a grid of the highest surface over each
## cell, which is a heightmap in everything but name. That is exactly the right
## shape for what needs it: the scatter has to know whether a spot is open lawn
## or the roof of a market stall, and the answer is the same every frame.
##
## Highest, not lowest, because the mesh has a base plate under it and a lawn on
## top, and every query here means "what would something standing here rest on".

## Cells across the village. 128 over thirty metres is a corner every 23cm —
## finer than anything scattered on it is wide, and 16k floats to hold.
const CELLS := 128

var _low: Vector2 = Vector2.ZERO
var _span: Vector2 = Vector2.ONE
var _heights: PackedFloat32Array = PackedFloat32Array()
var _floor: float = 0.0


## `mesh` is read once. Nothing keeps a reference to it afterwards.
func _init(mesh: Mesh, surface: int = 0) -> void:
	if mesh == null or mesh.get_surface_count() <= surface:
		return
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty():
		return

	var aabb: AABB = mesh.get_aabb()
	_low = Vector2(aabb.position.x, aabb.position.z)
	_span = Vector2(maxf(aabb.size.x, 0.001), maxf(aabb.size.z, 0.001))
	_floor = aabb.position.y

	_heights.resize(CELLS * CELLS)
	_heights.fill(_floor)

	var triangles: int = (indices.size() if not indices.is_empty() else vertices.size()) / 3
	for triangle: int in triangles:
		var a: Vector3
		var b: Vector3
		var c: Vector3
		if indices.is_empty():
			a = vertices[triangle * 3]
			b = vertices[triangle * 3 + 1]
			c = vertices[triangle * 3 + 2]
		else:
			a = vertices[indices[triangle * 3]]
			b = vertices[indices[triangle * 3 + 1]]
			c = vertices[indices[triangle * 3 + 2]]
		_rasterise(a, b, c)


## Height of the surface at a world XZ point, in metres.
func height_at(point: Vector2) -> float:
	if _heights.is_empty():
		return 0.0
	var cell: Vector2 = (point - _low) / _span * float(CELLS)
	var x: int = clampi(int(cell.x), 0, CELLS - 1)
	var y: int = clampi(int(cell.y), 0, CELLS - 1)
	return _heights[y * CELLS + x]


func is_ready() -> bool:
	return not _heights.is_empty()


## Fills every cell whose centre falls inside the triangle, keeping the highest
## answer. Nothing clever and nothing conservative: a triangle smaller than a
## cell can be missed entirely, which is correct here — a leaf that covers a
## fifth of a cell is not something anybody stands on.
func _rasterise(a: Vector3, b: Vector3, c: Vector3) -> void:
	var scale: Vector2 = Vector2(float(CELLS), float(CELLS)) / _span
	var pa: Vector2 = (Vector2(a.x, a.z) - _low) * scale
	var pb: Vector2 = (Vector2(b.x, b.z) - _low) * scale
	var pc: Vector2 = (Vector2(c.x, c.z) - _low) * scale

	var from_x: int = clampi(int(floor(minf(pa.x, minf(pb.x, pc.x)))), 0, CELLS - 1)
	var to_x: int = clampi(int(ceil(maxf(pa.x, maxf(pb.x, pc.x)))), 0, CELLS - 1)
	var from_y: int = clampi(int(floor(minf(pa.y, minf(pb.y, pc.y)))), 0, CELLS - 1)
	var to_y: int = clampi(int(ceil(maxf(pa.y, maxf(pb.y, pc.y)))), 0, CELLS - 1)

	var area: float = (pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)
	if absf(area) < 1e-9:
		return

	for y: int in range(from_y, to_y + 1):
		for x: int in range(from_x, to_x + 1):
			var point: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			# Barycentric, which doubles as the inside test and as the weights
			# for the height — one calculation rather than two.
			var u: float = ((pb.x - point.x) * (pc.y - point.y)
				- (pc.x - point.x) * (pb.y - point.y)) / area
			var v: float = ((pc.x - point.x) * (pa.y - point.y)
				- (pa.x - point.x) * (pc.y - point.y)) / area
			var w: float = 1.0 - u - v
			if u < 0.0 or v < 0.0 or w < 0.0:
				continue
			var height: float = a.y * u + b.y * v + c.y * w
			var index: int = y * CELLS + x
			if height > _heights[index]:
				_heights[index] = height
