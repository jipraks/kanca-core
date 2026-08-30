class_name HomeButton
extends Control

## Always-available exit from a mini-game (PLAN.md §12, §3.4).
##
## A child must be able to leave any activity at any moment, from an obvious
## control in the same place every time. The confirmation exists only so that a
## stray tap does not end a session — it is icon-only and either answer is fine.

signal home_confirmed()

var _button: BigButton = null
var _dialog_layer: CanvasLayer = null
var _dialog: IconConfirmDialog = null


func _ready() -> void:
	custom_minimum_size = BigButton.MIN_TOUCH_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_button = BigButton.new()
	_button.name = "Button"
	_button.custom_minimum_size = BigButton.MIN_TOUCH_SIZE
	# Already at §3.3's floor, so the target cannot shrink — only the panel
	# drawn inside it. A press landing just outside still works, which is the
	# forgiving direction.
	_button.visual_inset = 11.0
	_button.accent = Palette.UI_PANEL
	_button.icon_texture = PlaceholderFactory.build_glyph_icon("home", Palette.UI_TEXT, 96)
	_button.pressed.connect(_on_pressed)
	add_child(_button)

	# The dialog needs to cover the whole screen, so it gets its own layer rather
	# than living inside whatever corner this button was placed in.
	_dialog_layer = CanvasLayer.new()
	_dialog_layer.name = "ConfirmLayer"
	_dialog_layer.layer = 64
	add_child(_dialog_layer)

	_dialog = IconConfirmDialog.new()
	_dialog.name = "ConfirmDialog"
	_dialog.confirmed.connect(_on_confirmed)
	_dialog_layer.add_child(_dialog)


## Opens the confirmation directly. The Android back gesture routes here so that
## the hardware button and the on-screen button behave identically.
func request_exit() -> void:
	_on_pressed()


func _on_pressed() -> void:
	if _dialog.visible:
		return
	_dialog.open(PlaceholderFactory.build_glyph_icon("home", Palette.SIGNATURE, 160))


func _on_confirmed() -> void:
	home_confirmed.emit()
