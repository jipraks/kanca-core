extends Node

## Reports what actually arrived when a .glb was imported. Developer tool.
##
##   godot --headless --path . res://tools/model_probe.tscn
##
## Written because a whole rebuild of the village foliage came out looking
## identical to the version before it: the vertex gradient was in the file, and
## Godot was throwing it away somewhere between the file and the screen. Reading
## the docs would not have said where. This does.

const MODELS: Array[String] = [
	"res://assets/models/environment/warung.glb",
	"res://assets/models/environment/tree_leafy.glb",
]


func _ready() -> void:
	for path: String in MODELS:
		print("--- %s" % path)
		var instance: Node3D = ModelKit.instantiate(path)
		if instance == null:
			print("  did not load")
			continue
		_report(instance)
		instance.free()
	get_tree().quit(0)


func _report(node: Node) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var mesh: Mesh = mesh_instance.mesh
		for index: int in range(mesh.get_surface_count()):
			var format: int = mesh.surface_get_format(index)
			var material: Material = mesh.surface_get_material(index)
			var override: Material = mesh_instance.get_surface_override_material(index)
			var base: BaseMaterial3D = material as BaseMaterial3D
			# What Godot actually holds, as opposed to what the file says. The two
			# turned out to disagree, and no amount of reading the exported glTF
			# would have shown it.
			var arrays: Array = mesh.surface_get_arrays(index)
			var vertex_colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
			if vertex_colours != null and not vertex_colours.is_empty():
				var brightest: Color = vertex_colours[0]
				for colour: Color in vertex_colours:
					if colour.g > brightest.g:
						brightest = colour
				print("    brightest vertex colour in Godot: (%.4f, %.4f, %.4f)" % [
					brightest.r, brightest.g, brightest.b])
			print("  surface %d  has_colour=%s  material=%s  override=%s  uses_vc=%s" % [
				index,
				(format & Mesh.ARRAY_FORMAT_COLOR) != 0,
				material.get_class() if material != null else "none",
				override.get_class() if override != null else "none",
				str(base.vertex_color_use_as_albedo) if base != null else "n/a"])
			if base != null:
				var names: PackedStringArray = []
				for entry: Dictionary in base.get_property_list():
					if String(entry["name"]).contains("vertex_color"):
						names.append("%s=%s" % [entry["name"], base.get(entry["name"])])
				print("    vertex colour properties: %s" % ", ".join(names))
	for child: Node in node.get_children():
		_report(child)
