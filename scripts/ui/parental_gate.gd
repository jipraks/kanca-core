class_name ParentalGate
extends Control

## Blocks settings and any external link (PLAN.md §3.6).
##
## This is the one screen in the app that is allowed to depend on reading, because
## it is addressed to an adult and reading is precisely the barrier. A child who
## cannot yet read two-digit numerals cannot pass it, and a wrong answer draws a
## fresh challenge so that repeated guessing never converges.
##
## Nothing here is scary or scolding — a child who wanders in just gets sent back.

signal passed()
signal dismissed()

const CHOICE_COUNT := 3
const BUTTON_SIZE := Vector2(180, 180)
const MINIMUM_TARGET := 21
const MAXIMUM_TARGET := 98

## Parent-facing copy. The only user-facing strings in the codebase that are not
## in data/, because this surface is explicitly outside the child's experience.
const PROMPT_TEMPLATE := "Untuk melanjutkan, ketuk angka %d"
const SUBTITLE := "Halaman ini untuk orang tua."

var _prompt: Label = null
var _choices: HBoxContainer = null
var _target: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.CURTAIN, 0.7)
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
	panel.custom_minimum_size = Vector2(860, 480)
	panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	# Keeps the back button clear of the numeral choices by the §3.3 minimum.
	column.add_theme_constant_override("separation", 44)
	panel.add_child(column)

	var subtitle: Label = Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = SUBTITLE
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 26)
	subtitle.add_theme_color_override("font_color", Palette.UI_TEXT)
	column.add_child(subtitle)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 38)
	_prompt.add_theme_color_override("font_color", Palette.UI_TEXT)
	column.add_child(_prompt)

	_choices = HBoxContainer.new()
	_choices.name = "Choices"
	_choices.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices.add_theme_constant_override("separation", 60)
	column.add_child(_choices)

	var back: BigButton = BigButton.new()
	back.name = "Back"
	back.custom_minimum_size = Vector2(160, 130)
	back.accent = Palette.UI_DISABLED
	back.icon_texture = PlaceholderFactory.build_arrow_icon(Vector2.LEFT, Palette.UI_TEXT, 96)
	back.pressed.connect(_on_dismissed)
	column.add_child(back)


func open() -> void:
	visible = true
	_new_challenge()


func close() -> void:
	visible = false


func _new_challenge() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()

	var options: Array[int] = []
	_target = randi_range(MINIMUM_TARGET, MAXIMUM_TARGET)
	options.append(_target)

	# Distractors share no digit position with the target, so a parent glancing
	# quickly cannot mis-tap, and a child cannot match on shape alone.
	while options.size() < CHOICE_COUNT:
		var candidate: int = randi_range(MINIMUM_TARGET, MAXIMUM_TARGET)
		if _is_too_similar(candidate, options):
			continue
		options.append(candidate)

	options.shuffle()
	_prompt.text = PROMPT_TEMPLATE % _target

	for value: int in options:
		var button: Button = Button.new()
		button.name = "Choice%d" % value
		button.text = str(value)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = BUTTON_SIZE
		button.add_theme_font_size_override("font_size", 64)
		button.add_theme_color_override("font_color", Palette.UI_TEXT)
		button.add_theme_stylebox_override("normal", _choice_style(Palette.CREAM))
		button.add_theme_stylebox_override("hover", _choice_style(Palette.CREAM))
		button.add_theme_stylebox_override("pressed", _choice_style(Palette.CREAM.darkened(0.1)))
		button.add_theme_stylebox_override("focus", _choice_style(Palette.CREAM))
		button.pressed.connect(_on_choice.bind(value))
		_choices.add_child(button)


func _is_too_similar(candidate: int, existing: Array[int]) -> bool:
	for value: int in existing:
		if candidate == value:
			return true
		if candidate / 10 == value / 10 or candidate % 10 == value % 10:
			return true
	return false


func _on_choice(value: int) -> void:
	if value == _target:
		close()
		passed.emit()
		return
	# A wrong tap draws an entirely new challenge, so guessing does not narrow down.
	SfxBank.play(SfxBank.GENTLE)
	_new_challenge()


func _on_dismissed() -> void:
	close()
	dismissed.emit()


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.UI_PANEL
	style.corner_radius_top_left = 32
	style.corner_radius_top_right = 32
	style.corner_radius_bottom_left = 32
	style.corner_radius_bottom_right = 32
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	return style


func _choice_style(colour: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = colour
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	style.border_width_bottom = 6
	style.border_color = Palette.UI_PANEL_EDGE
	return style
