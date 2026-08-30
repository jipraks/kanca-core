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

| Character | `.glb` | |
|---|---|---|
| `kanca` | 74.8 KB | the kancil, 2.4 heads tall |

Built on the project owner's instruction of 2026-08-30; PLAN.md 16.2 records the
change from "will be commissioned". Provenance is clean either way — a model
described in code we wrote is authored work, which is the whole reason 11.1
forbids a *stock* mascot rather than forbidding a procedural one.

11.1's requirements, honestly: proportions (2-2.5 heads) **met**, 48x48
silhouette **met and tested**, one signature colour **met** (his coat is
`Palette.SIGNATURE` muted). Rig, five animations, four expressions: **not met and
not achievable this way.** Pointing is a rotation, not a gesture.

Two things the 48px test caught that nothing else would have. The icon camera
sits at -Y, which is right for an item with no front and photographs the *back*
of anything with a face — the first test came back as an unlit blob with a white
patch that turned out to be his tail. And his throat stripes, which are the
marking that identifies a real kancil, stood proud of the neck at that scale and
read as a pair of fangs; a plain chest bib replaced them.

## Procedural undergrowth - our own work

Built by `tools/blender/build_scatter.py`. Nothing here is worth looking at on
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
| _(none yet)_ | | | | Godot's built-in font is used until a display face is chosen. |

## Original work — not third-party

These are commissioned or produced for Kanca and are **not** covered by the CC0 rule.
They must never be replaced with stock assets (PLAN.md §11.1).

| Asset | Status |
|---|---|
| Kanca mascot model, rig, animations | Not started — design not finalised (PLAN.md §16.2) |
| App icon | Placeholder (`icon.svg`) — derived from the mascot once it exists |
| Voice recordings | Not started — script in `docs/DUBBING.md` |

## AI-generated art

Anything produced by an image or model generator is recorded here, **not** in the
CC0 tables above — it is not third-party licensed work, and it is not commissioned
human work either. Record the tool, the date, and enough of the prompt to
reproduce it. Provenance is what gets asked for if authorship is ever disputed.

| File | Tool | Date | Used as | Notes |
|---|---|---|---|---|
| _(none committed yet)_ | | | | |

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
