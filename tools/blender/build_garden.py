"""Builds the Kebun's furniture. Developer tool.

    blender --background --factory-startup --python tools/blender/build_garden.py -- \
        --all --out-dir assets/models/garden --preview /tmp/garden.png

A raised bed, three growth stages, a seed basket and a watering can.

The growth stages are generic on purpose. §8.2 grows a different crop in every
plot, and modelling a young banana, a young apple and a young orange separately
would be three models to say the same thing: something is coming up. The plant
carries the *stage*; the fruit that appears at the end is the item's own `.glb`,
which the Warung already uses - so what the child harvests is visibly the thing
they later sell.

Same brief as everything else - metres, origin at the base, Z-up, flat colours,
one baked material.
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
import build_scatter  # noqa: E402


def build_plot_bed():
    """A raised bed: four boards round a body of soil.

    The boards are the point. Soil on its own is a brown rectangle on grass and
    reads as a stain; a frame around it says somebody built this to grow things
    in, and it gives the drop target an edge a child can aim at.
    """
    timber = kb.make_material("bed_timber", (0.616, 0.435, 0.259), roughness=0.9)
    timber_dark = kb.make_material("bed_timber_dark", (0.494, 0.337, 0.196), roughness=0.9)
    soil = kb.make_material("bed_soil", (0.353, 0.243, 0.169), roughness=1.0)
    soil_dark = kb.make_material("bed_soil_dark", (0.286, 0.192, 0.129), roughness=1.0)

    TIMBER, TIMBER_DARK, SOIL, SOIL_DARK = 0, 1, 2, 3
    W, D, H = 1.40, 1.45, 0.26
    BOARD = 0.09

    bm = bmesh.new()

    # Soil first, so the boards overlap it rather than the other way round.
    kb.add_box(bm, (W - BOARD, D - BOARD, H * 0.82), (0.0, 0.0, H * 0.41), SOIL)

    # A few clods, so the surface is not a flat plane of one colour.
    for index in range(9):
        angle = index * 2.399
        radius = 0.34 * math.sqrt((index + 1) / 9.0)
        kb.add_blob(bm, (math.cos(angle) * radius * W * 0.62,
                         math.sin(angle) * radius * D * 0.62,
                         H * 0.80),
                    0.085 + 0.02 * (index % 3), SOIL_DARK if index % 2 else SOIL,
                    squash=(1.0, 1.0, 0.42))

    for side in (-1.0, 1.0):
        kb.add_box(bm, (W, BOARD, H), (0.0, side * (D - BOARD) * 0.5, H * 0.5), TIMBER)
        kb.add_box(bm, (BOARD, D, H), (side * (W - BOARD) * 0.5, 0.0, H * 0.5), TIMBER)
    # Corner pegs, standing slightly proud. Cheap, and they stop the frame
    # reading as a single moulded tray.
    for x in (-1.0, 1.0):
        for y in (-1.0, 1.0):
            kb.add_box(bm, (BOARD * 1.5, BOARD * 1.5, H * 1.22),
                       (x * (W - BOARD) * 0.5, y * (D - BOARD) * 0.5, H * 0.61),
                       TIMBER_DARK)

    obj = kb.mesh_from_bmesh("plot_bed", bm, [timber, timber_dark, soil, soil_dark])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.64, facet_jitter=0.06, seed=91)
    return obj


def _plant(name, height, blade_count, blade_length, width, seed):
    leaf = kb.make_material("%s_leaf" % name, (0.310, 0.588, 0.208), roughness=0.9)
    stem = kb.make_material("%s_stem" % name, (0.400, 0.612, 0.243), roughness=0.9)

    bm = bmesh.new()
    kb.sweep(
        bm,
        [(0.0, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0))),
         (1.0, Vector((0.0, 0.0, height)), Vector((0.0, 0.0, 1.0)))],
        lambda t, theta: kb.superellipse(theta, 0.026 * (1.0 - t * 0.35),
                                         0.026 * (1.0 - t * 0.35), squareness=2.0),
        5, material_index=1, cap_ends=True)
    build_scatter._blades(bm, blade_count, 0, length=blade_length, width=width,
                          spread=0.95, lean=0.85, seed=seed, segments=3)

    obj = kb.mesh_from_bmesh(name, bm, [leaf, stem])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.56, facet_jitter=0.07, seed=seed + 100)
    return obj


def build_plant_sprout():
    """Stage one: barely there. Two leaves and a stem, and small enough that the
    child can see it has changed when stage two arrives."""
    return _plant("plant_sprout", 0.11, 3, 0.13, 0.028, 7)


def build_plant_young():
    """Stage two: a real clump of leaves, no fruit yet."""
    return _plant("plant_young", 0.24, 6, 0.30, 0.048, 13)


def build_plant_grown():
    """Stage three: the bush the item's own model sits on top of."""
    return _plant("plant_grown", 0.34, 8, 0.42, 0.058, 19)


def build_seed_basket():
    """A woven basket of seed. Wider at the rim, because a basket that tapers the
    other way reads as a bucket."""
    weave = kb.make_material("basket_weave", (0.749, 0.549, 0.310), roughness=0.9)
    weave_dark = kb.make_material("basket_weave_dark", (0.612, 0.427, 0.220), roughness=0.9)
    seed = kb.make_material("basket_seed", (0.545, 0.427, 0.259), roughness=0.95)

    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.00), (0.230, 0.00), (0.255, 0.05),
        (0.285, 0.16), (0.310, 0.26),
    ], 10, material_at=0)
    # A rim band, and a couple of weave lines that survive at this size.
    kb.revolve(bm, [
        (0.310, 0.24), (0.325, 0.26), (0.310, 0.28),
    ], 10, material_at=1)
    kb.revolve(bm, [
        (0.268, 0.12), (0.281, 0.14), (0.268, 0.16),
    ], 10, material_at=1)
    # Heaped seed, sitting just below the rim.
    kb.add_blob(bm, (0.0, 0.0, 0.235), 0.255, 2, squash=(1.0, 1.0, 0.30))

    obj = kb.mesh_from_bmesh("seed_basket", bm, [weave, weave_dark, seed])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 30.0)
    kb.bake_vertex_colours(obj, base=0.62, facet_jitter=0.05, seed=23)
    return obj


def build_watering_can():
    """Body, spout, handle. The spout is what makes it readable at a glance -
    without it this is a mug."""
    metal = kb.make_material("can_metal", (0.373, 0.643, 0.804), roughness=0.65)
    metal_dark = kb.make_material("can_metal_dark", (0.271, 0.502, 0.667), roughness=0.7)

    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.00), (0.185, 0.00), (0.200, 0.06),
        (0.195, 0.24), (0.170, 0.30), (0.000, 0.32),
    ], 10, material_at=0)

    # Spout: rising away from the body and flaring at the end.
    kb.sweep(
        bm,
        [(0.0, Vector((0.15, 0.0, 0.10)), Vector((1.0, 0.0, 0.55)).normalized()),
         (0.5, Vector((0.34, 0.0, 0.22)), Vector((1.0, 0.0, 0.55)).normalized()),
         (1.0, Vector((0.46, 0.0, 0.31)), Vector((1.0, 0.0, 0.55)).normalized())],
        lambda t, theta: kb.superellipse(theta, 0.050 + 0.028 * t * t,
                                         0.050 + 0.028 * t * t, squareness=2.0),
        8, material_index=1, cap_ends=True)

    # Handle: an arch over the top.
    SAMPLES = 7
    spine = []
    for i in range(SAMPLES):
        t = i / (SAMPLES - 1.0)
        angle = math.pi * t
        point = Vector((-0.02 - math.cos(angle) * 0.17, 0.0, 0.30 + math.sin(angle) * 0.15))
        spine.append((t, point, Vector((0.0, 0.0, 1.0))))
    for i in range(SAMPLES):
        t, point, _tangent = spine[i]
        ahead = spine[min(i + 1, SAMPLES - 1)][1]
        behind = spine[max(i - 1, 0)][1]
        tangent = (ahead - behind)
        if tangent.length < 1e-5:
            tangent = Vector((0.0, 0.0, 1.0))
        spine[i] = (t, point, tangent.normalized())
    kb.sweep(bm, spine,
             lambda t, theta: kb.superellipse(theta, 0.030, 0.030, squareness=2.0),
             6, material_index=1, cap_ends=True)

    obj = kb.mesh_from_bmesh("watering_can", bm, [metal, metal_dark])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 34.0)
    kb.bake_vertex_colours(obj, base=0.60, facet_jitter=0.04, seed=29)
    return obj


BUILDERS = {
    "plant_grown": build_plant_grown,
    "plant_sprout": build_plant_sprout,
    "plant_young": build_plant_young,
    "plot_bed": build_plot_bed,
    "seed_basket": build_seed_basket,
    "watering_can": build_watering_can,
}


def report(obj, prop_id):
    triangles = kb.triangle_count(obj)
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    print("  %-15s %4d tris  %.2f x %.2f x %.2f m  %d mat  base %+0.4f" % (
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

    print("  %d garden pieces, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=1.7, height=400, elevation=0.30,
                                shaded=True, from_front=True)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
