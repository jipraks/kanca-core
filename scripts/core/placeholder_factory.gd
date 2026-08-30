class_name PlaceholderFactory
extends RefCounted

## Builds stand-in art so that development is never blocked on assets that do not
## exist yet (PLAN.md §10.5, §11.1).
##
## Every accessor checks for the real asset first. The moment a `.glb` or `.png`
## appears at the path named in data/items.json it is used instead, with no code
## change anywhere. That is the whole point: the asset track and the engineering
## track never have to wait for each other.
##
## Placeholders look deliberately provisional. They must never ship, and they must
## never be allowed to shape a design decision.

## How big an item is in the world. 1 world unit = 1 metre (§11).
##
## Larger than life on purpose. At the Warung camera a true-to-life 0.22m banana
## lands at about 55px, which is too small for a four-year-old to match against
## an order card. This still sits well inside the 0.5m shelf touch box, so §3.3
## is unaffected. Kept in step with ITEM_LONGEST_SIDE in tools/blender/build_items.py.
const ITEM_SIZE := 0.32

## Flat art reads smaller than a solid of the same nominal size, because it has no
## shaded sides to give it bulk. Cosmetic tuning, worth a second look on a device.
const SPRITE_SIZE_BOOST := 1.35

enum Shape { BOX, SPHERE, CYLINDER, CAPSULE, PRISM }

static var _material_cache: Dictionary = {}
static var _icon_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


# ---------------------------------------------------------------- 3D

## Visual for one shop/garden/kitchen item, in three tiers:
##
##   1. the real `.glb` named in data/items.json, if it exists
##   2. otherwise a billboarded sprite of the item's 2D icon, if that exists
##   3. otherwise a coloured primitive
##
## The middle tier exists because 2D art usually arrives long before 3D art does,
## and a picture of a banana is a far better stand-in than an anonymous yellow
## box. It is also a real answer in its own right: every camera in this game is
## fixed and the child never controls one (§7.1), which is exactly the condition
## under which a billboard reads as an object rather than as a card being swung
## around. Whether it stays as the shipped look is an art direction call — but
## nothing has to be decided to benefit from it, and a `.glb` always wins.
static func build_item_visual(item_id: String) -> Node3D:
	var item: Dictionary = ContentDB.get_item(item_id)

	var model_path: String = String(item.get("model", ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed != null:
			var instance: Node3D = packed.instantiate() as Node3D
			if instance != null:
				return instance
		Log.w("Model at %s could not be instantiated, falling back" % model_path, "PlaceholderFactory")

	# Deliberately checks the icon path rather than calling build_item_icon(),
	# which would hand back a generated swatch and turn every item into a flat
	# coloured square — worse than the primitive it would be replacing.
	var icon_path: String = String(item.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var texture: Texture2D = load(icon_path) as Texture2D
		if texture != null:
			return build_sprite_visual(texture, ITEM_SIZE)
		Log.w("Icon at %s did not load as a texture, falling back" % icon_path, "PlaceholderFactory")

	return build_primitive(item_id, Palette.for_key(item_id), ITEM_SIZE)


## A billboarded sprite standing on the ground, sized so its longest side is
## roughly `target_size` across.
static func build_sprite_visual(texture: Texture2D, target_size: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "SpriteVisual"

	var sprite: Sprite3D = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false

	# Alpha blending sorts by object centre, so two items overlapping on a tray
	# would flicker in front of each other. Discarding writes real depth per
	# pixel, and they stack correctly.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var longest: float = float(maxi(texture.get_width(), texture.get_height()))
	if longest <= 0.0:
		longest = 1.0
	sprite.pixel_size = target_size * SPRITE_SIZE_BOOST / longest

	# Sprite3D draws centred on its origin, so lifting it by half its height puts
	# its feet on the ground — matching where build_primitive puts a solid.
	sprite.position.y = float(texture.get_height()) * sprite.pixel_size * 0.5
	holder.add_child(sprite)

	return holder


## A coloured primitive whose shape is derived from the key, so two items are
## distinguishable by silhouette and not by colour alone.
static func build_primitive(key: String, colour: Color, size: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "Placeholder"

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = _mesh_for(key, size)
	mesh_instance.material_override = get_flat_material(colour)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position.y = size * 0.5
	holder.add_child(mesh_instance)

	return holder


## A stand-in humanoid: body capsule plus head sphere. Used for the player avatar,
## for customers, and for Kanca until the commissioned model arrives (§11.1, §16.2).
static func build_character(key: String, colour: Color, height: float = 1.2) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "PlaceholderCharacter"

	var body_height: float = height * 0.62
	var head_radius: float = height * 0.19

	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = height * 0.17
	capsule.height = maxf(body_height, capsule.radius * 2.0 + 0.01)
	capsule.radial_segments = 10
	capsule.rings = 3
	body.mesh = capsule
	body.material_override = get_flat_material(colour)
	body.position.y = body_height * 0.5
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(body)

	var head: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = head_radius
	sphere.height = head_radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	head.mesh = sphere
	head.material_override = get_flat_material(colour.lightened(0.25))
	head.position.y = body_height + head_radius * 0.7
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(head)

	# A small nose marker so the facing direction is readable while there is no
	# real model. Removed with the rest of the placeholder.
	var nose: MeshInstance3D = MeshInstance3D.new()
	var nose_mesh: BoxMesh = BoxMesh.new()
	nose_mesh.size = Vector3(head_radius * 0.3, head_radius * 0.3, head_radius * 0.5)
	nose.mesh = nose_mesh
	nose.material_override = get_flat_material(Palette.UI_TEXT)
	nose.position = Vector3(0.0, body_height + head_radius * 0.7, -head_radius * 0.9)
	nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(nose)

	Log.d("Placeholder character built for: %s" % key, "PlaceholderFactory")
	return holder


## Flat-shaded material, cached per colour so a shelf of 15 items does not blow the
## 25-materials-per-scene budget in PLAN.md §4.2.
static func get_flat_material(colour: Color) -> StandardMaterial3D:
	var cache_key: String = colour.to_html(false)
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_material_cache[cache_key] = material
	return material


## Unshaded material for highlight shells and prompt markers, which must read the
## same regardless of where the light is.
static func get_unshaded_material(colour: Color, transparent: bool = false) -> StandardMaterial3D:
	var cache_key: String = "unshaded_%s_%s" % [colour.to_html(true), transparent]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_cache[cache_key] = material
	return material


static func _mesh_for(key: String, size: float) -> Mesh:
	var shape: int = absi(hash(key + "shape")) % Shape.size()
	var cache_key: String = "%d_%0.3f" % [shape, size]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key] as Mesh

	var mesh: Mesh = null
	match shape:
		Shape.SPHERE:
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = size * 0.5
			sphere.height = size
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
		Shape.CYLINDER:
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = size * 0.42
			cylinder.bottom_radius = size * 0.42
			cylinder.height = size
			cylinder.radial_segments = 10
			cylinder.rings = 0
			mesh = cylinder
		Shape.CAPSULE:
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = size * 0.34
			capsule.height = size
			capsule.radial_segments = 10
			capsule.rings = 3
			mesh = capsule
		Shape.PRISM:
			var prism: PrismMesh = PrismMesh.new()
			prism.size = Vector3(size, size, size * 0.8)
			mesh = prism
		_:
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(size, size, size)
			mesh = box

	_mesh_cache[cache_key] = mesh
	return mesh


# ---------------------------------------------------------------- 2D icons

## Icon for an item. Returns the real texture when data/items.json names one that
## exists on disk, otherwise a generated swatch.
static func build_item_icon(item_id: String, size: int = 128) -> Texture2D:
	var item: Dictionary = ContentDB.get_item(item_id)
	var icon_path: String = String(item.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var texture: Texture2D = load(icon_path) as Texture2D
		if texture != null:
			return texture

	return build_swatch_icon(item_id, Palette.for_key(item_id), size)


## A rounded square in the key's colour with a distinguishing glyph. Deliberately
## crude so nobody mistakes it for finished art.
static func build_swatch_icon(key: String, colour: Color, size: int = 128) -> Texture2D:
	var cache_key: String = "%s_%d" % [key, size]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key] as Texture2D

	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var radius: float = float(size) * 0.22
	_fill_rounded_rect(image, Rect2(0, 0, size, size), radius, colour)

	var glyph_colour: Color = colour.darkened(0.4)
	var glyph: int = absi(hash(key + "glyph")) % 3
	var centre: Vector2 = Vector2(size, size) * 0.5
	var glyph_size: float = float(size) * 0.26
	match glyph:
		0:
			_fill_circle(image, centre, glyph_size, glyph_colour)
		1:
			_fill_rounded_rect(image, Rect2(centre - Vector2(glyph_size, glyph_size), Vector2(glyph_size, glyph_size) * 2.0), glyph_size * 0.25, glyph_colour)
		_:
			_fill_triangle(image, centre, glyph_size, glyph_colour)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	return texture


## Arrow pointing along `direction`, for the hub's directional pad (§3.3).
static func build_arrow_icon(direction: Vector2, colour: Color, size: int = 96) -> Texture2D:
	var facing: Vector2 = direction.normalized()
	var cache_key: String = "arrow_%0.2f_%0.2f_%s_%d" % [facing.x, facing.y, colour.to_html(false), size]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key] as Texture2D

	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var centre: Vector2 = Vector2(size, size) * 0.5
	var reach: float = float(size) * 0.38
	var perpendicular: Vector2 = Vector2(-facing.y, facing.x)
	var tip: Vector2 = centre + facing * reach
	var base_a: Vector2 = centre - facing * reach * 0.55 + perpendicular * reach * 0.9
	var base_b: Vector2 = centre - facing * reach * 0.55 - perpendicular * reach * 0.9

	_fill_triangle_points(image, tip, base_a, base_b, colour)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	return texture


## Flat circle used for the counting dots on the order card, where the dot is the
## carrier of meaning and the numeral beside it is only a reading aid (§3.1).
static func build_dot_icon(colour: Color, size: int = 48) -> Texture2D:
	var cache_key: String = "dot_%s_%d" % [colour.to_html(false), size]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key] as Texture2D

	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_fill_circle(image, Vector2(size, size) * 0.5, float(size) * 0.44, colour)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	return texture


## Simple pictograms for UI that has no art yet: check, home, star, coin, play,
## sleep, construction. Every one has to be readable at 48px, because that is the
## size a child sees on a phone (§11.1).
static func build_glyph_icon(glyph: String, colour: Color, size: int = 96) -> Texture2D:
	var cache_key: String = "glyph_%s_%s_%d" % [glyph, colour.to_html(false), size]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key] as Texture2D

	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var unit: float = float(size)
	var centre: Vector2 = Vector2(unit, unit) * 0.5
	var thickness: float = unit * 0.12

	match glyph:
		"check":
			_fill_line(image, Vector2(unit * 0.24, unit * 0.52), Vector2(unit * 0.44, unit * 0.72), thickness, colour)
			_fill_line(image, Vector2(unit * 0.44, unit * 0.72), Vector2(unit * 0.78, unit * 0.30), thickness, colour)
		"home":
			_fill_triangle_points(image,
				Vector2(unit * 0.5, unit * 0.16),
				Vector2(unit * 0.14, unit * 0.50),
				Vector2(unit * 0.86, unit * 0.50), colour)
			_fill_rounded_rect(image, Rect2(unit * 0.26, unit * 0.46, unit * 0.48, unit * 0.38), unit * 0.05, colour)
		"star":
			_fill_polygon(image, _star_points(centre, unit * 0.42, unit * 0.18, 5), colour)
		"coin":
			_fill_circle(image, centre, unit * 0.40, colour)
			_fill_circle(image, centre, unit * 0.29, colour.darkened(0.18))
		"play":
			_fill_triangle_points(image,
				Vector2(unit * 0.76, unit * 0.5),
				Vector2(unit * 0.30, unit * 0.20),
				Vector2(unit * 0.30, unit * 0.80), colour)
		"sleep":
			# Three rising dots stand in for Zzz, which would need a font and a
			# child cannot read letters anyway (§3.1).
			_fill_circle(image, Vector2(unit * 0.30, unit * 0.70), unit * 0.08, colour)
			_fill_circle(image, Vector2(unit * 0.50, unit * 0.52), unit * 0.11, colour)
			_fill_circle(image, Vector2(unit * 0.72, unit * 0.32), unit * 0.14, colour)
		"construction":
			# Stacked blocks, not crossed lines. The crossed version was an ✕,
			# which is the universal mark for "wrong" — on a building a child
			# cannot enter yet, that is a rebuke. §7.2 refuses a padlock for
			# exactly this reason and an ✕ is worse than a padlock. Blocks say
			# "still being built", and a three-year-old already knows blocks.
			var block: float = unit * 0.21
			var gap: float = unit * 0.035
			for row: int in range(3):
				var count: int = 3 - row
				var span: float = float(count) * block + float(count - 1) * gap
				var y: float = unit * 0.72 - float(row) * (block + gap)
				for column: int in range(count):
					var x: float = centre.x - span * 0.5 + float(column) * (block + gap)
					_fill_rounded_rect(image, Rect2(Vector2(x, y - block),
						Vector2(block, block)), block * 0.22, colour)
		_:
			Log.w("Unknown glyph: %s" % glyph, "PlaceholderFactory")
			_fill_circle(image, centre, unit * 0.34, colour)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	return texture


static func _star_points(centre: Vector2, outer: float, inner: float, points: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var step: float = PI / float(points)
	for i: int in range(points * 2):
		var radius: float = outer if i % 2 == 0 else inner
		var angle: float = -PI * 0.5 + step * float(i)
		result.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return result


static func _fill_polygon(image: Image, points: PackedVector2Array, colour: Color) -> void:
	if points.size() < 3:
		return
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point: Vector2 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)

	var x0: int = int(maxf(min_point.x, 0.0))
	var y0: int = int(maxf(min_point.y, 0.0))
	var x1: int = int(minf(max_point.x + 1.0, float(image.get_width())))
	var y1: int = int(minf(max_point.y + 1.0, float(image.get_height())))

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			if Geometry2D.is_point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), points):
				image.set_pixel(x, y, colour)


static func _fill_line(image: Image, from: Vector2, to: Vector2, thickness: float, colour: Color) -> void:
	var radius: float = thickness * 0.5
	var min_point: Vector2 = from.min(to) - Vector2(radius, radius)
	var max_point: Vector2 = from.max(to) + Vector2(radius, radius)

	var x0: int = int(maxf(min_point.x, 0.0))
	var y0: int = int(maxf(min_point.y, 0.0))
	var x1: int = int(minf(max_point.x + 1.0, float(image.get_width())))
	var y1: int = int(minf(max_point.y + 1.0, float(image.get_height())))

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			if Geometry2D.get_closest_point_to_segment(p, from, to).distance_to(p) <= radius:
				image.set_pixel(x, y, colour)


## Hollow circle, for the joystick base. A ring reads as "a place to put your
## thumb"; a filled disc reads as a button to press.
static func build_ring_icon(colour: Color, size: int = 256, thickness: float = 0.25) -> Texture2D:
	var cache_key: String = "ring_%s_%d_%0.2f" % [colour.to_html(true), size, thickness]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key] as Texture2D

	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var centre: Vector2 = Vector2(size, size) * 0.5
	var outer: float = float(size) * 0.48
	var inner: float = outer * (1.0 - clampf(thickness, 0.05, 0.95))

	for y: int in range(size):
		for x: int in range(size):
			var distance: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre)
			if distance <= outer and distance >= inner:
				image.set_pixel(x, y, colour)
			elif distance < inner:
				# Faint fill inside the ring, so the pad still reads as one target.
				image.set_pixel(x, y, Color(colour, colour.a * 0.32))

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	return texture


## Magnifier with a plus or a minus, for the village zoom buttons.
##
## §3.1 forbids UI that needs *text* to be understood, and a plus is a symbol
## rather than a word — but a three-year-old does not arrive knowing it either.
## What carries the meaning here is the immediate result: one press and the
## village visibly grows or shrinks, which teaches the button in a way no icon
## can. The lens is drawn thick and the bar oversized so both still read at 48px
## (§11.1). Worth putting in front of children before it is called settled.
static func build_zoom_icon(zoom_in: bool, colour: Color, size: int = 96) -> Texture2D:
	var cache_key: String = "zoom_%s_%s_%d" % [
		"in" if zoom_in else "out", colour.to_html(false), size]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key] as Texture2D

	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var unit: float = float(size)
	# The lens sits up and left to leave room for the handle running down-right.
	var centre: Vector2 = Vector2(unit * 0.44, unit * 0.42)
	var outer: float = unit * 0.30
	var inner: float = outer - unit * 0.075

	for y: int in range(size):
		for x: int in range(size):
			var distance: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre)
			if distance <= outer and distance >= inner:
				image.set_pixel(x, y, colour)

	var handle_start: Vector2 = centre + Vector2(1.0, 1.0).normalized() * (outer - unit * 0.02)
	var handle_end: Vector2 = centre + Vector2(1.0, 1.0).normalized() * (outer + unit * 0.20)
	_fill_thick_line(image, handle_start, handle_end, unit * 0.075, colour)

	var bar: float = inner * 0.62
	_fill_thick_line(image, centre - Vector2(bar, 0.0), centre + Vector2(bar, 0.0),
		unit * 0.055, colour)
	if zoom_in:
		_fill_thick_line(image, centre - Vector2(0.0, bar), centre + Vector2(0.0, bar),
			unit * 0.055, colour)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_icon_cache[cache_key] = texture
	return texture


## A line with rounded ends, drawn as the set of pixels within `radius` of the
## segment. Rounded because a square-ended stroke looks broken where the
## magnifier's handle meets its lens.
static func _fill_thick_line(image: Image, from: Vector2, to: Vector2, radius: float,
		colour: Color) -> void:
	var axis: Vector2 = to - from
	var length_squared: float = axis.length_squared()
	var x0: int = int(maxf(minf(from.x, to.x) - radius, 0.0))
	var y0: int = int(maxf(minf(from.y, to.y) - radius, 0.0))
	var x1: int = int(minf(maxf(from.x, to.x) + radius + 1.0, float(image.get_width())))
	var y1: int = int(minf(maxf(from.y, to.y) + radius + 1.0, float(image.get_height())))

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			var point: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var t: float = 0.0
			if length_squared > 1e-6:
				t = clampf((point - from).dot(axis) / length_squared, 0.0, 1.0)
			if point.distance_to(from + axis * t) <= radius:
				image.set_pixel(x, y, colour)


static func _fill_rounded_rect(image: Image, rect: Rect2, radius: float, colour: Color) -> void:
	var x0: int = int(maxf(rect.position.x, 0.0))
	var y0: int = int(maxf(rect.position.y, 0.0))
	var x1: int = int(minf(rect.position.x + rect.size.x, float(image.get_width())))
	var y1: int = int(minf(rect.position.y + rect.size.y, float(image.get_height())))
	var inner_min: Vector2 = rect.position + Vector2(radius, radius)
	var inner_max: Vector2 = rect.position + rect.size - Vector2(radius, radius)

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var nearest: Vector2 = Vector2(clampf(p.x, inner_min.x, inner_max.x), clampf(p.y, inner_min.y, inner_max.y))
			if p.distance_to(nearest) <= radius:
				image.set_pixel(x, y, colour)


static func _fill_circle(image: Image, centre: Vector2, radius: float, colour: Color) -> void:
	var x0: int = int(maxf(centre.x - radius, 0.0))
	var y0: int = int(maxf(centre.y - radius, 0.0))
	var x1: int = int(minf(centre.x + radius + 1.0, float(image.get_width())))
	var y1: int = int(minf(centre.y + radius + 1.0, float(image.get_height())))

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre) <= radius:
				image.set_pixel(x, y, colour)


static func _fill_triangle(image: Image, centre: Vector2, size: float, colour: Color) -> void:
	_fill_triangle_points(
		image,
		centre + Vector2(0.0, -size),
		centre + Vector2(-size, size * 0.8),
		centre + Vector2(size, size * 0.8),
		colour)


static func _fill_triangle_points(image: Image, a: Vector2, b: Vector2, c: Vector2, colour: Color) -> void:
	var x0: int = int(maxf(minf(a.x, minf(b.x, c.x)), 0.0))
	var y0: int = int(maxf(minf(a.y, minf(b.y, c.y)), 0.0))
	var x1: int = int(minf(maxf(a.x, maxf(b.x, c.x)) + 1.0, float(image.get_width())))
	var y1: int = int(minf(maxf(a.y, maxf(b.y, c.y)) + 1.0, float(image.get_height())))

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			if _point_in_triangle(p, a, b, c):
				image.set_pixel(x, y, colour)


static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1: float = _sign_of(p, a, b)
	var d2: float = _sign_of(p, b, c)
	var d3: float = _sign_of(p, c, a)
	var has_negative: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_positive: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_negative and has_positive)


static func _sign_of(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
