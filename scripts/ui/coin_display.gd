class_name CoinDisplay
extends HBoxContainer

## Running coin total (PLAN.md §7.1, §3.1).
##
## The coin pictogram carries the meaning; the numeral beside it is the reading
## aid §3.1 allows. A child who cannot read numbers still sees "coins, and they
## went up" — the pop animation is what communicates the change, not the digits.

const ICON_SIZE := Vector2(56, 56)
const POP_SCALE := 1.25
const POP_SECONDS := 0.18

@export var numeral_font_size: int = 44

## The hub shows the running total from GameState. A mini-game shows what this
## session has earned so far, because coins are only applied to GameState once
## the session ends (PLAN.md §6.2) - a display wired to GameState would sit at
## the old number for the whole round.
@export var follow_game_state: bool = true

var _icon: TextureRect = null
var _numeral: Label = null
var _pop_tween: Tween = null


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.texture = PlaceholderFactory.build_glyph_icon("coin", Palette.SIGNATURE, 128)
	_icon.custom_minimum_size = ICON_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_numeral = Label.new()
	_numeral.name = "Numeral"
	_numeral.add_theme_font_size_override("font_size", numeral_font_size)
	_numeral.add_theme_color_override("font_color", Palette.UI_TEXT)
	_numeral.add_theme_color_override("font_outline_color", Palette.UI_PANEL)
	_numeral.add_theme_constant_override("outline_size", 8)
	_numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_numeral)

	if follow_game_state:
		GameState.coins_changed.connect(_on_coins_changed)
		set_total(GameState.coins)
	else:
		set_total(0)


func set_total(total: int) -> void:
	if _numeral != null:
		_numeral.text = str(maxi(total, 0))


## Sets the number and plays the pop, for callers driving this manually.
func show_total(total: int) -> void:
	set_total(total)
	_pop()


func _on_coins_changed(total: int) -> void:
	set_total(total)
	_pop()


func _pop() -> void:
	if _icon == null:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_icon.pivot_offset = _icon.size * 0.5
	_pop_tween = create_tween()
	_pop_tween.tween_property(_icon, "scale", Vector2.ONE * POP_SCALE, POP_SECONDS).set_trans(Tween.TRANS_BACK)
	_pop_tween.tween_property(_icon, "scale", Vector2.ONE, POP_SECONDS).set_trans(Tween.TRANS_SINE)
