"""Turns a supplied gondola .blend into a stocked shop rack. Developer tool.

    blender --background "D:/Blender Assets/Gondola_1000x1850x500mm_V1.blend" \
        --python tools/blender/import_gondola.py -- \
        --out assets/models/shop/gondola.glb --preview /tmp/gondola.png

**This reads a file that is not in the repository.** The source lives outside the
project and its licence is not recorded, so the output must not be committed
until ASSETS.md can name a licence for it (PLAN.md 11). The script is committed;
what it produces is not, until that question is answered.

Three things have to happen to make an outside model usable here:

- **Strip the set.** The file ships a ground plane and a backdrop along with the
  fixture. Joined blindly they make a 7-metre object.
- **Stock it.** A shelving unit models the shelving, not the goods, and an empty
  rack behind a counter reads as a shop that has closed down.
- **Bake it flat.** Six PBR materials become one baked vertex-colour material,
  the same treatment every asset here gets, so it costs one draw call and
  matches the rest of the village instead of shading like a photograph.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kanca_build as kb  # noqa: E402
import build_shop  # noqa: E402


## Anything wider or deeper than this is set dressing, not the fixture.
FIXTURE_LIMIT = 2.5

## The red price rails mark the front edge of every shelf, which is the cheapest
## reliable way to find out where the shelves are without hard-coding heights
## that only suit one file.
RAIL_MATERIAL = "Shelf_liner"


def gather_fixture():
    """The gondola's own objects, without the floor it is standing on."""
    keep = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.data.polygons:
            continue
        size = obj.dimensions
        if max(size.x, size.y) > FIXTURE_LIMIT:
            continue
        keep.append(obj)
    return keep


def shelf_heights(objects):
    """Z of each shelf's top surface, read from the price rails."""
    heights = []
    for obj in objects:
        names = [m.name for m in obj.data.materials if m is not None]
        if RAIL_MATERIAL not in names:
            continue
        top = max((obj.matrix_world @ v.co).z for v in obj.data.vertices)
        heights.append(top)

    # Rails come in pairs and clusters; collapse anything within a few
    # centimetres into one shelf.
    heights.sort()
    merged = []
    for z in heights:
        if not merged or z - merged[-1] > 0.08:
            merged.append(z)
    return merged


def build(width_target, preview_only=False):
    fixture = gather_fixture()
    if not fixture:
        raise SystemExit("no fixture objects found - is this the right .blend?")

    shelves = shelf_heights(fixture)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in fixture:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = fixture[0]
    bpy.ops.object.join()

    rack = bpy.context.view_layer.objects.active
    rack.name = "gondola"

    # Goods, in the same shapes and colours the procedural rack uses, so the two
    # can stand side by side without looking like they came from different games.
    stock_materials = [kb.make_material("gondola_stock_%d" % i, rgb, roughness=0.75)
                       for i, rgb in enumerate(build_shop.STOCK_COLOURS)]
    base_count = len(rack.data.materials)
    for material in stock_materials:
        rack.data.materials.append(material)
    stock_indices = list(range(base_count, base_count + len(stock_materials)))

    width = rack.dimensions.x
    bm = bmesh.new()
    for row, z in enumerate(shelves):
        build_shop._stock_a_board(bm, width * 0.82, z + 0.012, 0.32, row * 3,
                                  stock_indices)
    goods = kb.mesh_from_bmesh("gondola_goods", bm, list(rack.data.materials))

    bpy.ops.object.select_all(action="DESELECT")
    rack.select_set(True)
    goods.select_set(True)
    bpy.context.view_layer.objects.active = rack
    bpy.ops.object.join()
    rack = bpy.context.view_layer.objects.active

    kb.select_only(rack)
    kb.place_origin_at_base(rack)
    if width_target > 0.0:
        kb.scale_to_longest_side(rack, rack.dimensions.z * (width_target / max(width, 1e-5)))
    kb.shade(rack, 24.0)
    kb.bake_vertex_colours(rack, base=0.58, facet_jitter=0.045, seed=83)

    print("  gondola  %d tris  %.2f x %.2f x %.2f m  %d shelves  %d mat" % (
        kb.triangle_count(rack), rack.dimensions.x, rack.dimensions.y,
        rack.dimensions.z, len(shelves), len(rack.data.materials)))
    return rack


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="")
    parser.add_argument("--preview", default="")
    parser.add_argument("--width", type=float, default=0.0,
                        help="scale the fixture so it is this wide, in metres")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    rack = build(args.width)

    for other in bpy.data.objects:
        other.hide_render = other is not rack

    if args.out:
        kb.export_glb(rack, args.out)
        print("  wrote %s" % args.out)
    if args.preview:
        kb.render_contact_sheet([rack], args.preview, span=2.4, height=460,
                                elevation=0.24, shaded=True, from_front=True)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
