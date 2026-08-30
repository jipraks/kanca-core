extends Node

## Persists GameState to user://save.json (PLAN.md §6.1).
##
## Corrupt, truncated or missing saves reset to a valid default. The child never
## sees an error and the app never refuses to start — a lost save is a bad day,
## a crash loop is a dead install.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

## Writes are debounced so that a burst of signals during a session end produces
## one file write rather than a dozen.
const AUTOSAVE_DEBOUNCE_SECONDS := 1.0

signal save_completed()
signal load_completed(was_recovered: bool)

var _debounce_timer: Timer = null
var _dirty: bool = false


func _ready() -> void:
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = AUTOSAVE_DEBOUNCE_SECONDS
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)

	GameState.coins_changed.connect(_on_state_changed_int)
	GameState.inventory_changed.connect(_on_state_changed)
	GameState.progress_changed.connect(_on_state_changed)

	load_game()


func _notification(what: int) -> void:
	# Android backgrounds the app without warning. Anything not written by now is
	# gone, so flush synchronously rather than waiting for the debounce.
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			flush()


## Marks the state dirty and starts the debounce. Safe to call as often as needed.
func request_save() -> void:
	_dirty = true
	if _debounce_timer != null:
		_debounce_timer.start()


## Writes immediately if anything is pending.
func flush() -> void:
	if not _dirty:
		return
	save_game()


func save_game() -> bool:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"state": GameState.to_dict(),
	}
	var ok: bool = JsonLoader.write_dict(SAVE_PATH, payload)
	if ok:
		_dirty = false
		Log.d("Saved to %s" % SAVE_PATH, "SaveManager")
		save_completed.emit()
	else:
		Log.e("Save failed, progress this session may be lost", "SaveManager")
	return ok


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		Log.i("No save file yet, starting fresh", "SaveManager")
		GameState.reset()
		_dirty = false
		load_completed.emit(false)
		return

	var payload: Dictionary = JsonLoader.load_dict(SAVE_PATH)
	if payload.is_empty():
		_recover("save file is missing or unreadable")
		return

	var version: int = int(payload.get("version", 0))
	if version <= 0 or version > SAVE_VERSION:
		_recover("unsupported save version %d" % version)
		return

	var state: Variant = payload.get("state", null)
	if typeof(state) != TYPE_DICTIONARY:
		_recover("save file has no usable state block")
		return

	var migrated: Dictionary = _migrate(state as Dictionary, version)
	GameState.from_dict(migrated)
	_dirty = false
	Log.i("Save loaded (version %d)" % version, "SaveManager")
	load_completed.emit(false)


## Deletes the save and starts over. Used by the settings screen behind the
## parental gate (§3.6) — never reachable by a child.
func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var error: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if error != OK:
			Log.w("Could not delete %s: %s" % [SAVE_PATH, error_string(error)], "SaveManager")
	GameState.reset()
	save_game()


func _recover(reason: String) -> void:
	Log.e("Resetting progress: %s" % reason, "SaveManager")
	GameState.reset()
	save_game()
	load_completed.emit(true)


## Hook for future save format changes. Nothing to migrate at version 1.
func _migrate(state: Dictionary, from_version: int) -> Dictionary:
	if from_version == SAVE_VERSION:
		return state
	Log.i("Migrating save from version %d to %d" % [from_version, SAVE_VERSION], "SaveManager")
	return state


func _on_state_changed() -> void:
	request_save()


func _on_state_changed_int(_total: int) -> void:
	request_save()


func _on_debounce_timeout() -> void:
	if _dirty:
		save_game()
