class_name ContentDB
extends RefCounted

## Read-only access to everything in data/.
##
## PLAN.md §9: adding an item, level or recipe must never require a code change,
## and a malformed file must never crash the app. Every accessor here returns a
## usable value even when the file behind it is missing or broken.
##
## Gameplay code must never touch FileAccess directly (§15) — it comes through here.

const ITEMS_PATH := "res://data/items.json"
const MINI_GAMES_PATH := "res://data/minigames.json"
const VOICE_MANIFEST_PATH := "res://data/voice_manifest.json"
const LEVELS_DIR := "res://data/levels/"

const _REQUIRED_ITEM_KEYS: Array[String] = ["display_name", "voice_id", "category"]
const _REQUIRED_MINI_GAME_KEYS: Array[String] = ["scene", "display_name", "order"]

## Levels above this are defined in data but not yet implemented in code.
## Warung levels 4-5 (payment and change) are stretch scope per PLAN.md §16.5 —
## they stay switched off rather than half-built.
const MAX_PLAYABLE_LEVEL := 3

static var _items: Dictionary = {}
static var _mini_games: Dictionary = {}
static var _voice_manifest: Dictionary = {}
## game_id -> the whole parsed level file, so blocks alongside "levels"
## (Warung customers, Dapur dishes) are reachable without a second loader.
static var _level_files: Dictionary = {}
static var _loaded: bool = false


## Called once at boot so the first mini-game entry is not stalled by disk reads.
static func preload_all() -> void:
	_ensure_loaded()
	for game_id: String in _mini_games:
		_ensure_levels(game_id)


static func reload() -> void:
	_items.clear()
	_mini_games.clear()
	_voice_manifest.clear()
	_level_files.clear()
	_loaded = false
	_ensure_loaded()


# ---------------------------------------------------------------- items

static func has_item(item_id: String) -> bool:
	_ensure_loaded()
	return _items.has(item_id)


## Always returns a usable item dictionary. An unknown id yields a generic entry
## rather than null, so a typo in a level file degrades into a plain box instead
## of a crash.
static func get_item(item_id: String) -> Dictionary:
	_ensure_loaded()
	if _items.has(item_id):
		return _items[item_id] as Dictionary
	Log.w("Unknown item id: %s" % item_id, "ContentDB")
	return {
		"display_name": item_id.capitalize(),
		"voice_id": "item_%s" % item_id,
		"category": "lain",
		"growable": false,
		"grow_stages": 3,
		"price": 1000,
	}


static func get_item_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key: String in _items:
		ids.append(key)
	ids.sort()
	return ids


static func get_growable_item_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key: String in _items:
		var item: Dictionary = _items[key]
		if bool(item.get("growable", false)):
			ids.append(key)
	ids.sort()
	return ids


static func get_item_display_name(item_id: String) -> String:
	return String(get_item(item_id).get("display_name", item_id))


static func get_item_voice_id(item_id: String) -> String:
	return String(get_item(item_id).get("voice_id", "item_%s" % item_id))


# ---------------------------------------------------------------- mini-games

## game_id -> { scene, display_name, order, unlock_requires, hub_position, colour }
## The router and the hub both read this, which is what keeps a fourth mini-game
## from needing changes in either of them (PLAN.md §6.2).
static func get_mini_games() -> Dictionary:
	_ensure_loaded()
	return _mini_games


static func get_mini_game(game_id: String) -> Dictionary:
	_ensure_loaded()
	if _mini_games.has(game_id):
		return _mini_games[game_id] as Dictionary
	Log.e("Unknown mini-game id: %s" % game_id, "ContentDB")
	return {}


## Whether a mini-game can actually be entered right now — that is, whether its
## scene exists on disk. Distinct from GameState.is_unlocked, which is about the
## child's progress. A registered mini-game that has not been built yet shows in
## the village as under construction rather than as a door that leads nowhere.
static func is_mini_game_available(game_id: String) -> bool:
	var scene: String = String(get_mini_game(game_id).get("scene", ""))
	return not scene.is_empty() and ResourceLoader.exists(scene)


## Mini-game ids in hub display order.
static func get_mini_game_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key: String in _mini_games:
		ids.append(key)
	ids.sort_custom(_compare_mini_game_order)
	return ids


static func _compare_mini_game_order(a: String, b: String) -> bool:
	var order_a: int = int((_mini_games[a] as Dictionary).get("order", 99))
	var order_b: int = int((_mini_games[b] as Dictionary).get("order", 99))
	if order_a == order_b:
		return a < b
	return order_a < order_b


# ---------------------------------------------------------------- levels

## 1-based, clamped into range. Out-of-range input returns the nearest valid level
## rather than nothing, so progression can never dead-end.
static func get_level(game_id: String, level_index: int) -> Dictionary:
	var levels: Array = get_levels(game_id)
	if levels.is_empty():
		Log.e("No levels defined for: %s" % game_id, "ContentDB")
		return {}
	var clamped: int = clampi(level_index, 1, levels.size())
	return levels[clamped - 1] as Dictionary


static func get_levels(game_id: String) -> Array:
	_ensure_levels(game_id)
	var file: Dictionary = _level_files.get(game_id, {}) as Dictionary
	return file.get("levels", []) as Array


## Any other top-level block in a level file: the Warung's customer roster, the
## Dapur's dish definitions. Keeps one file per mini-game instead of scattering
## its content across several.
static func get_level_data(game_id: String, key: String, fallback: Variant = null) -> Variant:
	_ensure_levels(game_id)
	var file: Dictionary = _level_files.get(game_id, {}) as Dictionary
	return file.get(key, fallback)


static func get_level_count(game_id: String) -> int:
	return get_levels(game_id).size()


## Highest level the child can actually reach today. Caps at MAX_PLAYABLE_LEVEL so
## that levels defined ahead of their implementation are never handed to a child.
static func get_max_playable_level(game_id: String) -> int:
	return mini(get_level_count(game_id), MAX_PLAYABLE_LEVEL)


# ---------------------------------------------------------------- voice

static func get_voice_manifest() -> Dictionary:
	_ensure_loaded()
	return _voice_manifest


# ---------------------------------------------------------------- loading

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_items()
	_load_mini_games()
	_load_voice_manifest()


static func _load_items() -> void:
	var raw: Dictionary = JsonLoader.load_dict(ITEMS_PATH)
	var source: Dictionary = raw.get("items", {}) as Dictionary
	if source.is_empty():
		Log.e("items.json missing or empty, falling back to a minimal item set", "ContentDB")
		_items = _fallback_items()
		return

	for item_id: String in source:
		var entry: Dictionary = source[item_id] as Dictionary
		var missing: Array[String] = JsonLoader.missing_keys(entry, _REQUIRED_ITEM_KEYS)
		if not missing.is_empty():
			Log.e("Item %s missing required keys %s, skipped" % [item_id, missing], "ContentDB")
			continue
		_items[item_id] = entry

	if _items.is_empty():
		_items = _fallback_items()


static func _load_mini_games() -> void:
	var raw: Dictionary = JsonLoader.load_dict(MINI_GAMES_PATH)
	var source: Dictionary = raw.get("mini_games", {}) as Dictionary
	for game_id: String in source:
		var entry: Dictionary = source[game_id] as Dictionary
		var missing: Array[String] = JsonLoader.missing_keys(entry, _REQUIRED_MINI_GAME_KEYS)
		if not missing.is_empty():
			Log.e("Mini-game %s missing required keys %s, skipped" % [game_id, missing], "ContentDB")
			continue
		_mini_games[game_id] = entry

	if _mini_games.is_empty():
		Log.e("minigames.json missing or empty, the hub will have no buildings", "ContentDB")


static func _load_voice_manifest() -> void:
	var raw: Dictionary = JsonLoader.load_dict(VOICE_MANIFEST_PATH)
	_voice_manifest = raw.get("voices", {}) as Dictionary
	if _voice_manifest.is_empty():
		Log.e("voice_manifest.json missing or empty, all voice lines will be silent", "ContentDB")


static func _ensure_levels(game_id: String) -> void:
	if _level_files.has(game_id):
		return
	var path: String = "%s%s.json" % [LEVELS_DIR, game_id]
	var raw: Dictionary = JsonLoader.load_dict(path)
	if (raw.get("levels", []) as Array).is_empty():
		Log.e("No levels in %s, using a single safe default level" % path, "ContentDB")
		raw["levels"] = [_fallback_level()]
	_level_files[game_id] = raw


static func _fallback_items() -> Dictionary:
	return {
		"pisang": {"display_name": "Pisang", "voice_id": "item_pisang", "category": "buah", "growable": true, "grow_stages": 3, "price": 2000},
		"apel": {"display_name": "Apel", "voice_id": "item_apel", "category": "buah", "growable": true, "grow_stages": 3, "price": 3000},
		"telur": {"display_name": "Telur", "voice_id": "item_telur", "category": "protein", "growable": false, "grow_stages": 0, "price": 2500},
		"roti": {"display_name": "Roti", "voice_id": "item_roti", "category": "makanan", "growable": false, "grow_stages": 0, "price": 5000},
	}


static func _fallback_level() -> Dictionary:
	return {
		"index": 1,
		"customers_per_session": 3,
		"item_types_per_order": 1,
		"quantity_range": [1, 3],
		"item_pool": ["pisang", "apel", "telur", "roti"],
		"money_enabled": false,
		"intro_voice_id": "",
	}
