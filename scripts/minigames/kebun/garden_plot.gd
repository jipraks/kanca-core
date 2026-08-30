class_name GardenPlot
extends Node3D

## One patch of soil (PLAN.md §8.2).
##
## The life cycle is the lesson: seed, then water, then three visible stages of
## growth, then fruit. Doing it out of order is never punished — the plot just
## does not respond and Kanca says what comes next.
##
## Growth takes six seconds, total. §3.4 is blunt about this: a child must never
## be made to wait in real time, so this is patience at a scale they can hold.

signal became_ready(plot: GardenPlot)

enum State { EMPTY, SEEDED, GROWING, READY, HARVESTED }

## Sizes derived from the camera, not chosen by eye. The Kebun view is
## orthographic at 60 degrees (see kebun.tscn), so one world unit is a fixed 90px
## and the depth axis is foreshortened by 0.866. That makes the §3.3 floor a
## straight calculation: a plot needs 1.45 units of width and 1.5 of depth to
## clear 120px, and 0.55 of clearance to keep 40px from its neighbour.
## tools/kebun_test.tscn measures the real projection and fails if this drifts.
const DROP_ZONE_SIZE := Vector3(1.45, 0.3, 1.5)
const HARVEST_TOUCH_SIZE := Vector3(1.4, 0.5, 1.45)
const SOIL_SIZE := Vector3(1.4, 0.18, 1.45)

const BED_MODEL := "res://assets/models/garden/plot_bed.glb"
const STAGE_MODELS: Array[String] = [
	"res://assets/models/garden/plant_sprout.glb",
	"res://assets/models/garden/plant_young.glb",
	"res://assets/models/garden/plant_grown.glb",
]

var index: int = 0
var item_id: String = ""
var required_item_id: String = ""

var _state: int = State.EMPTY
var _grow_seconds: float = 6.0
var _stages: int = 3

var _soil: Node3D = null
var _mound: MeshInstance3D = null
var _plant: Node3D = null
var _stage_visuals: Array[Node3D] = []
var _fruit: Node3D = null
var _requirement_label: Sprite3D = null
var _drop_zone: DropTarget = null
var _harvest_target: TapTarget = null
var _grow_tween: Tween = null


func setup(plot_index: int, grow_seconds: float, stages: int, required: String = "") -> void:
	index = plot_index
	name = "Plot%d" % plot_index
	_grow_seconds = maxf(grow_seconds, 0.5)
	_stages = maxi(stages, 1)
	required_item_id = required

	_build_soil()
	_build_zones()

	if not required_item_id.is_empty():
		_build_requirement_label()


# ---------------------------------------------------------------- queries

func get_state() -> int:
	return _state


func can_plant() -> bool:
	return _state == State.EMPTY


func needs_water() -> bool:
	return _state == State.SEEDED


func is_ready() -> bool:
	return _state == State.READY


func is_finished() -> bool:
	return _state == State.HARVESTED


## Level 3 asks the child to match the seed to a labelled plot (§8.2). Until then
## every plot takes anything.
func accepts_seed(candidate_item_id: String) -> bool:
	if required_item_id.is_empty():
		return true
	return candidate_item_id == required_item_id


func get_drop_zone() -> DropTarget:
	return _drop_zone


func get_harvest_target() -> TapTarget:
	return _harvest_target


# ---------------------------------------------------------------- actions

func plant(planted_item_id: String) -> void:
	item_id = planted_item_id
	_state = State.SEEDED

	_mound.visible = true
	_mound.material_override = PlaceholderFactory.get_flat_material(Palette.SOIL.darkened(0.15))
	_mound.scale = Vector3.ZERO

	var tween: Tween = create_tween()
	tween.tween_property(_mound, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK)

	if _requirement_label != null:
		_requirement_label.visible = false

	SfxBank.play(SfxBank.POP, 0.85)


func water() -> void:
	if _state != State.SEEDED:
		return
	_state = State.GROWING

	# Soil darkens where the water landed. Cause and effect, visible immediately
	# — §8.2 lists that as a learning goal in its own right.
	_set_wet(true)
	SfxBank.play(SfxBank.WHOOSH, 1.3)

	_plant.visible = true
	_show_stage(1)

	var per_stage: float = _grow_seconds / float(_stages)
	_grow_tween = create_tween()
	for stage: int in range(2, _stages + 1):
		_grow_tween.tween_interval(per_stage)
		_grow_tween.tween_callback(_show_stage.bind(stage))
	_grow_tween.tween_interval(per_stage)
	_grow_tween.tween_callback(_become_ready)


## Returns what was picked, or an empty string if there was nothing to pick.
func harvest() -> String:
	if _state != State.READY:
		return ""

	_state = State.HARVESTED
	_harvest_target.set_tappable(false)

	var harvested: String = item_id
	SfxBank.play(SfxBank.CHIME)

	var tween: Tween = create_tween()
	tween.tween_property(_fruit, "scale", Vector3.ONE * 1.35, 0.1).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_fruit, "scale", Vector3.ZERO, 0.16)
	tween.parallel().tween_property(_plant, "scale", Vector3(0.7, 0.5, 0.7), 0.16)
	tween.tween_callback(_hide_fruit)

	return harvested


## Nudge for a plot that was asked to do something out of order. It stays exactly
## as it was — nothing is undone, nothing is lost (§3.2).
func nudge() -> void:
	var target: Node3D = _plant if _plant.visible else _soil
	var tween: Tween = create_tween()
	tween.tween_property(target, "scale", Vector3(1.12, 0.9, 1.12), 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(target, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- internals

## Shows the model for `stage`, counting from one.
##
## Levels may ask for more or fewer stages than there are models, so the stage is
## mapped across the models rather than indexed directly — four stages over three
## models means one of them is held for two beats, which still reads as growth.
func _show_stage(stage: int) -> void:
	if _stage_visuals.is_empty():
		return

	var progress: float = float(stage) / float(_stages)
	var index: int = clampi(int(ceilf(progress * float(_stage_visuals.size()))) - 1,
		0, _stage_visuals.size() - 1)

	for slot: int in range(_stage_visuals.size()):
		(_stage_visuals[slot] as Node3D).visible = slot == index

	var shown: Node3D = _stage_visuals[index] as Node3D
	shown.scale = Vector3.ONE

	# A little overshoot each time, so each stage reads as a distinct event
	# rather than a smooth slide a child might not notice.
	var tween: Tween = create_tween()
	tween.tween_property(shown, "scale", Vector3(1.18, 0.92, 1.18), 0.09).set_trans(Tween.TRANS_SINE)
	tween.tween_property(shown, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK)

	SfxBank.play(SfxBank.POP, 0.9 + 0.15 * float(stage))


func _become_ready() -> void:
	_state = State.READY

	_fruit = PlaceholderFactory.build_item_visual(item_id)
	_fruit.name = "Fruit"
	_fruit.position.y = SOIL_SIZE.y + 0.62
	_fruit.scale = Vector3.ZERO
	add_child(_fruit)

	var tween: Tween = create_tween()
	tween.tween_property(_fruit, "scale", Vector3.ONE * 1.25, 0.16).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_fruit, "scale", Vector3.ONE, 0.12)

	_harvest_target.set_tappable(true)
	SfxBank.play(SfxBank.CHIME, 1.15)
	became_ready.emit(self)


func _hide_fruit() -> void:
	if _fruit != null:
		_fruit.queue_free()
		_fruit = null
	_plant.visible = false
	_mound.visible = false
	_set_wet(false)


## Darkens the whole bed rather than repainting it.
##
## The bed is one baked material carrying wood *and* soil in its vertex colours,
## so overriding it with a flat brown would turn the frame into mud. Multiplying
## the albedo down keeps every colour and darkens all of them — which is also
## what water actually does to a wooden box full of earth.
func _set_wet(wet: bool) -> void:
	var shade: Color = Color(0.68, 0.66, 0.62) if wet else Color.WHITE
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_soil, meshes)
	for mesh: MeshInstance3D in meshes:
		for index: int in range(mesh.mesh.get_surface_count()):
			var source: BaseMaterial3D = mesh.mesh.surface_get_material(index) as BaseMaterial3D
			if source == null:
				continue
			var tinted: BaseMaterial3D = source.duplicate() as BaseMaterial3D
			tinted.albedo_color = shade
			mesh.set_surface_override_material(index, tinted)


static func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		into.append(mesh)
	for child: Node in node.get_children():
		_collect_meshes(child, into)


func _build_soil() -> void:
	_soil = _build_bed()
	_soil.name = "Soil"
	add_child(_soil)

	_mound = MeshInstance3D.new()
	_mound.name = "Mound"
	var mound_mesh: SphereMesh = SphereMesh.new()
	mound_mesh.radius = 0.18
	mound_mesh.height = 0.2
	mound_mesh.radial_segments = 10
	mound_mesh.rings = 4
	_mound.mesh = mound_mesh
	_mound.position.y = SOIL_SIZE.y
	_mound.visible = false
	_mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mound)

	# One node per growth stage, all built up front and shown one at a time.
	# Swapping whole models rather than scaling one is what makes a stage read as
	# an event: a seedling and a leafy bush are different shapes, and a child
	# watching a prism get taller is watching a prism get taller.
	_plant = Node3D.new()
	_plant.name = "Plant"
	_plant.position.y = SOIL_SIZE.y
	_plant.visible = false
	add_child(_plant)

	for path: String in STAGE_MODELS:
		var stage_visual: Node3D = ModelKit.instantiate(path)
		if stage_visual == null:
			stage_visual = _build_placeholder_plant(_stage_visuals.size())
		stage_visual.name = "Stage%d" % (_stage_visuals.size() + 1)
		stage_visual.visible = false
		_plant.add_child(stage_visual)
		_stage_visuals.append(stage_visual)


## The raised bed, or the old brown box when the model is missing (§10.5).
func _build_bed() -> Node3D:
	var bed: Node3D = ModelKit.instantiate(BED_MODEL)
	if bed != null:
		return bed

	var box_visual: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = SOIL_SIZE
	box_visual.mesh = box
	box_visual.material_override = PlaceholderFactory.get_flat_material(Palette.SOIL)
	box_visual.position.y = SOIL_SIZE.y * 0.5
	box_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return box_visual


func _build_placeholder_plant(index: int) -> Node3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	var height: float = lerpf(0.18, 0.72, float(index + 1) / float(STAGE_MODELS.size()))
	prism.size = Vector3(0.26, height, 0.2)
	visual.mesh = prism
	visual.material_override = PlaceholderFactory.get_flat_material(Palette.GRASS_DARK)
	visual.position.y = height * 0.5
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual


func _build_zones() -> void:
	_drop_zone = DropTarget.new()
	_drop_zone.name = "DropZone"
	add_child(_drop_zone)
	_drop_zone.add_zone_box(DROP_ZONE_SIZE, Vector3(0.0, DROP_ZONE_SIZE.y * 0.5, 0.0))

	_harvest_target = TapTarget.new()
	_harvest_target.name = "HarvestTarget"
	add_child(_harvest_target)
	_harvest_target.add_touch_box(HARVEST_TOUCH_SIZE, Vector3(0.0, 0.5, 0.0))
	_harvest_target.set_tappable(false)


## Level 3 only: a picture of the seed this plot wants (§8.2). A picture, never a
## word — the child cannot read (§3.1).
func _build_requirement_label() -> void:
	_requirement_label = Sprite3D.new()
	_requirement_label.name = "Requirement"
	_requirement_label.texture = PlaceholderFactory.build_item_icon(required_item_id, 128)
	_requirement_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_requirement_label.shaded = false
	_requirement_label.pixel_size = 0.003
	_requirement_label.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_requirement_label.position.y = 0.5
	add_child(_requirement_label)
