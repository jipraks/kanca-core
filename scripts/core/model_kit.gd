class_name ModelKit
extends RefCounted

## Loading a `.glb` the way this project needs it (PLAN.md §11).
##
## Exists for one reason. Every model built by `tools/blender/` carries a baked
## vertex gradient in COLOR_0 — darker at the base, lighter at the top, with a
## few per-cent of variation between facets. That gradient is what stands in for
## texture: it is the difference between a tree canopy with shape and a green
## blob.
##
## Godot's glTF importer reads COLOR_0 into the mesh faithfully and then leaves
## `vertex_color_use_as_albedo` switched off, so the data arrives and is ignored.
## Nothing errors, nothing warns, and the model simply looks flat — which is
## exactly how a whole rebuild of the village's foliage came out looking
## identical to the version before it.
##
## Every path that loads a model goes through here, so that switch is thrown once
## and in one place.

static var _prepared: Dictionary = {}


## Loads and instantiates a model, or returns null if it is not there.
##
## Missing models are not an error — the whole art pipeline is built so that a
## generated stand-in takes over when a file is absent (§10.5). Callers fall back
## rather than fail.
static func instantiate(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		Log.w("Model at %s is not a scene" % path, "ModelKit")
		return null

	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		Log.w("Model at %s did not instantiate as a Node3D" % path, "ModelKit")
		return null

	prepare(instance)
	return instance


## Pulls the first mesh out of a model, ready for a MultiMesh.
static func load_mesh(path: String) -> Mesh:
	var instance: Node3D = instantiate(path)
	if instance == null:
		return null
	var found: MeshInstance3D = _first_mesh(instance)
	var mesh: Mesh = found.mesh if found != null else null
	instance.free()
	return mesh


static func prepare(root: Node) -> void:
	var mesh_instance: MeshInstance3D = root as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		_enable_vertex_colours(mesh_instance.mesh)
	for child: Node in root.get_children():
		prepare(child)


## Switches the mesh's materials over to using vertex colour as albedo.
##
## Mutates the imported resource rather than overriding per instance, on purpose:
## every copy of a tree shares one mesh, and the flag is a property of how the
## model was authored, not of where it is standing. Done once per mesh — the
## village asks for this a few hundred times a load.
static func _enable_vertex_colours(mesh: Mesh) -> void:
	var key: int = mesh.get_instance_id()
	if _prepared.has(key):
		return
	_prepared[key] = true

	for index: int in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(index) as StandardMaterial3D
		if material == null:
			continue
		material.vertex_color_use_as_albedo = true

		# Anisotropic filtering, for the one model in the project that has a
		# texture. A ground plane is seen almost edge-on across most of the
		# screen, and plain mipmapping picks the blur level from whichever axis
		# is shrinking fastest — so the far half of the village is filtered as if
		# it were shrinking equally in both, and comes out smeared. This is the
		# switch that decides that, and glTF import leaves it on the isotropic
		# setting. Costs nothing on a model with no texture.
		if material.albedo_texture != null:
			material.texture_filter = 				BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


static func _first_mesh(node: Node) -> MeshInstance3D:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		return mesh
	for child: Node in node.get_children():
		var found: MeshInstance3D = _first_mesh(child)
		if found != null:
			return found
	return null
