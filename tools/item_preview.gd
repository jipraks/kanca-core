extends Node3D

## Renders item visuals exactly as the game builds them, and saves a PNG.
## Developer tool — never shipped.
##
##   godot --path . res://tools/item_preview.tscn -- pisang apel jeruk
##
## Must run windowed, not headless: headless uses a dummy renderer and would
## produce a blank image.
##
## This is the check that matters after adding a model. A preview rendered in
## Blender is a picture of the model; this is a picture of the game. It confirms
## the scale, that the origin really sits on the ground, which tier the factory
## landed on, and what the colour looks like through Godot's own tonemap.

const OUTPUT_PATH := "user://item_preview.png"
const SPACING := 0.34
const DEFAULT_ITEMS: Array[String] = ["pisang", "apel", "telur", "roti"]


func _ready() -> void:
	var item_ids: Array[String] = _requested_items()
	print("=== item preview: %s ===" % [item_ids])

	_build_stage(item_ids.size())

	for i: int in range(item_ids.size()):
		var item_id: String = item_ids[i]
		var visual: Node3D = PlaceholderFactory.build_item_visual(item_id)
		visual.position.x = (float(i) - float(item_ids.size() - 1) * 0.5) * SPACING
		add_child(visual)

		var aabb: AABB = _combined_aabb(visual)
		print("  %-14s tier=%-9s size=%.3f x %.3f x %.3f m   base at y=%+.4f" % [
			item_id, _describe_tier(item_id),
			aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.y])

	# Two frames so the models are actually drawn before the buffer is grabbed.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var error: int = image.save_png(OUTPUT_PATH)
	if error == OK:
		print("  saved %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	else:
		print("  FAILED to save: %s" % error_string(error))

	get_tree().quit(0 if error == OK else 1)


func _requested_items() -> Array[String]:
	var requested: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if ContentDB.has_item(argument):
			requested.append(argument)
		else:
			print("  (ignoring unknown item: %s)" % argument)
	return requested if not requested.is_empty() else DEFAULT_ITEMS


## Which of the three tiers in PlaceholderFactory.build_item_visual answered.
func _describe_tier(item_id: String) -> String:
	var item: Dictionary = ContentDB.get_item(item_id)
	if ResourceLoader.exists(String(item.get("model", ""))):
		return "model"
	if ResourceLoader.exists(String(item.get("icon", ""))):
		return "sprite"
	return "primitive"


func _combined_aabb(node: Node) -> AABB:
	var result: AABB = AABB()
	var started: bool = false
	for child: Node in _walk(node):
		var visual: VisualInstance3D = child as VisualInstance3D
		if visual == null:
			continue
		var box: AABB = visual.global_transform * visual.get_aabb()
		if not started:
			result = box
			started = true
		else:
			result = result.merge(box)
	return result


func _walk(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_walk(child))
	return found


func _build_stage(count: int) -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("f2f2f2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	# Kept close to what the mini-game scenes actually use. Over-lighting the
	# preview washes every colour out and invites saturating models that were
	# already right.
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.05
	add_child(sun)

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(float(count) * SPACING + 0.18, 0.4)
	camera.position = Vector3(0.0, 0.32, 0.9)
	camera.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)
