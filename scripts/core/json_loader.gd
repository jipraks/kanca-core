class_name JsonLoader
extends RefCounted

## The only place in the codebase that reads a JSON file from disk.
##
## PLAN.md §9: validate on load, and on a malformed file log loudly and fall back
## to a safe default. Never crash the app in front of a child.


## Returns the parsed dictionary, or an empty dictionary on any failure.
## Callers substitute their own fallback when the result is empty.
static func load_dict(path: String) -> Dictionary:
	var parsed: Variant = _parse(path)
	if parsed == null:
		return {}
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.e("Expected a JSON object at the root of %s, got %s" % [path, type_string(typeof(parsed))], "JsonLoader")
		return {}
	return parsed as Dictionary


static func write_dict(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		Log.e("Cannot open %s for writing: %s" % [path, error_string(FileAccess.get_open_error())], "JsonLoader")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		Log.w("Data file not found: %s" % path, "JsonLoader")
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		Log.e("Cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())], "JsonLoader")
		return null

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		Log.e("Malformed JSON in %s, line %d: %s" % [path, json.get_error_line(), json.get_error_message()], "JsonLoader")
		return null

	return json.data


## Reports every required key a dictionary is missing. Empty result means valid.
static func missing_keys(source: Dictionary, required: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for key: String in required:
		if not source.has(key):
			missing.append(key)
	return missing
