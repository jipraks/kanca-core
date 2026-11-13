class_name CelebrationOverlay
extends Control

## Session completion screen (PLAN.md §12, §8.1.9).
##
## Every session ends well, because there is no way to lose (§3.2). The stars
## count what the child did, never how well — five rounds played is five stars,
## full stop.

signal dismissed()

## A child should not have to find a button to move on, but must be able to.
const AUTO_DISMISS_SECONDS := 6.0
const STAR_SIZE := Vector2(84, 84)

## By height. He is half as wide as he is tall, so a square box under-sizes him.
const MASCOT_HEIGHT := 230

var _mascot: TextureRect = null
var _star_row: HBoxContainer = null
var _coin_row: CountingRow = null
var _continue_button: BigButton = null
var _auto_timer: Timer = null
var _bounce_tween: Tween = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(Palette.CREAM, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre: CenterContainer = CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 28)
	centre.add_child(column)

	_mascot = TextureRect.new()
	_mascot.name = "Mascot"
	_mascot.texture = PlaceholderFactory.build_mascot_portrait(MASCOT_HEIGHT)
	_mascot.custom_minimum_size = Vector2(MASCOT_HEIGHT * 0.6, MASCOT_HEIGHT)
	_mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_mascot)

	_star_row = HBoxContainer.new()
	_star_row.name = "Stars"
	_star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_star_row.add_theme_constant_override("separation", 16)
	_star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_star_row)

	var coin_line: HBoxContainer = HBoxContainer.new()
	coin_line.name = "Coins"
	coin_line.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_line.add_theme_constant_override("separation", 20)
	coin_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(coin_line)

	var coin_icon: TextureRect = TextureRect.new()
	coin_icon.name = "CoinIcon"
	coin_icon.texture = PlaceholderFactory.build_glyph_icon("coin", Palette.SIGNATURE, 128)
	coin_icon.custom_minimum_size = Vector2(88, 88)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_line.add_child(coin_icon)

	_coin_row = CountingRow.new()
	_coin_row.name = "CoinCount"
	coin_line.add_child(_coin_row)

	_continue_button = BigButton.new()
	_continue_button.name = "Continue"
	_continue_button.custom_minimum_size = Vector2(200, 160)
	_continue_button.accent = Palette.CORRECT
	_continue_button.icon_texture = PlaceholderFactory.build_glyph_icon("check", Palette.UI_PANEL, 128)
	_continue_button.pressed.connect(_dismiss)
	column.add_child(_continue_button)

	_auto_timer = Timer.new()
	_auto_timer.name = "AutoDismiss"
	_auto_timer.one_shot = true
	_auto_timer.wait_time = AUTO_DISMISS_SECONDS
	_auto_timer.timeout.connect(_dismiss)
	add_child(_auto_timer)


func show_result(result: MiniGameResult) -> void:
	for child: Node in _star_row.get_children():
		child.queue_free()

	for i: int in range(maxi(result.rounds_completed, 1)):
		var star: TextureRect = TextureRect.new()
		star.texture = PlaceholderFactory.build_glyph_icon("star", Palette.SIGNATURE, 128)
		star.custom_minimum_size = STAR_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.modulate.a = 0.0
		_star_row.add_child(star)

	_coin_row.set_count(result.coins_earned)

	visible = true
	modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.2)

	_animate_stars()
	_start_bounce()

	SfxBank.play(SfxBank.SUCCESS)
	VoiceBank.play("kanca_celebrate")

	_auto_timer.start()


func _animate_stars() -> void:
	# Stars land one at a time so the child can count them as they arrive.
	var tween: Tween = create_tween()
	for child: Node in _star_row.get_children():
		var star: TextureRect = child as TextureRect
		tween.tween_property(star, "modulate:a", 1.0, 0.12)
		tween.parallel().tween_property(star, "scale", Vector2.ONE, 0.12).from(Vector2.ONE * 1.6)
		tween.tween_callback(SfxBank.play.bind(SfxBank.CHIME, 1.0))
		tween.tween_interval(0.08)


func _start_bounce() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_mascot.pivot_offset = _mascot.size * 0.5
	_bounce_tween = create_tween().set_loops()
	_bounce_tween.tween_property(_mascot, "scale", Vector2(1.06, 0.94), 0.28).set_trans(Tween.TRANS_SINE)
	_bounce_tween.tween_property(_mascot, "scale", Vector2(0.96, 1.06), 0.28).set_trans(Tween.TRANS_SINE)
	_bounce_tween.tween_property(_mascot, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


func _dismiss() -> void:
	if not visible:
		return
	_auto_timer.stop()
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	visible = false
	dismissed.emit()
