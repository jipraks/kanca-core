class_name Palette
extends RefCounted

## Every colour used by generated placeholder art and by code-built UI lives here.
##
## PLAN.md §11.1 requires one signature colour used consistently across the icon,
## the loading screen and primary buttons. SIGNATURE is provisional until the
## mascot is commissioned (§16.2) — changing it here changes it everywhere.

const SIGNATURE := Color("f5a623")
const SIGNATURE_DARK := Color("c9821a")
const SIGNATURE_LIGHT := Color("ffd18a")

const CREAM := Color("fee5ad")
const SKY := Color("86c7eb")
const GRASS := Color("7cc576")
const GRASS_DARK := Color("5da85c")
const SOIL := Color("9c6b4a")
const WOOD := Color("b07d42")
const STONE := Color("b9b3a7")
const PATH := Color("c2a165")

## Ground colours, kept apart from GRASS and PATH above because the village floor
## is not one colour and never was. A single flat green over forty units reads as
## a snooker table however good the buildings standing on it are; what makes a
## place look grown rather than laid out is that no two square metres of it match.
const MEADOW := Color("7cb342")
const MEADOW_LIGHT := Color("9ccc65")
const MEADOW_DARK := Color("5a8f34")
const MEADOW_DRY := Color("a8bb52")
const DIRT := Color("d2a35c")
const DIRT_DARK := Color("b8843f")
const HILL_FAR := Color("6f9e63")
const HILL_HAZE := Color("8fb389")

## Building materials, for the "still being built" marker. A colour, not a
## shape, is what stops it reading as leftover UI.
const BRICK := Color("d97b44")

## Feedback colours. Note there is no "wrong" red anywhere — PLAN.md §3.2 forbids
## anything that reads as punishment. An incorrect answer gets ATTENTION, which is
## a warm nudge, not a rebuke.
const CORRECT := Color("6ec46e")
const ATTENTION := Color("ffc861")
const HINT_GLOW := Color("fff3b0")

const UI_PANEL := Color("fffaf0")
const UI_PANEL_EDGE := Color("d9c9a8")
const UI_TEXT := Color("4a3b2a")
const UI_DISABLED := Color("cfc7ba")

const CURTAIN := Color("2b2118")


## Deterministic colour for a string key, so a given item always looks the same
## across runs without anybody hand-picking 15 colours for placeholders.
static func for_key(key: String) -> Color:
	var h: int = hash(key)
	var hue: float = float(h % 360) / 360.0
	var sat: float = 0.55 + float((h / 360) % 25) / 100.0
	var val: float = 0.72 + float((h / 9000) % 20) / 100.0
	return Color.from_hsv(hue, sat, val)
