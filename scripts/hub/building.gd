class_name Building
extends Node3D

## One mini-game entrance in the village (PLAN.md §7.1, §7.2).
##
## Everything about it comes from data/minigames.json — position, size, colour,
## and what unlocks it. Adding a fourth building means adding a fourth entry
## there, and nothing in this file or in the hub changes.
##
## Approaching shows a prompt; entering needs a deliberate tap. Never auto-enter
## on proximity — a child who walks past a door and gets teleported inside learns
## to avoid the door.

signal player_approached(game_id: String)
signal player_left(game_id: String)

## How close the child has to be for the prompt to appear.
const TRIGGER_RADIUS := 4.2

## Signboard, standing in front of each building facing the village.
const SIGN_BOARD := Vector3(1.85, 0.95, 0.12)
const SIGN_POST_HEIGHT := 1.25
const MARKER_BOB_HEIGHT := 0.18
const MARKER_BOB_SECONDS := 1.6

var game_id: String = ""
var is_unlocked: bool = true

var _config: Dictionary = {}
var _model: Node3D = null
var _sign: Node3D = null
var _marker: Sprite3D = null
var _marker_base_y: float = 0.0
var _elapsed: float = 0.0


func setup(id: String, config: Dictionary, unlocked: bool) -> void:
	game_id = id
	_config = config
	is_unlocked = unlocked
	name = "Building_%s" % id

	var position_2d: Array = _config.get("hub_position", [0.0, 0.0]) as Array
	position = Vector3(float(position_2d[0]), 0.0, float(position_2d[1]))
	rotation_degrees.y = float(_config.get("hub_rotation_degrees", 0.0))

	_build_structure()
	_build_sign()
	_refresh_tint()
	_build_trigger()
	_build_marker()


## Called when unlocking changes underneath the child — the building brightens and
## its marker stops being a "resting" one.
func set_unlocked(unlocked: bool) -> void:
	if is_unlocked == unlocked:
		return
	is_unlocked = unlocked
	_refresh_marker()
	_refresh_tint()


func get_icon() -> Texture2D:
	var icon_path: String = String(_config.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var texture: Texture2D = load(icon_path) as Texture2D
		if texture != null:
			return texture
	return PlaceholderFactory.build_swatch_icon("building_%s" % game_id, _body_colour(), 160)


func get_display_name() -> String:
	return String(_config.get("display_name", game_id.capitalize()))


func _process(delta: float) -> void:
	if _marker == null:
		return
	# A gently bobbing marker reads as "come here" without any text.
	_elapsed += delta
	var phase: float = sin(_elapsed / MARKER_BOB_SECONDS * TAU)
	_marker.position.y = _marker_base_y + phase * MARKER_BOB_HEIGHT


# ---------------------------------------------------------------- construction

## The real model if data/minigames.json names one that exists, otherwise the
## generated box-and-prism stand-in. Same two-tier arrangement the items use.
## Three cases, and the difference between the first two matters.
##
## No model *named* means the building is part of the village mesh: it is already
## on screen and there is nothing to instance. A placeholder box here would stand
## inside the building the child can see.
##
## A model named but missing is the §10.5 case, and still gets its stand-in.
func _build_structure() -> void:
	var model_path: String = String(_config.get("model", ""))
	if model_path.is_empty():
		_build_collider()
		return

	var instance: Node3D = ModelKit.instantiate(model_path)
	if instance != null:
		instance.name = "Model"
		add_child(instance)
		_model = instance
		_build_collider()
		return

	_build_placeholder_structure()


## Sized from building_size, not from the model. The declared footprint is what
## the approach trigger is built from too, and a roof is allowed to overhang it.
## The collider is measured from the model, not from data/minigames.json.
##
## `building_size` describes the building; the model also has steps, a veranda
## and a fence, and none of that is in the number. So the child could walk onto
## the Warung's steps, stand at ground level because that is where the floor
## collider is, and watch the step swallow their legs to the knee.
##
## Taking the model's own bounds means anything the modeller adds is solid the
## moment it exists, which is the only version of this that stays true.
func _build_collider() -> void:
	var bounds: AABB = _model_bounds()
	var collider: StaticBody3D = StaticBody3D.new()
	collider.name = "Collider"
	collider.collision_layer = 1
	collider.collision_mask = 0

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	shape.position = bounds.get_center()
	collider.add_child(shape)
	add_child(collider)


## The model's combined extent in the building's own space, falling back to the
## declared size when there is no model to measure (§10.5).
func _model_bounds() -> AABB:
	var size: Vector3 = _building_size()
	var fallback: AABB = AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
	if _model == null:
		return fallback

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_model, meshes)
	if meshes.is_empty():
		return fallback

	var bounds: AABB = AABB()
	var started: bool = false
	for mesh: MeshInstance3D in meshes:
		# Into the building's space, so a model rotated on its own node still
		# measures correctly.
		var local: Transform3D = global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = local * mesh.get_aabb()
		bounds = box if not started else bounds.merge(box)
		started = true

	# The child should stop *at* the building rather than a hand's width inside
	# it, and a box hugging the model exactly leaves them clipping the eaves.
	return bounds.grow(0.12)


static func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		into.append(mesh)
	for child: Node in node.get_children():
		_collect_meshes(child, into)


## Generated stand-in, used until a real model exists (§11).
func _build_placeholder_structure() -> void:
	var size: Vector3 = _building_size()

	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	body.mesh = box
	body.material_override = PlaceholderFactory.get_flat_material(_body_colour())
	body.position.y = size.y * 0.5
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	var roof: MeshInstance3D = MeshInstance3D.new()
	roof.name = "Roof"
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(size.x * 1.12, size.y * 0.45, size.z * 1.12)
	roof.mesh = prism
	roof.material_override = PlaceholderFactory.get_flat_material(_roof_colour())
	roof.position.y = size.y + size.y * 0.22
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(roof)

	var collider: StaticBody3D = StaticBody3D.new()
	collider.name = "Collider"
	collider.collision_layer = 1
	collider.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position.y = size.y * 0.5
	collider.add_child(shape)
	add_child(collider)


## A signboard in front of the building, carrying its icon with the name beneath.
##
## The icon is the sign. §3.1 is unambiguous: no UI element may depend on text to
## be understood, and a board reading "WARUNG" means nothing to a child who
## cannot read. The word is there as a reading aid alongside the picture — which
## is exactly the use §3.1 does allow — and it is deliberately the smaller half.
##
## Placed at local -Z, which is the building's front: the hub turns each building
## so that side faces the village.
func _build_sign() -> void:
	var size: Vector3 = _building_size()
	_sign = Node3D.new()
	_sign.name = "Sign"
	# Beside the entrance, not in the middle of it: the path from the plaza
	# arrives here, and a child should not have to walk through the sign.
	_sign.position = Vector3(size.x * 0.34, 0.0, -(size.z * 0.5 + 0.55))
	add_child(_sign)

	var post: MeshInstance3D = MeshInstance3D.new()
	post.name = "Post"
	var post_mesh: BoxMesh = BoxMesh.new()
	post_mesh.size = Vector3(0.18, SIGN_POST_HEIGHT, 0.18)
	post.mesh = post_mesh
	post.material_override = PlaceholderFactory.get_flat_material(Palette.WOOD.darkened(0.25))
	post.position.y = SIGN_POST_HEIGHT * 0.5
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sign.add_child(post)

	var board: MeshInstance3D = MeshInstance3D.new()
	board.name = "Board"
	var board_mesh: BoxMesh = BoxMesh.new()
	board_mesh.size = SIGN_BOARD
	board.mesh = board_mesh
	board.material_override = PlaceholderFactory.get_flat_material(Palette.UI_PANEL)
	board.position.y = SIGN_POST_HEIGHT + SIGN_BOARD.y * 0.5
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sign.add_child(board)

	var face_z: float = -(SIGN_BOARD.z * 0.5 + 0.02)

	var icon: Sprite3D = Sprite3D.new()
	icon.name = "Icon"
	icon.texture = get_icon()
	icon.shaded = false
	icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Sized from the board's width, not its height: building icons are wide and
	# low, and fitting them by height leaves them tiny.
	icon.pixel_size = (SIGN_BOARD.x * 0.82) / maxf(float(icon.texture.get_width()), 1.0)
	# Sprite3D faces +Z by default; the board's front is -Z.
	icon.rotation_degrees.y = 180.0
	icon.position = Vector3(0.0, SIGN_POST_HEIGHT + SIGN_BOARD.y * 0.60, face_z)
	_sign.add_child(icon)

	var label: Label3D = Label3D.new()
	label.name = "Name"
	label.text = get_display_name()
	label.font_size = 72
	label.pixel_size = 0.0030
	label.modulate = Palette.UI_TEXT
	label.outline_size = 0
	label.shaded = false
	label.rotation_degrees.y = 180.0
	label.position = Vector3(0.0, SIGN_POST_HEIGHT + SIGN_BOARD.y * 0.18, face_z)
	_sign.add_child(label)


func _build_trigger() -> void:
	var area: Area3D = Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 16
	area.collision_mask = 2
	area.monitoring = true

	var shape: CollisionShape3D = CollisionShape3D.new()
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = TRIGGER_RADIUS + _building_size().x * 0.35
	cylinder.height = 4.0
	shape.shape = cylinder
	shape.position.y = 2.0
	area.add_child(shape)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _build_marker() -> void:
	_marker = Sprite3D.new()
	_marker.name = "Marker"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.shaded = false
	_marker.pixel_size = 0.012
	_marker.no_depth_test = false
	_marker_base_y = _building_size().y + 2.0
	_marker.position.y = _marker_base_y
	add_child(_marker)
	_refresh_marker()


## What floats above a building, and when.
##
## Nothing at all once it is open. The marker used to show the building's own
## icon — and those icons are rendered from the building models, so an unlocked
## warung hovered a photograph of itself two metres above its roof. It said
## nothing the sign below it did not already say, and it looked like a bug
## because it read like one.
##
## §7.1's "large floating icon prompt" is the UI button that appears on
## approach, not this. This is only for the two states the sign cannot express:
## resting, and not built yet.
func _refresh_marker() -> void:
	if _marker == null:
		return
	if is_unlocked:
		_marker.visible = false
		return
	_marker.visible = true

	# Locked buildings rest or are being built. Never a padlock — a lock reads as
	# punishment, and nothing in this app punishes (§7.2).
	#
	# The building-materials marker is brick-coloured, not white. Shape alone was
	# not enough: a stack of white rounded squares hanging in the sky reads as
	# leftover interface, and the first person to see it asked what it was —
	# which is the answer. In brick it reads as a pile of something.
	var style: String = String(_config.get("locked_style", "sleeping"))
	var sleeping: bool = style == "sleeping"
	var glyph: String = "sleep" if sleeping else "construction"
	var tint: Color = Palette.UI_PANEL if sleeping else Palette.BRICK
	_marker.texture = PlaceholderFactory.build_glyph_icon(glyph, tint, 128)
	_marker.modulate = Color(1.0, 1.0, 1.0, 0.92)


func _refresh_tint() -> void:
	# The sign rests along with the building it belongs to.
	_dim_model(_sign, not is_unlocked)

	if _model != null:
		_dim_model(_model, not is_unlocked)
		return
	var body: MeshInstance3D = get_node_or_null("Body") as MeshInstance3D
	if body != null:
		body.material_override = PlaceholderFactory.get_flat_material(_body_colour())
	var roof: MeshInstance3D = get_node_or_null("Roof") as MeshInstance3D
	if roof != null:
		roof.material_override = PlaceholderFactory.get_flat_material(_roof_colour())


## A resting building is washed out rather than recoloured. `material_overlay`
## paints over the model's own materials without replacing them, so a locked
## building still looks like itself — replacing the materials would flatten a
## five-colour building into one grey mass, and §7.2 wants "not ready yet", not
## "gone".
func _dim_model(root: Node, dimmed: bool) -> void:
	var overlay: StandardMaterial3D = null
	if dimmed:
		overlay = PlaceholderFactory.get_unshaded_material(Color(Palette.STONE, 0.55), true)
	for node: Node in _descendants(root):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh != null:
			mesh.material_overlay = overlay


func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	found.append(root)
	for child: Node in root.get_children():
		found.append_array(_descendants(child))
	return found


func _building_size() -> Vector3:
	var raw: Array = _config.get("building_size", [6.0, 3.0, 5.0]) as Array
	if raw.size() < 3:
		return Vector3(6.0, 3.0, 5.0)
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _body_colour() -> Color:
	var colour: Color = Color(String(_config.get("colour", "cccccc")))
	return colour if is_unlocked else colour.lerp(Palette.STONE, 0.55)


func _roof_colour() -> Color:
	var colour: Color = Color(String(_config.get("roof_colour", "999999")))
	return colour if is_unlocked else colour.lerp(Palette.STONE, 0.55)


func _on_body_entered(body: Node3D) -> void:
	if body is HubPlayer:
		player_approached.emit(game_id)


func _on_body_exited(body: Node3D) -> void:
	if body is HubPlayer:
		player_left.emit(game_id)
