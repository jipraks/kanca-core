# Kanca — Development Plan

> Working specification for AI coding agents. Read this file completely before writing any code.
> When this document conflicts with your own assumptions, **this document wins**.
> When this document is silent on something that matters, **ask — do not invent**. See [§16 Open Decisions](#16-open-decisions).

---

## 1. Product Summary

**Kanca** is a 3D educational game for Indonesian children aged 4–6, shipped as a single Android app containing several mini-games connected by a shared village hub.

| Field | Value |
|---|---|
| Play Store title | `Kanca - Game Edukatif Anak` |
| Package name | `id.kancagame.app` — **permanent, never change** |
| Repository | `jipraks/kanca-core` |
| Website | https://kancagame.id |
| Engine | Godot 4.7.2 (standard build, GDScript) |
| Platform | Android only for v1.0 |
| Content language | Bahasa Indonesia only |
| Code/comment language | English |
| Target age | 4–6 years (pre-literate) |

**Kanca** is also the name of the mascot: a *kancil* (mouse-deer) who acts as the child's companion and guide. He is **not** the player character. He narrates, instructs, encourages, and celebrates.

---

## 2. Non-Goals

These are out of scope for v1.0. Do not build them, do not scaffold for them, do not add config flags for them.

- ❌ iOS, web, or desktop builds
- ❌ Any network request of any kind
- ❌ Ads, analytics, crash reporting, telemetry, remote config
- ❌ User accounts, login, cloud save, leaderboards
- ❌ In-app purchases
- ❌ Multiplayer or social features
- ❌ Localisation infrastructure (Indonesian is hardcoded content for v1.0)
- ❌ Procedural generation of any kind
- ❌ Multiplayer, chat, or user-generated content

**Rationale:** the app targets children under 13 and will ship under Google Play's Families policy. Every item above either violates that policy, complicates compliance review, or adds surface area with no v1.0 value. The "no network calls" rule is absolute — an app that makes zero network requests can truthfully declare zero data collection, which is the strongest possible position in this category.

---

## 3. Design Rules for Ages 4–6

**These are hard constraints, not suggestions.** Most standard mobile UX advice is wrong for this age group. Violating any rule below is a bug.

### 3.1 The child cannot read

- **No UI element may depend on text to be understood.** Every button, label, and instruction must be comprehensible via icon + voice alone.
- Text may appear as decoration or as a reading aid **alongside** an icon, never as the sole carrier of meaning.
- Numerals are permitted **only when paired with a countable visual** (e.g. `3` shown next to three dots). This teaches numeral recognition instead of assuming it.
- All instructions are delivered by Kanca's voice. Every screen must be usable with the text stripped out.

### 3.2 No failure, no punishment

- **No game over. No lives. No score that can go down.**
- **No countdown timers.** Nothing that creates time pressure.
- Wrong answers get a gentle, friendly response and an immediate free retry. The mistake never costs anything.
- Never block progress on a correct answer. If a child fails the same step 3 times, Kanca escalates hints until the correct action is visually highlighted.
- Nothing in the app may produce a sad, scary, or scolding tone.

### 3.3 Touch and controls

- **Minimum interactive target: 120 × 120 px** at the 1280×720 base resolution. Primary action buttons should be larger. This is far above the adult 48dp guideline and it is deliberate.
- Minimum 40 px gap between adjacent interactive elements.
- **Drag-and-drop is the primary interaction** for mini-games. It is more reliable than tapping for small hands.
- Hub movement uses an **on-screen control in the bottom-left**, not tap-to-move. (See [§16](#16-open-decisions) — directional buttons and a virtual joystick both satisfy this; the joystick is what currently ships.) Steering the avatar and steering the camera are separate: the stick moves the child, a drag on the village turns the view.
- Every touch gets immediate feedback: visual (scale/highlight), audio (soft click), within 100ms.
- No double-tap or long-press anywhere. No swipe or multi-touch in the mini-games — drag-and-drop stays the only gesture a child needs to complete a task.
- **The village camera is the exception.** One-finger drag rotates it and pinch zooms it (§7.1). Decided 2026-08-30, replacing an earlier blanket ban on pinch. The camera is the one place where a gesture controls nothing the child can fail at: it moves the view, never the game state, so a misfire costs a moment and no progress.

### 3.4 Session and pacing

- A mini-game round must be completable in **2–4 minutes**.
- Never require the child to wait in real time. Growth, cooking, and timers resolve in **seconds**, never minutes or hours.
- Animations should be quick and readable. Cap transitions at 400ms; a child will tap again if nothing happens.
- Allow exiting any mini-game at any time from a persistent, obvious home button.

### 3.5 Audio is not optional

- The app must be fully usable **with the screen muted only as a degraded experience** — but audio is the primary instruction channel, so assume it is on.
- Never play two voice lines simultaneously. Voice is a queue, not a fire-and-forget.
- Music must duck to ~30% volume while a voice line plays.
- Background music should be calm and loopable. Never abrasive or fast.

### 3.6 Parent-facing surfaces

- Any link, settings screen, or external action must sit behind a **parental gate**: a simple challenge a young child cannot pass (e.g. "tap the number forty-seven" shown as a numeral among distractors, or a hold-for-3-seconds control).
- The parental gate must never be bypassable by trial and error within a few taps.

---

## 4. Technical Stack

### 4.1 Engine configuration

| Setting | Value | Rationale |
|---|---|---|
| Godot version | 4.7.2 stable, **standard** build | Not .NET. GDScript only. |
| Renderer | **Compatibility** (OpenGL ES 3.0) | Maximum device reach. The Indonesian market for this app skews toward low-end Android with unreliable Vulkan drivers. Low-poly stylised art does not need Vulkan features. |
| Base resolution | 1280 × 720 | |
| Stretch mode | `canvas_items` | |
| Stretch aspect | `expand` | |
| Orientation | **Landscape**, locked | Two-handed grip, better for hub navigation. |
| Target framerate | 30 FPS stable | 60 is not needed and costs battery. Stability matters more than peak. |
| Physics | Jolt (Godot 4 default) | |

Pin the exact Godot version in the README. Export templates must match the editor version exactly — 4.7.1 templates will not work with a 4.7.2 editor.

### 4.2 Performance budget

Target reference device: mid-low Android, ~4GB RAM, Adreno 6xx or Mali-G52 class, Android 10+.

| Metric | Budget |
|---|---|
| Draw calls per frame | < 100 |
| Visible triangles | < 80,000 |
| Texture memory | < 128 MB |
| Unique materials per scene | < 25 |
| Final AAB size | < 150 MB |
| Cold start to hub | < 5 seconds |

Enforcement: no real-time shadows except one baked-style directional light with low resolution. No SSAO, no SSR, no volumetric fog, no post-processing beyond a simple tonemap. Bake lighting where possible. Use texture atlases.

### 4.3 Toolchain

Already configured on the developer's machine: Android Studio (SDK, NDK, CMake), JDK 17, physical Android test device.

Agents must **not** modify Godot editor settings, keystore paths, or SDK configuration — those are machine-local and already working.

---

## 5. Repository Structure

```
kanca-core/
├── PLAN.md                     # this file
├── README.md
├── ASSETS.md                   # asset credits + license record (mandatory)
├── .gitignore                  # must ignore .godot/, *.keystore, .env, exports/
├── project.godot
│
├── addons/                     # third-party plugins only
│
├── assets/
│   ├── models/
│   │   ├── mascot/             # Kanca — custom, do not replace with stock
│   │   ├── environment/
│   │   ├── items/
│   │   └── characters/         # villagers, customers
│   ├── textures/
│   ├── fonts/
│   ├── audio/
│   │   ├── music/
│   │   ├── sfx/
│   │   └── voice/
│   │       ├── kanca/
│   │       ├── customer/
│   │       ├── number/
│   │       └── item/
│   └── ui/                     # icons, button art
│
├── scenes/
│   ├── boot/                   # splash, loading
│   ├── hub/                    # village world
│   ├── minigames/
│   │   ├── warung/
│   │   ├── kebun/
│   │   └── dapur/
│   ├── ui/                     # shared components
│   └── mascot/                 # Kanca scene, reusable across all contexts
│
├── scripts/
│   ├── autoload/
│   ├── core/                   # base classes, interfaces
│   ├── minigames/
│   └── ui/
│
├── data/                       # JSON content — see §9
│   ├── items.json
│   ├── voice_manifest.json
│   └── levels/
│       ├── warung.json
│       ├── kebun.json
│       └── dapur.json
│
└── docs/
    ├── DUBBING.md              # voice line recording script
    └── ART_STYLE.md
```

### 5.1 Repository hygiene

- **Never commit:** `*.keystore`, `*.jks`, `.env`, `export_presets.cfg` (contains keystore paths), the `.godot/` folder, or exported binaries.
- Use **Git LFS** for `assets/models/`, `assets/textures/`, and `assets/audio/` from the very first commit. Retrofitting LFS later requires history rewriting.
- Every third-party asset must be recorded in `ASSETS.md` with source URL and license before it is committed.

---

## 6. Core Architecture

### 6.1 Autoloads

Register these as singletons in `project.godot`, in this order:

| Autoload | File | Responsibility |
|---|---|---|
| `GameState` | `scripts/autoload/game_state.gd` | In-memory progress: unlocked mini-games, per-game level, coin count, inventory. Single source of truth. Emits signals on change. |
| `SaveManager` | `scripts/autoload/save_manager.gd` | Serialises `GameState` to `user://save.json`. Autosaves on mini-game completion and on app pause. Handles corrupt/missing saves by resetting to a valid default — never crash, never show an error to a child. |
| `AudioManager` | `scripts/autoload/audio_manager.gd` | Owns three buses: `Music`, `SFX`, `Voice`. Voice playback is a **queue**. Ducks music while voice plays. |
| `VoiceBank` | `scripts/autoload/voice_bank.gd` | Resolves logical voice IDs to audio streams. Handles composed multi-clip lines. See [§10](#10-audio-system). |
| `SceneRouter` | `scripts/autoload/scene_router.gd` | All scene transitions go through here. Fade out → load → fade in. Never call `change_scene_to_file` directly anywhere else. |

**Rule:** autoloads may not reference each other's internals. Communicate via signals or public methods only.

### 6.2 Mini-game contract

Every mini-game inherits from `scripts/core/mini_game.gd`:

```gdscript
class_name MiniGame
extends Node3D

## Emitted when a full session ends (all rounds complete).
signal session_completed(result: MiniGameResult)

## Emitted when the child taps the home button.
signal exit_requested()

## Called by SceneRouter after the scene is ready and faded in.
func start_session(level_index: int) -> void:
    push_error("start_session must be overridden")

## Called when the app loses focus or the pause button is pressed.
func pause_session() -> void:
    pass

func resume_session() -> void:
    pass

## Voice ID for the "how to play" instruction, played on entry.
func get_intro_voice_id() -> String:
    return ""
```

`MiniGameResult` is a simple resource carrying `rounds_completed`, `coins_earned`, and `items_produced`. The hub consumes it to update `GameState`.

This contract means adding a fourth mini-game later requires **no changes** to the hub or router.

### 6.3 Scene flow

```
Boot → Hub ⇄ MiniGame
         ↓
      Settings (behind parental gate)
```

The hub is never unloaded while a mini-game runs — it is hidden. This makes returning instant, which matters when a child bounces between activities every two minutes.

---

## 7. The Hub — Kampung Kanca

A small 3D village. The child walks around and enters buildings to start mini-games.

### 7.1 Requirements

- Enclosed, walkable area roughly 40 × 40 world units. Bounded by natural scenery (fences, hedges, water) — **never invisible walls the child can walk into and get stuck against**.
- **Follow camera, fixed pitch.** Third-person, elevated, looking down at ~35°. Follows the player on X/Z with smoothing.
- **The child controls the camera's heading and distance.** One-finger drag on the village rotates it; pinch zooms between 6.5 and 22 units; two on-screen buttons step the same zoom for anyone who does not find the pinch. The pitch stays welded at ~35° and the camera always looks at the player, so there is no way to end up staring at the sky or to lose the avatar off-frame — the two failures the earlier fixed camera existed to prevent. Decided 2026-08-30, replacing "the child never controls the camera".
- Movement stays relative to the camera, which now means relative to its *current* heading — up on the stick is always away from the viewer, whichever way the village has been turned.
- Player character is the child's avatar — a simple, neutral child character. Kanca follows alongside as a companion NPC.
- Movement: four on-screen directional buttons, bottom-left. Movement is relative to the camera, not the character. Speed ~4 units/sec — brisk enough not to feel tedious.
- Three buildings for v1.0, visually distinct and instantly readable: **Kebun** (garden plot), **Warung** (shop stall), **Dapur** (kitchen).
- Approaching a building shows a large floating icon prompt. A single tap on the prompt enters. **Never auto-enter on proximity** — accidental entry is frustrating.
- Kanca idles near the player, plays occasional idle voice lines (rate-limited to at most one per 45 seconds), and points toward the recommended next activity.

### 7.2 Progressive unlocking

| State | Available |
|---|---|
| First launch | Kebun only |
| After 1 Kebun session | Kebun + Warung |
| After 1 Warung session | All three |

Locked buildings are visible but shown as "not ready yet" with a friendly visual (under construction, sleeping). Never a padlock — locks read as punishment.

---

## 8. Mini-Game Specifications

### 8.1 MG-01 — Warung (flagship, build this first)

The child runs a small shop. A customer arrives and asks for items; the child finds them, counts them out, and hands them over.

**Learning goals:** counting 1–10, item recognition and naming, later Indonesian currency and simple change-making.

**Camera:** fixed. Positioned behind the counter, looking out at the customer. No camera movement at all.

**Round loop:**

1. Customer walks in from the left, stops at the counter, waves.
2. Kanca voice: brief instruction (first round of a session only).
3. Customer voice: order, assembled by `VoiceBank` (see [§10.3](#103-composed-voice-lines)).
4. **Order card** appears in the top-right: for each requested item, show the item icon + a row of counting dots + the numeral. This is the persistent visual reference — the child can re-hear the order by tapping the card.
5. Child drags items from the shelf onto the counter tray. Each dragged item plays its name in Kanca's voice — this is passive vocabulary learning and should never be skipped.
6. Items on the tray can be dragged back to the shelf to undo. Undo must always be available.
7. Child taps the large confirm button (Kanca giving a thumbs up).
8. **Validation:**
   - *Correct* → coin sound, customer happy voice, Kanca praise, coins fly to the counter, customer leaves. Next customer after 1.5s.
   - *Incorrect* → customer gentle confused voice, the order card pulses, items stay on the tray for adjustment. **No penalty, no round loss.** After 3 failed attempts, correct items on the shelf begin glowing.
9. Session = 5 customers. Then a completion screen: coins earned, Kanca celebration, return to hub.

**Level progression** (defined in `data/levels/warung.json`, not in code):

| Level | Content |
|---|---|
| 1 | One item type, quantity 1–3. No money. |
| 2 | One item type, quantity 1–5. No money. |
| 3 | Two item types, quantity 1–3 each. No money. |
| 4 | Two item types + customer pays with exact coins; child taps to accept payment. |
| 5 | Simple change: customer pays with a note worth more; child selects the correct single coin as change. |

Levels 4–5 are **stretch scope**. Ship levels 1–3 in the first release if time is tight; the money mechanic is where the design risk lives and it deserves real testing with children.

**Items for v1.0** (15, defined in `data/items.json`): pisang, apel, jeruk, telur, roti, susu, permen, biskuit, air mineral, mie instan, gula, minyak, sabun, beras, es krim.

**Customers:** 3 visual variants (child, adult woman, adult man) with matching voice sets. Rotate randomly, never the same variant twice in a row.

### 8.2 MG-02 — Kebun

Plant, water, and harvest produce, which then stocks the Warung.

**Learning goals:** plant life cycle, cause and effect, sequencing, patience at a child-appropriate scale.

- A grid of 6 plots, fixed camera looking down at the garden.
- Loop per plot: drag seed to plot → drag watering can to plot → plant grows through 3 visible stages over **6 seconds total** (never longer) → tap to harvest.
- Harvested produce is added to `GameState.inventory` and appears on the Warung shelf next session. **This is the chain that makes the app feel like one world rather than a bag of unrelated games.**
- Session = fill and harvest all 6 plots. ~3 minutes.
- Level progression adds seed variety, and later requires matching the right seed to a labelled plot.

### 8.3 MG-03 — Dapur

Follow a recipe's steps in the correct order.

**Learning goals:** sequencing and ordering — a genuine cognitive skill that is under-served in this category — plus ingredient and utensil vocabulary.

- Fixed camera on a kitchen counter.
- Kanca states the dish. A recipe strip along the bottom shows 3–5 steps as icons.
- Child performs each step by dragging the right ingredient or tool to the right place.
- **Order matters.** Out-of-order actions produce a gentle "not yet" from Kanca and the correct next step icon bounces. Nothing is lost.
- Dishes for v1.0: nasi goreng, es teh, roti bakar, sate. Defined in `data/levels/dapur.json`.
- Ingredients are consumed from `GameState.inventory`, purchased with Warung coins.

### 8.4 The economy chain

```
Kebun (harvest produce) → Warung (sell for coins) → Dapur (spend coins on ingredients)
```

Keep this **loose**. A child must never be blocked from playing a mini-game because they lack resources. If inventory is empty, the Warung stocks a default set automatically and the Dapur provides ingredients free. The chain is a narrative reward, not a gate.

---

## 9. Data-Driven Content

All game content lives in `data/` as JSON. **Adding a new item, level, or recipe must never require a code change.**

`data/items.json`:

```json
{
  "pisang": {
    "display_name": "Pisang",
    "model": "res://assets/models/items/pisang.glb",
    "icon": "res://assets/ui/items/pisang.png",
    "voice_id": "item_pisang",
    "category": "buah",
    "growable": true,
    "grow_stages": 3,
    "price": 2000
  }
}
```

`data/levels/warung.json`:

```json
{
  "levels": [
    {
      "index": 1,
      "customers_per_session": 5,
      "item_types_per_order": 1,
      "quantity_range": [1, 3],
      "item_pool": ["pisang", "apel", "telur", "roti"],
      "money_enabled": false,
      "intro_voice_id": "kanca_warung_intro_1"
    }
  ]
}
```

Validate all JSON on load. On a malformed file, log loudly and fall back to a hardcoded safe default — never crash the app in front of a child.

---

## 10. Audio System

Audio is the primary instruction channel. Treat it as a first-class system, not a polish task.

### 10.1 Voice pipeline

- Recording masters: WAV 48kHz mono. **Do not commit WAV masters to the repo** — keep them outside version control or in a separate LFS-tracked folder.
- In-game format: **OGG Vorbis, mono, ~96kbps**.
- Normalise to approximately −3 dBFS. Trim leading and trailing silence to under 50ms.

### 10.2 Naming convention

```
assets/audio/voice/kanca/kanca_ui_benar_01.ogg
assets/audio/voice/kanca/kanca_ui_salah_03.ogg
assets/audio/voice/customer/cust_open_02.ogg
assets/audio/voice/customer/cust_happy_01.ogg
assets/audio/voice/number/num_7.ogg
assets/audio/voice/item/item_pisang.ogg
```

Pattern: `{speaker}_{category}_{key}[_{variant}].ogg`

`data/voice_manifest.json` maps every logical voice ID to its file(s) and variant count. `VoiceBank` reads only this manifest — it never scans the filesystem.

### 10.3 Composed voice lines

Customer orders are **assembled at runtime from clips**, not recorded as whole sentences. Recording every combination would require hundreds of clips; composition needs about forty.

```
[cust_open_*] + [num_N] + [item_X] + [cust_close_*]
  "Mbak, saya mau beli"  "tiga"   "pisang"    "ya"
```

Implementation requirements for `VoiceBank.play_composed(parts: Array[String])`:

- Play clips sequentially with a **90ms gap** between them. This gap is what makes concatenation sound natural rather than clipped — do not remove it as an "optimisation".
- Multi-item orders insert a `cust_and` connector clip between item groups.
- The whole composed line must be interruptible and re-playable (the child can tap the order card to hear it again).
- If any clip is missing from the manifest, log a warning and skip that part rather than failing the whole line.

### 10.4 Variant rotation

Voice IDs marked with a variant count > 1 in the manifest must **rotate without immediate repetition**. A child plays dozens of rounds per session; hearing the identical "Hebat!" every time makes the app feel mechanical. Shuffle the variant order and cycle through it, reshuffling when exhausted.

### 10.5 Placeholder audio

Real dubbing happens **after** gameplay is working, because the line list will change. Agents must generate placeholder audio so development is never blocked:

- Generate short silent OGG files (matching expected duration, ~1s) for every voice ID in the manifest.
- Log every voice ID as it plays, so line coverage can be verified without audio.
- Provide a script `tools/check_voice_coverage.gd` that reports which manifest entries have no real recording yet.

The full recording script lives in `docs/DUBBING.md` and is maintained alongside the manifest.

---

## 11. Art Direction and Asset Pipeline

- **Style:** low-poly stylised, flat or lightly-shaded materials, bright saturated palette. No realism, no PBR complexity.
- **Sources:** Kenney and Quaternius CC0 packs for environment, props, and items. These two libraries share a compatible visual language — mixing in packs from elsewhere will make the game look assembled rather than designed.
- **Licensing rule:** CC0 only. No CC-BY, no "free for non-commercial", no asset with unclear provenance. Record every asset in `ASSETS.md` at commit time.
- **Format:** glTF (`.glb`). `.blend` files may be imported directly if needed but `.glb` is preferred for repo size.
- **Scale:** 1 world unit = 1 metre. Normalise all imported assets to this before committing.

### 11.1 The mascot is the exception

**Kanca's model is custom and must not be substituted with a stock asset.** He appears on every screen and is the app icon — a recognisable stock character would undermine the entire brand.

Requirements when the model arrives:

- Silhouette must be identifiable at **48 × 48 px**. Test this explicitly.
- 2–2.5 heads tall.
- Rigged with a minimal skeleton. Required animations: `idle`, `walk`, `point`, `celebrate`, `think`.
- Blend shapes or swappable textures for 4 expressions: happy, confused, proud, sleepy.
- One signature colour, used consistently across the icon, loading screen, and primary buttons.

As of 2026-08-30 the model exists and is procedural (see §16.2). It satisfies the proportion and silhouette requirements above and none of the rig, animation or expression requirements. The generated capsule remains as the fallback when the file is missing, as it does for every other asset — but it is no longer what anyone sees.

---

## 12. UI Components

Build these as reusable scenes in `scenes/ui/`:

| Component | Notes |
|---|---|
| `BigButton` | Minimum 120×120px, icon-driven, press animation, click SFX, optional voice ID on press. |
| `DirectionalPad` | Four arrow buttons for hub movement. |
| `OrderCard` | Item icon + counting dots + numeral. Tappable to replay the voice line. |
| `HomeButton` | Persistent, top-left, always available in mini-games. Confirms with a simple two-choice dialog (icon-based). |
| `ParentalGate` | Blocks settings and any external link. |
| `LoadingScreen` | Kanca animation + progress. Never a bare progress bar. |
| `CelebrationOverlay` | Session completion: coins, stars, Kanca celebrating. |

All UI must scale correctly across 16:9 through 20:9 aspect ratios and respect Android safe areas (notches, gesture bars). Test at 1280×720 and 2400×1080.

---

## 13. Build and Release

### 13.1 Export configuration

- Debug builds: APK, debug keystore, deployed directly to the test device.
- Release builds: **AAB** (Android App Bundle) — required by Google Play.
- Target the current Google Play required API level. Verify this at release time; the requirement increases annually.
- Include arm64-v8a and armeabi-v7a. Skip x86 unless emulator testing demands it.

### 13.2 Play Store compliance checklist

This app targets children and ships under the Families policy. All of the following are **blocking**:

- [ ] Target Audience declaration set to a children's age band
- [ ] Data safety form completed — should declare **no data collected, no data shared**
- [ ] Privacy policy live at `https://kancagame.id/privacy`
- [ ] Public contact email configured (`halo@kancagame.id`)
- [ ] Content rating questionnaire completed
- [ ] No third-party ad SDKs, no analytics SDKs, no tracking of any kind
- [ ] No advertising ID or persistent identifier collected
- [ ] Every external link behind a parental gate
- [ ] App icon (512×512), feature graphic (1024×500), minimum 4 screenshots
- [ ] Release keystore generated and **backed up in at least two places**

> ⚠️ **The release keystore and the package name are permanent.** Losing the keystore means the app can never be updated again. Changing the package name means publishing a new app and losing all installs and reviews. Treat both as irreplaceable.

> ⚠️ **Verify current Play Console requirements before planning the release date.** New personal developer accounts have been subject to a mandatory closed-testing period with a minimum tester count before production access is granted. Confirm the current rule in Play Console — it affects the timeline by weeks, not days.

---

## 14. Milestones

Each milestone must be independently verifiable on a physical device.

### M0 — Foundation
Repo initialised with the structure in §5, `.gitignore` and Git LFS configured, `project.godot` set up per §4.1, empty scene exports and runs on the test device.
**Done when:** an APK installs and displays a solid colour on the physical phone.

### M1 — Core systems and hub
All five autoloads implemented. Hub scene walkable with directional buttons. Three building entry points wired to the router. Save/load working across app restarts.
**Done when:** the child can walk around the village, enter a placeholder mini-game scene, exit back to the hub, and progress survives a force-close.

### M2 — Warung vertical slice
`MiniGame` base class. Warung levels 1–3 fully playable with placeholder audio and placeholder art. Data-driven from JSON.
**Done when:** a full 5-customer session can be completed, with correct and incorrect answers handled per §8.1.
**This is the milestone that proves the concept.** Test it with real children before proceeding.

### M3 — Audio and identity
`VoiceBank` composition working. Real dubbing recorded and integrated. Kanca's final model, rig, and animations in place. App icon.
**Done when:** the Warung is playable start to finish with real voice and the real mascot, with no text required.

### M4 — Kebun and Dapur
Both mini-games built to the same standard. Economy chain connected.
**Done when:** produce harvested in Kebun appears in the Warung, and coins earned there buy Dapur ingredients.

### M5 — Polish and compliance
Settings screen, parental gate, music, celebration overlays, safe-area handling, performance pass against §4.2 budgets, full §13.2 checklist.
**Done when:** every checklist item is ticked and the app holds 30 FPS on the reference device.

### M6 — Release
Closed testing, feedback iteration, store listing, production release.

---

## 15. Coding Conventions

- **GDScript with static typing everywhere.** `var count: int = 0`, typed function signatures, typed arrays.
- `snake_case` for files, variables, and functions. `PascalCase` for classes and nodes.
- Use `class_name` for anything instantiated from more than one place.
- **Signals over polling.** Never poll `GameState` in `_process`.
- Never call `get_node` with long hardcoded paths across scene boundaries. Use exported node references or signals.
- No business logic in `_process` or `_physics_process` beyond movement and animation.
- Every `data/` file access goes through a loader in `scripts/core/` — never `FileAccess` scattered through gameplay code.
- Comments and identifiers in English. User-facing strings in Indonesian, and all of them live in `data/`, never inline in scripts.
- No `print()` in committed code — use a `Log` helper that can be compiled out of release builds.

---

## 16. Open Decisions

**Do not resolve these unilaterally. Ask before proceeding if a task depends on one.**

1. **Repo scope.** Is `kanca-core` the single repository for the entire game, or does it hold shared systems with mini-games split into separate repos? This plan assumes **single repository**. Confirm before restructuring.
2. **Mascot design.** **Amended again 2026-08-31:** Kanca is a supplied model —
   an upright, expressive kancil with a teal neckerchief, supplied as a
   three-pose sheet (idle, point, celebrate) and repaired by
   `tools/blender/import_mascot.py`. The procedural builder is deleted. He is
   textured, which §11 otherwise forbids, and generated, which the CC0-only
   sourcing rule otherwise forbids; both still stand for everything else and
   `ASSETS.md` records the position. He gains three of §11.1's five poses and
   loses the walk — the poses have no separable legs. *Superseded, same day:*
   Kanca is a quadruped. He was built
   upright at two and a half heads on the reading that §11.1's proportion rule and
   §7.1's "points at things" both needed a biped; the project owner's judgement was
   that a mouse-deer standing on its hind legs did not look like the animal it is
   meant to be. The proportion rule in §11.1 goes with it — it describes a chibi
   biped and cannot describe a quadruped — and pointing is now a turn and a raised
   foreleg. `WalkCycle` trots him. ~~Not finalised, will be commissioned.~~
   **Resolved 2026-08-30:** Kanca is built procedurally by `tools/blender/build_characters.py`, on the project owner's instruction. The rule against *stock* models still stands and §11.1 still applies — a model described in code we wrote is authored work, which a downloaded one is not. What he still lacks is the rig, the five animations and the four expressions §11.1 asks for; a script that writes vertices cannot produce those, so pointing is currently a rotation rather than a gesture. Re-open this if the mascot is ever commissioned properly.
3. **Village art.** **Resolved 2026-08-31:** the procedurally generated village
   was replaced by a single supplied mesh (Meshy AI), on the project owner's
   instruction and with the eye-level render in front of them. It is a decision
   against §11's texture and PBR rules and against the CC0-only sourcing rule,
   both of which still stand for everything else; `ASSETS.md` records what was
   repaired to make it usable, what it costs, and the copyright position.
   Re-open this if the village is ever modelled properly.
4. **Movement controls.** Directional buttons are the specified default, based on the belief that tap-to-move confuses this age group. A virtual joystick (available natively since Godot 4.7) may be tested as an alternative — but only after directional buttons are working and only with real children.
5. **Renderer.** Compatibility is chosen for reach. If device testing shows acceptable Vulkan behaviour across the target range, Mobile renderer may be reconsidered for better lighting. Do not switch without device data.
6. **Money mechanics.** Warung levels 4–5 (payment and change) are unvalidated with the target age group. Treat as stretch scope and do not let them block the release of levels 1–3.
7. **Monetisation.** Undecided for v1.0. Assume free with no IAP and no ads. Do not build any monetisation scaffolding.

---

## 17. Quick Reference for Agents

Before every commit, verify:

- [ ] No UI element requires reading to be understood
- [ ] No timers, no fail states, no penalties
- [ ] All touch targets ≥ 120×120 px at base resolution
- [ ] No network calls, no analytics, no ads
- [ ] All user-facing strings in `data/`, not in scripts
- [ ] All new assets recorded in `ASSETS.md` with a CC0-compatible license
- [ ] No keystore, `.env`, or `.godot/` staged
- [ ] Static types on all new declarations
- [ ] New content is data-driven, not hardcoded
- [ ] Tested on the physical device, not only in the editor