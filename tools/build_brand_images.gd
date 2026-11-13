extends Node

## Composes every brand image from two sources. Developer tool — never shipped.
##
##   godot --headless --path . res://tools/build_brand_images.tscn
##
## The sources are `assets/ui/brand/kanca_full.png`, which is a photograph of the
## mascot model taken by `tools/blender/build_branding.py`, and
## `assets/ui/brand/wordmark.svg`. Nothing here draws Kanca — PLAN.md §11.1 wants
## the icon to *be* the mascot, and a second drawing of him is a second mascot
## that starts drifting from the first the day either one is touched.
##
## Composited in Godot rather than in Blender or an image editor so that the
## rasteriser that assembles the icon is the one that draws the game. The SVG
## wordmark on the splash screen and the SVG wordmark in the store graphic come
## out of the same ThorVG, at the same gamma, with the same antialiasing.
##
## Run `tools/check_branding.tscn` afterwards. It measures what this wrote.

const BRAND_DIR := "res://assets/ui/brand/"
const STORE_DIR := "res://store/"
const MASCOT := BRAND_DIR + "kanca_full.png"
const WORDMARK := BRAND_DIR + "wordmark.svg"

## How wide the drawn letters are inside the wordmark's 581-unit viewBox. Widths
## asked for below are widths of the letters, not of the file: the SVG carries
## padding, and a lockup laid out on the file's edges sits visibly off-centre.
const WORDMARK_INK := 501.0

## Android's adaptive icon is a 108dp canvas of which the inner 72dp is ever
## drawn, and only the central 66dp circle is guaranteed to survive the
## launcher's mask. Every number below is on the 432px canvas that 108dp becomes
## at xxxhdpi, and the whole icon is laid out once, here, then cropped for the
## other sizes — so what Google Play shows and what sits on the home screen
## cannot disagree.
const CANVAS := 432
const VISIBLE_ORIGIN := 72   # 18dp inset: where the launcher starts drawing
const VISIBLE := 288         # the 72dp of the 108dp canvas that is ever drawn

## Everything here is placed by *width*, whatever shape the mascot is. He has now
## been landscape and portrait within a day, and a layout keyed to the axis that
## happens to be longer has to be rewritten each time; keyed to width it only has
## to be renumbered.
##
## What limits him is the 66dp safe circle catching the corners of his bounding
## box — for a subject nearly twice as tall as he is wide, a far tighter
## constraint than the edge of the canvas. These three numbers were tuned against
## that circle and `tools/check_branding.gd` measures it: change any of them and
## run the checker before believing the result.
const MASCOT_WIDTH := 126
const MASCOT_TOP := 106
const HILL_TOP := 320

## Boot splash. 1280x720 is the base resolution (PLAN.md §4.2); Godot scales the
## image to the window and fills the rest with the same cream, so the letterbox
## on a 20:9 phone is invisible.
const SPLASH := Vector2i(1280, 720)
const SPLASH_MASCOT_WIDTH := 260
const SPLASH_WORDMARK_WIDTH := 430
const SPLASH_GAP := 46

## Play Store feature graphic. Fixed by Google at 1024x500.
const FEATURE := Vector2i(1024, 500)

var _mascot: Image = null
var _mascot_ink: Rect2i = Rect2i()
var _written: int = 0


func _ready() -> void:
	print("=== Kanca brand images ===")
	print("")

	if not _load_sources():
		get_tree().quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE_DIR))

	var background: Image = _icon_background()
	var foreground: Image = _icon_foreground()

	_write(BRAND_DIR + "adaptive_background_432.png", background)
	_write(BRAND_DIR + "adaptive_foreground_432.png", foreground)
	_write(BRAND_DIR + "adaptive_monochrome_432.png", _monochrome(foreground))

	# What the launcher actually shows: the two layers flattened, then cropped to
	# the 72dp the mask leaves. Deriving the square icons from the adaptive one
	# rather than composing them again is the point — three separate layouts are
	# three icons that slowly stop being the same icon.
	var flat: Image = background.duplicate()
	_blend(flat, _premultiplied(foreground), Vector2i.ZERO)
	var launcher: Image = flat.get_region(
		Rect2i(VISIBLE_ORIGIN, VISIBLE_ORIGIN, VISIBLE, VISIBLE))

	_write(BRAND_DIR + "app_icon_512.png", _resized(launcher, Vector2i(512, 512)))
	_write(BRAND_DIR + "launcher_192.png", _resized(launcher, Vector2i(192, 192)))

	# The UI wants a small one. The master is 1024 square and mostly empty, and a
	# TextureRect asked to draw it at 160px would scale it down 6x with no mips —
	# which is exactly the aliasing everything else in this project takes trouble
	# to avoid. Derived here rather than rendered again, so it cannot disagree.
	_write(BRAND_DIR + "kanca_portrait_256.png", _portrait(320))

	_write(BRAND_DIR + "splash_1280x720.png", _splash())
	# Android 12's splash screen draws this under the icon, capped at 200x80dp.
	_write(BRAND_DIR + "wordmark_800.png",
		_unpremultiplied(_wordmark(800, Palette.UI_TEXT)))

	_write(STORE_DIR + "feature_graphic_1024x500.png", _feature_graphic())

	print("")
	print("=== %d images written ===" % _written)
	print("")
	print("Re-import them, then measure what was written:")
	print("  godot --headless --path . --import")
	print("  godot --headless --path . res://tools/check_branding.tscn")
	get_tree().quit(0)


# ---------------------------------------------------------------- sources

func _load_sources() -> bool:
	if not FileAccess.file_exists(MASCOT):
		printerr("missing %s — run tools/blender/build_branding.py first" % MASCOT)
		return false
	if not FileAccess.file_exists(WORDMARK):
		printerr("missing %s" % WORDMARK)
		return false

	_mascot = Image.load_from_file(MASCOT)
	_mascot.convert(Image.FORMAT_RGBA8)
	_mascot_ink = _alpha_bounds(_mascot)
	print("  mascot  %s, ink %s" % [_mascot.get_size(), _mascot_ink])
	return true


## The rendered master carries transparent margin on every side. Placing the
## image would place the margin; placing the ink places the animal.
func _alpha_bounds(image: Image) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a <= 0.004:
				continue
			low.x = mini(low.x, x)
			low.y = mini(low.y, y)
			high.x = maxi(high.x, x)
			high.y = maxi(high.y, y)
	if high.x < low.x:
		return Rect2i(0, 0, image.get_width(), image.get_height())
	return Rect2i(low, high - low + Vector2i.ONE)


# ---------------------------------------------------------------- the icon

## Sky, hill, and the shadow he casts on it.
##
## The shadow is here rather than on the layer with Kanca on it for two reasons,
## and the second one is the one that decided it. A shadow drawn with him would
## be a dark smudge over open sky wherever it reaches past the crest of the hill;
## and it would count as part of the foreground's ink, which is measured against
## the adaptive icon's safe circle — so a soft edge nobody would miss would be
## costing the mascot the room to be bigger.
func _icon_background() -> Image:
	var canvas: Image = _sky_field(Vector2i(CANVAS, CANVAS), float(HILL_TOP), CANVAS * 0.055)
	var shadow: int = int(MASCOT_WIDTH * 0.80)
	var depth: int = maxi(int(shadow * 0.10), 3)
	_ground_shadow(canvas, CANVAS / 2, MASCOT_TOP + _mascot_height(MASCOT_WIDTH) + depth,
		shadow, depth)
	return canvas


## Kanca, and nothing else. A launcher may slide the two layers against each
## other: a mascot drifting a little over the ground is what parallax is for,
## whereas ground drifting over itself is a seam.
func _icon_foreground() -> Image:
	var canvas: Image = Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	_place_mascot(canvas, MASCOT_WIDTH, CANVAS / 2, MASCOT_TOP)
	return _unpremultiplied(canvas)


## Themed icons are silhouettes — the launcher throws the colour away and tints
## what is left. His ears are the whole reason this still reads as Kanca.
func _monochrome(foreground: Image) -> Image:
	var mono: Image = foreground.duplicate()
	_tint(mono, Color.WHITE)
	return mono


# ---------------------------------------------------------------- canvases

## Kanca alone, cropped to his own outline, `width` px across.
func _portrait(width: int) -> Image:
	var height: int = _mascot_height(width)
	var canvas: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	_place_mascot(canvas, width, width / 2, 0)
	return _unpremultiplied(canvas)


func _splash() -> Image:
	var canvas: Image = Image.create_empty(SPLASH.x, SPLASH.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))

	var wordmark: Image = _wordmark(SPLASH_WORDMARK_WIDTH, Palette.UI_TEXT)
	var mascot_height: int = _mascot_height(SPLASH_MASCOT_WIDTH)
	var lockup: int = mascot_height + SPLASH_GAP + wordmark.get_height()
	var top: int = int((SPLASH.y - lockup) * 0.5)

	_place_mascot(canvas, SPLASH_MASCOT_WIDTH, SPLASH.x / 2, top)
	_blend(canvas, wordmark, Vector2i(
		int((SPLASH.x - wordmark.get_width()) * 0.5),
		top + mascot_height + SPLASH_GAP))
	return _unpremultiplied(canvas)


func _feature_graphic() -> Image:
	var horizon: float = FEATURE.y * 0.76
	var canvas: Image = _sky_field(FEATURE, horizon, FEATURE.y * 0.055)

	var width: int = int(FEATURE.x * 0.19)
	var height: int = _mascot_height(width)
	var standing: int = int(horizon) + 8
	var depth: int = maxi(int(width * 0.08), 3)
	_ground_shadow(canvas, int(FEATURE.x * 0.30), standing + depth,
		int(width * 0.80), depth)
	_place_mascot(canvas, width, int(FEATURE.x * 0.30), standing - height)

	# Kept well clear of the right edge. Play crops and overlays this graphic
	# differently in half a dozen places, and the name is the one thing that
	# cannot afford to lose its last letter.
	var wordmark: Image = _wordmark(int(FEATURE.x * 0.40), Palette.UI_TEXT)
	_blend(canvas, wordmark, Vector2i(
		int(FEATURE.x * 0.52),
		int((FEATURE.y - wordmark.get_height()) * 0.46)))
	return canvas


## Sky above, one hill below, and nothing else. Whatever else goes on a brand
## image has to survive being 48px wide on a home screen, and at that size a
## village is mud.
func _sky_field(size: Vector2i, hill_top: float, bulge: float) -> Image:
	# Drawn at double size and halved, which is the cheapest antialiasing there
	# is: at exactly 2:1 a bilinear resize is a four-pixel box average.
	var scale: int = 2
	var wide: int = size.x * scale
	var high: int = size.y * scale
	var canvas: Image = Image.create_empty(wide, high, false, Image.FORMAT_RGBA8)

	# Deeper than the sky the game draws. The mascot went from a mostly cream-and-
	# orange upright figure to a wide, evenly lit tan animal, and against
	# Palette.SKY his sunlit back came within 0.08 of the sky in luminance — which
	# is a mark that separates by hue alone, and roughly one boy in twelve does not
	# get hue (ART_STYLE.md). Dropping the sky two stops is the cheapest way to put
	# the difference back where everybody can see it.
	var top_colour: Color = Palette.SKY.darkened(0.30)
	var low_colour: Color = Palette.SKY.darkened(0.04)
	for y: int in high:
		canvas.fill_rect(Rect2i(0, y, wide, 1),
			top_colour.lerp(low_colour, float(y) / float(high - 1)))

	# The crest sits at `hill_top` and the ends of it drop `bulge` lower, which
	# is enough curve to read as ground rather than as a horizontal rule.
	var crest: float = hill_top * scale
	var drop: float = maxf(bulge * scale, 1.0)
	var half: float = wide * 0.5
	var radius: float = (half * half + drop * drop) / (2.0 * drop)
	var band: float = maxf(size.y * 0.018 * scale, 2.0)

	_fill_disc(canvas, half, crest + radius, radius, Palette.MEADOW_LIGHT)
	_fill_disc(canvas, half, crest + radius + band, radius, Palette.GRASS)

	canvas.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return canvas


func _fill_disc(canvas: Image, centre_x: float, centre_y: float, radius: float,
		colour: Color) -> void:
	for y: int in canvas.get_height():
		var dy: float = float(y) + 0.5 - centre_y
		if absf(dy) > radius:
			continue
		var span: float = sqrt(radius * radius - dy * dy)
		var left: int = maxi(int(centre_x - span), 0)
		var right: int = mini(int(centre_x + span), canvas.get_width())
		if right > left:
			canvas.fill_rect(Rect2i(left, y, right - left, 1), colour)


# ---------------------------------------------------------------- placement

## A soft ellipse on the ground under his hooves, so he stands on the hill
## instead of in front of it. Costs nothing at icon size, where it is a smudge
## three pixels tall, and does the whole job at store size.
##
## `centre_y` is the middle of the ellipse and belongs a whole `depth` below his
## hooves, so that the top of it lands on the grass line rather than a few pixels
## above it, where it would be a grey bruise in the sky.
func _ground_shadow(canvas: Image, centre_x: int, centre_y: int, width: int,
		depth_px: int) -> void:
	var half: float = width * 0.5
	var depth: float = maxf(float(depth_px), 2.0)
	var baseline: int = centre_y
	var colour: Color = Palette.MEADOW_DARK
	for y: int in range(int(baseline - depth), int(baseline + depth) + 1):
		if y < 0 or y >= canvas.get_height():
			continue
		for x: int in range(centre_x - int(half), centre_x + int(half) + 1):
			if x < 0 or x >= canvas.get_width():
				continue
			var across: float = (float(x) + 0.5 - centre_x) / half
			var down: float = (float(y) + 0.5 - baseline) / depth
			var falloff: float = 1.0 - (across * across + down * down)
			if falloff <= 0.0:
				continue
			# Premultiplied, because everything else placed on these canvases is.
			var strength: float = falloff * falloff * 0.42
			var under: Color = canvas.get_pixel(x, y)
			var rest: float = 1.0 - strength
			canvas.set_pixel(x, y, Color(
				colour.r * strength + under.r * rest,
				colour.g * strength + under.g * rest,
				colour.b * strength + under.b * rest,
				strength + under.a * rest))


## What `width` px of mascot comes to in height, at his own proportions.
func _mascot_height(width: int) -> int:
	return int(round(float(width) * float(_mascot_ink.size.y)
		/ float(_mascot_ink.size.x)))


## Scales the mascot's ink to `width` and blends it in premultiplied.
func _place_mascot(canvas: Image, width: int, centre_x: int, top: int) -> void:
	var height: int = _mascot_height(width)
	var cut: Image = _mascot.get_region(_mascot_ink)
	cut.premultiply_alpha()
	cut.resize(width, height, Image.INTERPOLATE_LANCZOS)
	_blend(canvas, cut, Vector2i(centre_x - width / 2, top))


## The wordmark cropped to its letters, `width` px across, premultiplied.
##
## Rasterised at double size and brought back down. ThorVG antialiases the round
## caps into the edge pixels, so cropping to the ink at final size shaves a
## fraction off every terminal; oversampling puts that fraction below one pixel.
func _wordmark(width: int, colour: Color) -> Image:
	var image: Image = Image.new()
	var source: String = FileAccess.get_file_as_string(WORDMARK)
	var error: int = image.load_svg_from_string(source, 2.0 * float(width) / WORDMARK_INK)
	if error != OK:
		printerr("wordmark failed to rasterise: %d" % error)
		return Image.create_empty(width, 1, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	# Tint before premultiplying: every pixel of the wordmark is one colour and
	# the letterforms live entirely in the alpha, so recolouring is a fill.
	_tint(image, colour)
	image.premultiply_alpha()

	var ink: Rect2i = _alpha_bounds(image)
	var cropped: Image = image.get_region(ink)
	cropped.resize(width, int(round(float(width) * ink.size.y / ink.size.x)),
		Image.INTERPOLATE_LANCZOS)
	return cropped


func _tint(image: Image, colour: Color) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			image.set_pixel(x, y, Color(colour.r, colour.g, colour.b,
				image.get_pixel(x, y).a))


# ---------------------------------------------------------------- pixels

## Source-over with a premultiplied source.
##
## `Image.blend_rect` expects straight alpha, and straight alpha is what makes a
## downscaled render grow a dark halo: the transparent margin around the mascot
## is black, and a filter that has not been told to ignore it averages that
## black into every edge pixel. Premultiplying first, resizing, then blending
## like this is the fix, and it is why nothing here calls blend_rect.
func _blend(canvas: Image, source: Image, at: Vector2i) -> void:
	for y: int in source.get_height():
		var target_y: int = at.y + y
		if target_y < 0 or target_y >= canvas.get_height():
			continue
		for x: int in source.get_width():
			var target_x: int = at.x + x
			if target_x < 0 or target_x >= canvas.get_width():
				continue
			var top_pixel: Color = source.get_pixel(x, y)
			if top_pixel.a <= 0.0:
				continue
			var under: Color = canvas.get_pixel(target_x, target_y)
			var rest: float = 1.0 - top_pixel.a
			canvas.set_pixel(target_x, target_y, Color(
				top_pixel.r + under.r * rest,
				top_pixel.g + under.g * rest,
				top_pixel.b + under.b * rest,
				top_pixel.a + under.a * rest))


func _premultiplied(image: Image) -> Image:
	var copy: Image = image.duplicate()
	copy.premultiply_alpha()
	return copy


## PNG stores straight alpha, so anything that stays transparent has to come back
## out of premultiplied form before it is written.
func _unpremultiplied(image: Image) -> Image:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.0:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			image.set_pixel(x, y, Color(
				minf(pixel.r / pixel.a, 1.0),
				minf(pixel.g / pixel.a, 1.0),
				minf(pixel.b / pixel.a, 1.0),
				minf(pixel.a, 1.0)))
	return image


func _resized(image: Image, size: Vector2i) -> Image:
	var copy: Image = image.duplicate()
	copy.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return copy


func _write(path: String, image: Image) -> void:
	var error: int = image.save_png(path)
	if error != OK:
		printerr("  could not write %s: %d" % [path, error])
		return
	_written += 1
	print("  %-46s %d x %d" % [path.trim_prefix("res://"),
		image.get_width(), image.get_height()])
