"""Builds the small things that fill the village floor. Developer tool.

    blender --background --factory-startup --python tools/blender/build_scatter.py -- \
        --all --out-dir assets/models/environment --preview /tmp/scatter.png

Bushes, ferns, flowers, grass, rocks and a bamboo fence panel. None of these is
interesting on its own, which is the point: what separates a village from a green
field with three buildings on it is a hundred pieces of undergrowth nobody looks
at directly.

Budget is per-copy and tight, because these get scattered by the hundred rather
than placed by the dozen. A fence panel at six hundred triangles is not a small
model - repeated round a 160-metre boundary it costs forty thousand, which is
half the scene budget spent on something nobody looks at.

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


def _blades(bm, count, material_index, length, width, spread, lean, seed=0.0,
            segments=4):
    """A fan of tapered blades rising from one point and arching outwards.

    Grass and fern fronds are the same shape at different scales. Blades rather
    than a blob because these sit at the camera's near edge, where a lump of
    green reads as a lump of green.
    """
    for index in range(count):
        # Deterministic pseudo-spread: no RNG, so a rebuild is byte-identical.
        wobble = math.sin((index + 1) * 2.399 + seed)
        yaw = math.tau * index / count + wobble * 0.28
        reach = length * (0.72 + 0.28 * abs(math.sin((index + 1) * 1.7 + seed)))
        direction = Vector((math.cos(yaw), math.sin(yaw), 0.0))

        SAMPLES = segments + 1
        spine = []
        for i in range(SAMPLES):
            t = i / (SAMPLES - 1.0)
            # Up first, then over: a blade bends under its own weight.
            rise = math.sin(t * math.pi * 0.55) * reach * lean
            position = direction * (reach * spread * t * t) + Vector((0.0, 0.0, rise))
            step = 1.0 / (SAMPLES - 1.0)
            ahead_t = min(t + step, 1.0)
            ahead = direction * (reach * spread * ahead_t * ahead_t) + Vector((
                0.0, 0.0, math.sin(ahead_t * math.pi * 0.55) * reach * lean))
            tangent = ahead - position
            if tangent.length < 1e-5:
                tangent = Vector((0.0, 0.0, 1.0))
            spine.append((t, position, tangent.normalized()))

        def section(t, theta, w=width):
            # Widest a third of the way up, pointed at the tip.
            taper = math.sin(math.pi * min(max(t * 0.75 + 0.12, 0.02), 0.99)) ** 0.7
            return kb.superellipse(theta, w * taper, w * taper * 0.22, squareness=2.4)

        kb.sweep(bm, spine, section, 4, material_index=material_index, cap_ends=True)


def build_bush():
    """Three overlapping lobes. The offsets are the whole model."""
    leaf = kb.make_material("bush_leaf", (0.243, 0.502, 0.196), roughness=0.92)
    under = kb.make_material("bush_shade", (0.157, 0.353, 0.141), roughness=0.95)

    bm = bmesh.new()
    kb.add_blob(bm, (0.00, 0.00, 0.36), 0.44, 0, squash=(1.0, 0.92, 0.78))
    kb.add_blob(bm, (-0.30, 0.14, 0.22), 0.30, 1, squash=(1.0, 1.0, 0.85))
    kb.add_blob(bm, (0.26, -0.12, 0.25), 0.27, 0, squash=(1.0, 1.0, 0.88))

    obj = kb.mesh_from_bmesh("bush", bm, [leaf, under])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Flat, not smoothed. A gradient painted onto a smooth-shaded sphere is a
    # soft bloom; painted onto flat facets it is a low-poly canopy. The vertex
    # colours were doing their job long before this line was right - what was
    # wrong was that the normals were averaging the facets away.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.48, facet_jitter=0.09, seed=11)
    return obj


def build_fern():
    """Tropical undergrowth: long arching fronds, no trunk."""
    frond = kb.make_material("fern_frond", (0.337, 0.549, 0.184), roughness=0.9)

    bm = bmesh.new()
    _blades(bm, 5, 0, length=0.88, width=0.12, spread=1.15, lean=1.0, segments=3)
    _blades(bm, 3, 0, length=0.52, width=0.08, spread=0.85, lean=1.1, seed=1.3, segments=2)

    obj = kb.mesh_from_bmesh("fern", bm, [frond])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Flat, not smoothed. A gradient painted onto a smooth-shaded sphere is a
    # soft bloom; painted onto flat facets it is a low-poly canopy. The vertex
    # colours were doing their job long before this line was right - what was
    # wrong was that the normals were averaging the facets away.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.50, facet_jitter=0.09, seed=13)
    return obj


def build_grass_tuft():
    """The cheapest thing here and the one that does the most. Scattered thickly
    it turns a painted floor into ground."""
    blade = kb.make_material("grass_blade", (0.494, 0.702, 0.267), roughness=0.95)

    bm = bmesh.new()
    _blades(bm, 4, 0, length=0.40, width=0.050, spread=0.75, lean=1.0, segments=2)

    obj = kb.mesh_from_bmesh("grass_tuft", bm, [blade])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Flat, not smoothed. A gradient painted onto a smooth-shaded sphere is a
    # soft bloom; painted onto flat facets it is a low-poly canopy. The vertex
    # colours were doing their job long before this line was right - what was
    # wrong was that the normals were averaging the facets away.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.54, facet_jitter=0.10, seed=17)
    return obj


def _flower_plant(name, petal_rgb):
    """A low leafy clump with a couple of blooms held above it.

    Two materials, not four. Every material is a separate surface and therefore
    a separate draw call, and there are two of these plants scattered forty-odd
    times each - four materials apiece was eight draw calls spent on stamens.
    """
    leaf = kb.make_material("%s_leaf" % name, (0.310, 0.545, 0.212), roughness=0.92)
    petal = kb.make_material("%s_petal" % name, petal_rgb, roughness=0.7)

    bm = bmesh.new()
    _blades(bm, 4, 0, length=0.30, width=0.06, spread=0.9, lean=0.95, segments=2)

    for index, (x, y, z) in enumerate(((0.00, 0.02, 0.40), (-0.15, -0.10, 0.32))):
        kb.sweep(
            bm,
            [(0.0, Vector((x * 0.35, y * 0.35, 0.02)), Vector((0.0, 0.0, 1.0))),
             (1.0, Vector((x, y, z)), Vector((0.0, 0.0, 1.0)))],
            lambda t, theta: kb.superellipse(theta, 0.018, 0.018, squareness=2.0),
            4, material_index=0, cap_ends=True)
        # One flattened blob for the whole flower head. A ring of petals is the
        # right shape and the wrong price.
        kb.add_blob(bm, (x, y, z), 0.085, 1, squash=(1.0, 1.0, 0.38))

    obj = kb.mesh_from_bmesh(name, bm, [leaf, petal])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Flat, not smoothed. A gradient painted onto a smooth-shaded sphere is a
    # soft bloom; painted onto flat facets it is a low-poly canopy. The vertex
    # colours were doing their job long before this line was right - what was
    # wrong was that the normals were averaging the facets away.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.58, facet_jitter=0.07, seed=19)
    return obj


def build_flower_red():
    return _flower_plant("flower_red", (0.882, 0.271, 0.184))


def build_flower_purple():
    return _flower_plant("flower_purple", (0.639, 0.353, 0.788))


def build_rock():
    """An icosphere pushed out of round. Angular, because a smooth grey ball on
    grass reads as a beach ball."""
    stone = kb.make_material("rock_stone", (0.400, 0.404, 0.384), roughness=0.95)

    bm = bmesh.new()
    result = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.34)
    for index, vert in enumerate(result["verts"]):
        # Deterministic displacement, so the rock is the same rock every build.
        push = 1.0 + 0.26 * math.sin(index * 2.7) * math.cos(index * 1.3)
        vert.co.x *= push * 1.15
        vert.co.y *= push
        vert.co.z *= push * 0.62
    for face in bm.faces:
        face.material_index = 0

    obj = kb.mesh_from_bmesh("rock", bm, [stone])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Left faceted on purpose: no smoothing angle high enough to round it off.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.62, facet_jitter=0.11, seed=23)
    return obj


def build_bamboo_fence():
    """One panel: two posts and three rails, meant to be repeated end to end.

    Bamboo rather than a hedge because 7.1 wants a boundary a child can see
    themselves stopped by, and a green wall against green grass is very close to
    the invisible wall the rule exists to forbid.
    """
    cane = kb.make_material("bamboo_cane", (0.788, 0.647, 0.267), roughness=0.75)
    cane_dark = kb.make_material("bamboo_node", (0.639, 0.494, 0.180), roughness=0.8)

    PANEL = 3.3
    HEIGHT = 1.15
    bm = bmesh.new()

    def cane_run(start, end, radius, material_index, nodes=3):
        start_vector, end_vector = Vector(start), Vector(end)
        axis = end_vector - start_vector
        if axis.length < 1e-5:
            return
        tangent = axis.normalized()
        SAMPLES = max(nodes * 2 + 2, 6)
        spine = []
        for i in range(SAMPLES):
            t = i / (SAMPLES - 1.0)
            spine.append((t, start_vector + axis * t, tangent))

        def section(t, theta):
            # Bulge at the nodes. It is the only thing that says bamboo rather
            # than dowel, and it costs nothing.
            swell = 1.0 + 0.14 * max(0.0, math.cos(t * math.pi * 2.0 * nodes))
            return kb.superellipse(theta, radius * swell, radius * swell, squareness=2.0)

        kb.sweep(bm, spine, section, 4, material_index=material_index, cap_ends=True)

    for side in (-1.0, 1.0):
        x = side * PANEL * 0.5
        cane_run((x, 0.0, 0.0), (x, 0.0, HEIGHT), 0.075, 0, nodes=2)

    for rail_z, radius in ((HEIGHT * 0.82, 0.055), (HEIGHT * 0.42, 0.052)):
        cane_run((-PANEL * 0.5 - 0.06, 0.0, rail_z), (PANEL * 0.5 + 0.06, 0.0, rail_z),
                 radius, 1, nodes=3)

    obj = kb.mesh_from_bmesh("bamboo_fence", bm, [cane, cane_dark])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    kb.shade(obj, 40.0)
    kb.bake_vertex_colours(obj, base=0.70, facet_jitter=0.05, seed=29)
    return obj


BUILDERS = {
    "bamboo_fence": build_bamboo_fence,
    "bush": build_bush,
    "fern": build_fern,
    "flower_purple": build_flower_purple,
    "flower_red": build_flower_red,
    "grass_tuft": build_grass_tuft,
    "rock": build_rock,
}


def report(obj, prop_id):
    triangles = kb.triangle_count(obj)
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    flag = "  <-- over budget" if triangles > 340 else ""
    print("  %-14s %4d tris  %.2f x %.2f x %.2f m  %d mat  base %+0.4f%s" % (
        prop_id, triangles, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z,
        len(obj.data.materials), lowest, flag))
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

    print("  %d props, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=1.6, height=380, elevation=0.30,
                                shaded=True)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
