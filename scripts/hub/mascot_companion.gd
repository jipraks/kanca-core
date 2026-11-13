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
## commission and PLAN.md now records the change. He went onto four legs on
## 2026-08-31, on the same authority.
##
## He has three poses, not a walk. The model is a supplied one (ASSETS.md) and
## arrives as one mesh per pose — idle, point and celebrate — which is three of
## the five §11.1 asks for and further than a procedural mascot ever got. What it
## costs is the trot: the poses are continuous remeshed shells with no separable
## legs, so `WalkCycle` has nothing to swing and he crosses the village without
## moving his feet. That is the trade, and it is the right way round for a
## companion who is stationary most of a session and expressive in the moments
## that matter.
##
## Still missing from §11.1: `walk`, `think`, and the four expressions.

## §7.1 caps idle chatter at one line per 45 seconds. Constant talking from a
## companion goes from charming to grating faster than anyone expects.
const MODEL := "res://assets/models/characters/kanca.glb"
const HEIGHT := 0.80

## The pose children inside that model. Named by the import script, which cut
## them out of one sheet — so they share a material and a texture, and swapping
## between them is two visibility flags rather than a load.
const POSE_IDLE := "idle"
const POSE_POINT := "point"
const POSE_CELEBRATE := "celebrate"

## How long a celebration is held before he settles back to idle.
const CELEBRATE_SECONDS := 4.0

## Above this, in metres per second, he is walking rather than standing — and a
## walking companion does not hold a pose.
const POINT_SPEED := 0.25

const IDLE_VOICE_INTERVAL := 45.0

## First line comes sooner than the steady-state interval, so arriving in the
## village is not silent.
const FIRST_IDLE_DELAY := 8.0

const FOLLOW_DISTANCE := 2.0
const CATCH_UP_DISTANCE := 3.4
const SPEED := 4.6
const TURN_SHARPNESS := 8.0

## Breathing, in metres. A twentieth of what the old floating bob was: a mascot
## who hovers is a balloon, and with no walk cycle left this is the only thing
## moving while he stands there.
const BREATH_HEIGHT := 0.007
const BREATH_SECONDS := 3.1

## How far above and below himself he looks for the floor, in metres. Generous:
## the village rises and falls by a third of a metre and he can be caught halfway
## up the step of a market stall.
const GROUND_PROBE := 3.0

@export var target: Node3D = null

var _visual: Node3D = null
var _idle_timer: Timer = null
var _poses: Dictionary = {}
var _pose: String = POSE_IDLE
var _celebrate_left: float = 0.0
var _elapsed: float = 0.0
var _speed: float = 0.0
var _point_at: Vector3 = Vector3.INF
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y

	_visual = ModelKit.instantiate(MODEL)
	if _visual == null:
		_visual = PlaceholderFactory.build_character("kanca", Palette.SIGNATURE, HEIGHT)
	_visual.name = "Visual"
	add_child(_visual)
	_collect_poses()
	_show_pose(POSE_IDLE)

	_idle_timer = Timer.new()
	_idle_timer.name = "IdleVoice"
	_idle_timer.one_shot = false
	_idle_timer.wait_time = FIRST_IDLE_DELAY
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)
	_idle_timer.start()


func _physics_process(delta: float) -> void:
	_elapsed += delta

	var travelled: float = 0.0
	if target != null:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		var distance: float = to_target.length()

		# Hangs back until the child has genuinely walked off, so he is not
		# permanently shuffling on the spot.
		if distance > CATCH_UP_DISTANCE:
			var step: Vector3 = to_target.normalized() * SPEED * delta
			var remaining: float = distance - FOLLOW_DISTANCE
			step = step.limit_length(maxf(remaining, 0.0))
			global_position += step
			travelled = step.length()

	# Measured, not assumed. He spends most of a session inside the follow
	# distance doing nothing, and legs that swing at a nominal speed while the
	# animal is stationary are the thing everyone notices.
	_speed = travelled / maxf(delta, 1e-5)
	if _celebrate_left > 0.0:
		_celebrate_left -= delta
	_choose_pose()
	_stand()
	_face(delta)


## Points at the activity the child should try next. Passing Vector3.INF means
## "nothing in particular", and he simply faces the player again.
func point_at(world_position: Vector3) -> void:
	_point_at = world_position
	_choose_pose()


func clear_point() -> void:
	_point_at = Vector3.INF
	_choose_pose()


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


## How far the ground is above or below him, in metres.
##
## A ray rather than a sampler. He used to be told where the surface was by
## `VillageGround.Sampler`, which could answer from the noise function that drew
## it; the village is a supplied mesh now and nothing can answer that question
## except the mesh. He is a plain Node3D and not a physics body — he never
## collides with anything, he only has to stand on the floor — so one ray a frame
## is the whole cost.
func _ground_height() -> float:
	var world: World3D = get_world_3d()
	if world == null:
		return 0.0
	var from: Vector3 = global_position + Vector3.UP * GROUND_PROBE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * (GROUND_PROBE * 2.0))
	# Layer 1 is "world": the village and the buildings, not the child.
	query.collision_mask = 1
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return float((hit["position"] as Vector3).y) - global_position.y


## Puts him on the ground, breathing.
##
## The breath is a seventh of a centimetre and it is the only thing moving while
## he stands still. Without it a static mesh reads as a prop rather than an
## animal — and with the walk gone, this is the whole of his idle.
func _stand() -> void:
	if _visual == null:
		return
	_visual.position.y = _ground_height() \
		+ sin(_elapsed / BREATH_SECONDS * TAU) * BREATH_HEIGHT


## Finds the pose meshes the import script left inside the model.
func _collect_poses() -> void:
	for name: String in [POSE_IDLE, POSE_POINT, POSE_CELEBRATE]:
		var node: Node3D = _find_node(_visual, name)
		if node != null:
			_poses[name] = node


func _show_pose(pose: String) -> void:
	if _poses.is_empty():
		return
	_pose = pose if _poses.has(pose) else POSE_IDLE
	for name: String in _poses:
		(_poses[name] as Node3D).visible = name == _pose


## Which pose the moment calls for. Celebrating outranks pointing, pointing
## outranks standing about — and **walking outranks pointing**, because an
## outstretched arm held while catching up reads as a fixed prop being dragged
## along rather than as a gesture. He puts the arm down to run and puts it back
## up when he arrives, which is what makes it read as pointing at all.
func _choose_pose() -> void:
	var wanted: String = POSE_IDLE
	if _celebrate_left > 0.0:
		wanted = POSE_CELEBRATE
	elif _point_at != Vector3.INF and _speed < POINT_SPEED:
		wanted = POSE_POINT
	if wanted != _pose:
		_show_pose(wanted)


## Both arms up, for a few seconds, when the child has just finished something.
func celebrate() -> void:
	_celebrate_left = CELEBRATE_SECONDS
	_choose_pose()


## Which way he is turned: **at the child**, unless he is pointing at something.
##
## He tried facing his direction of travel for a while, on a misreading of what
## was wrong when he appeared to walk sideways. What was actually wrong was the
## model — it was exported facing backwards — and turning him to face his path
## was fixing the symptom of a different bug while breaking the thing a
## companion is for. He looks at the child. That is the whole character.
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


static func _find_node(root: Node, suffix: String) -> Node3D:
	if root.name.to_lower().ends_with(suffix):
		return root as Node3D
	for child: Node in root.get_children():
		var found: Node3D = _find_node(child, suffix)
		if found != null:
			return found
	return null


func _restart_idle_timer() -> void:
	if _idle_timer == null:
		return
	_idle_timer.wait_time = IDLE_VOICE_INTERVAL
	_idle_timer.start()
