extends Node

## Every scene transition in the game (PLAN.md §6.1).
##
## Nothing else may call `change_scene_to_file`. Two reasons: the fade has to be
## consistent everywhere, and the hub must stay loaded while a mini-game runs so
## that coming back is instant — a child bounces between activities every couple
## of minutes and a two-second reload each way is most of the session (§6.3).

signal transition_started()
signal transition_finished()

## The hub listens for this and is the only consumer of MiniGameResult (§6.2).
signal mini_game_finished(game_id: String, result: MiniGameResult)
signal mini_game_exited(game_id: String)

## Raised on the Android back gesture. Whatever is on screen decides what it means.
signal back_requested()

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const LOADING_SCENE := "res://scenes/ui/loading_screen.tscn"

const FADE_SECONDS := 0.25

## The loading screen only appears if loading actually takes long enough to
## notice. Flashing it for 60ms looks like a glitch.
const LOADING_SCREEN_DELAY_MS := 250

var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _loading_layer: CanvasLayer = null
var _loading_screen: LoadingScreen = null

var _hub: Node = null
var _current_mini_game: MiniGame = null
var _current_game_id: String = ""
var _transitioning: bool = false
var _scene_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The overlays hang off this autoload so that no child is added to root while
	# the engine is still setting root up. Scenes themselves go directly under
	# root, because SceneTree.current_scene must be a direct child of it.
	_loading_layer = CanvasLayer.new()
	_loading_layer.name = "LoadingLayer"
	_loading_layer.layer = 120
	_loading_layer.visible = false
	add_child(_loading_layer)

	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 128
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = Palette.CURTAIN
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _current_mini_game != null:
				_current_mini_game.pause_session()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if _current_mini_game != null:
				_current_mini_game.resume_session()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back_requested.emit()


# ---------------------------------------------------------------- navigation

func is_transitioning() -> bool:
	return _transitioning


func get_current_mini_game_id() -> String:
	return _current_game_id


func go_to_hub() -> void:
	if _transitioning:
		return
	_transitioning = true
	transition_started.emit()

	AudioManager.clear_voice_queue()
	await _fade_out()

	if _current_mini_game != null:
		_current_mini_game.queue_free()
		_current_mini_game = null
	_current_game_id = ""

	_release_boot_scene()

	if _hub == null:
		var packed: PackedScene = await _load_packed(HUB_SCENE)
		if packed == null:
			Log.e("Hub scene could not be loaded, the app has nowhere to go", "SceneRouter")
			_transitioning = false
			await _fade_in()
			return
		_hub = packed.instantiate()
		get_tree().root.add_child(_hub)
		get_tree().current_scene = _hub as Node
	else:
		_set_hub_active(true)

	# One frame so the hub can lay itself out before the curtain lifts.
	await get_tree().process_frame

	await _fade_in()
	_transitioning = false
	transition_finished.emit()


func go_to_mini_game(game_id: String) -> void:
	if _transitioning:
		return

	var config: Dictionary = ContentDB.get_mini_game(game_id)
	var scene_path: String = String(config.get("scene", ""))
	if scene_path.is_empty():
		Log.e("Mini-game %s has no scene path in data/minigames.json" % game_id, "SceneRouter")
		return

	_transitioning = true
	transition_started.emit()

	AudioManager.clear_voice_queue()
	await _fade_out()

	_set_hub_active(false)

	var packed: PackedScene = await _load_packed(scene_path)
	if packed == null:
		Log.e("Mini-game scene failed to load: %s" % scene_path, "SceneRouter")
		_set_hub_active(true)
		await _fade_in()
		_transitioning = false
		return

	var instance: MiniGame = packed.instantiate() as MiniGame
	if instance == null:
		Log.e("%s does not extend MiniGame" % scene_path, "SceneRouter")
		_set_hub_active(true)
		await _fade_in()
		_transitioning = false
		return

	_current_mini_game = instance
	_current_game_id = game_id
	instance.session_completed.connect(_on_session_completed.bind(game_id))
	instance.exit_requested.connect(_on_exit_requested.bind(game_id))
	get_tree().root.add_child(instance)

	await get_tree().process_frame
	await _fade_in()

	_transitioning = false
	transition_finished.emit()

	# Started only once the curtain is up, so the intro voice line is not talking
	# to a black screen (§6.2).
	var level: int = clampi(GameState.get_level(game_id), 1, maxi(1, ContentDB.get_max_playable_level(game_id)))
	instance.start_session(level)


func _on_session_completed(result: MiniGameResult, game_id: String) -> void:
	if _hub == null:
		# Defensive: the hub is the intended consumer, but progress must never be
		# silently dropped because it happened not to exist.
		Log.w("Session finished with no hub loaded, applying result directly", "SceneRouter")
		GameState.apply_result(result)
	else:
		mini_game_finished.emit(game_id, result)
	go_to_hub()


func _on_exit_requested(game_id: String) -> void:
	mini_game_exited.emit(game_id)
	go_to_hub()


# ---------------------------------------------------------------- internals

## Hides the hub without unloading it (§6.3).
##
## A CanvasLayer does not inherit visibility from a Node3D ancestor — it is a
## separate rendering root, which is the entire point of it. So hiding the hub's
## 3D world left its interface on screen: the joystick and the zoom buttons sat
## on top of every mini-game, and the child saw two coin counters stacked on each
## other, one from the hub and one from the game they were playing.
##
## The layers have to be hidden by name, one at a time.
func _set_hub_active(active: bool) -> void:
	if _hub == null:
		return
	var hub_node: CanvasItem = _hub as CanvasItem
	if hub_node != null:
		hub_node.visible = active
	var hub_3d: Node3D = _hub as Node3D
	if hub_3d != null:
		hub_3d.visible = active
	_set_layers_visible(_hub, active)
	_hub.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


static func _set_layers_visible(root: Node, visible: bool) -> void:
	for child: Node in root.get_children():
		var layer: CanvasLayer = child as CanvasLayer
		if layer != null:
			layer.visible = visible
		_set_layers_visible(child, visible)


## The boot scene hands over once and is never returned to.
func _release_boot_scene() -> void:
	var current: Node = get_tree().current_scene
	if current == null or current == _hub:
		return
	get_tree().current_scene = null
	current.queue_free()


func _fade_out() -> void:
	_fade_rect.visible = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_SECONDS)
	await tween.finished


func _fade_in() -> void:
	_hide_loading_screen()
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_SECONDS)
	await tween.finished
	_fade_rect.visible = false
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _load_packed(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene

	if not ResourceLoader.exists(path):
		Log.e("Scene not found: %s" % path, "SceneRouter")
		return null

	var request_error: int = ResourceLoader.load_threaded_request(path, "PackedScene")
	if request_error != OK:
		Log.w("Threaded load unavailable for %s, loading on the main thread" % path, "SceneRouter")
		var direct: PackedScene = load(path) as PackedScene
		_scene_cache[path] = direct
		return direct

	var started_at: int = Time.get_ticks_msec()
	var loading_shown: bool = false

	while true:
		var progress: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(path, progress)

		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if not loading_shown and Time.get_ticks_msec() - started_at > LOADING_SCREEN_DELAY_MS:
					_show_loading_screen()
					loading_shown = true
				if loading_shown and _loading_screen != null and not progress.is_empty():
					_loading_screen.set_progress(float(progress[0]))
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
				_scene_cache[path] = packed
				return packed
			_:
				Log.e("Threaded load failed for %s (status %d)" % [path, status], "SceneRouter")
				return null

	return null


func _show_loading_screen() -> void:
	if _loading_screen == null:
		if not ResourceLoader.exists(LOADING_SCENE):
			return
		var packed: PackedScene = load(LOADING_SCENE) as PackedScene
		if packed == null:
			return
		_loading_screen = packed.instantiate() as LoadingScreen
		if _loading_screen == null:
			return
		_loading_layer.add_child(_loading_screen)

	_loading_screen.set_progress(0.0)
	_loading_layer.visible = true


func _hide_loading_screen() -> void:
	if _loading_layer != null:
		_loading_layer.visible = false
