class_name Log
extends RefCounted

## Central logging.
##
## PLAN.md §15 forbids bare `print()` in committed code so that logging can be
## stripped from release builds in exactly one place. Release builds start at WARN,
## so DEBUG and INFO calls cost a single integer comparison and never build a string.

enum Level {
	DEBUG = 0,
	INFO = 1,
	WARN = 2,
	ERROR = 3,
	SILENT = 4,
}

static var min_level: int = Level.DEBUG


static func _static_init() -> void:
	min_level = Level.DEBUG if OS.is_debug_build() else Level.WARN


static func d(message: String, context: String = "") -> void:
	if min_level <= Level.DEBUG:
		print(_format("DEBUG", context, message))


static func i(message: String, context: String = "") -> void:
	if min_level <= Level.INFO:
		print(_format("INFO", context, message))


## Something is wrong but the app carries on. Never surfaced to the child.
static func w(message: String, context: String = "") -> void:
	if min_level <= Level.WARN:
		push_warning(_format("WARN", context, message))


## Something is broken. The app must still degrade gracefully — a child never
## sees an error (PLAN.md §6.1, §9).
static func e(message: String, context: String = "") -> void:
	if min_level <= Level.ERROR:
		push_error(_format("ERROR", context, message))


static func _format(level_name: String, context: String, message: String) -> String:
	if context.is_empty():
		return "[%s] %s" % [level_name, message]
	return "[%s][%s] %s" % [level_name, context, message]
