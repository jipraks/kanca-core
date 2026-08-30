class_name IconConfirmDialog
extends Control

## Two-choice confirmation, entirely in icons (PLAN.md §12).
##
## Both options are positive: a green tick for "yes, go back to the village" and
## a play triangle for "no, carry on playing". Neither reads as a punishment or a
## dead end, which rules out the usual red X (§3.2).

signal confirmed()
signal cancelled()

const PANEL_SIZE := Vector2(720, 420)
const BUTTON_SIZE := Vector2(180, 180)

var _subject: TextureRect = null
var _confirm_button: BigButton = null
var _cancel_button: BigButton = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.CURTAIN, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre: CenterContainer = CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 32)
	panel.add_child(column)

	_subject = TextureRect.new()
	_subject.name = "Subject"
	_subject.custom_minimum_size = Vector2(140, 140)
	_subject.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_subject.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_subject.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_subject)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Choices"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# §3.3: adjacent interactive elements stay at least 40px apart.
	row.add_theme_constant_override("separation", 80)
	column.add_child(row)

	_cancel_button = _make_button("KeepPlaying", "play", Palette.SIGNATURE)
	_cancel_button.pressed.connect(_on_cancel)
	row.add_child(_cancel_button)

	_confirm_button = _make_button("Confirm", "check", Palette.CORRECT)
	_confirm_button.pressed.connect(_on_confirm)
	row.add_child(_confirm_button)


## `subject_icon` says what the question is about — the house for "leave", the
## mini-game's own icon for "start this". There is no text version of it.
func open(subject_icon: Texture2D, voice_id: String = "") -> void:
	_subject.texture = subject_icon
	visible = true
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	if not voice_id.is_empty():
		VoiceBank.play(voice_id)


func close() -> void:
	visible = false


func _make_button(node_name: String, glyph: String, colour: Color) -> BigButton:
	var button: BigButton = BigButton.new()
	button.name = node_name
	button.custom_minimum_size = BUTTON_SIZE
	button.accent = colour
	button.icon_texture = PlaceholderFactory.build_glyph_icon(glyph, Palette.UI_PANEL, 128)
	return button


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.UI_PANEL
	style.corner_radius_top_left = 40
	style.corner_radius_top_right = 40
	style.corner_radius_bottom_left = 40
	style.corner_radius_bottom_right = 40
	style.border_width_bottom = 8
	style.border_color = Palette.UI_PANEL_EDGE
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	return style


func _on_confirm() -> void:
	close()
	confirmed.emit()


func _on_cancel() -> void:
	close()
	cancelled.emit()
