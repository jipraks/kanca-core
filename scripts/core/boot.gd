extends Control

## First scene the app shows (PLAN.md §6.3).
##
## Its whole job is to warm the content cache and hand over to SceneRouter. It is
## freed by the router once the hub exists and is never returned to.

## Long enough that the brand registers, short enough that nobody is waiting.
## PLAN.md §4.2 budgets under five seconds from cold start to hub, and §3.4
## forbids making a child wait in real time for anything.
const MINIMUM_SPLASH_SECONDS := 0.6

@onready var _logo: TextureRect = $Centre/Logo


func _ready() -> void:
	Log.i("Kanca %s starting" % ProjectSettings.get_setting("application/config/version", "?"), "Boot")

	# Placeholder mark, replaced by the real mascot once it is commissioned (§11.1).
	_logo.texture = PlaceholderFactory.build_swatch_icon("kanca", Palette.SIGNATURE, 256)

	_hand_over()


func _hand_over() -> void:
	var started_at: int = Time.get_ticks_msec()

	# Reading every data file once here keeps the first mini-game entry free of
	# disk hitches later (§9).
	ContentDB.preload_all()

	var elapsed: float = float(Time.get_ticks_msec() - started_at) / 1000.0
	Log.i("Content loaded in %.0fms" % (elapsed * 1000.0), "Boot")

	if elapsed < MINIMUM_SPLASH_SECONDS:
		await get_tree().create_timer(MINIMUM_SPLASH_SECONDS - elapsed).timeout

	SceneRouter.go_to_hub()
