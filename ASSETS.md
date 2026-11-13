# Asset Register

Every third-party asset in this repository **must** be recorded here, with its source
URL and license, **before** it is committed (PLAN.md §5.1).

## Licensing rule

**CC0 only.** No CC-BY, no "free for non-commercial", no asset with unclear provenance.
An asset whose license cannot be verified does not enter the repository — the app ships
under Google Play's Families policy and a licensing dispute at review time is expensive.

Preferred sources, because they share a compatible visual language (PLAN.md §11):

- [Kenney](https://kenney.nl/assets) — CC0 1.0
- [Quaternius](https://quaternius.com/) — CC0 1.0

## Models

Third-party models only. Anything built by our own scripts is listed under
Original work below.

| File | Source | Author | License | Notes |
|---|---|---|---|---|
| _(none yet)_ | | | | |

## Procedural models — our own work

Built by `tools/blender/build_items.py`, which is committed alongside them. The
script is the source; the `.glb` is output, and re-running it reproduces the file
exactly.

Worth being explicit about, given the copyright question hanging over generated
art: a model described in code we wrote is unambiguously **authored work**. There
is no provenance question to answer later.

```powershell
& "D:/Program Files/Blender/blender.exe" --background --factory-startup `
  --python tools/blender/build_items.py -- --item pisang `
  --out assets/models/items/pisang.glb
```

| Item | `.glb` | icon `.png` |
|---|---|---|
| `air_mineral` | 13.0 KB | 45.8 KB |
| `apel` | 6.9 KB | 54.9 KB |
| `beras` | 8.1 KB | 50.0 KB |
| `biskuit` | 10.7 KB | 49.3 KB |
| `es_krim` | 6.2 KB | 45.4 KB |
| `gula` | 6.8 KB | 49.8 KB |
| `jeruk` | 6.4 KB | 50.2 KB |
| `mie_instan` | 7.2 KB | 40.1 KB |
| `minyak` | 13.0 KB | 43.1 KB |
| `permen` | 7.5 KB | 43.3 KB |
| `pisang` | 7.6 KB | 33.2 KB |
| `roti` | 10.8 KB | 42.4 KB |
| `sabun` | 4.4 KB | 38.6 KB |
| `susu` | 3.5 KB | 37.7 KB |
| `telur` | 4.1 KB | 46.5 KB |

All fifteen are under the 600-triangle budget; 3,970 triangles for the whole set.

The **icons are rendered from the models**, by the same script, in the same run.
The order card, the seed baskets and the building prompts all show icons, and if
those were drawn separately they would drift — a child matching a card against a
shelf would be matching two different pictures of the same thing.

```powershell
& "D:/Program Files/Blender/blender.exe" --background --factory-startup `
  --python tools/blender/build_items.py -- --all `
  --out-dir assets/models/items --icon-dir assets/ui/items
```

## Procedural buildings — our own work

**No longer in the village**, which is one generated mesh as of 2026-08-31 (see
AI-generated art). These three are still built and still committed: they are what
the hub falls back to if that mesh is ever removed, and they remain the reference
for what a building here is meant to be — a roof with real thickness, geometry
standing in for texture, and an inside you can see.

Built by `tools/blender/build_buildings.py`. Three deliberately different
silhouettes, because PLAN.md §7.1 asks for buildings that read from across the
village and colour alone does not carry that far:

| Building | Silhouette | `.glb` | icon | Triangles |
|---|---|---|---|---|
| `warung` | steep corrugated gable; open counter you can see into | 67.1 KB | 77.6 KB | 1170 |
| `dapur` | tiled hip roof; open pavilion with a lit stove | 54.3 KB | 71.1 KB | 950 |
| `kebun` | no building; fenced plot with a roofed gate | 103.7 KB | 68.0 KB | 1814 |

3,934 triangles for all three, against a 4,000-per-building budget.

What makes them read at village distance is not polygon count but three things
that cost almost nothing: **roofs with real thickness**, so the eave has a
fascia instead of being a sheet of card; **geometry standing in for texture** —
the Warung's corrugation is alternating raised strips, the Dapur's tiles are
stepped rows; and **an inside you can see**, which is why the Warung has stocked
shelves and the Dapur a lit stove.

```powershell
& "D:/Program Files/Blender/blender.exe" --background --factory-startup `
  --python tools/blender/build_buildings.py -- --all `
  --out-dir assets/models/environment --icon-dir assets/ui/buildings
```

The Kebun's fence is load-bearing, not decoration. The hub gives every building a
solid box collider, and §7.1 forbids invisible walls — so an open garden needs a
boundary a child can see themselves bumping into.

## Procedural scenery — our own work

Built by `tools/blender/build_props.py`. Two tree types rather than one: the
village is seen from a fixed camera at a distance, and twelve copies of the same
tree is what makes a place look generated rather than built.

| Prop | `.glb` | Triangles |
|---|---|---|
| `tree_leafy` | 4.4 KB | 124 |
| `tree_banana` | 22.7 KB | 780 |

```powershell
& "D:/Program Files/Blender/blender.exe" --background --factory-startup `
  --python tools/blender/build_props.py -- --all --out-dir assets/models/environment
```

## Procedural characters - our own work

Built by `tools/blender/build_characters.py`. One `_humanoid` builder
parameterised by height, palette and proportions, so everyone in the village is
the same construction with different numbers - which is what keeps them looking
like they come from the same place.

| Character | `.glb` | |
|---|---|---|
| `player` | 87.9 KB | the child's avatar |
| `cust_anak` | 88.1 KB | child customer |
| `cust_ibu` | 88.8 KB | woman, skirt and bob |
| `cust_bapak` | 89.8 KB | man, peci and trousers |

Roughly 1,000 triangles each. Proportions are the design: the player and the
child customer are about three and a half heads, the adults nearer four and a
quarter. That head ratio separates a grown-up from a child far more than height
does, and it is one number.

The customers' palettes track the `colour` each variant carries in
`data/levels/warung.json`, because that colour is still what the generated
stand-in uses when a model is missing - two different pinks for the same
customer would be worse than one.

```powershell
& "D:/Program Files/Blender/blender.exe" --background --factory-startup `
  --python tools/blender/build_characters.py -- --all `
  --out-dir assets/models/characters
```

### Kanca

**Not built here any more** — he is a supplied model (see AI-generated art
above). What follows is the history of the procedural one, kept because the
findings in it are about the tooling rather than about him.

| Character | `.glb` | |
|---|---|---|
| ~~`kanca`~~ | — | superseded 2026-08-31 |

Built on the project owner's instruction of 2026-08-30; PLAN.md 16.2 records the
change from "will be commissioned". Provenance is clean either way — a model
described in code we wrote is authored work, which is the whole reason 11.1
forbids a *stock* mascot rather than forbidding a procedural one.

**Rebuilt on four legs, 2026-08-31**, on the project owner's instruction;
PLAN.md 16.2 records it. He was upright at two and a half heads because 11.1's
proportion rule and 7.1's "points at things" both seemed to need a biped. A
mouse-deer standing on its hind legs does not look like the animal it is meant to
be, so the proportion rule goes with the change - it describes a chibi biped and
cannot describe a quadruped.

11.1's requirements, honestly: 48x48 silhouette **met and tested**, one signature
colour **met** (his coat is `Palette.SIGNATURE` muted), and he **walks** - four
legs on hip pivots, trotted in diagonal pairs by `WalkCycle`, with no skeleton.
Pointing is a turn and a raised foreleg, which is what the animal would do. Rig,
five animations, four expressions: **still not met.**

Two things the rebuild turned up. His body runs along Y and every limb built in
this project until now ran up Z, which is the one case `kb.sweep`'s ring frame
gets wrong - it pins the binormal to +Y, so a spine along Y produces a ring
containing the spine and the sweep comes out as a flat plate. The first
four-legged Kanca had a fin for a torso and a grey card for a belly. `sweep` now
takes an optional `up`, and the default is left alone because a correct frame is
a *different* frame: the across axis comes out negated, which would flip the
winding of every face in the repository. And overlapping ellipsoids, tried as a
way round it, read as an armadillo - you can see every shell crossing every
other one.

Two things the 48px test caught that nothing else would have. The icon camera
sits at -Y, which is right for an item with no front and photographs the *back*
of anything with a face — the first test came back as an unlit blob with a white
patch that turned out to be his tail. And his throat stripes, which are the
marking that identifies a real kancil, stood proud of the neck at that scale and
read as a pair of fangs; a plain chest bib replaced them.

## Procedural undergrowth - our own work

Scattered in the Kebun only since 2026-08-31; the village brought its own. Built
by `tools/blender/build_scatter.py`. Nothing here is worth looking at on
its own, and that is the point: a green field with three good buildings on it
still reads as a green field. What makes somewhere look like a place is a few
hundred bushes, ferns and stones nobody ever looks at directly.

| Prop | `.glb` |
|---|---|
| `bamboo_fence` | 15.4 KB |
| `bush` | 7.1 KB |
| `fern` | 14.8 KB |
| `flower_red` | 12.2 KB |
| `flower_purple` | 12.2 KB |
| `grass_tuft` | 6.6 KB |
| `rock` | 3.1 KB |

Scattered by `scripts/hub/village_scatter.gd`, one MultiMeshInstance3D per type.
That is not an optimisation detail - placed as ordinary nodes, four hundred
plants cost four hundred draw calls against a budget of a hundred (PLAN.md 4.2).

## Vertex colours, and why every model has exactly one material

Every `.glb` in this project carries a baked colour gradient in `COLOR_0`:
darker at the base, full colour at the top, with a few per cent of variation
between neighbouring facets. `kb.bake_vertex_colours()` writes it.

It does two jobs that turn out to be one job.

**It stands in for texture.** Every material here is a single flat colour, and a
flat colour on a low-poly model gives it no shape beyond what the light happens
to catch - a tree canopy comes out as a green blob, a roof as a coloured card.
Darkening the underside costs no texture memory, no UVs and no draw calls, and
it is most of what the hand-painted look in the reference art actually is.

**It collapses the materials.** Once the colour lives in the mesh, the whole
model can share one white material. A material is a surface is a draw call: the
three buildings were spending eighteen between them and the player six on his
own. Collapsing them cut the village from 153 draw calls to 70.

Two traps, both of which cost real time here:

- **Smoothing hides it.** A gradient painted onto a smooth-shaded sphere is a
  soft bloom; painted onto flat facets it is a low-poly canopy. Foliage is built
  with `kb.shade(obj, 1.0)` for exactly this reason. The first version of the
  gradient was correct in the file, correct in Godot, and invisible on screen.
- **The values are stored in sRGB, not linear.** Godot's Compatibility renderer
  always treats mesh vertex colours as sRGB and converts them.
  `StandardMaterial3D.vertex_color_is_srgb` reads like the switch that decides
  this, is `false`, and is ignored - the docs note it applies only to Forward+
  and Mobile. A linear value written here goes through the transfer function
  twice, which is not a dimmer but a hue shift: baked linear, the Warung's
  yellow sign came out orange and its mint roof came out bottle green. The
  Blender material puts a gamma node in the way so previews and icons stay
  right.

`scripts/core/model_kit.gd` is the only place models are loaded, because Godot's
glTF importer reads `COLOR_0` faithfully and then leaves
`vertex_color_use_as_albedo` switched off. Nothing errors and nothing warns; the
model simply looks flat.

## Procedural shop fittings - our own work

Built by `tools/blender/build_shop.py`. Racks, crates and sacks for the Warung.

| Fitting | `.glb` |
|---|---|
| `shelf_unit` | 88.2 KB |
| `crate` | 19.2 KB |
| `sack_pile` | 25.7 KB |
| `hanging_bananas` | 13.9 KB |

**None of it is playable and none of it can be.** PLAN.md 3.3 sets a 120x120px
minimum touch target and a 40px gap, which at the Warung's camera distance caps
what a child can pick up at five items (`MAX_SHELF_SLOTS`). Five bananas on a
counter is not a warung, so the shop is stocked *behind* the five: four racks of
jars and packets, crates of fruit, sacks of rice, all out of reach.

The boundary matters in both directions, and `tools/warung_test.gd` guards it. A
tin that looks like the apple beside it and does not respond to a small hand does
not just fail once - it teaches a child that touching things is not how this
works, which is the opposite of what every other screen is trying to teach.

Stock is baked into the rack model rather than placed separately: forty objects,
one mesh, one material, one draw call.

## ⚠️ Unlicensed third-party — NOT CLEARED FOR RELEASE

| File | Source | Licence | Status |
|---|---|---|---|
| `assets/models/shop/gondola.glb` | `D:/Blender Assets/Gondola_1000x1850x500mm_V1.blend`, supplied 2026-08-30 | **unknown** | in the build, blocked for release |

Derived from a `.blend` supplied by the project owner from outside the
repository. It is 4,092 triangles, one baked material, and it looks right — but
PLAN.md 11 allows third-party assets only under CC0 and requires the source URL
and licence recorded here **before commit**, and this app ships under the Play
Families policy where the bar is higher, not lower.

Nothing about the model tells you where it came from. Until someone can name the
licence, this is the one asset in the project whose provenance cannot be
answered, and that is worth more than the shelf is.

Two ways to clear it: name the source and licence, or rebuild the same shape in
`tools/blender/` the way everything else here is built. The importer
(`tools/blender/import_gondola.py`) is committed; its output should not be, until
one of those happens.

**Rejected: the supplied tree models.** 1.52 million triangles across fourteen
meshes, against a scene budget of 80,000 — the *smallest* tree is 33,760. That
alone is arguable; what settles it is that decimation cannot fix it. Asked for
900 triangles, the collapse decimator returned 13,431, and it does so because the
foliage is thousands of separate leaf islands and collapse cannot merge across
islands. The floor is roughly one triangle per leaf. What comes back at any
usable budget is a bare winter skeleton with the leaves deleted.

## Procedural garden pieces - our own work

Built by `tools/blender/build_garden.py`.

| Piece | `.glb` |
|---|---|
| `plot_bed` | 26.4 KB |
| `plant_sprout` | 7.9 KB |
| `plant_young` | 13.7 KB |
| `plant_grown` | 17.5 KB |
| `seed_basket` | 13.6 KB |
| `watering_can` | 15.3 KB |

The growth stages are generic on purpose. §8.2 grows a different crop in every
plot, and modelling a young banana, a young apple and a young orange separately
would be three models saying the same thing: *something is coming up*. The plant
carries the stage; the fruit that appears at the end is the item's own `.glb`,
the one the Warung already sells - so what the child harvests is visibly the
thing they later hand over a counter.

The Kebun's surroundings are not new assets at all. It reuses the village's
vertex-coloured ground, its bamboo fence and its bushes and grass, because §8.4
says the Kebun and the Warung are one world and the produce chain is what proves
it. A garden with its own flat green floor and its own brown plank fence would
have said the opposite before the child planted anything.

## Procedural branding - our own work

Two steps, and the split between them is the point.

`tools/blender/build_branding.py` photographs the mascot - the same
`build_kanca()` the game loads, not a copy of him - and writes one oversized
master render. `tools/build_brand_images.gd` composes every canvas from that
master, in Godot.

| File | | |
|---|---|---|
| `assets/ui/brand/kanca_full.png` | 1024x1024 | the master render, the source of everything below |
| `assets/ui/brand/kanca_portrait_256.png` | 320x213 | the loading screen and the celebration overlay |
| `assets/ui/brand/wordmark.svg` | vector | the name, drawn as stroked geometry |
| `assets/ui/brand/app_icon_512.png` | 512x512 | `config/icon`, and the Play listing icon |
| `assets/ui/brand/launcher_192.png` | 192x192 | pre-Oreo Android launcher icon |
| `assets/ui/brand/adaptive_foreground_432.png` | 432x432 | adaptive icon, and the Android 12 splash icon |
| `assets/ui/brand/adaptive_background_432.png` | 432x432 | adaptive icon background, hill and shadow |
| `assets/ui/brand/adaptive_monochrome_432.png` | 432x432 | themed icon |
| `assets/ui/brand/splash_1280x720.png` | 1280x720 | `boot_splash/image`, and `scenes/boot/boot.tscn` |
| `assets/ui/brand/wordmark_800.png` | 800x172 | Android 12 splash branding image |
| `store/feature_graphic_1024x500.png` | 1024x500 | Play Store listing |

```powershell
& "D:/Program Files/Blender/blender.exe" --background --factory-startup `
  --python tools/blender/build_branding.py -- --out-dir assets/ui/brand
```

```powershell
& $env:GODOT --headless --path . res://tools/build_brand_images.tscn
& $env:GODOT --headless --path . --import
& $env:GODOT --headless --path . res://tools/check_branding.tscn
```

`store/` is excluded from the Android export alongside `tools/`
(`exclude_filter`), so the feature graphic is in the repository but never in
the app.

### The icon is a photograph of the mascot, not a picture of him

§11.1 asks for one signature colour across the icon, the loading screen and the
primary buttons, and for the icon to be Kanca. A separately drawn icon satisfies
that on the day it is drawn and stops satisfying it the first time either the
model or the drawing is touched - and nobody notices, because the two are never
on screen at once. Rendering the model means there is only one Kanca and there
is nothing to keep in step.

Composed in Godot rather than in Blender or an image editor for the same reason
one step down: the splash screen the engine draws before the first frame, the
splash the boot scene draws after it, and the wordmark inside the icon all come
out of the same rasteriser, at the same gamma, with the same antialiasing.

### The wordmark is geometry, not a typeface

No display face has been chosen (see Fonts below) and §11 allows third-party
assets only under CC0, which most good free fonts are not - OFL is a licence,
not a waiver. Five letters drawn as stroked paths with round caps is authored
work with nothing to license and nothing to embed, and it recolours by tinting
because the letterforms live entirely in the alpha.

It is also the one place in the app where text carries meaning, which §3.1
otherwise forbids. A brand name is not a UI element: nothing a child has to
understand depends on reading it, and the mascot is doing the identifying.

### The camera moved when the mascot did

The master render is taken at 58 degrees off face-on. It was twenty while Kanca
stood up: far enough round to see the snout, near enough that the mark stayed
symmetrical. Head-on, a quadruped is a face above a chest with two legs hidden
behind two legs - the body length, the arch of the back and the separation of
fore and hind all disappear, and every one of them is what says "animal" rather
than "toy".

Two things followed. The framing had to be computed by projecting the bounding
box onto the camera's own axes rather than by taking the larger of the world
width and height, or a metre of animal gets framed against sixty centimetres of
world X and the render loses its nose and its tail. And every brand canvas is now
laid out by *width*: he is half again as wide as he is tall, so the adaptive
icon's safe circle catches the corners of his bounding box long before the canvas
edge does.

### One layout, five icons

Every icon here is derived from a single layout on Android's 432px adaptive
canvas rather than composed separately. The launcher icon is the two adaptive
layers flattened and cropped to the 72dp that a mask actually leaves; the Play
icon is that crop at 512; the legacy icon is the same at 192. Composing them
independently is how a set of icons slowly stops being one icon.

The hill and the shadow are in the background layer and Kanca alone is in the
foreground, which is not a stylistic choice. A launcher may slide the two layers
against each other, and a shadow drawn with the mascot would also be a grey
bruise in the sky wherever it reached past the crest of the hill - and would
count against the safe circle that decides how big he is allowed to be.

`tools/check_branding.gd` measures all of it, including the 48x48 test §11.1
asks for by hand: it shrinks the mascot to 48px, walks the silhouette row by
row, and insists the neck still pinches between the ears and the body. That
articulation is what a person reads as "an animal with a head" from across a
home screen, and it is the first thing lost when the mascot is scaled down a
little too far.

## Textures

| File | Source | Author | License | Notes |
|---|---|---|---|---|
| _(none yet)_ | | | | |

## Audio — music & SFX

| File | Source | Author | License | Notes |
|---|---|---|---|---|
| _(none yet)_ | | | | |

## Audio — voice

| File | Source | Author | License | Notes |
|---|---|---|---|---|
| _(none yet)_ | | | | Original recordings, commissioned. Not third-party. |

## Fonts

| File | Source | Author | License | Notes |
|---|---|---|---|---|
| _(none yet)_ | | | | |

Godot's built-in font is used until a display face is chosen. The wordmark does
not wait on that decision and does not make one: it is drawn geometry, not set
type, so choosing a face later changes the UI and leaves the brand alone.

## Original work — not third-party

These are commissioned or produced for Kanca and are **not** covered by the CC0 rule.
They must never be replaced with stock assets (PLAN.md §11.1).

| Asset | Status |
|---|---|
| Kanca mascot model | Built (§16.2, 2026-08-30). Rig, animations and expressions still missing |
| App icon, launcher icons, splash, wordmark | Built, rendered from the mascot — see Procedural branding above |
| Voice recordings | Not started — script in `docs/DUBBING.md` |

## AI-generated art

Anything produced by an image or model generator is recorded here, **not** in the
CC0 tables above — it is not third-party licensed work, and it is not commissioned
human work either. Record the tool, the date, and enough of the prompt to
reproduce it. Provenance is what gets asked for if authorship is ever disputed.

| File | Tool | Date | Used as | Notes |
|---|---|---|---|---|
| `assets/models/environment/village_market.glb` | Meshy AI, from a reference image of the procedural village | 2026-08-31 | The whole village hub — ground, paths, fence, trees and all three buildings | Supplied by the project owner as `Meshy_AI_Sunny_Village_Market_0831031237_texture.glb`. Repaired by `tools/blender/import_village.py`; see below. |
| `assets/models/characters/kanca.glb` | Meshy AI, from a generated three-pose character sheet | 2026-08-31 | **The mascot**, everywhere: the village companion, the boot splash, the app icon, the loading screen, the celebration overlay | Supplied as `Meshy_AI_Cheerful_Little_Deer__0831040018_texture.glb`. Repaired by `tools/blender/import_mascot.py`; see below. |
| `assets/models/characters/player.glb` | Tripo AI | 2026-08-31 | **The child's avatar** in the village | Supplied as `stylized boy character 3d model.glb` — a two-figure turnaround sheet, 501,214 triangles, 3 × 4096 maps. Repaired by `tools/blender/import_character.py`; see below. |

### The child

Same four repairs as the others, plus two of its own.

| | |
|---|---|
| Triangles | 6,500, from 252,226 in the figure that was kept. Measured, not chosen: at 9,000 the hub came out 2,230 over the §4.2 ceiling, because a character that casts a shadow is drawn twice |
| Atlas | 4096 → **1024**. A 4096 map for a child a couple of hundred pixels high is 64 MB of texture to describe him — half the §4.2 budget on one character — and more than `dilate` can hold: Blender's Python runs out of memory before it finishes |
| Sheet | Two figures side by side. `kb.split_figures` finds the empty column and keeps one; a file with no gap is left alone |

**He is rigged, and that is the point.** Everything `build_characters.py` builds
carries its legs as separate child objects with the pivot at the hip, and
`WalkCycle` rotates those. A supplied model is one continuous shell: there is no
leg to rotate, and cutting one out leaves a hole at the hip that opens every time
it swings. `kb.rig_legs` binds the mesh to three bones — `root`, `leg_l`,
`leg_r` — and `WalkCycle` poses them instead.

The weights are **computed, not `ARMATURE_AUTOMATIC`**. Automatic weights solve a
heat equation over the surface, which on a remesh with the legs nearly touching
bleeds one leg's influence into the other and puts a little of the belly on both.
A vertex here belongs to a leg if it is below the hip and on that side of the
middle, with a deliberate fade at each boundary — a rule you can read off the
model, predict, and fix.

`tools/integration_test.tscn` advances the cycle and looks at the bone pose. Both
ways this breaks are silent: a model with no skeleton reports no legs and does
nothing, and a model whose bones are named something else does the same for a
different reason. The child skated across the village for exactly as long as it
took somebody to notice.

**A bone's pose in Godot replaces its rest; it is not a delta from it.** Whatever
the word suggests, `set_bone_pose_rotation` writes the bone's whole local
rotation, initialised to the rest. Setting only the rotation therefore throws the
rest's orientation away — and since these bones point down the leg, that stood
both of them on end: the legs swung up over the child's head and the body between
them collapsed into the collar. `WalkCycle` composes `rest * rotation` and writes
both components.

The same fact catches the *test*. Measuring the pose's own angle reads a half
turn while the child stands perfectly still, so the check has to measure the
swing relative to the rest — which is why the first version of it passed for the
wrong reason and then failed for the right one.

### The mascot

Kanca is a supplied model as of 2026-08-31, on the project owner's instruction —
"lebih playful dan fun". PLAN.md §16.2 records it. This is the third answer to
that question in two days: commissioned, then procedural, then upright, then a
quadruped, and now this. The procedural builder was **deleted** rather than left
in `build_characters.py`, because it wrote to the same path the importer does and
`--all` would have quietly replaced the shipped mascot.

**It arrives as the reference sheet, modelled** — three poses standing side by
side in one mesh, 83,050 triangles between them. `import_mascot.py` splits them
on the empty columns between the figures (found in the vertex histogram, not
typed in), drops the PBR maps, dilates the atlas, turns each pose to face +Y,
scales to 0.80m, and decimates.

| | |
|---|---|
| Poses | `idle`, `point`, `celebrate` — three of the five §11.1 asks for |
| Triangles | 6,000 each, from 26–29k. §11 budgets 3,000; at that ratio the decimator starts eating the eyebrows, and only one pose is ever in the scene |
| File | One `.glb` with three children, 898 KB. Exported separately they would be three copies of the same 2048 atlas — 48 MB of texture memory for a mascot who is in one pose at a time |

**He does not walk.** `WalkCycle` swings legs that are separate objects pivoting
at the hip, and there is no way to cut a leg out of a continuous remeshed shell
without leaving a hole that opens every time it swings. He crosses the village
without moving his feet. That is a real regression against the trotting quadruped
he replaced, and it was accepted for the expression: a companion is stationary
for most of a session and the moments that matter are the ones where he points
at the next thing to do or cheers because the child finished something.

Still missing from §11.1: `walk`, `think`, and the four expressions.

**Two traps worth knowing**, both of which cost real time here:

- The glTF importer leaves objects on `rotation_mode = QUATERNION`, and assigning
  `rotation_euler` to one of those is **silently ignored**. The model exported
  facing exactly the way it came in and stood in the village with its back to
  everything it was meant to be looking at.
- Splitting by loose parts is useless on a remesh. This one has 251 disconnected
  islands and not one of them is a character — the split has to be spatial.

### The village

It replaced a procedurally generated village on the project owner's instruction
of 2026-08-31, with the eye-level render in front of them. That is worth
recording plainly, because it is a decision against three things this file and
ART_STYLE.md otherwise say, and the reasons for it were the reasons given at the
time: from the distance the hub camera actually sits, it is warmer, softer and
better planted than the village it replaces.

**It is cheap, which was the surprise.** 10,100 triangles for an entire village,
one mesh, one material. The procedural village it replaced drew 64,000. The hub
now measures 20,272 triangles and 62 draw calls against the §4.2 ceilings of
80,000 and 100.

**Three of the four faults ASSETS.md predicts of generated models were there,
and `tools/blender/import_village.py` fixes each:**

- *Full PBR set.* 2048 base colour, 4096 metallic-roughness, 2048 normal. §11
  allows none of the last two and they were four fifths of the 19.7 MB file.
  Dropped; the export is 6.2 MB.
- *No UV padding.* The auto-unwrap has 3,844 islands with bare black between
  them — invisible at 1:1 and ruinous once anything averages neighbouring
  texels, which mipmapping does every frame and ETC2 does in 4×4 blocks at
  import. Every edge in the village would have grown a black fringe on the
  device and nowhere else. The atlas is dilated eight pixels outward from each
  island.
- *Diorama scale.* 1.9 units across, modelled to be looked at from above. Scaled
  so the village is 30m and its buildings land in the 5–7m §11 asks for, and
  dropped so the grass sits at y=0.

**The fourth cannot be fixed by a script.** It is a remesh, not a model: rounded
edges, no thickness in the roofs, no interior. Up close it is soft. That is the
trade the owner made and the render they made it on.

Three things sharpened it a long way short of remodelling it, and the first is
the one that mattered:

- **Its normals.** It arrives smooth-shaded with custom split normals — right for
  the high-poly sculpt it was remeshed from, and the reason ten thousand
  triangles standing in for a village looked melted. Averaged normals across a
  low-poly surface do not read as smooth, they read as soft: every roof plane,
  tree facet and fence post blended into its neighbour. `import_village.py`
  clears the custom normals and re-shades sharp above 30°. The same finding this
  file already records about the foliage, where the vertex gradient was correct
  and invisible because the normals were averaging the facets away.
- **Anisotropic filtering** (`ModelKit`). A ground plane is seen almost edge-on
  across most of the screen, and plain mipmapping picks its blur from whichever
  axis shrinks fastest, so the far half of the village was filtered as though it
  were shrinking equally in both. glTF import leaves this on the isotropic
  setting.
- **Undergrowth sown over it** (`Hub.SOWN`). The atlas has no resolution to spare
  for the largest surface in the scene, so the open middle was a flat expanse of
  pale green — the part of the screen a child looks at most. Four hundred-odd
  vertex-coloured tufts, flowers and bushes, the same ones the Kebun scatters,
  put crisp detail exactly where the texture has none and match the child and
  Kanca rather than the backdrop.

**There are no buildings in it.** The mesh is one shell in 3,844 disconnected
fragments; the Warung's roof and the grass under it are the same surface. The
hub does not need them separated — a child never enters a building from the
village, they walk up, a prompt appears, and the router loads a different scene
(PLAN.md §6.3, §7.1). `Building` places a collider, a sign and a trigger at a
position measured off the mesh and draws no model. What that costs is the locked
Dapur: it used to grey out whole, and now only its sign dims behind the
under-construction marker.

**Copyright.** The note below applies. This is scenery rather than the mascot,
so the stake is lower — but in several jurisdictions a purely generated image
with no meaningful human authorship may attract no copyright protection at all,
and that now covers the look of the village.

Two things to weigh before any of this becomes shipped art:

- **The mascot is an open decision.** PLAN.md §16.2 says in as many words: *do not
  generate or select a stock mascot model*. Using a generated Kanca means changing
  that decision deliberately, not drifting past it.
- **Copyright.** In several jurisdictions purely generated images, with no
  meaningful human authorship, may attract no copyright protection at all. For a
  banana on a shelf that costs nothing. For the mascot — which is the app icon and
  the whole brand — it means there may be no basis to stop anyone else using it.
  Using generated art as the *brief* for a human modeller avoids this: the
  resulting model is authored work.
