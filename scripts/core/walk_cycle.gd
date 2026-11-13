class_name WalkCycle
extends RefCounted

## Swings a character's legs and reports when a foot lands.
##
## Two kinds of character reach this, and it drives both the same way.
##
## **Skinned.** A supplied model is one continuous shell, so it is bound to a
## three-bone skeleton by `kanca_build.rig_legs` — `root`, `leg_l`, `leg_r` — and
## the legs are posed. Cutting a leg out of a shell instead would leave a hole at
## the hip that opens every time it swings.
##
## **Jointed.** The characters `build_characters.py` builds carry their legs as
## separate child nodes with the pivot at the hip, named `<name>_leg_l` and
## `_leg_r`, and those are simply rotated. No skeleton, no animation player, no
## imported clips — the whole vocabulary a character sixty pixels tall needs, for
## a couple of draw calls instead of a rig.
##
## Owned by whoever is walking rather than being a node, because it holds one
## float and needs to be asked, not to run on its own.

## Radians at the top of the swing. Beyond about this the legs start to read as
## kicking rather than walking.
const MAX_SWING := 0.62

## How much of the swing survives at walking pace. Feeding raw speed in means a
## character nudged one step takes a full stride.
const SPEED_REFERENCE := 4.0

## Vertical bob, in metres, at full stride. Small: the body rises when a leg
## straightens, and overdoing it turns a walk into a bounce.
const BOB_HEIGHT := 0.035

## Strides per second at the reference speed.
const CADENCE := 2.15

var _body: Node3D = null
var _skeleton: Skeleton3D = null
var _legs: Array[Dictionary] = []
var _phase: float = 0.0
var _base_y: float = 0.0


## `root` is an instantiated character model.
func _init(root: Node3D) -> void:
	_body = root
	if root == null:
		return
	_base_y = root.position.y

	_skeleton = _find_skeleton(root)
	if _skeleton != null and _bind_bones():
		return
	_skeleton = null
	_bind_nodes(root)


## Where standing height is, before the bob is added.
##
## Whoever owns this puts the character on the ground and the cycle keeps the
## pen: two things writing to one `position.y` is how a walk turns into a
## stutter.
func set_base_height(y: float) -> void:
	_base_y = y


## True when the model actually has legs to swing. A character still using the
## generated stand-in does not, and every caller has to cope with that rather
## than assume the model is there (§10.5).
func has_legs() -> bool:
	return not _legs.is_empty()


## Advances the cycle and returns true on the frames a foot lands.
##
## `speed` is metres per second. Passing zero eases the legs back to standing
## rather than freezing them mid-stride, which is what makes stopping look like
## stopping instead of like a dropped frame.
func advance(delta: float, speed: float) -> bool:
	if not has_legs():
		# Still has to be put on the ground. A character on the generated
		# stand-in cannot step, but it can sink.
		if _body != null:
			_body.position.y = _base_y
		return false

	var pace: float = clampf(speed / SPEED_REFERENCE, 0.0, 1.4)
	if pace < 0.05:
		_settle(delta)
		return false

	var previous: float = _phase
	_phase = fposmod(_phase + delta * CADENCE * TAU * pace, TAU)

	for leg: Dictionary in _legs:
		_swing(leg, sin(_phase + float(leg["offset"])) * MAX_SWING * pace)

	if _body != null:
		# Twice the stride frequency: the body rises on each leg, not each cycle.
		_body.position.y = _base_y + absf(sin(_phase)) * BOB_HEIGHT * pace

	# A foot plants at each half turn, where its swing passes through zero.
	return _crossed_half_turn(previous, _phase)


## Eases back to standing. Nothing here rotates instantly: a leg snapping to
## vertical the frame a child lifts their thumb reads as a glitch.
func _settle(delta: float) -> void:
	var weight: float = 1.0 - exp(-12.0 * delta)
	for leg: Dictionary in _legs:
		var held: float = lerpf(float(leg["angle"]), 0.0, weight)
		_swing(leg, held)
	if _body != null:
		_body.position.y = lerpf(_body.position.y, _base_y, weight)
	_phase = lerpf(_phase, 0.0, weight) if _phase < PI else lerpf(_phase, TAU, weight)


## Turns one leg by `angle` radians about the axis bound for it.
##
## The pose is composed onto the **rest**, not written over it. A bone's pose in
## Godot is its whole local transform, initialised to the rest — not a delta from
## it, whatever "pose" suggests. Setting the rotation alone therefore throws the
## rest's own orientation away, and since these bones point down the leg, that
## stood both of them on end: the legs swung up over the child's head and the
## body between them collapsed. Rest first, rotation after.
func _swing(leg: Dictionary, angle: float) -> void:
	leg["angle"] = angle
	if _skeleton != null:
		var index: int = int(leg["bone"])
		var posed: Transform3D = (leg["rest"] as Transform3D) 			* Transform3D(Basis(leg["axis"] as Vector3, angle), Vector3.ZERO)
		_skeleton.set_bone_pose_position(index, posed.origin)
		_skeleton.set_bone_pose_rotation(index, posed.basis.get_rotation_quaternion())
		return
	(leg["node"] as Node3D).rotation.x = angle


# ---------------------------------------------------------------- binding

func _bind_bones() -> bool:
	# Every pose starts at the rest, explicitly.
	#
	# Godot keeps a bone's pose as position, rotation and scale *separate* from
	# its rest, and until something sets them the position component is zero
	# rather than the rest's. Setting only the rotation therefore does two
	# things: it turns the bone, and it silently moves it to the skeleton's
	# origin. Here that dropped both legs half a metre, under the floor, and what
	# was left on screen was a child's head lying on the grass.
	_skeleton.reset_bone_poses()

	for name: String in ["leg_l", "leg_r"]:
		var index: int = _skeleton.find_bone(name)
		if index < 0:
			_legs.clear()
			return false
		_legs.append({
			"bone": index,
			# The whole rest transform, because the pose replaces it rather than
			# adding to it. Keeping only the origin was the first attempt and it
			# lost the bone's orientation.
			"rest": _skeleton.get_bone_rest(index),
			# World X, expressed in the bone's own space, rather than assumed to
			# be its local X. Which way a bone's space is turned depends on how
			# the exporter chose to orient it — guessing gives a leg that swings
			# sideways, and the guess differs for every model anybody supplies.
			"axis": _rest_axis(index, Vector3.RIGHT),
			"offset": 0.0 if name == "leg_l" else PI,
			"angle": 0.0,
		})
	return true


## The direction, in a bone's rest space, that points along `world_axis`.
func _rest_axis(index: int, world_axis: Vector3) -> Vector3:
	var rest: Transform3D = _skeleton.get_bone_global_rest(index)
	var axis: Vector3 = rest.basis.inverse() * world_axis
	if axis.length_squared() < 1e-6:
		return Vector3.RIGHT
	return axis.normalized()


func _bind_nodes(root: Node3D) -> void:
	for name: String in ["_leg_l", "_leg_r"]:
		var node: Node3D = _find_leg(root, name)
		if node == null:
			_legs.clear()
			return
		_legs.append({
			"node": node,
			"offset": 0.0 if name == "_leg_l" else PI,
			"angle": 0.0,
		})


static func _find_skeleton(node: Node) -> Skeleton3D:
	var skeleton: Skeleton3D = node as Skeleton3D
	if skeleton != null:
		return skeleton
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


static func _crossed_half_turn(from: float, to: float) -> bool:
	if to < from:
		# Wrapped past TAU, which is also a crossing of zero.
		return true
	return from < PI and to >= PI


static func _find_leg(node: Node, suffix: String) -> Node3D:
	if node.name.to_lower().ends_with(suffix):
		return node as Node3D
	for child: Node in node.get_children():
		var found: Node3D = _find_leg(child, suffix)
		if found != null:
			return found
	return null
