class_name SafeAreaMargin
extends MarginContainer

## Keeps UI clear of notches, punch-holes and the Android gesture bar (PLAN.md §12).
##
## Wrap a screen's UI in one of these. On desktop the safe area is the whole
## window, so it collapses to the minimum padding and nothing moves.

## Applied even where there is no cutout, so buttons are never flush to the edge.
@export var minimum_padding: int = 24


func _ready() -> void:
	_apply()
	get_viewport().size_changed.connect(_apply)


func _apply() -> void:
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	var viewport_size: Vector2 = get_viewport_rect().size
	if window_size.x <= 0.0 or window_size.y <= 0.0 or viewport_size.x <= 0.0:
		_set_uniform(minimum_padding)
		return

	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		_set_uniform(minimum_padding)
		return

	# The safe area is reported in physical screen pixels; the UI lives in the
	# 1280×720 stretch space, so the insets have to be converted.
	var ratio: Vector2 = viewport_size / window_size

	_set_margin("margin_left", float(safe.position.x) * ratio.x)
	_set_margin("margin_top", float(safe.position.y) * ratio.y)
	_set_margin("margin_right", (window_size.x - float(safe.position.x + safe.size.x)) * ratio.x)
	_set_margin("margin_bottom", (window_size.y - float(safe.position.y + safe.size.y)) * ratio.y)


func _set_margin(key: String, inset: float) -> void:
	add_theme_constant_override(key, int(maxf(inset, float(minimum_padding))))


func _set_uniform(value: int) -> void:
	for key: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		add_theme_constant_override(key, value)
