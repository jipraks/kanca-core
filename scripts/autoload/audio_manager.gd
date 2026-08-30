extends Node

## Owns the three audio buses and the voice queue (PLAN.md §6.1, §3.5).
##
## Two rules drive the whole design:
##   1. Never play two voice lines at once. Voice is a queue, not fire-and-forget.
##   2. Music ducks to ~30% while a voice line plays, and comes back after.
##
## The queue also accepts entries with a null stream and a duration. That is how
## an unrecorded line behaves during development: the timing, the queueing, the
## ducking and the gap between composed clips are all exercised for real, without
## a single recorded file (§10.5).

signal voice_started(voice_id: String)
signal voice_finished(voice_id: String)
signal voice_queue_emptied()

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const VOICE_BUS := "Voice"

## 30% of the music volume while a voice line plays (§3.5).
const DUCK_LINEAR := 0.3
const DUCK_FADE_SECONDS := 0.15
const MUSIC_FADE_SECONDS := 0.6

## Enough for the busiest moment (several items dropping plus a coin flourish).
const SFX_POOL_SIZE := 8

const SILENCE_DB := -80.0

var _music_player: AudioStreamPlayer = null
var _voice_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0

var _voice_queue: Array[Dictionary] = []
var _queue_running: bool = false

## Bumped whenever the queue is cleared, so an in-flight coroutine can tell that
## it is stale and bail out instead of resuming over the top of a new line.
var _generation: int = 0

var _music_volume_linear: float = 0.7
var _is_ducked: bool = false
var _duck_tween: Tween = null


func _ready() -> void:
	# Voice must keep flowing while the tree is paused, otherwise a line started
	# just before a pause menu opens would never finish and the queue would stall.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	_music_player.name = "MusicPlayer"
	add_child(_music_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = VOICE_BUS
	_voice_player.name = "VoicePlayer"
	add_child(_voice_player)

	for i: int in range(SFX_POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = SFX_BUS
		player.name = "SfxPlayer%d" % i
		add_child(player)
		_sfx_players.append(player)

	apply_volume_settings()


# ---------------------------------------------------------------- voice

## Appends one clip to the voice queue. A null stream is played as `duration`
## seconds of silence, which is how unrecorded lines behave (§10.5).
## `gap_after` is what makes composed lines sound like a sentence (§10.3).
func enqueue_voice(stream: AudioStream, voice_id: String, gap_after: float = 0.0, duration: float = 0.0) -> void:
	_voice_queue.append({
		"stream": stream,
		"voice_id": voice_id,
		"gap_after": maxf(gap_after, 0.0),
		"duration": maxf(duration, 0.0),
	})
	if not _queue_running:
		_run_queue()


## Cuts the current line and drops everything queued behind it. Used when the
## child re-taps the order card, or leaves for another screen (§10.3).
func clear_voice_queue() -> void:
	_generation += 1
	_voice_queue.clear()
	if _voice_player != null:
		_voice_player.stop()
	_queue_running = false
	_set_ducked(false)


func is_voice_playing() -> bool:
	return _queue_running


func get_queue_length() -> int:
	return _voice_queue.size()


func _run_queue() -> void:
	_queue_running = true
	var generation: int = _generation
	_set_ducked(true)

	while not _voice_queue.is_empty() and generation == _generation:
		var request: Dictionary = _voice_queue.pop_front()
		var voice_id: String = String(request["voice_id"])
		var stream: AudioStream = request["stream"] as AudioStream

		voice_started.emit(voice_id)

		if stream != null:
			_voice_player.stream = stream
			_voice_player.play()
			# Polled rather than awaiting `finished`, because stopping a player
			# does not emit it — awaiting would hang the queue forever on a cut.
			while _voice_player.playing and generation == _generation:
				await get_tree().process_frame
		else:
			Log.d("Voice placeholder: %s (%.2fs)" % [voice_id, request["duration"]], "AudioManager")
			await _wait(float(request["duration"]), generation)

		if generation != _generation:
			return

		voice_finished.emit(voice_id)
		await _wait(float(request["gap_after"]), generation)

	if generation != _generation:
		return

	_queue_running = false
	_set_ducked(false)
	voice_queue_emptied.emit()


## Frame-polled wait that a queue clear can interrupt.
func _wait(seconds: float, generation: int) -> void:
	if seconds <= 0.0:
		return
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and generation == _generation:
		await get_tree().process_frame


# ---------------------------------------------------------------- music

func play_music(stream: AudioStream, fade_in: bool = true) -> void:
	if stream == null:
		return
	if _music_player.stream == stream and _music_player.playing:
		return

	_music_player.stream = stream
	_music_player.volume_db = SILENCE_DB if fade_in else 0.0
	_music_player.play()

	if fade_in:
		var tween: Tween = create_tween()
		tween.tween_property(_music_player, "volume_db", 0.0, MUSIC_FADE_SECONDS)


func stop_music(fade_out: bool = true) -> void:
	if not _music_player.playing:
		return
	if not fade_out:
		_music_player.stop()
		return
	var tween: Tween = create_tween()
	tween.tween_property(_music_player, "volume_db", SILENCE_DB, MUSIC_FADE_SECONDS)
	tween.tween_callback(_music_player.stop)


# ---------------------------------------------------------------- sfx

## Every touch needs feedback inside 100ms (§3.3), so this never waits on a free
## player — it steals the oldest one rather than dropping the sound.
func play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func _next_sfx_player() -> AudioStreamPlayer:
	for i: int in range(_sfx_players.size()):
		var index: int = (_sfx_cursor + i) % _sfx_players.size()
		if not _sfx_players[index].playing:
			_sfx_cursor = (index + 1) % _sfx_players.size()
			return _sfx_players[index]

	var fallback: AudioStreamPlayer = _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return fallback


# ---------------------------------------------------------------- volume

func apply_volume_settings() -> void:
	_music_volume_linear = float(GameState.get_setting("music_volume", 0.7))
	set_bus_volume_linear(SFX_BUS, float(GameState.get_setting("sfx_volume", 1.0)))
	set_bus_volume_linear(VOICE_BUS, float(GameState.get_setting("voice_volume", 1.0)))
	_apply_music_volume(false)


func set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		Log.e("Audio bus not found: %s" % bus_name, "AudioManager")
		return
	var clamped: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, clamped <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, 0.001)))


func _set_ducked(ducked: bool) -> void:
	if _is_ducked == ducked:
		return
	_is_ducked = ducked
	_apply_music_volume(true)


func _apply_music_volume(animated: bool) -> void:
	var index: int = AudioServer.get_bus_index(MUSIC_BUS)
	if index < 0:
		Log.e("Audio bus not found: %s" % MUSIC_BUS, "AudioManager")
		return

	var target_linear: float = _music_volume_linear * (DUCK_LINEAR if _is_ducked else 1.0)
	AudioServer.set_bus_mute(index, _music_volume_linear <= 0.001)
	var target_db: float = linear_to_db(maxf(target_linear, 0.001))

	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()

	if not animated:
		AudioServer.set_bus_volume_db(index, target_db)
		return

	var start_db: float = AudioServer.get_bus_volume_db(index)
	_duck_tween = create_tween()
	_duck_tween.tween_method(
		func(value: float) -> void: AudioServer.set_bus_volume_db(index, value),
		start_db, target_db, DUCK_FADE_SECONDS)
