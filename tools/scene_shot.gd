extends Node

## Screenshots a mini-game as it actually runs. Developer tool — never shipped.
##
##   godot --path . res://tools/scene_shot.tscn -- warung
##   godot --path . res://tools/scene_shot.tscn -- kebun 1
##
## Must run windowed: headless uses a dummy renderer and saves a blank image.
##
## The point is lighting and scale in context. A model looks one way on a neutral
## turntable and another on a shelf under the scene's own light, and the second
## one is the only one a child will ever see.

const DEFAULT_GAME := "warung"
const SETTLE_SECONDS := 2.4


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var game_id: String = String(arguments[0]) if arguments.size() > 0 else DEFAULT_GAME
	var level: int = int(arguments[1]) if arguments.size() > 1 else 1

	if game_id == "hub":
		await _shoot_hub()
	elif game_id == "kebun_growing":
		await _shoot_kebun_growing()
		return

	var scene_path: String = String(ContentDB.get_mini_game(game_id).get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		print("no scene for %s" % game_id)
		get_tree().quit(1)
		return

	var instance: MiniGame = (load(scene_path) as PackedScene).instantiate() as MiniGame
	add_child(instance)
	await get_tree().process_frame
	instance.start_session(level)

	# Let the shelf stock itself and the first customer walk in, so the shot
	# shows a round in progress rather than an empty room.
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var output: String = "user://%s_shot.png" % game_id
	var error: int = get_viewport().get_texture().get_image().save_png(output)
	if error == OK:
		print("saved %s" % ProjectSettings.globalize_path(output))
	else:
		print("FAILED to save: %s" % error_string(error))

	get_tree().quit(0 if error == OK else 1)


## Drags the left button from `from` by `by`, in small steps. Steps rather than
## one jump because a single 220px motion is not what a finger produces, and the
## thing being tested is the path a finger takes.
func _push_drag(from: Vector2, by: Vector2) -> void:
	var viewport: Viewport = get_viewport()

	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	viewport.push_input(press)
	await get_tree().process_frame

	const STEPS := 11
	var step: Vector2 = by / float(STEPS)
	for index: int in range(STEPS):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = from + step * float(index + 1)
		motion.global_position = motion.position
		motion.relative = step
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion)
		await get_tree().process_frame

	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = from + by
	release.global_position = release.position
	viewport.push_input(release)
	await get_tree().process_frame


## Plants and waters every Kebun plot, then photographs it part-grown.
##
## An empty garden is a picture of six boxes. The whole point of the mini-game is
## what appears in them, and none of it is visible until something is planted —
## so a screenshot of the Kebun at rest says nothing about whether the growth
## stages are right.
func _shoot_kebun_growing() -> void:
	var kebun: Node3D = (load("res://scenes/minigames/kebun/kebun.tscn") as PackedScene).instantiate() as Node3D
	add_child(kebun)
	await get_tree().process_frame
	kebun.start_session(0)
	await get_tree().process_frame

	# Staggered, so the shot catches the plots at different stages — which is the
	# only way one still picture shows that there *are* stages.
	var index: int = 0
	for plot: Node in kebun._plots:
		plot.plant(plot.item_id)
		plot.water()
		await get_tree().create_timer(0.55).timeout
		index += 1

	await get_tree().create_timer(SETTLE_SECONDS + 0.6).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var error: int = get_viewport().get_texture().get_image().save_png("user://kebun_growing.png")
	print("saved %s" % ProjectSettings.globalize_path("user://kebun_growing.png")
		if error == OK else "FAILED: %s" % error_string(error))
	get_tree().quit(0 if error == OK else 1)


## The village, with whatever the current save has unlocked.
##
##   ... -- hub                     as a new player sees it
##   ... -- hub unlocked            everything awake
##   ... -- hub unlocked 45 8.5     turned 45 degrees, zoomed to 8.5 units
##   ... -- hub unlocked drag        a real drag across open village
##   ... -- hub unlocked dragstick   the same drag, but starting on the joystick
##   ... -- hub unlocked walk        joystick held, caught mid-stride
##
## The yaw and distance arguments exist because the camera is steerable now and a
## screenshot is the only way to check which way a drag actually turns things.
func _shoot_hub() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 1 and String(arguments[1]) == "unlocked":
		GameState.record_session("kebun")
		GameState.record_session("warung")

	var hub: Node3D = (load(SceneRouter.HUB_SCENE) as PackedScene).instantiate() as Node3D
	add_child(hub)
	await get_tree().process_frame

	var camera: HubCamera = hub.get_node_or_null("Camera") as HubCamera
	var suffix: String = ""

	# A drag pushed through the real window, which is the only place the answer
	# means anything: whether it turns the village depends on Godot's own control
	# hit-testing, and the headless root window is not the size the game runs at.
	# Walks the avatar and photographs the result. A still cannot show motion, but
	# it can show a leg that is not vertical - and that is the only evidence that
	# the model's leg nodes, the walk cycle and the physics step are actually
	# connected to each other.
	#
	# The movement action is pressed directly rather than through a synthetic
	# touch on the joystick. That is deliberate: whether a touch reaches the stick
	# is a separate question, and one the `dragstick` mode above already answers.
	# Mixing the two means a failure here could be either, and the first attempt
	# at this did exactly that - zero speed, and no way to tell which half was
	# wrong.
	if arguments.size() > 2 and String(arguments[2]) == "walk":
		var towards: StringName = &"hub_move_up" if (arguments.size() > 3
			and String(arguments[3]) == "building") else &"hub_move_right"
		Input.action_press(towards, 1.0)
		# Long enough to be mid-stride, short enough that the avatar is still in
		# the middle of the frame: at 4 m/s a second of walking crosses a quarter
		# of the village.
		for _index: int in range(46):
			await get_tree().process_frame
		suffix = "_walk"
		var player: Node = hub.get_node_or_null("Player")
		if player != null:
			var walker: WalkCycle = player._walk as WalkCycle
			print("  at %s" % player.global_position)
			print("  ground speed: %.2f m/s   legs: %s   left leg angle: %.3f rad" % [
				Vector2(player.velocity.x, player.velocity.z).length(),
				"found" if walker != null and walker.has_legs() else "MISSING",
				(walker._left.rotation.x if walker != null and walker.has_legs() else 0.0)])
	elif camera != null and arguments.size() > 2 and String(arguments[2]).begins_with("drag"):
		var on_stick: bool = String(arguments[2]) == "dragstick"
		var from: Vector2 = Vector2(150.0, 600.0) if on_stick else Vector2(640.0, 260.0)
		await _push_drag(from, Vector2(220.0, 0.0))
		suffix = "_dragstick" if on_stick else "_drag"
		print("  yaw after the drag: %.4f rad" % camera.get_yaw())
	elif camera != null and arguments.size() > 2:
		camera.turn_by(deg_to_rad(String(arguments[2]).to_float()))
		suffix += "_yaw%s" % String(arguments[2])
	elif camera != null and arguments.size() > 3:
		camera.set_distance(String(arguments[3]).to_float())
		suffix += "_d%s" % String(arguments[3])

	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var output_path: String = "user://hub_shot%s.png" % suffix
	var error: int = get_viewport().get_texture().get_image().save_png(output_path)
	if error == OK:
		print("saved %s" % ProjectSettings.globalize_path(output_path))
	else:
		print("FAILED to save: %s" % error_string(error))
	get_tree().quit(0 if error == OK else 1)
