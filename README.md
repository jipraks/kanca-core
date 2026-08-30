# Kanca — Game Edukatif Anak

3D educational game for Indonesian children aged 4–6. Android only. One app, several
mini-games, one shared village hub.

| | |
|---|---|
| Package name | `id.kancagame.app` — **permanent, never change** |
| Engine | **Godot 4.7.2 stable, standard build** (not .NET) |
| Renderer | Compatibility (OpenGL ES 3.0) |
| Base resolution | 1280 × 720, landscape locked |
| Content language | Bahasa Indonesia |
| Code & comments | English |

> **Read [`PLAN.md`](PLAN.md) completely before writing any code.** It is the
> specification. [`docs/PHASES.md`](docs/PHASES.md) is the execution order.

---

## Getting started

### 1. Engine

Godot **4.7.2 stable** exactly. Export templates must match the editor version — 4.7.1
templates will not work with a 4.7.2 editor.

On this machine the editor lives at:

```
D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
```

### 2. Git LFS

Models, textures and audio are LFS-tracked from the first commit. Before your first
clone or pull of binary assets:

```bash
git lfs install
```

### 3. Open the project

Open `project.godot` in the editor, or run the whole test suite from the repo root.

**PowerShell** (point it at the editor once per session):

```powershell
$env:GODOT = "D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
```

```powershell
./tools/run_tests.ps1
```

Or pass the path directly, without setting anything:

```powershell
./tools/run_tests.ps1 -Godot "D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
```

**git-bash**, if you prefer it:

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ./tools/run_tests.sh
```

The two runners do the same thing. Note that the bash form above is bash-only —
`VAR=value command` is not PowerShell syntax and PowerShell will refuse it.

---

## Tests

Everything is verifiable headlessly. No suite needs a device, a window or a human.

| Suite | What it covers |
|---|---|
| `tools/smoke_test.tscn` | Autoloads, content loading, save round-trip, corrupt-save recovery, voice queue |
| `tools/ui_smoke_test.tscn` | Every UI component, plus an automated audit of the §3.3 touch rules |
| `tools/warung_test.tscn` | A full five-customer Warung session, right answers and wrong ones |
| `tools/integration_test.tscn` | Boot to hub to mini-game and back, unlocking, progress across a restart |

Run one on its own to see every individual check:

```powershell
& $env:GODOT --headless --path . res://tools/warung_test.tscn
```

The touch-target audits are the ones worth knowing about. PLAN.md §3.3 sets a
120 × 120 px minimum and a 40 px gap, and §17 asks for that to be verified before
every commit. Checking it by eye on a phone does not scale, so the UI suite walks
each component and measures it, and the Warung suite projects the 3D shelf into
screen space and measures that. Both have already caught real violations.

### Voice tooling

```powershell
& $env:GODOT --headless --path . res://tools/check_voice_coverage.tscn
```

```powershell
& $env:GODOT --headless --path . res://tools/generate_dubbing_script.tscn
```

The first reports which of the 65 manifest entries still have no recording. The
second regenerates `docs/DUBBING.md` from the manifest — never edit that file by
hand, or the recording and the game will drift apart.

---

## Project layout

```
scenes/       Scene files (.tscn), grouped by area
scripts/      GDScript, mirroring the scene layout
  autoload/     The five singletons — see PLAN.md §6.1
  core/         Base classes, data loaders, shared helpers
  ui/           Reusable UI component logic
  hub/          Village hub logic
  minigames/    One folder per mini-game
data/         All game content as JSON — see PLAN.md §9
assets/       Models, textures, audio, fonts, UI art (LFS)
docs/         Dubbing script, art style, phase plan
tools/        Developer-only scripts, never shipped
```

`scripts/hub/` is the one addition to the tree in PLAN.md §5 — the hub is a substantial
scene with several controllers and putting them in `scripts/core/` would have muddied
"core" into "everything".

`tools/` is developer-only and must be excluded from release exports.

### One gotcha if you hand-write a `.tscn`

Godot serialises `Transform3D` **row-major** in scene files, while the GDScript
constructor takes column axes. The two are transposes of each other, so a rotation
matrix that looks right in code comes out rotating the opposite way in a scene file.
Every camera and light in this repo has been checked against the running engine
rather than against the maths. If you write one by hand, verify it — a camera
pitched +30° instead of −30° still renders, just at nothing you wanted to see.

The same goes for colour. Three separate colour-space bugs have been fixed in
this project and every one of them looked like a lighting problem first: glTF
base colour factors are linear while swatches are sRGB, Blender's viewport
`diffuse_color` is sRGB while the BSDF beside it is linear, and Godot's
Compatibility renderer treats mesh vertex colours as sRGB whatever
`vertex_color_is_srgb` says. If a colour looks wrong, check which space it is in
before touching a light.

---

## Architecture in one page

Five autoloads, registered in this order, none of them reaching into another's
internals — they talk through signals and public methods only:

| Autoload | Responsibility |
|---|---|
| `GameState` | Single source of truth for progress, coins, inventory. Emits on change. |
| `SaveManager` | Serialises `GameState` to `user://save.json`. Corrupt save ⇒ clean reset. |
| `AudioManager` | Owns `Music` / `SFX` / `Voice` buses. Voice is a **queue**. Ducks music. |
| `VoiceBank` | Resolves logical voice IDs to streams, composes multi-clip lines. |
| `SceneRouter` | Every scene transition. Nothing else calls `change_scene_to_file`. |

Mini-games inherit `scripts/core/mini_game.gd` and are reached only through the router,
so adding a fourth one needs no change to the hub or the router.

All content — items, levels, recipes, voice lines — lives in `data/` as JSON, read
through `ContentDB`. **Adding an item or a level must never require a code change.**

---

## Placeholders

Development is never blocked on art or audio that does not exist yet:

- **Models** — `PlaceholderFactory` builds a coloured primitive when the `.glb` named in
  `data/items.json` is absent. The moment a real file appears at that path it is used
  instead, with no code change.
- **Voice** — `VoiceBank` resolves paths from `data/voice_manifest.json`. When a file is
  missing it logs the voice ID and simulates the clip's duration, so timing, queueing,
  ducking and composition are all exercised without a single recorded line.
  Run `tools/check_voice_coverage.gd` to list what still needs recording.

Placeholders are marked in an obviously provisional style on purpose. **Never ship
them**, and never let placeholder art drive a design decision (PLAN.md §11.1).

---

## Current state

Phases P0 through P4a are built and green (see [`docs/PHASES.md`](docs/PHASES.md)):
the foundation, all five autoloads, the UI component set, the walkable village,
the Warung at levels 1-3, and the Kebun with the first half of the economy chain.

A fresh save now plays through properly: the village sends a new player to the
garden, what they grow lands in the inventory, that opens the Warung, and the
shelf stocks itself from the produce. Serving the Warung opens the Dapur, which
is **not built yet** and shows in the village as under construction rather than
as a door that leads nowhere.

PLAN.md §14 is explicit that M2 is the milestone that proves the concept and
**should be tested with real children before the remaining mini-game is built**.
That is the next step, and it is not an engineering one.

## Hard rules

These come from PLAN.md and are not negotiable:

- No network requests of any kind. No ads, no analytics, no telemetry. The app must be
  able to truthfully declare **zero data collected**.
- No UI element may depend on text to be understood — the player cannot read.
- No fail states, no lives, no countdown timers, no score that can go down.
- Minimum touch target **120 × 120 px** at 1280×720, minimum 40 px apart.
- Static types on every declaration. No `print()` — use `Log`.
- Every user-facing string lives in `data/`, never inline in a script.
- Never commit a keystore, `.env`, `export_presets.cfg`, `.godot/`, or a built binary.

Full pre-commit checklist: PLAN.md §17.
