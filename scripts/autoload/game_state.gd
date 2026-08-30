extends Node

## Single source of truth for player progress (PLAN.md §6.1).
##
## Holds state in memory and emits on change. It never touches the disk — that is
## SaveManager's job — and it never reaches into another autoload.

signal coins_changed(total: int)
signal inventory_changed()
signal progress_changed()
signal state_reset()

var coins: int = 0

## item_id -> count
var inventory: Dictionary = {}

## game_id -> next level to play, 1-based
var levels: Dictionary = {}

## game_id -> number of completed sessions. Drives unlocking (§7.2).
var sessions_completed: Dictionary = {}

## Persisted player-facing settings. Volumes are linear 0.0-1.0.
var settings: Dictionary = {
	"music_volume": 0.7,
	"sfx_volume": 1.0,
	"voice_volume": 1.0,
}


# ---------------------------------------------------------------- coins

func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_changed.emit(coins)


## Returns false when the child cannot afford it. Callers must treat that as
## "offer it free" rather than "block the activity" — PLAN.md §8.4 forbids the
## economy ever gating play.
func try_spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true


# ---------------------------------------------------------------- inventory

func add_item(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	inventory[item_id] = get_item_count(item_id) + count
	inventory_changed.emit()


func try_consume_item(item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return true
	var available: int = get_item_count(item_id)
	if available < count:
		return false
	var remaining: int = available - count
	if remaining <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = remaining
	inventory_changed.emit()
	return true


func get_item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func get_stocked_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in inventory:
		if int(inventory[key]) > 0:
			ids.append(key)
	ids.sort()
	return ids


func has_any_stock() -> bool:
	return not get_stocked_item_ids().is_empty()


# ---------------------------------------------------------------- progression

func get_level(game_id: String) -> int:
	return int(levels.get(game_id, 1))


func get_sessions_completed(game_id: String) -> int:
	return int(sessions_completed.get(game_id, 0))


## Unlock rules live in data/minigames.json, not here, so a fourth mini-game slots
## in without touching this file (§7.2, §6.2).
func is_unlocked(game_id: String) -> bool:
	var config: Dictionary = ContentDB.get_mini_game(game_id)
	var requirement: Variant = config.get("unlock_requires", null)
	if typeof(requirement) != TYPE_DICTIONARY:
		return true

	var requirement_dict: Dictionary = requirement as Dictionary
	var required_game: String = String(requirement_dict.get("game", ""))
	var required_sessions: int = int(requirement_dict.get("sessions", 1))
	if required_game.is_empty():
		return true
	return get_sessions_completed(required_game) >= required_sessions


## Applies everything a finished session produced. Called by the hub, which is the
## only consumer of MiniGameResult (§6.2).
func apply_result(result: MiniGameResult) -> void:
	if result == null:
		Log.w("apply_result called with null", "GameState")
		return

	for item_id: String in result.items_consumed:
		try_consume_item(item_id, int(result.items_consumed[item_id]))

	for item_id: String in result.items_produced:
		add_item(item_id, int(result.items_produced[item_id]))

	add_coins(result.coins_earned)
	record_session(result.game_id)


func record_session(game_id: String) -> void:
	if game_id.is_empty():
		return
	sessions_completed[game_id] = get_sessions_completed(game_id) + 1
	_advance_level(game_id)
	progress_changed.emit()


func _advance_level(game_id: String) -> void:
	var ceiling: int = ContentDB.get_max_playable_level(game_id)
	if ceiling <= 0:
		return
	levels[game_id] = mini(get_level(game_id) + 1, ceiling)


# ---------------------------------------------------------------- settings

func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	if settings.get(key) == value:
		return
	settings[key] = value
	progress_changed.emit()


# ---------------------------------------------------------------- serialisation

func to_dict() -> Dictionary:
	return {
		"coins": coins,
		"inventory": inventory.duplicate(),
		"levels": levels.duplicate(),
		"sessions_completed": sessions_completed.duplicate(),
		"settings": settings.duplicate(),
	}


## Tolerates anything. Every field is validated independently, so one corrupt key
## costs that key only and never the whole save (§6.1).
func from_dict(data: Dictionary) -> void:
	coins = maxi(0, int(data.get("coins", 0)))
	inventory = _sanitise_counts(data.get("inventory", {}))
	levels = _sanitise_counts(data.get("levels", {}))
	sessions_completed = _sanitise_counts(data.get("sessions_completed", {}))

	var loaded_settings: Variant = data.get("settings", {})
	if typeof(loaded_settings) == TYPE_DICTIONARY:
		for key: String in (loaded_settings as Dictionary):
			if settings.has(key):
				settings[key] = loaded_settings[key]

	coins_changed.emit(coins)
	inventory_changed.emit()
	progress_changed.emit()


func reset() -> void:
	coins = 0
	inventory = {}
	levels = {}
	sessions_completed = {}
	settings = {
		"music_volume": 0.7,
		"sfx_volume": 1.0,
		"voice_volume": 1.0,
	}
	state_reset.emit()
	coins_changed.emit(coins)
	inventory_changed.emit()
	progress_changed.emit()


func _sanitise_counts(source: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(source) != TYPE_DICTIONARY:
		return result
	for key: Variant in (source as Dictionary):
		if typeof(key) != TYPE_STRING:
			continue
		var value: int = int((source as Dictionary)[key])
		if value > 0:
			result[key] = value
	return result
