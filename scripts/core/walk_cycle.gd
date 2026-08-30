class_name WalkCycle
extends RefCounted

## Swings a character's legs and reports when a foot lands.
##
## The models built by `tools/blender/build_characters.py` carry their legs as
## separate child nodes with the pivot at the hip, so a walk is two rotations
## about X and nothing else — no skeleton, no animation player, no imported
## clips. That is the whole vocabulary a character sixty pixels tall needs, and
## it costs two draw calls instead of a rig.
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

var _left: Node3D = null
var _right: Node3D = null
var _body: Node3D = null
var _phase: float = 0.0
var _base_y: float = 0.0


## `root` is an instantiated character model. Legs are found by name, matching
## the `<name>_leg_l` / `<name>_leg_r` the build script writes.
func _init(root: Node3D) -> void:
	_body = root
	if root == null:
		return
	_base_y = root.position.y
	_left = _find_leg(root, "_leg_l")
	_right = _find_leg(root, "_leg_r")


## True when the model actually has legs to swing. A character still using the
## generated stand-in does not, and every caller has to cope with that rather
## than assume the model is there (§10.5).
func has_legs() -> bool:
	return _left != null and _right != null


## Advances the cycle and returns true on the frames a foot lands.
##
## `speed` is metres per second. Passing zero eases the legs back to standing
## rather than freezing them mid-stride, which is what makes stopping look like
## stopping instead of like a dropped frame.
func advance(delta: float, speed: float) -> bool:
	if not has_legs():
		return false

	var pace: float = clampf(speed / SPEED_REFERENCE, 0.0, 1.4)
	if pace < 0.05:
		_settle(delta)
		return false

	var previous: float = _phase
	_phase = fposmod(_phase + delta * CADENCE * TAU * pace, TAU)

	var swing: float = sin(_phase) * MAX_SWING * pace
	_left.rotation.x = swing
	_right.rotation.x = -swing
	if _body != null:
		# Twice the stride frequency: the body rises on each leg, not each cycle.
		_body.position.y = _base_y + absf(sin(_phase)) * BOB_HEIGHT * pace

	# A foot plants at each half turn, where its swing passes through zero.
	return _crossed_half_turn(previous, _phase)


## Eases back to standing. Nothing here rotates instantly: a leg snapping to
## vertical the frame a child lifts their thumb reads as a glitch.
func _settle(delta: float) -> void:
	var weight: float = 1.0 - exp(-12.0 * delta)
	_left.rotation.x = lerpf(_left.rotation.x, 0.0, weight)
	_right.rotation.x = lerpf(_right.rotation.x, 0.0, weight)
	if _body != null:
		_body.position.y = lerpf(_body.position.y, _base_y, weight)
	_phase = lerpf(_phase, 0.0, weight) if _phase < PI else lerpf(_phase, TAU, weight)


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
