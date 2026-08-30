extends Node

## Resolves logical voice IDs to audio, and assembles composed lines (PLAN.md §10).
##
## Reads data/voice_manifest.json and nothing else — it never scans the filesystem,
## so a file that exists but is not in the manifest simply does not exist as far as
## the game is concerned (§10.2).
##
## Playback itself belongs to AudioManager. This class decides *what* plays.

signal voice_requested(voice_id: String)
signal missing_recording(voice_id: String)

## The gap that makes concatenated clips sound like a sentence rather than a
## machine reading a list. Do not remove it as an optimisation (§10.3).
const COMPOSED_GAP_SECONDS := 0.09

## Used when the manifest entry has no duration and the file is missing.
const DEFAULT_PLACEHOLDER_DURATION := 0.9

## Fallback connector inserted between item groups in a multi-item order (§10.3).
## Each customer variant has its own ("cust_ibu_and"), so callers normally pass
## theirs — the same word in a different voice mid-sentence is jarring.
const CONNECTOR_VOICE_ID := "cust_and"

var _entries: Dictionary = {}
var _stream_cache: Dictionary = {}

## voice_id -> remaining variant indices for this cycle. Shuffled, drained, then
## reshuffled — a child hears dozens of rounds and identical praise every time
## makes the app feel mechanical (§10.4).
var _variant_bags: Dictionary = {}
var _last_variant: Dictionary = {}

## Voice IDs asked for at least once this run, whether or not a recording existed.
## Feeds tools/check_voice_coverage.gd.
var _requested_ids: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_entries = ContentDB.get_voice_manifest()
	Log.i("Voice manifest loaded: %d entries" % _entries.size(), "VoiceBank")


# ---------------------------------------------------------------- playback

## Plays one line. Returns the resolved variant index, or -1 when the ID is unknown.
func play(voice_id: String, gap_after: float = 0.0) -> int:
	if voice_id.is_empty():
		return -1

	_requested_ids[voice_id] = true
	voice_requested.emit(voice_id)

	if not _entries.has(voice_id):
		Log.w("Voice ID not in manifest: %s" % voice_id, "VoiceBank")
		return -1

	var variant: int = _next_variant(voice_id)
	var path: String = resolve_path(voice_id, variant)
	var stream: AudioStream = _load_stream(path)

	if stream == null:
		missing_recording.emit(voice_id)

	AudioManager.enqueue_voice(stream, voice_id, gap_after, get_duration(voice_id))
	return variant


## Plays several clips back to back as one sentence. Any part missing from the
## manifest is skipped with a warning rather than failing the whole line (§10.3).
func play_composed(parts: Array[String]) -> void:
	var playable: Array[String] = []
	for part: String in parts:
		if part.is_empty():
			continue
		if not _entries.has(part):
			Log.w("Skipping unknown part in composed line: %s" % part, "VoiceBank")
			continue
		playable.append(part)

	if playable.is_empty():
		Log.w("Composed line had no playable parts", "VoiceBank")
		return

	for i: int in range(playable.size()):
		var is_last: bool = i == playable.size() - 1
		play(playable[i], 0.0 if is_last else COMPOSED_GAP_SECONDS)


## Replays a line from the start. This is what the order card's tap-to-repeat does,
## so it must cut whatever is currently speaking (§10.3, §8.1.4).
func replay_composed(parts: Array[String]) -> void:
	AudioManager.clear_voice_queue()
	play_composed(parts)


func stop_all() -> void:
	AudioManager.clear_voice_queue()


## Flattens item groups into one part list, inserting the connector between them:
##   [[num_3, item_pisang], [num_1, item_roti]] with "cust_ibu_and"
##   -> [num_3, item_pisang, cust_ibu_and, num_1, item_roti]
func join_groups(groups: Array, connector: String = CONNECTOR_VOICE_ID) -> Array[String]:
	var parts: Array[String] = []
	for i: int in range(groups.size()):
		if i > 0 and not connector.is_empty():
			parts.append(connector)
		for part: String in (groups[i] as Array):
			parts.append(part)
	return parts


# ---------------------------------------------------------------- resolution

func has_entry(voice_id: String) -> bool:
	return _entries.has(voice_id)


## True when an actual recording exists on disk for at least one variant.
func has_recording(voice_id: String) -> bool:
	if not _entries.has(voice_id):
		return false
	var count: int = get_variant_count(voice_id)
	for variant: int in range(count):
		if ResourceLoader.exists(resolve_path(voice_id, variant)):
			return true
	return false


## Naming convention from §10.2: a single-variant line has no numeric suffix,
## a multi-variant line is suffixed _01, _02, ...
func resolve_path(voice_id: String, variant: int) -> String:
	var entry: Dictionary = _entries.get(voice_id, {}) as Dictionary
	var base: String = String(entry.get("base", ""))
	if base.is_empty():
		return ""
	if get_variant_count(voice_id) <= 1:
		return "%s.ogg" % base
	return "%s_%02d.ogg" % [base, variant + 1]


func get_variant_count(voice_id: String) -> int:
	var entry: Dictionary = _entries.get(voice_id, {}) as Dictionary
	return maxi(1, int(entry.get("variants", 1)))


func get_duration(voice_id: String) -> float:
	var entry: Dictionary = _entries.get(voice_id, {}) as Dictionary
	return maxf(float(entry.get("duration", DEFAULT_PLACEHOLDER_DURATION)), 0.05)


## The Indonesian line as written. Used by the dubbing script generator, and by
## the debug overlay — never rendered to the child as instruction (§3.1).
func get_text(voice_id: String) -> String:
	var entry: Dictionary = _entries.get(voice_id, {}) as Dictionary
	return String(entry.get("text", ""))


func get_all_voice_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _entries:
		ids.append(key)
	ids.sort()
	return ids


## Manifest entries that still have no recording. Drives the coverage tool (§10.5).
func get_missing_recordings() -> Array[String]:
	var missing: Array[String] = []
	for voice_id: String in get_all_voice_ids():
		if not has_recording(voice_id):
			missing.append(voice_id)
	return missing


func get_requested_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _requested_ids:
		ids.append(key)
	ids.sort()
	return ids


# ---------------------------------------------------------------- internals

func _next_variant(voice_id: String) -> int:
	var count: int = get_variant_count(voice_id)
	if count <= 1:
		return 0

	var bag: Array = _variant_bags.get(voice_id, []) as Array
	if bag.is_empty():
		bag = []
		for i: int in range(count):
			bag.append(i)
		bag.shuffle()
		# Reshuffling can put the just-played variant first, which is exactly the
		# immediate repetition the shuffle exists to avoid.
		if bag.size() > 1 and int(bag[0]) == int(_last_variant.get(voice_id, -1)):
			var moved: Variant = bag.pop_front()
			bag.append(moved)

	var variant: int = int(bag.pop_front())
	_variant_bags[voice_id] = bag
	_last_variant[voice_id] = variant
	return variant


func _load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		_stream_cache[path] = null
		return null

	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		Log.w("Voice file exists but did not load as audio: %s" % path, "VoiceBank")
	_stream_cache[path] = stream
	return stream
