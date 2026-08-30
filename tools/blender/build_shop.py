"""Builds the warung's fittings. Developer tool.

    blender --background --factory-startup --python tools/blender/build_shop.py -- \
        --all --out-dir assets/models/shop --preview /tmp/shop.png

Shelving, crates, baskets and sacks - the stock that makes a shop look like a
shop.

**None of this is playable and none of it can be.** PLAN.md 3.3 sets a 120x120px
minimum touch target and a 40px gap, which at the warung's camera distance caps
the goods a child can actually pick up at five (see MAX_SHELF_SLOTS in
scripts/minigames/warung/warung.gd). A warung stocked with five bananas is not a
warung. So the shelves are dressing: dozens of jars and packets that read as a
well-stocked shop from across the counter, standing behind five very large items
the child can reach.

Getting that boundary wrong in the other direction would be worse than a bare
shop. A tin that looks like the apple beside it but cannot be picked up teaches a
child that touching things does not work.

Stock is baked into the shelf model rather than placed separately: one mesh, one
material, one draw call for forty objects.

Same brief as everything else - metres, origin at the base, Z-up, flat colours.
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


# Stock colours, picked to read as different goods at a glance rather than to be
# identifiable. A child is not meant to shop from these.
STOCK_COLOURS = [
    (0.847, 0.325, 0.267),   # tomato tin
    (0.949, 0.741, 0.259),   # oil
    (0.353, 0.588, 0.831),   # detergent
    (0.612, 0.784, 0.404),   # tea
    (0.902, 0.588, 0.278),   # biscuits
    (0.702, 0.478, 0.784),   # soap
    (0.949, 0.902, 0.804),   # rice
    (0.404, 0.663, 0.573),   # sardines
]


def _jar(bm, centre, radius, height, material_index):
    """A tin or a jar: a short cylinder with a lid ring."""
    kb.revolve(bm, [
        (0.000, 0.0),
        (radius, 0.0),
        (radius, height * 0.86),
        (radius * 0.82, height * 0.90),
        (radius * 0.82, height),
        (0.000, height),
    ], 6, material_at=material_index)
    # revolve builds at the origin, so shift the new geometry into place.
    _shift_recent(bm, centre)


def _shift_recent(bm, offset):
    """Moves everything added since the last call. bmesh has no scope, so this
    tracks by tagging: anything untagged is new."""
    moved = Vector(offset)
    for vert in bm.verts:
        if not vert.tag:
            vert.co += moved
            vert.tag = True


def _packet(bm, centre, size, material_index):
    kb.add_box(bm, size, (0.0, 0.0, size[2] * 0.5), material_index)
    _shift_recent(bm, (centre[0], centre[1], centre[2]))


def _sack(bm, centre, radius, height, material_index, tie_index=None):
    """A rice sack: near-straight sides, a hard gather at the neck, and a tie.

    The first version was a smooth revolved lump and it read as a boulder - the
    silhouette of a sack is not its bulk but the pinch at the top, and a profile
    that eases into that pinch throws the whole shape away.
    """
    kb.revolve(bm, [
        (0.000, 0.0),
        (radius * 0.92, 0.0),
        (radius, height * 0.18),
        (radius, height * 0.66),
        (radius * 0.86, height * 0.80),
        (radius * 0.30, height * 0.88),
        (radius * 0.26, height),
        (0.000, height * 1.02),
    ], 7, material_at=material_index)
    _shift_recent(bm, centre)

    if tie_index is not None:
        kb.add_blob(bm, (0.0, 0.0, height * 0.885), radius * 0.34, tie_index,
                    squash=(1.0, 1.0, 0.45))
        _shift_recent(bm, centre)


def _stock_a_board(bm, width, board_z, depth, row_seed, materials):
    """Fills one shelf board with a run of assorted goods.

    Deliberately uneven. A row of identical tins at identical spacing reads as
    wallpaper; gaps, pairs and the odd sack read as a shop where things have been
    taken off the shelf and put back.
    """
    x = -width * 0.5 + 0.10
    index = 0
    while x < width * 0.5 - 0.12:
        pick = int(abs(math.sin((index + 1) * 2.7 + row_seed) * 1000)) % 10
        material_index = materials[(index + row_seed) % len(materials)]

        if pick < 5:
            radius = 0.055 + 0.012 * (pick % 3)
            height = 0.16 + 0.04 * (pick % 3)
            _jar(bm, (x + radius, depth * 0.10, board_z), radius, height, material_index)
            x += radius * 2.0 + 0.035
        elif pick < 8:
            size = (0.13 + 0.02 * (pick % 2), 0.09, 0.20 + 0.03 * (pick % 2))
            _packet(bm, (x + size[0] * 0.5, depth * 0.08, board_z), size, material_index)
            x += size[0] + 0.035
        else:
            # A gap. Shelves are never full.
            x += 0.10
        index += 1


def build_shelf_unit():
    """A four-board rack, stocked. The warung's back wall in one model."""
    timber = kb.make_material("shelf_timber", (0.549, 0.396, 0.239), roughness=0.9)
    timber_dark = kb.make_material("shelf_timber_dark", (0.435, 0.302, 0.176), roughness=0.9)
    stock = [kb.make_material("shelf_stock_%d" % i, rgb, roughness=0.75)
             for i, rgb in enumerate(STOCK_COLOURS)]

    TIMBER, TIMBER_DARK = 0, 1
    stock_indices = list(range(2, 2 + len(stock)))

    WIDTH, DEPTH, HEIGHT = 1.80, 0.42, 2.05
    BOARDS = (0.28, 0.78, 1.28, 1.78)

    bm = bmesh.new()
    for vert in bm.verts:
        vert.tag = True

    # Uprights and a back panel, so the rack reads as furniture from the side as
    # well as head-on.
    for side in (-1.0, 1.0):
        kb.add_box(bm, (0.07, DEPTH, HEIGHT),
                   (side * (WIDTH * 0.5 - 0.035), 0.0, HEIGHT * 0.5), TIMBER_DARK)
    # Back panel on -Y. The shop faces +Y, and putting this on the wrong side
    # turns the whole rack into a plain box with every tin behind it.
    kb.add_box(bm, (WIDTH, 0.05, HEIGHT), (0.0, -DEPTH * 0.5 + 0.025, HEIGHT * 0.5),
               TIMBER_DARK)
    for board_z in BOARDS:
        kb.add_box(bm, (WIDTH - 0.07, DEPTH, 0.055), (0.0, 0.0, board_z), TIMBER)
    for vert in bm.verts:
        vert.tag = True

    for row, board_z in enumerate(BOARDS):
        _stock_a_board(bm, WIDTH - 0.16, board_z + 0.028, DEPTH, row * 3, stock_indices)

    obj = kb.mesh_from_bmesh("shelf_unit", bm,
                             [timber, timber_dark] + stock)
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.60, facet_jitter=0.05, seed=53)
    return obj


def build_crate():
    """An open wooden crate with produce heaped in it."""
    timber = kb.make_material("crate_timber", (0.612, 0.443, 0.267), roughness=0.9)
    fruit_a = kb.make_material("crate_fruit_a", (0.902, 0.475, 0.180), roughness=0.7)
    fruit_b = kb.make_material("crate_fruit_b", (0.784, 0.271, 0.235), roughness=0.7)

    W, D, H = 0.62, 0.46, 0.30
    bm = bmesh.new()
    for vert in bm.verts:
        vert.tag = True

    kb.add_box(bm, (W, D, 0.04), (0.0, 0.0, 0.02), 0)
    for side in (-1.0, 1.0):
        kb.add_box(bm, (0.035, D, H), (side * (W * 0.5 - 0.018), 0.0, H * 0.5), 0)
        kb.add_box(bm, (W, 0.035, H), (0.0, side * (D * 0.5 - 0.018), H * 0.5), 0)
    for vert in bm.verts:
        vert.tag = True

    # Heaped, not stacked: three rows sitting proud of the rim.
    for index in range(7):
        angle = index * 2.399
        x = math.cos(angle) * W * 0.28
        y = math.sin(angle) * D * 0.26
        kb.add_blob(bm, (x, y, H * 0.92 + 0.04 * (index % 2)), 0.085,
                    1 if index % 2 == 0 else 2, squash=(1.0, 1.0, 0.88))

    obj = kb.mesh_from_bmesh("crate", bm, [timber, fruit_a, fruit_b])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.62, facet_jitter=0.06, seed=59)
    return obj


def build_sack_pile():
    """Three rice sacks leaning on each other, for the floor beside the counter."""
    # Warmer and more saturated than real hessian. Against a grey floor at the
    # back of the shop, a true sack colour reads as stone.
    hessian = kb.make_material("sack_hessian", (0.878, 0.729, 0.427), roughness=0.95)
    hessian_dark = kb.make_material("sack_hessian_dark", (0.749, 0.596, 0.322),
                                    roughness=0.95)
    tie = kb.make_material("sack_tie", (0.545, 0.416, 0.220), roughness=0.9)

    bm = bmesh.new()
    for vert in bm.verts:
        vert.tag = True

    _sack(bm, (-0.17, 0.04, 0.0), 0.21, 0.52, 0, tie_index=2)
    _sack(bm, (0.19, -0.05, 0.0), 0.19, 0.46, 1, tie_index=2)
    _sack(bm, (0.00, 0.03, 0.44), 0.17, 0.38, 0, tie_index=2)

    obj = kb.mesh_from_bmesh("sack_pile", bm, [hessian, hessian_dark, tie])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.66, facet_jitter=0.05, seed=61)
    return obj


def build_hanging_bananas():
    """A bunch on a hook. Every warung has one and it costs sixty triangles."""
    peel = kb.make_material("hang_peel", (0.937, 0.784, 0.196), roughness=0.7)
    stalk = kb.make_material("hang_stalk", (0.478, 0.365, 0.180), roughness=0.9)

    bm = bmesh.new()
    for vert in bm.verts:
        vert.tag = True

    kb.add_box(bm, (0.05, 0.05, 0.22), (0.0, 0.0, 0.11), 1)
    for index in range(6):
        angle = math.tau * index / 6.0
        offset = Vector((math.cos(angle) * 0.10, math.sin(angle) * 0.09, -0.14))
        kb.add_blob(bm, offset, 0.115, 0, squash=(0.55, 0.42, 1.0))

    obj = kb.mesh_from_bmesh("hanging_bananas", bm, [peel, stalk])
    kb.select_only(obj)
    # Hangs from its top, so the origin goes to the hook rather than the base.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.58, facet_jitter=0.06, seed=67)
    return obj


BUILDERS = {
    "crate": build_crate,
    "hanging_bananas": build_hanging_bananas,
    "sack_pile": build_sack_pile,
    "shelf_unit": build_shelf_unit,
}


def report(obj, prop_id):
    triangles = kb.triangle_count(obj)
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    print("  %-17s %4d tris  %.2f x %.2f x %.2f m  %d mat  base %+0.4f" % (
        prop_id, triangles, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z,
        len(obj.data.materials), lowest))
    return triangles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prop", choices=sorted(BUILDERS))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--out-dir")
    parser.add_argument("--preview", default="")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    ids = sorted(BUILDERS) if args.all else ([args.prop] if args.prop else [])
    if not ids:
        parser.error("pass --prop <id> or --all")

    kb.reset_scene()
    built = []
    total = 0
    for prop_id in ids:
        obj = BUILDERS[prop_id]()
        total += report(obj, prop_id)
        out_path = args.out if args.out else os.path.join(args.out_dir, "%s.glb" % prop_id)
        kb.export_glb(obj, out_path)
        built.append(obj)

    print("  %d fittings, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=2.4, height=420, elevation=0.26,
                                shaded=True, from_front=True)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
