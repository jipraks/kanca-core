extends Node

## Measures a scene against the performance budget in PLAN.md. Developer tool.
##
##   godot --path . res://tools/scene_budget.tscn -- hub
##
## Not headless: these numbers come from the renderer having actually drawn a
## frame, so they account for culling, for MultiMesh batching, and for the shadow
## pass. An estimate from triangle counts in the build scripts would have said the
## village was fine right up until it was not.
##
## §4.2 sets the limits: under 100 draw calls and under 80,000 visible triangles,
## on Compatibility, on a low-end Android phone. Exits non-zero when either is
## breached, so it can go in the test run.
##
## **Only the hub is measurable this way today.** A mini-game builds its shelves
## and its produce through the MiniGame lifecycle, which the router drives, so
## loading one of those scenes directly gives an empty room and a very
## comfortable number. The floor below exists so that comfort is refused rather
## than reported.

const DRAW_CALL_LIMIT := 100
const TRIANGLE_LIMIT := 80000

## Enough frames for the renderer's own counters to settle.
const SETTLE_FRAMES := 12

## Below this, the scene did not finish building. Any scene the child actually
## looks at draws more than this before the ground is laid.
const PLAUSIBLE_FLOOR := 5000


func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var scene_id: String = String(arguments[0]) if arguments.size() > 0 else "hub"

	print("=== Kanca scene budget: %s ===" % scene_id)

	GameState.record_session("kebun")
	GameState.record_session("warung")

	var path: String = SceneRouter.HUB_SCENE
	if scene_id != "hub":
		path = "res://scenes/minigames/%s/%s.tscn" % [scene_id, scene_id]
	if not ResourceLoader.exists(path):
		print("no scene at %s" % path)
		get_tree().quit(1)
		return

	var root: Node = (load(path) as PackedScene).instantiate()

	# A scene whose script failed to parse still instantiates: Godot builds the
	# nodes, fails to attach the script, and prints an error into a log nobody is
	# reading. Everything the script would have built is simply absent, and this
	# tool cheerfully reported four thousand triangles and "within budget" for a
	# village that had not been built at all.
	#
	# A measuring tool that passes when the thing it measures is broken is worse
	# than no tool, because it is trusted.
	if root.get_script() == null:
		print("  the scene root has no script attached — it failed to load.")
		print("  Any number printed below would be measuring an empty scene.")
		root.free()
		get_tree().quit(1)
		return

	add_child(root)
	for index: int in range(SETTLE_FRAMES):
		await RenderingServer.frame_post_draw

	var draw_calls: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)

	if primitives < PLAUSIBLE_FLOOR:
		print("  triangles   %8d  — too few for a built scene." % primitives)
		print("  This scene builds its contents through the MiniGame lifecycle,")
		print("  which only the router drives. Nothing has been measured.")
		get_tree().quit(1)
		return

	var over: bool = false
	over = _report("draw calls", draw_calls, DRAW_CALL_LIMIT) or over
	over = _report("triangles", primitives, TRIANGLE_LIMIT) or over

	print("=== %s ===" % ("OVER BUDGET" if over else "within budget"))
	get_tree().quit(1 if over else 0)


func _report(label: String, value: int, limit: int) -> bool:
	var over: bool = value > limit
	print("  %-12s %8d  /%8d  %s" % [label, value, limit,
		"OVER by %d" % (value - limit) if over else "ok"])
	return over
