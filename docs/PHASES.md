# Kanca — Phase Breakdown

Execution plan derived from [PLAN.md §14 Milestones](../PLAN.md). PLAN.md defines *what*
and *why*; this file defines *in what order* and *what "done" looks like per phase*.

If the two ever disagree, **PLAN.md wins** and this file gets fixed.

---

## Phase map

| Phase | Name | PLAN milestone | Status | Blocked on external assets? |
|---|---|---|---|---|
| P0 | Repo foundation & build pipeline | M0 | Built | No |
| P1 | Core systems (autoloads, data, mini-game contract) | M1 (part) | Built | No |
| P2 | UI components & the Hub | M1 (part) | Built | No |
| P3 | Warung vertical slice (levels 1–3) | M2 | Built, awaiting child testing | No |
| P4a | Kebun + economy chain | M4 (part) | Built, awaiting child testing | No |
| P4b | Dapur | M4 (part) | Not started | No |
| P5 | Audio & identity (real dubbing, Kanca model, icon) | M3 | Identity built, audio not started | **Yes** — voice, and a rig |
| P6 | Polish, settings, parental gate, performance | M5 | Not started | Partly |
| P7 | Compliance & release | M6 | Not started | **Yes** |

"Built" means the phase's own headless suite passes. It does **not** mean it has
been run on the physical device or in front of a child, which are separate gates
and are called out per phase below.

### Deviation from PLAN.md milestone order — flagged deliberately

PLAN.md orders M3 (audio + mascot identity) **before** M4 (Kebun + Dapur). This breakdown
swaps them: P4 builds the remaining mini-games, P5 integrates real audio and the mascot.

Rationale: M3 depends entirely on work that happens **outside this repository** — voice
talent recording a script, and a commissioned mascot model, rig and animations. Neither
can be produced by writing code. Blocking all engineering on them would idle the build.

The two tracks run in parallel:

- **Engineering track:** P0 → P1 → P2 → P3 → P4 → P6 → P7
- **Asset track (starts at the same time as P3):** finalise the dubbing script from
  `data/voice_manifest.json` → record → master → drop into `assets/audio/voice/`.
  Commission the mascot → rig → animate → drop into `assets/models/mascot/`.

P5 is the point where the asset track merges back in. Every system is built so that
merge is a **file drop with no code change**: `VoiceBank` resolves paths from the
manifest and silently falls back to a logged, timed placeholder when a file is absent,
and `PlaceholderFactory` yields to a real `.glb` the moment one exists at the expected
path.

**This reordering is a judgement call, not a resolved open decision.** Say the word and
P4/P5 swap back.

---

## P0 — Repo foundation & build pipeline

**Goal:** an empty but correctly-configured project that installs and runs on the phone.

- Directory tree per PLAN.md §5.
- `.gitignore` (keystore, `.godot/`, exports, `.env`, WAV masters).
- `.gitattributes` with Git LFS from the **first** commit (§5.1).
- `project.godot`: Compatibility renderer, 1280×720, `canvas_items`/`expand`, landscape
  locked, 30 FPS cap, autoloads registered, 3D physics layer names.
- `default_bus_layout.tres` with `Music` / `SFX` / `Voice` buses.
- Boot scene that shows the brand colour and hands over to the router.
- `README.md`, `ASSETS.md`, `docs/`.

**Done when:** a debug APK installs on the physical device and displays the boot screen.

**Status:** the project boots to the hub with zero errors. The APK step is
outstanding — `%APPDATA%/Godot/export_templates` is empty, so the 4.7.2 templates
still need downloading through the editor before anything can be exported.

---

## P1 — Core systems

**Goal:** every shared system a mini-game will need, with nothing game-specific in them.

- Five autoloads per §6.1: `GameState`, `SaveManager`, `AudioManager`, `VoiceBank`,
  `SceneRouter`. No autoload touches another's internals.
- `Log` helper — replaces `print()` and compiles down in release builds (§15).
- `ContentDB` + `JsonLoader` in `scripts/core/`: the **only** path to `data/` files.
  Validates on load, falls back to a safe hardcoded default on malformed JSON (§9).
- `MiniGame` base class and `MiniGameResult` (§6.2).
- Seed data: `items.json` (15 items), `voice_manifest.json`, `levels/*.json`.

**Done when:** the project boots headless with zero errors, a save round-trips through
`user://save.json`, and a deliberately corrupted save resets cleanly instead of crashing.

**Status:** done. `tools/smoke_test.tscn`, 53 checks.

---

## P2 — UI components & the Hub

**Goal:** the village works and progress survives a force-close.

- `scenes/ui/`: `BigButton`, `DirectionalPad`, `HomeButton`, `IconConfirmDialog`,
  `OrderCard`, `LoadingScreen`, `CelebrationOverlay`, `ParentalGate` (§12).
- Hub: 40×40 walkable village, hedge boundary (no invisible walls), 35° follow camera
  the child can turn and zoom, joystick movement, three buildings, tap-to-enter prompt,
  Kanca companion with rate-limited idle lines (§7.1).
- Progressive unlocking: Kebun → +Warung → +Dapur (§7.2).
- Safe-area handling for notches and gesture bars.

**Done when:** the child can walk the village, enter and exit a mini-game, and progress
survives a force-close.

### The camera stopped being fixed

§7.1 originally said the child never controls the camera, and §3.3 banned pinch
outright. Both were changed on the project owner's instruction on 2026-08-30, and
PLAN.md now records the new rule rather than the old one.

What was kept is the part with a reason behind it. The pitch is still welded at
35° and the camera still always looks at the player, so no input produces a view
the child has to be rescued from — no sky, no lost avatar. What opened up is
heading and distance, neither of which can strand anyone.

Two things came out of it that were not obvious going in:

- **Movement is specified as camera-relative, and a turning camera makes that
  load-bearing.** `screen_to_world` has to rotate input by the current heading,
  or the child turns the village half a circle and then walks towards the screen
  when they push up. That failure is invisible in a screenshot; the core suite
  pins it.
- **The gesture layer has to sit at the bottom of the UI stack.** Godot offers a
  touch to the topmost control first, so a full-screen catcher above the joystick
  would swallow every press and spin the village whenever the child tried to
  walk. Verified with a real drag in a real window — see `scene_shot -- hub
  unlocked drag` and `dragstick`, which report the resulting heading.

Still unproven: whether children of this age find the pinch at all, and whether
turning the village helps them or disorients them. The zoom buttons exist partly
as insurance against the first. Both belong in the §14 testing round.

**Status:** done. `tools/ui_smoke_test.tscn` (84 checks, including an automated
audit of the §3.3 touch rules) and `tools/integration_test.tscn` (29 checks).

A building whose mini-game scene does not exist yet shows as under construction
and cannot be entered, so the village never offers a door that leads nowhere while
P4 is outstanding.

**Movement controls — §16.3 was resolved by the developer, not by testing.** The
hub now uses an analogue stick (Godot 4.7's own `VirtualJoystick`, wrapped as
`AnalogStick`) instead of the directional pad. §16.3 allows a joystick "only
after directional buttons are working and only with real children"; the first
half held, the second has not happened yet.

The directional pad is still in the repo and still tested. Both implement
`MovementControl`, so swapping them back for a session with children is one line
in `hub.tscn` — which is what §16.3 asked for in the first place.

---

## P3 — Warung vertical slice

**Goal:** the milestone that proves the concept.

- Full round loop per §8.1: customer arrival → composed voice order → order card →
  drag items to tray → undo by dragging back → confirm → validate.
- Correct: coins, praise, customer leaves. Incorrect: gentle response, free retry,
  **no penalty**. Three failures escalate to glowing the correct shelf items.
- Session = 5 customers, then celebration and return to hub.
- Levels 1–3 data-driven from `data/levels/warung.json`. Levels 4–5 (money, change) are
  stretch scope per §16.5 and are gated off, not half-built.

**Done when:** a full 5-customer session completes on the device with placeholder audio
and placeholder art. **Test with real children before starting P4.**

**Status:** built and green headlessly — `tools/warung_test.tscn`, 39 checks,
covering the drag path through real pointer input, the hint escalation, and a full
five-customer session. Not yet run on the device, and **not yet tested with
children, which is the actual gate on P4**.

Two things the automated checks changed along the way, worth knowing:

- The shelf slot spacing is derived from the touch rules rather than chosen. At
  the Warung camera distance, 0.85 world units is what keeps neighbouring slots
  more than 40 px apart on screen. More than five slots cannot be shown at the
  minimum touch size without running off the frame, so the count is capped and
  the cap is logged rather than applied silently.
- The strongest hint glows *every* item in the order, not only the ones still
  short. Glowing "what is missing" highlights nothing at all when a child has one
  too many — which left them stuck at exactly the point §8.1.8 exists to prevent.

---

## P4 — Kebun & Dapur + economy chain

- Kebun: 6 plots, seed → water → 3 growth stages in 6 seconds total → harvest (§8.2).
- Dapur: recipe strip, ordered steps, gentle "not yet" on wrong order (§8.3).
- Economy chain wired: Kebun harvest stocks the Warung, Warung coins buy Dapur
  ingredients — and **never gates play** when inventory is empty (§8.4).

**Done when:** produce harvested in Kebun appears on the Warung shelf, and coins earned
there buy Dapur ingredients.

**Status of P4a (Kebun):** built and green - tools/kebun_test.tscn, 73 checks. The
first half of the chain is closed and verified end to end by the integration
suite: a fresh save is sent to the garden, what is grown lands in the inventory,
that unlocks the Warung, and the shelf then stocks itself from the produce.

The Kebun camera is **orthographic**, unlike every other scene. That was not a
style choice. Under perspective the back row of plots projected smaller than the
front row, and no arrangement satisfied both the 120px minimum and the 40px gap
at once. Orthographic makes every plot identical on screen, so no plot is harder
for a child to hit than another, and the layout constants fall straight out of
the touch rules instead of being tuned by eye.

**P4b (Dapur) is what remains**, plus the known data gap below.

Groundwork already in place: the Warung stocks its shelf from `GameState.inventory`
first and falls back to the level pool, and records what it sold as
`items_consumed`. The chain is loose in both directions, as §8.4 requires.

**Known gap to close in this phase:** `data/levels/dapur.json` names ingredients
and utensils that are not in `data/items.json` — `es_batu`, `mentega`, `piring`,
`spatula`, `daging`, `kecap`, `tusuk`. They resolve to a logged fallback today.
They need real entries, and they should be marked so they never appear on the
Warung shelf as things to sell.

---

## P5 — Audio & identity *(external assets required)*

- Dubbing script finalised in `docs/DUBBING.md`, recorded, mastered to OGG per §10.1.
- `tools/check_voice_coverage.gd` reports zero missing recordings.
- Kanca's commissioned model, rig, five animations, four expressions (§11.1).
- App icon derived from the mascot; 48×48 silhouette test passed.

**Done when:** the Warung plays start to finish with real voice and the real mascot,
fully usable with every string stripped out.

**Status — identity: built.** The icon, the launcher icons, the boot splash and
the wordmark are in, all rendered from the mascot model rather than drawn beside
it, and `tools/check_branding.tscn` is in `run_tests` — including the 48×48
silhouette test §11.1 asks for, which is now measured rather than eyeballed. The
app no longer ships a placeholder icon.

What is still open from this phase is the half that needs a person. The rig, the
five animations and the four expressions cannot come out of a generator script,
so Kanca still points by rotating.

**Status — audio: not started.** The manifest is written and the tooling is ready
— 65 lines, 112 clips once variants are counted. `docs/DUBBING.md` is generated
from it, and `tools/check_voice_coverage.tscn` currently reports 0 of 65
recorded. Nothing in the engine is waiting on any of it: an unrecorded line still
queues, still ducks the music and still takes its stated duration.

---

## P6 — Polish, settings, parental gate, performance

- Settings screen behind the parental gate; music; celebration overlays.
- Performance pass against the §4.2 budgets on the reference device.
- Aspect-ratio pass: 16:9 through 20:9, tested at 1280×720 and 2400×1080.

**Done when:** the app holds 30 FPS on the reference device and every §17 checklist item
passes.

---

## P7 — Compliance & release

- Every blocking item in §13.2.
- Release keystore generated and **backed up in two places** — losing it ends the app's
  ability to ever update.
- Closed testing (verify the current Play Console tester-count and duration requirement
  before committing to a date — it moves the timeline by weeks).

**Done when:** the app is live under the Families policy.

### The village floor

The buildings were finished long before the village looked like anywhere, and
the reason was the ground: one flat green box, three beige rectangles laid on
top of it for paths, and seventy per cent of the screen empty. Good buildings
standing on a snooker table still read as a snooker table.

What changed:

- **The paths are painted into the ground rather than stacked on it.** One
  vertex-coloured mesh (`scripts/hub/village_ground.gd`), which buys no
  z-fighting, no strips left floating when the ground stops being flat, and
  edges that fray into the grass instead of being ruled.
- **Smooth colour and smooth normals, deliberately.** The first version coloured
  each triangle as a whole and used flat normals, reasoning that the art being
  chased is faceted. That was a misreading: what is faceted in it is the
  *objects* - the rocks, the plants, the roofs. The ground under them is smooth.
  Flat colour per triangle turned the meadow into a chessboard with the mesh grid
  showing through it, and flat normals on an undulating surface shaded every
  triangle differently, which made the same grid visible twice over.
- **Three octaves of noise rather than one.** A single broad wave gives a field
  that is lighter over there and flat everywhere between; a single fine one gives
  speckle. All three are far coarser than the mesh, so the lattice they are
  sampled on never shows.
- **Four hundred pieces of undergrowth**, biased towards the boundary so the
  village has an overgrown edge and an open middle rather than an even sprinkle.
- **A bamboo fence in front of the hedge**, because a green wall against green
  grass is very close to the invisible wall 7.1 exists to forbid.
- **Hills and far trees beyond the boundary.** A hedge with empty sky above it
  tells a child exactly how big the world is.

### The performance budget stopped being a guess

That art work took the village to **355 draw calls and 136,480 triangles**
against 4.2's limits of 100 and 80,000 - and nothing said so. Every model was
under budget on its own; the cost was in how many of them there were and how
many materials each carried.

`tools/scene_budget.gd` now measures the running scene from the renderer's own
counters and runs as part of `tools/run_tests.ps1`. It is not headless: a
headless run draws nothing, and an estimate from triangle counts in the build
scripts would have said the village was fine right up until it was not.

It also refuses to report on a scene that failed to build. It reported "within
budget" for a village of 4,222 triangles once, because a parse error in `hub.gd`
left the scene as bare nodes with no script attached - Godot builds the nodes,
fails to attach the script, and prints the error into a log nobody is reading. A
measuring tool that passes when the thing it measures is broken is worse than no
tool, because it is trusted.

Current: **70 draw calls, 75,019 triangles.**

### Walking, and two things floating above buildings

The avatar slid. Legs are now separate child objects in the exported `.glb`, with
the pivot at the hip, so a walk is two rotations about X and a body bob -
`scripts/core/walk_cycle.gd`, shared by the player and the Warung customers. No
skeleton, no animation clips: rigid legs pivoting at the hip is the whole
vocabulary a character sixty pixels tall needs, and it costs four draw calls
across the village rather than a rig.

Splitting the model broke two things that only showed up as numbers. The
single-object helpers `scale_to_longest_side` and `place_origin_at_base` only see
the object handed to them, so once the legs were children they normalised the
*torso*: every character came out five per cent tall and sunk two centimetres
into the ground. `fit_hierarchy` replaces both. And the vertex gradient, measured
per object, squeezed the full base-to-top ramp into a 20cm leg and shaded it like
a different material - `bake_vertex_colours` now takes the character's own
`z_range`.

Footsteps are synthesised as filtered noise rather than a tone. A sine at this
length comes out as a small musical blip, and a blip playing twice a second pulls
the ear straight to it.

Two things were floating above the buildings, and both were bugs:

- **An unlocked building hovered a picture of itself.** The marker showed
  `get_icon()`, and the building icons are rendered from the building models. It
  said nothing the sign below already said. §7.1's "large floating icon prompt"
  is the UI button that appears on approach; the 3D marker is now only for the
  two states a sign cannot express, resting and not-yet-built.
- **The not-yet-built marker was an ✕.** Two crossed lines, which is the
  universal mark for *wrong*, hanging over a building a child cannot enter yet.
  §7.2 refuses a padlock because a lock reads as punishment; an ✕ is worse than a
  padlock. It is now a stack of blocks.

### The village became solid

Four faults, reported from play, all of the same family: things that looked like
they were there and were not.

- **The fence is now the boundary.** It used to be decoration standing in front
  of a dark green hedge that carried the collision. So the child walked *through*
  the fence and was stopped by a surface half a metre behind it — which is very
  close to the invisible wall §7.1 exists to forbid, with the added insult of a
  visible fence that does nothing. The hedge is gone entirely; the colliders sit
  on the line of posts, and `Hub.fence_line()` is the single figure the panels,
  the colliders and the scatter all read.
- **Trees are solid.** MultiMesh draws hundreds of copies from one mesh and
  carries no collision at all, so every tree in the village could be walked
  straight through. Each instance now gets a trunk collider — the trunk only, not
  the canopy, because being blocked by leaves a metre above your head is its own
  kind of wrong.
- **Backdrop hills stopped eating the player.** Nothing checked a hill's radius
  against its distance: at the old numbers one could be 40 metres across and 36
  from the centre, putting its near slope inside the fence. Unshaded and
  uncollidable, it read as a wall the child sank into. Radius is now clamped to
  leave clear ground outside the fence.
- **The "still being built" marker was unreadable.** A stack of white rounded
  squares in the sky reads as leftover interface — the first person to see it
  asked what it was, which is the answer. Brick-coloured, it reads as a pile of
  materials. Shape was not the problem; colour was.

`tools/integration_test.gd` now walks the avatar into the fence and checks where
they stop, and counts trunk colliders against the trees actually planted rather
than against `TREE_COUNT` — the scatter rejects any tree that would land on a
path or a building, so the count is not knowable in advance, and a hard-coded one
would pass for the wrong reason the day a building moves.

### The counting dots came off the order card

§8.1 step 4 specifies "item icon + a row of counting dots + the numeral", and the
dots were the part that mattered: §3.1 forbids UI that needs reading, and for a
three-year-old who does not yet know that the shape "3" means three, the dots
were the only thing on the card answering *how many*. The numeral was the reading
aid beside them.

Removed on the project owner's instruction on 2026-08-30 — the card was judged
cluttered, and the two do compete at that size. `CountingRow.show_dots` keeps the
mechanism a flag rather than a deletion, and the numeral is enlarged to 76pt to
carry the quantity alone.

**What this costs is real:** quantity on the order card is now literate-only. The
youngest players in the target range can see *what* is wanted and not *how many*.
That belongs in the §14 testing round rather than in an argument.

Narrowing the card broke something the UI suite caught: with less height to fill,
the row box distributed the spare into the icon and rendered a square icon at
96×105. `EXPAND_IGNORE_SIZE` stops the texture deciding the slot; it took
`SIZE_SHRINK_CENTER` to stop the container deciding it too.

### Buildings are solid all the way to their steps

The collider came from `building_size` in `data/minigames.json`, which describes
the building. The model also has steps, a veranda and a fence, and none of that
is in the number — so a child could walk onto the Warung's steps, stand at ground
level because that is where the floor is, and watch the step swallow their legs
to the knee. The collider is now measured from the model's own bounds, which
means anything a modeller adds is solid the moment it exists.

### The Kebun got built

Six flat brown squares on a flat green plane, with a 2D icon standing in for
every plant. Now: raised beds with timber frames and clods of soil, three growth
stages as separate models rather than one prism getting taller, a woven seed
basket and a real watering can — and the village's own ground, fence and
undergrowth around it rather than a second, different-looking world.

Two bugs surfaced doing it, and both were in code that had been working for
weeks:

- **The hub's interface was on top of every mini-game.** `_set_hub_active` hid
  the hub's `Node3D` — but a CanvasLayer does not inherit visibility from a 3D
  ancestor; that is the entire point of it. So the joystick and the zoom buttons
  sat over the Kebun, and the child saw two coin counters stacked on each other,
  one from the hub and one from the game. Layers now have to be hidden by hand.
- **A plaza of radius zero is not "no plaza".** `VillageGround.dirt_at` computes
  `distance_to(centre) - radius`, so with a radius of zero everything near the
  origin reads as trodden path — and the Kebun, reusing that ground with no
  plaza at all, grew a patch of bare earth in the middle of its lawn. The scatter
  had the same shape of bug, rejecting plants for standing too close to a plaza
  that did not exist.

Both are the cost of reuse, and both are worth it: the alternative was a second
ground, a second fence and a second scatter, each with its own bugs to find.
