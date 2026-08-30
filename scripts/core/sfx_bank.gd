class_name SfxBank
extends RefCounted

## Sound effects, with synthesised placeholders (PLAN.md §3.3, §10.5).
##
## Every touch needs audible feedback inside 100ms. Waiting for a sound designer
## would mean building the whole game without it and discovering the timing
## problems late, so unrecorded effects are generated as short waveforms at first
## use. They are crude on purpose — nobody will mistake them for finished audio.
##
## A real file at res://assets/audio/sfx/<id>.ogg always wins, with no code change.

const SFX_DIR := "res://assets/audio/sfx/"
const MIX_RATE := 22050

const CLICK := "click"
const POP := "pop"
const COIN := "coin"
const SUCCESS := "success"
const GENTLE := "gentle"
const WHOOSH := "whoosh"
const CHIME := "chime"
const STEP := "step"

static var _cache: Dictionary = {}


## Plays a sound by id. Unknown ids are a no-op rather than an error, so a typo in
## a rarely-hit branch never becomes a crash in front of a child.
static func play(sfx_id: String, pitch: float = 1.0) -> void:
	var stream: AudioStream = get_stream(sfx_id)
	if stream == null:
		Log.w("Unknown sfx id: %s" % sfx_id, "SfxBank")
		return
	AudioManager.play_sfx(stream, pitch)


static func get_stream(sfx_id: String) -> AudioStream:
	if _cache.has(sfx_id):
		return _cache[sfx_id] as AudioStream

	var real_path: String = "%s%s.ogg" % [SFX_DIR, sfx_id]
	if ResourceLoader.exists(real_path):
		var loaded: AudioStream = load(real_path) as AudioStream
		if loaded != null:
			_cache[sfx_id] = loaded
			return loaded

	var generated: AudioStream = _synthesise(sfx_id)
	_cache[sfx_id] = generated
	return generated


## True while a sound is still a synthesised stand-in. Used by the asset checklist.
static func is_placeholder(sfx_id: String) -> bool:
	return not ResourceLoader.exists("%s%s.ogg" % [SFX_DIR, sfx_id])


static func get_all_ids() -> Array[String]:
	return [CLICK, POP, COIN, SUCCESS, GENTLE, WHOOSH, CHIME, STEP]


static func _synthesise(sfx_id: String) -> AudioStream:
	match sfx_id:
		CLICK:
			# Short, soft, unmistakably a button. Nothing sharp.
			return _tone(760.0, 620.0, 0.05, 42.0, 0.35)
		POP:
			return _tone(420.0, 900.0, 0.09, 26.0, 0.4)
		COIN:
			return _sequence([[988.0, 0.06], [1318.0, 0.14]], 0.4)
		SUCCESS:
			return _sequence([[523.0, 0.09], [659.0, 0.09], [784.0, 0.22]], 0.42)
		CHIME:
			return _sequence([[784.0, 0.10], [1046.0, 0.26]], 0.38)
		GENTLE:
			# The "not quite" sound. Falls a little, stays warm, never buzzes —
			# nothing in this app may sound like a scolding (§3.2).
			return _tone(430.0, 330.0, 0.22, 9.0, 0.3)
		WHOOSH:
			return _tone(240.0, 120.0, 0.18, 12.0, 0.22)
		STEP:
			# A footfall is broadband, not a note. A sine here comes out as a
			# little musical blip that pulls the ear straight to it — which is
			# the last thing a sound playing twice a second should do.
			return _thud(0.075, 0.12)
		_:
			return null


## Filtered noise with a fast decay: a soft footfall on earth.
##
## Deterministic, from a fixed seed, so the sound is byte-identical every run —
## a footstep that differs slightly each launch is a footstep that cannot be
## compared when someone reports it is too loud.
static func _thud(duration: float, volume: float) -> AudioStreamWAV:
	var sample_count: int = int(duration * float(MIX_RATE))
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	# A one-pole low-pass. White noise on its own is a hiss; rolled off this hard
	# it becomes a dull knock, which is what a foot on packed earth sounds like.
	var smoothed: float = 0.0
	const CUTOFF := 0.14

	for i: int in range(sample_count):
		var t: float = float(i) / float(MIX_RATE)
		smoothed += (rng.randf_range(-1.0, 1.0) - smoothed) * CUTOFF
		var envelope: float = exp(-46.0 * t) * _fade_in(t)
		var sample: float = smoothed * envelope * volume
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	return _wrap(data)


## One note with a pitch glide and an exponential decay.
static func _tone(freq_start: float, freq_end: float, duration: float, decay: float, volume: float) -> AudioStreamWAV:
	var sample_count: int = int(duration * float(MIX_RATE))
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)

	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / float(MIX_RATE)
		var progress: float = float(i) / float(maxi(sample_count - 1, 1))
		var frequency: float = lerpf(freq_start, freq_end, progress)
		phase += TAU * frequency / float(MIX_RATE)
		var envelope: float = exp(-decay * t) * _fade_in(t)
		var sample: float = sin(phase) * envelope * volume
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	return _wrap(data)


## Several notes back to back, for coin and success flourishes.
static func _sequence(notes: Array, volume: float) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()

	for note: Variant in notes:
		var note_array: Array = note as Array
		var frequency: float = float(note_array[0])
		var duration: float = float(note_array[1])
		var sample_count: int = int(duration * float(MIX_RATE))
		var offset: int = data.size()
		data.resize(offset + sample_count * 2)

		var phase: float = 0.0
		for i: int in range(sample_count):
			var t: float = float(i) / float(MIX_RATE)
			phase += TAU * frequency / float(MIX_RATE)
			var envelope: float = exp(-11.0 * t) * _fade_in(t)
			var sample: float = sin(phase) * envelope * volume
			data.encode_s16(offset + i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	return _wrap(data)


## A couple of milliseconds of ramp-up, so the waveform never starts on a step —
## a hard edge reads as a click on top of the sound.
static func _fade_in(t: float) -> float:
	const ATTACK := 0.004
	return minf(t / ATTACK, 1.0)


static func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
