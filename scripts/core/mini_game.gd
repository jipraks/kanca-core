class_name MiniGame
extends Node3D

## Base class every mini-game inherits (PLAN.md §6.2).
##
## The router talks to a mini-game only through this surface, and the hub only
## through MiniGameResult. That is what lets a fourth mini-game be added with no
## change to either of them — it is registered in data/minigames.json and nowhere
## else in code.

## Emitted when a full session ends (all rounds complete).
signal session_completed(result: MiniGameResult)

## Emitted when the child taps the home button and confirms.
signal exit_requested()

var level_index: int = 1
var is_paused: bool = false


## Called by SceneRouter after the scene is ready and faded in.
func start_session(level: int) -> void:
	level_index = level
	push_error("start_session must be overridden by %s" % get_script().resource_path)


## Called when the app loses focus or the pause button is pressed.
func pause_session() -> void:
	is_paused = true


func resume_session() -> void:
	is_paused = false


## Voice ID for the "how to play" instruction, played on entry.
func get_intro_voice_id() -> String:
	return ""


## Must match the key in data/minigames.json.
func get_game_id() -> String:
	return ""


## Subclasses call this instead of emitting the signal directly, so that every
## exit path runs through one place.
func request_exit() -> void:
	exit_requested.emit()


func finish_session(result: MiniGameResult) -> void:
	Log.i(result.describe(), "MiniGame")
	session_completed.emit(result)
