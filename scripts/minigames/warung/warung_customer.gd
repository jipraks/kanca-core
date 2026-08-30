class_name WarungCustomer
extends Node3D

## A customer at the warung counter (PLAN.md §8.1).
##
## Three visual variants with matching voice sets, defined in
## data/levels/warung.json. The customer is never annoyed and never disappointed:
## a wrong order gets a puzzled "hmm, I don't think that's it", and the child
## simply carries on (§3.2).

const MODEL_DIR := "res://assets/models/characters/"

const WALK_SECONDS := 1.1
const WAVE_SECONDS := 0.45

var variant_id: String = ""
var voice_prefix: String = ""

var _visual: Node3D = null
var _walk: WalkCycle = null
var _height: float = 1.3
var _walking: bool = false
var _last_position: Vector3 = Vector3.ZERO


func setup(config: Dictionary) -> void:
	variant_id = String(config.get("id", "anak"))
	voice_prefix = String(config.get("voice_prefix", "cust_%s" % variant_id))
	_height = float(config.get("height", 1.3))
	name = "Customer_%s" % variant_id

	_visual = _build_visual(config)
	_visual.name = "Visual"
	add_child(_visual)
	_walk = WalkCycle.new(_visual)


## The built model if there is one, otherwise the generated stand-in in the
## roster's colour (§10.5).
##
## The model path is derived from the variant id rather than written into
## data/levels/warung.json. A fourth customer added to the roster looks for a
## fourth model without anyone editing two files, and gets a coloured stand-in
## until it exists.
func _build_visual(config: Dictionary) -> Node3D:
	var model: Node3D = ModelKit.instantiate(MODEL_DIR + "cust_%s.glb" % variant_id)
	if model != null:
		return model

	var colour: Color = Color(String(config.get("colour", "cccccc")))
	return PlaceholderFactory.build_character("customer_%s" % variant_id, colour, _height)


## The legs swing while the tween carries the body across. Measured from where
## the customer actually got to, not from the tween's own progress: the tween
## eases, and legs at a constant cadence under an easing body read as skating.
func _process(delta: float) -> void:
	if _walk == null or not _walk.has_legs():
		return
	var travelled: float = 0.0
	if _walking and delta > 0.0:
		travelled = global_position.distance_to(_last_position) / delta
	_last_position = global_position
	if _walk.advance(delta, travelled if _walking else 0.0):
		SfxBank.play(SfxBank.STEP, randf_range(0.90, 1.02))


## Walks in from the side and waves (§8.1, step 1).
func walk_in(from_position: Vector3, to_position: Vector3) -> void:
	position = from_position
	_face_counter()

	var tween: Tween = create_tween()
	tween.tween_property(self, "position", to_position, WALK_SECONDS).set_trans(Tween.TRANS_SINE)
	_add_walk_bob(tween)
	_walking = true
	await tween.finished
	_walking = false

	await wave()


func walk_out(to_position: Vector3) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", to_position, WALK_SECONDS).set_trans(Tween.TRANS_SINE)
	_add_walk_bob(tween)
	await tween.finished


func wave() -> void:
	if _visual == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_visual, "rotation:z", deg_to_rad(9.0), WAVE_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_visual, "rotation:z", 0.0, WAVE_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)
	await tween.finished


func speak_greeting() -> void:
	VoiceBank.play("%s_greet" % voice_prefix)


func speak_order(order: WarungOrder) -> void:
	VoiceBank.play_composed(order.to_voice_parts())


func repeat_order(order: WarungOrder) -> void:
	VoiceBank.replay_composed(order.to_voice_parts())


func react_happy() -> void:
	VoiceBank.play("%s_happy" % voice_prefix)
	_hop()


## Puzzled, never cross. Nothing in this app scolds (§3.2).
func react_confused() -> void:
	VoiceBank.play("%s_confused" % voice_prefix)
	_tilt()


func speak_farewell() -> void:
	VoiceBank.play("%s_bye" % voice_prefix)


## The counter, and the camera behind it, are at +Z from where a customer stands.
## A model faces -Z by default, so leaving this at zero had every customer
## standing with their back to the child.
func _face_counter() -> void:
	if _visual != null:
		_visual.rotation.y = Facing.angle_towards(Vector3.BACK)


func _add_walk_bob(tween: Tween) -> void:
	if _visual == null:
		return
	var bob: Tween = create_tween().set_loops(int(WALK_SECONDS / 0.28) + 1)
	bob.tween_property(_visual, "position:y", 0.06, 0.14).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_visual, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_SINE)


func _hop() -> void:
	if _visual == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_visual, "position:y", 0.22, 0.16).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_visual, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE)


func _tilt() -> void:
	if _visual == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_visual, "rotation:z", deg_to_rad(11.0), 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_visual, "rotation:z", 0.0, 0.28).set_trans(Tween.TRANS_SINE)
