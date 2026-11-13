extends Control

## First scene the app shows (PLAN.md §6.3).
##
## Its whole job is to warm the content cache and hand over to SceneRouter. It is
## freed by the router once the hub exists and is never returned to.
##
## What it draws is the same image the engine drew for itself a moment earlier —
## `application/boot_splash/image`, over the same `bg_color`. Two pictures of the
## brand, however close, produce a visible jump at the handover; one picture
## produces none, and the seam a child would notice is the one nobody planned.

## Long enough that the brand registers, short enough that nobody is waiting.
## PLAN.md §4.2 budgets under five seconds from cold start to hub, and §3.4
## forbids making a child wait in real time for anything.
const MINIMUM_SPLASH_SECONDS := 0.6

@onready var _lockup: TextureRect = $Lockup
@onready var _fallback: CenterContainer = $Centre
@onready var _fallback_logo: TextureRect = $Centre/Logo


func _ready() -> void:
	Log.i("Kanca %s starting" % ProjectSettings.get_setting("application/config/version", "?"), "Boot")

	# Filling the viewport rather than centred at its own size, because that is
	# what the engine does with the same image a moment earlier. Anything else
	# makes the logo change size on the frame this scene appears.
	var lockup: Texture2D = PlaceholderFactory.build_splash_lockup()
	_lockup.texture = lockup
	_lockup.visible = lockup != null

	# Only reachable if the brand images have been deleted from the repo.
	_fallback.visible = lockup == null
	if lockup == null:
		_fallback_logo.texture = PlaceholderFactory.build_mascot_portrait(220)

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
