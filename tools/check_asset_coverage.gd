extends Node

## Reports which art slots are still generated placeholders (PLAN.md §11).
##
##   godot --headless --path . res://tools/check_asset_coverage.tscn
##
## The counterpart to check_voice_coverage. Every path below is one the game
## already looks for: drop a file there and it is used on the next run, with no
## code change. Nothing here needs to be registered, imported or wired up.
##
## Item paths come from data/items.json, so adding an item adds a slot here too.

const MASCOT_MODEL := "res://assets/models/characters/kanca.glb"
const PLAYER_MODEL := "res://assets/models/characters/player.glb"
const BRAND_DIR := "res://assets/ui/brand/"
const BRAND_FILES := {
	"mascot master": "kanca_full.png",
	"mascot portrait": "kanca_portrait_256.png",
	"wordmark": "wordmark.svg",
	"adaptive fg": "adaptive_foreground_432.png",
	"adaptive bg": "adaptive_background_432.png",
	"adaptive mono": "adaptive_monochrome_432.png",
}
const BUILDING_ICON_DIR := "res://assets/ui/buildings/"

var _present: int = 0
var _missing: int = 0


func _ready() -> void:
	print("=== Kanca asset coverage ===")
	print("")

	_report_item_icons()
	_report_item_models()
	_report_building_icons()
	_report_characters()
	_report_mascot()
	_report_sfx()

	print("=== %d present, %d still placeholder ===" % [_present, _missing])
	print("")
	print("Anything listed as missing is being generated at runtime instead.")
	print("Drop a real file at the path shown and it takes over immediately.")
	get_tree().quit(0)


func _report_item_icons() -> void:
	print("--- item icons (order card, seed baskets, building prompts) ---")
	print("2D. PNG with transparency, square, 256x256 is plenty.")
	for item_id: String in ContentDB.get_item_ids():
		var path: String = String(ContentDB.get_item(item_id).get("icon", ""))
		_report(item_id, path)
	print("")


func _report_item_models() -> void:
	print("--- item models (shelf, tray, garden fruit) ---")
	print("3D. glTF .glb, roughly 0.2m across, 1 unit = 1 metre.")
	for item_id: String in ContentDB.get_item_ids():
		var path: String = String(ContentDB.get_item(item_id).get("model", ""))
		_report(item_id, path)
	print("")


func _report_building_icons() -> void:
	print("--- building icons (village markers and entry prompt) ---")
	for game_id: String in ContentDB.get_mini_game_ids():
		var path: String = String(ContentDB.get_mini_game(game_id).get("icon", ""))
		_report(game_id, path)
	print("")


func _report_characters() -> void:
	print("--- characters ---")
	print("3D. Z-up in Blender, origin at the feet, facing +Y so it exports")
	print("looking down Godot's -Z. 1 unit = 1 metre.")
	_report("player", PLAYER_MODEL)
	for variant: String in ["anak", "ibu", "bapak"]:
		_report("customer %s" % variant,
			"res://assets/models/characters/cust_%s.glb" % variant)
	print("")


func _report_mascot() -> void:
	print("--- Kanca ---")
	print("Supplied model, repaired by tools/blender/import_mascot.py (§16.2).")
	print("Three poses in one file: idle, point, celebrate. Still missing from")
	print("§11.1 are walk, think, and the four expressions — the poses are")
	print("continuous shells with no separable legs, so he does not step.")
	_report("mascot model", MASCOT_MODEL)
	print("")

	print("--- brand ---")
	print("Rendered from the mascot and composed by tools/build_brand_images.gd.")
	print("tools/check_branding.tscn measures them; this only says they are here.")
	_report("app icon", String(ProjectSettings.get_setting("application/config/icon", "")))
	_report("boot splash",
		String(ProjectSettings.get_setting("application/boot_splash/image", "")))
	for label: String in BRAND_FILES:
		_report(label, BRAND_DIR + String(BRAND_FILES[label]))
	print("")


func _report_sfx() -> void:
	print("--- sound effects ---")
	print("Synthesised waveforms until a real .ogg appears at these paths.")
	for sfx_id: String in SfxBank.get_all_ids():
		var path: String = "%s%s.ogg" % [SfxBank.SFX_DIR, sfx_id]
		_report(sfx_id, path)
	print("")


func _report(label: String, path: String) -> void:
	if path.is_empty():
		print("  %-18s no path declared" % label)
		_missing += 1
		return

	var exists: bool = ResourceLoader.exists(path)
	if exists:
		_present += 1
	else:
		_missing += 1
	print("  %-18s %s  %s" % [label, "present    " if exists else "placeholder", path])

