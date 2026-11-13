extends Node

## Measures the brand images. Developer tool — never shipped.
##
##   godot --headless --path . res://tools/check_branding.tscn
##
## PLAN.md §11.1 asks for a silhouette identifiable at 48 × 48 px and says, in as
## many words, *test this explicitly — shrink it and look at it, do not assume*.
## Looking at it is still worth doing and this writes a strip for exactly that,
## but "looked fine to me" is not a check that survives the next person changing
## the layout by six pixels, so the parts that can be measured are measured.
##
## The two that matter and are easy to get wrong:
##
## - **The 48px read.** What makes Kanca legible at icon size is not detail, it
##   is that his head, his neck and his body are three separate widths. Squash
##   that articulation and you have an orange blob that could be any mascot. The
##   silhouette test below finds the narrowest row between his ears and his feet
##   and insists it is genuinely narrower than both.
## - **The adaptive safe zone.** Android masks a 108dp icon to whatever shape the
##   launcher likes and only guarantees the middle 66dp circle. Ink outside it is
##   not a warning at build time or a crash at run time; it is a cropped ear on
##   somebody's phone, found after release.

const BRAND_DIR := "res://assets/ui/brand/"
const STORE_DIR := "res://store/"

## 66dp of a 108dp canvas, in the 432px pixels that becomes at xxxhdpi.
const SAFE_RADIUS := 132.0
const CANVAS := 432.0

## Where the strip for the human eye is written. Deliberately outside the repo:
## it is a thing to look at once, not an asset.
const STRIP := "user://brand_scale_test.png"
const STRIP_SIZES: Array[int] = [192, 96, 48, 32]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("=== Kanca branding ===")
	print("")

	_check_files()
	_check_adaptive()
	_check_opaque_icons()
	_check_monochrome()
	_check_splash()
	_check_silhouette_at_48()
	_write_scale_strip()

	print("")
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------- checks

func _check_files() -> void:
	print("--- files and sizes ---")
	var expected: Dictionary = {
		BRAND_DIR + "kanca_full.png": Vector2i(1024, 1024),
		BRAND_DIR + "adaptive_background_432.png": Vector2i(432, 432),
		BRAND_DIR + "adaptive_foreground_432.png": Vector2i(432, 432),
		BRAND_DIR + "adaptive_monochrome_432.png": Vector2i(432, 432),
		BRAND_DIR + "app_icon_512.png": Vector2i(512, 512),
		BRAND_DIR + "launcher_192.png": Vector2i(192, 192),
		BRAND_DIR + "splash_1280x720.png": Vector2i(1280, 720),
		STORE_DIR + "feature_graphic_1024x500.png": Vector2i(1024, 500),
	}
	# The Android 12 splash draws the branding image at up to 200 x 80dp and
	# scales nothing up, so its height is whatever the letters are — checked
	# against that ceiling rather than against a number copied from the writer.
	var branding: Image = _load(BRAND_DIR + "wordmark_800.png")
	if branding == null:
		_check("wordmark_800.png", false, "missing")
	else:
		_check("wordmark_800.png fits the 200 x 80dp branding slot",
			branding.get_width() == 800 and branding.get_height() <= 320,
			"got %s, Android caps it at 800 x 320 in xxxhdpi pixels" % branding.get_size())

	# The UI portrait is the master cropped and scaled, so what is worth checking
	# is that it still *is* — same proportions, at the width the UI asks for.
	# Pinning its pixel height instead means the check fails every time the
	# mascot's own proportions change, which is the day it is least useful.
	var master: Image = _load(BRAND_DIR + "kanca_full.png")
	var portrait: Image = _load(BRAND_DIR + "kanca_portrait_256.png")
	if master == null or portrait == null:
		_check("kanca_portrait_256.png", false, "missing")
	else:
		var ink: Rect2i = _alpha_bounds(master)
		var wanted: float = float(ink.size.y) / float(ink.size.x)
		var got: float = float(portrait.get_height()) / float(portrait.get_width())
		_check("the UI portrait is the master, scaled",
			portrait.get_width() == 320 and absf(got - wanted) < 0.02,
			"master is %.3f tall per unit across, portrait is %.3f (%s)"
				% [wanted, got, portrait.get_size()])

	for path: String in expected:
		var image: Image = _load(path)
		if image == null:
			_check(path.get_file(), false, "missing — run tools/build_brand_images.tscn")
			continue
		var size: Vector2i = image.get_size()
		_check(path.get_file(), size == expected[path],
			"expected %s, got %s" % [expected[path], size])
	print("")


func _check_adaptive() -> void:
	print("--- adaptive icon (Android 108dp canvas) ---")
	var foreground: Image = _load(BRAND_DIR + "adaptive_foreground_432.png")
	if foreground == null:
		return

	var ink: Rect2i = _alpha_bounds(foreground)
	var centre := Vector2(CANVAS * 0.5, CANVAS * 0.5)
	var worst: float = 0.0
	for corner: Vector2 in [
		Vector2(ink.position), Vector2(ink.end.x, ink.position.y),
		Vector2(ink.position.x, ink.end.y), Vector2(ink.end),
	]:
		worst = maxf(worst, corner.distance_to(centre))

	# Corners of the bounding box, not of the ink itself: a bounding box is the
	# pessimistic case, and passing on the pessimistic case means it cannot be
	# cropped whatever mask the launcher picks.
	_check("logo inside the 66dp safe circle", worst <= SAFE_RADIUS,
		"furthest ink corner is %.0fpx from centre, limit is %.0f" % [worst, SAFE_RADIUS])
	_check("logo is not lost in the middle of it", worst >= SAFE_RADIUS * 0.80,
		"furthest ink corner is only %.0fpx out; the icon will read small" % worst)

	var background: Image = _load(BRAND_DIR + "adaptive_background_432.png")
	if background != null:
		_check("background layer is fully opaque", _is_opaque(background),
			"a transparent background layer shows through as black on some launchers")
	print("")


func _check_opaque_icons() -> void:
	print("--- square icons ---")
	for name: String in ["app_icon_512.png", "launcher_192.png"]:
		var image: Image = _load(BRAND_DIR + name)
		if image == null:
			continue
		_check("%s is opaque" % name, _is_opaque(image),
			"Play renders transparency as black in some surfaces")
	var feature: Image = _load(STORE_DIR + "feature_graphic_1024x500.png")
	if feature != null:
		_check("feature graphic is opaque", _is_opaque(feature), "Play requires it")
	print("")


func _check_monochrome() -> void:
	print("--- themed (monochrome) layer ---")
	var mono: Image = _load(BRAND_DIR + "adaptive_monochrome_432.png")
	if mono == null:
		return
	var coloured: int = 0
	for y: int in range(0, mono.get_height(), 3):
		for x: int in range(0, mono.get_width(), 3):
			var pixel: Color = mono.get_pixel(x, y)
			if pixel.a > 0.02 and (pixel.r < 0.99 or pixel.g < 0.99 or pixel.b < 0.99):
				coloured += 1
	_check("silhouette carries no colour", coloured == 0,
		"%d sampled pixels are not white; the launcher tints this layer itself" % coloured)
	print("")


func _check_splash() -> void:
	print("--- boot splash ---")
	var splash: Image = _load(BRAND_DIR + "splash_1280x720.png")
	if splash == null:
		return

	_check("splash keeps its transparency", not _is_opaque(splash),
		"it is drawn over boot_splash/bg_color, so the background must not be baked in")

	var ink: Rect2i = _alpha_bounds(splash)
	var drift: Vector2 = Vector2(ink.get_center()) - Vector2(splash.get_size()) * 0.5
	# Godot centres the boot splash in the window, so an off-centre lockup inside
	# the image is an off-centre lockup on the device.
	_check("lockup is centred", absf(drift.x) <= 4.0 and absf(drift.y) <= 8.0,
		"lockup centre is off by %s" % drift)
	_check("lockup leaves room around it",
		ink.size.x <= splash.get_width() * 0.6 and ink.size.y <= splash.get_height() * 0.85,
		"lockup is %s in a %s frame" % [ink.size, splash.get_size()])
	print("")


## The §11.1 test, made repeatable.
##
## Downscale the mascot layer to 48px across and walk the alpha coverage row by
## row. What the test looks for changed with the mascot: it used to find the neck
## pinch between a standing figure's ears and its body, and a quadruped has no
## such pinch looking down the rows. What says "animal" for this one is the gap
## between the legs — four thin uprights under a solid body. Lose that and you
## have an orange lozenge on a plinth, which is what a mascot scaled a little too
## far always turns into.
func _check_silhouette_at_48() -> void:
	print("--- silhouette at 48 x 48 (PLAN.md §11.1) ---")
	var foreground: Image = _load(BRAND_DIR + "adaptive_foreground_432.png")
	if foreground == null:
		return

	var small: Image = foreground.get_region(_alpha_bounds(foreground))
	small.premultiply_alpha()
	# Scaled by width. He is wider than he is tall, and the safe circle sizes him
	# across, so across is the axis that lands on 48 in the icon.
	small.resize(48, maxi(int(round(48.0 * small.get_height() / small.get_width())), 1),
		Image.INTERPOLATE_LANCZOS)

	var coverage: PackedInt32Array = PackedInt32Array()
	for y: int in small.get_height():
		var row: int = 0
		for x: int in small.get_width():
			if small.get_pixel(x, y).a >= 0.5:
				row += 1
		coverage.append(row)

	var body_low: int = int(coverage.size() * 0.58)
	var legs_high: int = int(coverage.size() * 0.72)

	var body: int = _widest(coverage, 0, body_low)
	var legs: float = _mean(coverage, legs_high, coverage.size())

	print("  %dpx tall at 48 across; widest body row %d px, mean leg row %.1f px"
		% [small.get_height(), body, legs])
	_check("daylight under him: the legs still read as legs",
		legs < body * 0.55, "legs cover %.1f of the body's %d — he is on a plinth"
			% [legs, body])
	_check("the mascot is wide enough to read", body >= 24,
		"widest point is %dpx of 48; the icon is mostly background" % body)

	_check_contrast()


## Does the mascot separate from what he is standing against?
##
## Measured across the whole of him, not at a sample point. The first version of
## this read one pixel near the middle of the icon, which for one mascot was his
## sunlit back and for the next was the knot of his neckerchief — teal, against a
## blue sky, 0.017 apart, and a failure that says nothing about whether the icon
## works. The mask is the foreground layer's own alpha, so it is exactly him.
##
## ART_STYLE.md: roughly one boy in twelve has a colour vision deficiency, so hue
## on its own is not a signal. Luminance is the one everybody gets.
func _check_contrast() -> void:
	var foreground: Image = _load(BRAND_DIR + "adaptive_foreground_432.png")
	var background: Image = _load(BRAND_DIR + "adaptive_background_432.png")
	if foreground == null or background == null:
		return

	var subject: float = 0.0
	var subject_count: int = 0
	var sky: float = 0.0
	var sky_count: int = 0
	for y: int in range(0, foreground.get_height(), 2):
		for x: int in range(0, foreground.get_width(), 2):
			var pixel: Color = foreground.get_pixel(x, y)
			if pixel.a > 0.9:
				subject += _luma(pixel)
				subject_count += 1
			elif pixel.a < 0.02 and y < foreground.get_height() * 0.55:
				# Sky only: the hill below is a different problem and he is
				# standing on it rather than against it.
				sky += _luma(background.get_pixel(x, y))
				sky_count += 1

	if subject_count == 0 or sky_count == 0:
		_check("subject separates from the background", false, "nothing to measure")
		return

	var separation: float = absf(subject / subject_count - sky / sky_count)
	print("  mean subject luma %.3f, mean sky luma %.3f"
		% [subject / subject_count, sky / sky_count])
	_check("subject separates from the sky in luminance alone", separation >= 0.10,
		"only %.3f apart" % separation)
	print("")


## Not a check. The strip exists because §11.1 says to look at it, and a number
## that passes is not the same as an icon that reads.
func _write_scale_strip() -> void:
	var icon: Image = _load(BRAND_DIR + "app_icon_512.png")
	if icon == null:
		return

	var pad: int = 16
	var width: int = pad
	for size: int in STRIP_SIZES:
		width += size + pad
	var strip: Image = Image.create_empty(width, STRIP_SIZES[0] + pad * 2, false,
		Image.FORMAT_RGBA8)
	strip.fill(Palette.UI_PANEL)

	var at: int = pad
	for size: int in STRIP_SIZES:
		var scaled: Image = icon.duplicate()
		scaled.resize(size, size, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(scaled, Rect2i(0, 0, size, size),
			Vector2i(at, pad + (STRIP_SIZES[0] - size) / 2))
		at += size + pad

	if strip.save_png(STRIP) == OK:
		print("--- for the eye ---")
		print("  %s" % ProjectSettings.globalize_path(STRIP))
		print("  The 48px one is the test §11.1 actually asks for.")


# ---------------------------------------------------------------- helpers

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.load_from_file(path)
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _alpha_bounds(image: Image) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a <= 0.02:
				continue
			low.x = mini(low.x, x)
			low.y = mini(low.y, y)
			high.x = maxi(high.x, x)
			high.y = maxi(high.y, y)
	if high.x < low.x:
		return Rect2i(0, 0, image.get_width(), image.get_height())
	return Rect2i(low, high - low + Vector2i.ONE)


func _is_opaque(image: Image) -> bool:
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a < 0.999:
				return false
	return true


func _widest(rows: PackedInt32Array, from_row: int, to_row: int) -> int:
	var best: int = 0
	for i: int in range(from_row, mini(to_row, rows.size())):
		best = maxi(best, rows[i])
	return best


func _mean(rows: PackedInt32Array, from_row: int, to_row: int) -> float:
	var total: int = 0
	var counted: int = 0
	for i: int in range(from_row, mini(to_row, rows.size())):
		total += rows[i]
		counted += 1
	return float(total) / float(maxi(counted, 1))


## Rec. 709 luminance, which is close enough to what an eye does with it.
func _luma(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


func _check(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s%s" % [label, "" if detail.is_empty() else " — " + detail])
