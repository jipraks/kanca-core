class_name MascotCompanion
extends Node3D

## Kanca walking alongside the child in the village (PLAN.md §7.1).
##
## He is a companion, not the player character — he never blocks, never has to be
## waited for, and never gets in the way. He idles nearby, occasionally says
## something, and points at whatever is worth doing next.
##
## The model is built by tools/blender/build_characters.py, on the project
## owner's instruction of 2026-08-30 — §16.2 previously reserved his design for a
## commission and PLAN.md now records the change.
##
## He still has no rig, no animations and no expressions. §11.1 asks for idle,
## walk, point, celebrate and think, plus four faces; what exists is a static
## mesh bobbed and turned by code. Pointing is a rotation, not a gesture.

## §7.1 caps idle chatter at one line per 45 seconds. Constant talking from a
## companion goes from charming to grating faster than anyone expects.
const MODEL := "res://assets/models/characters/kanca.glb"
const HEIGHT := 0.85

const IDLE_VOICE_INTERVAL := 45.0

## First line comes sooner than the steady-state interval, so arriving in the
## village is not silent.
const FIRST_IDLE_DELAY := 8.0

const FOLLOW_DISTANCE := 2.0
const CATCH_UP_DISTANCE := 3.4
const SPEED := 4.6
const TURN_SHARPNESS := 8.0
const BOB_HEIGHT := 0.05
const BOB_SECONDS := 1.1

@export var target: Node3D = null

var _visual: Node3D = null
var _idle_timer: Timer = null
var _elapsed: float = 0.0
var _point_at: Vector3 = Vector3.INF
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y

	_visual = ModelKit.instantiate(MODEL)
	if _visual == null:
		_visual = PlaceholderFactory.build_character("kanca", Palette.SIGNATURE, HEIGHT)
	_visual.name = "Visual"
	add_child(_visual)

	_idle_timer = Timer.new()
	_idle_timer.name = "IdleVoice"
	_idle_timer.one_shot = false
	_idle_timer.wait_time = FIRST_IDLE_DELAY
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)
	_idle_timer.start()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_bob()

	if target == null:
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	# Hangs back until the child has genuinely walked off, so he is not
	# permanently shuffling on the spot.
	if distance > CATCH_UP_DISTANCE:
		var step: Vector3 = to_target.normalized() * SPEED * delta
		var remaining: float = distance - FOLLOW_DISTANCE
		global_position += step.limit_length(maxf(remaining, 0.0))

	_face(delta)


## Points at the activity the child should try next. Passing Vector3.INF means
## "nothing in particular", and he simply faces the player again.
func point_at(world_position: Vector3) -> void:
	_point_at = world_position


func clear_point() -> void:
	_point_at = Vector3.INF


## Said once when the village loads, outside the idle rate limit.
func greet() -> void:
	VoiceBank.play("kanca_welcome")
	_restart_idle_timer()


## Suppresses idle chatter while something more important is speaking.
func pause_idle_chatter() -> void:
	if _idle_timer != null:
		_idle_timer.stop()


func resume_idle_chatter() -> void:
	_restart_idle_timer()


func _bob() -> void:
	if _visual == null:
		return
	_visual.position.y = sin(_elapsed / BOB_SECONDS * TAU) * BOB_HEIGHT


func _face(delta: float) -> void:
	if _visual == null:
		return

	var look_at_position: Vector3 = _point_at
	if look_at_position == Vector3.INF:
		if target == null:
			return
		look_at_position = target.global_position

	var to_look: Vector3 = look_at_position - global_position
	to_look.y = 0.0
	if to_look.length_squared() < 0.01:
		return

	var desired: float = Facing.angle_towards(to_look)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, desired, 1.0 - exp(-TURN_SHARPNESS * delta))


func _on_idle_timeout() -> void:
	# Never talk over something else — voice is a queue, and a companion barging
	# into an instruction is worse than silence (§3.5).
	if AudioManager.is_voice_playing():
		return
	VoiceBank.play("kanca_hub_idle")
	_restart_idle_timer()


func _restart_idle_timer() -> void:
	if _idle_timer == null:
		return
	_idle_timer.wait_time = IDLE_VOICE_INTERVAL
	_idle_timer.start()
