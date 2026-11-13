# Art Style

Working reference for anyone making or choosing art for Kanca. The rules come from
[PLAN.md §11](../PLAN.md) and §4.2; this file is where they turn into decisions
you can act on.

---

## The look

Low-poly stylised. Flat or lightly-shaded materials, bright saturated palette. No
realism, no PBR complexity, no normal maps, no roughness maps.

The test for whether a piece fits: **would it look at home next to a Kenney or a
Quaternius asset?** Those two libraries share a visual language, and the whole
reason for sticking to them is that a game assembled from five different free
packs looks assembled rather than designed.

## Sources and licensing

CC0 only. No CC-BY, no "free for non-commercial", nothing with unclear
provenance. The app ships under Google Play's Families policy and a licensing
question at review time is expensive to answer late.

- [Kenney](https://kenney.nl/assets) — CC0 1.0
- [Quaternius](https://quaternius.com/) — CC0 1.0

Every third-party file is recorded in [`ASSETS.md`](../ASSETS.md) **at commit
time**, with its source URL and licence. Not afterwards.

## Technical constraints

| | |
|---|---|
| Format | glTF (`.glb`) preferred. `.blend` imports if it must, but `.glb` keeps the repo smaller. |
| Scale | 1 world unit = 1 metre. Normalise before committing. |
| Shadows | One directional light, low shadow resolution. Nothing else casts. |
| Post-processing | A simple tonemap and nothing more. No SSAO, no SSR, no volumetric fog. |
| Textures | Atlas where possible. ETC2/ASTC compression is on for Android. |

**Three exceptions, and they are large ones.** The village hub, the mascot and
the child are all supplied, textured models (ASSETS.md, AI-generated art).
Everything else in the game — every item, every other character, every prop — is
untextured, one flat material, with its shading baked into vertex colours. Two consequences worth knowing before
adding anything: a new prop authored in the village's style will not match the
items a child picks up, and the village's own atlas has no padding to spare, so
nothing can be added to it. New props go in as vertex-coloured models, the way
the rest of the game does.

Two renderer settings exist for that mesh and are worth knowing before they get
turned off as a performance saving: 2× MSAA, and one orthogonal shadow split
instead of the default four. The split matters most — every split re-draws every
shadow caster, and four of them cost 40,000 triangles of the §4.2 budget to
shadow a village thirty metres across that the camera never leaves.

Per-scene budgets from §4.2, on a mid-low Android device:

| Metric | Budget |
|---|---|
| Draw calls per frame | < 100 |
| Visible triangles | < 80,000 |
| Texture memory | < 128 MB |
| Unique materials per scene | < 25 |

The material budget is the one that gets blown first. `PlaceholderFactory` caches
materials by colour for exactly this reason — fifteen shelf items share three or
four materials rather than owning fifteen. Real assets should share materials the
same way.

## Colour

`scripts/core/palette.gd` is the single place colours are defined. Anything drawn
in code reads from there, so changing the signature colour changes it everywhere
at once.

One rule that is easy to miss: **there is no "wrong" red anywhere in the app**.
§3.2 rules out anything that reads as punishment. An incorrect answer uses
`Palette.ATTENTION`, a warm amber that says "look again", never a rebuke.

`SIGNATURE` is settled now that the mascot exists. His coat is it, muted: a
character wearing a button colour at full strength looks like a button. The icon,
the loading screen and the boot screen all show the same render of him, so the
agreement §11.1 asks for is structural rather than something to remember.

The brand images add two colours that are not his and are not meant to be. The
icon puts him on `SKY` over `GRASS` — orange against blue is the widest hue
separation available, and it is a luminance separation too, which is the one that
survives a colour vision deficiency. The wordmark is `UI_TEXT`, the same brown
the UI already speaks in.

## Kanca himself

**The mascot is the one asset that must never be a stock model.** He is on every
screen and he is the app icon; a recognisable free character would undermine the
whole brand.

Requirements when the commissioned model arrives:

- Silhouette identifiable at **48 × 48 px**. Test this explicitly — shrink it and
  look at it, do not assume.
- 2 to 2.5 heads tall.
- Minimal skeleton, rigged. Animations required: `idle`, `walk`, `point`,
  `celebrate`, `think`.
- Four expressions via blend shapes or swappable textures: happy, confused,
  proud, sleepy.
- One signature colour, used consistently across the icon, the loading screen and
  primary buttons.

He is a supplied model as of 2026-08-31 (§16.2, ASSETS.md) — upright,
expressive, with a teal neckerchief, in three poses. The 48px silhouette is met
and tested. `idle`, `point` and `celebrate` are met. `walk`, `think` and the four
expressions are not: the poses are continuous shells with no separable legs, so
he does not step.

The rule against a *stock* mascot still stands. A generated one is a different
thing from a downloaded one — and a weaker thing than either, because a purely
generated image may attract no copyright protection at all, which for the app
icon means there may be no basis to stop anyone else using it.

## The brand

Everything with the name or the face on it — the app icon, the launcher icons,
the boot splash, the store graphic — is rendered from that same model and
composed by two scripts. `ASSETS.md` has the pipeline and the reasoning; what
matters when making a change is:

- **Never draw Kanca.** Move the camera in `tools/blender/build_branding.py`, or
  change the model. A second picture of him is a second mascot.
- **Re-run the checker.** `tools/check_branding.tscn` measures the adaptive
  icon's safe zone and the 48px silhouette, and is in `run_tests`. Six pixels of
  layout is enough to lose an ear on somebody's launcher.
- **Look at the strip it writes.** It renders the icon at 192, 96, 48 and 32 and
  prints the path. §11.1 asks for that explicitly, and a passing number is not
  the same thing as an icon that reads.

## How art reaches the game

Nothing needs registering, importing or wiring. Every slot is a path the game
already looks for; drop a file there and it is used on the next run.

To see every slot and what is still missing:

```powershell
& $env:GODOT --headless --path . res://tools/check_asset_coverage.tscn
```

### Items resolve in three tiers

`PlaceholderFactory.build_item_visual()` takes the first of these that exists:

1. **`assets/models/items/<id>.glb`** - the real model. Always wins.
2. **`assets/ui/items/<id>.png`** - the item's 2D icon, shown as a billboarded
   sprite standing on the ground.
3. A coloured primitive.

Tier 2 exists because 2D art almost always arrives before 3D art, and a picture
of a banana is a far better stand-in than an anonymous yellow box. The same PNG
also serves as the flat icon on the order card and the seed baskets, so one file
covers both.

It is also a legitimate final answer, not only a stopgap. Every camera in this
game is fixed and the child never controls one (§7.1), which is exactly the
condition under which a billboard reads as an object rather than as a card being
swung to face you. Whether the game ships 2.5D items against 3D scenery is an art
direction decision - but it costs nothing to look at it first, and a `.glb`
takes over the moment one appears.

## Model brief

What a `.glb` has to satisfy to drop straight in. Written for handing to whoever
or whatever is making the model.

| | |
|---|---|
| Format | `.glb` (binary glTF), textures embedded |
| Scale | 1 unit = 1 metre |
| Origin | **Bottom centre.** The game places models by their feet; an origin at the centre buries half the model in the shelf |
| Forward | **-Z.** Godot's convention. A model authored facing +Z walks backwards |
| Up | +Y |
| Rigging | None for items and props. The mascot needs a real skeleton |
| Materials | Flat colour. No metallic/roughness/normal maps — the whole look is unlit-ish (§11) |

Triangle budgets, from the §4.2 ceiling of 80,000 visible triangles per scene. A
Warung round can have fifteen item instances on screen at once, so items are the
ones that matter:

| Asset | Longest side | Triangles |
|---|---|---|
| Shop / garden item | ~0.22 m | 200–600 |
| Customer, player avatar | 0.95–1.42 m | ≤ 3,000 |
| Kanca | 0.85 m | ≤ 3,000, rigged |
| Building | 5–7 m | ≤ 4,000 |
| Tree, fence, prop | varies | ≤ 400 |

### If the model comes out of a generator

Generated `.glb` files are usually wrong in four predictable ways: far too many
triangles, arbitrary scale, origin at the centre of the bounding box, and full
PBR texture sets. The first and last need fixing in Blender — decimate, and strip
the maps down to flat colour. Scale and origin the game can absorb on load.

**Rigging is the one thing a generator will not give you.** Kanca needs a
skeleton, five animations and four expressions (§11.1); a static mesh cannot be
made to point at a building or celebrate. Generated art is a good *brief* for
that model, not a substitute for it.

## Placeholders

Everything currently on screen that is not UI text is generated at runtime by
`scripts/core/placeholder_factory.gd`: coloured primitives for items, capsule
figures for characters, flat swatches and pictograms for icons. Sound effects are
synthesised the same way in `scripts/core/sfx_bank.gd`.

Two things follow from that:

1. **Dropping in a real asset needs no code change.** The factory checks for the
   file named in `data/items.json` first and only generates a stand-in when it is
   absent. Put a `.glb` at the path and it is used.
2. **Placeholders look deliberately provisional, and must never ship.** They also
   must not shape a design decision — if something reads well as a coloured box,
   that tells you nothing about whether it will read well as a banana.

## Reading at arm's length

Everything is looked at by a four-year-old holding a phone. Before calling a
piece finished:

- Can you tell what it is from across the room?
- Can you tell it apart from its neighbour on the shelf by **shape**, not only by
  colour? Roughly 1 in 12 boys has a colour vision deficiency, and colour alone is
  a weak signal for anyone at this size.
- Does it still read at 48 × 48 px?
