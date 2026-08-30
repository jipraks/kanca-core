extends Node

## Reports which voice lines still have no recording (PLAN.md §10.5).
##
##   godot --headless --path . res://tools/check_voice_coverage.tscn
##
## The manifest is the contract between engineering and the recording session:
## anything listed there is expected to exist, anything not listed does not exist
## as far as the game is concerned. This is how you tell, at a glance, how far
## through the recording you are — and it is the check that has to come back
## clean before P5 can be called done.

func _ready() -> void:
	var ids: Array[String] = VoiceBank.get_all_voice_ids()
	var missing: Array[String] = VoiceBank.get_missing_recordings()
	var recorded: int = ids.size() - missing.size()

	print("=== Kanca voice coverage ===")
	print("Manifest entries: %d" % ids.size())
	print("Recorded:         %d" % recorded)
	print("Missing:          %d" % missing.size())
	print("Clips to record:  %d (counting every variant)" % _count_clips(ids))
	print("")

	if missing.is_empty():
		print("Every line in the manifest has a recording.")
		get_tree().quit(0)
		return

	var by_speaker: Dictionary = {}
	for voice_id: String in missing:
		var speaker: String = _speaker_of(voice_id)
		if not by_speaker.has(speaker):
			by_speaker[speaker] = [] as Array[String]
		(by_speaker[speaker] as Array[String]).append(voice_id)

	var speakers: Array[String] = []
	for key: String in by_speaker:
		speakers.append(key)
	speakers.sort()

	for speaker: String in speakers:
		var entries: Array[String] = by_speaker[speaker]
		print("--- %s (%d lines, %d clips) ---" % [speaker, entries.size(), _count_clips(entries)])
		for voice_id: String in entries:
			var variants: int = VoiceBank.get_variant_count(voice_id)
			var suffix: String = " x%d" % variants if variants > 1 else ""
			print("  %-28s%-6s %s" % [voice_id, suffix, VoiceBank.get_text(voice_id)])
		print("")

	print("Expected paths follow the naming convention in PLAN.md 10.2.")
	print("Example: %s" % VoiceBank.resolve_path(missing[0], 0))
	get_tree().quit(0)


func _count_clips(ids: Array[String]) -> int:
	var total: int = 0
	for voice_id: String in ids:
		total += VoiceBank.get_variant_count(voice_id)
	return total


func _speaker_of(voice_id: String) -> String:
	var manifest: Dictionary = ContentDB.get_voice_manifest()
	var entry: Dictionary = manifest.get(voice_id, {}) as Dictionary
	return String(entry.get("speaker", "unknown"))
