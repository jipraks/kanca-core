"""Builds the village scenery props in Blender. Developer tool.

    blender --background --factory-startup --python tools/blender/build_props.py -- \
        --all --out-dir assets/models/environment --preview /tmp/props.png

Two trees, deliberately different from each other. The village is seen from a
fixed camera at a distance (PLAN.md 7.1), so what carries is the silhouette: one
round leafy canopy and one banana palm with big drooping fronds. Repeating a
single tree twelve times is what makes a place look generated rather than built.

Same brief as everything else - metres, origin at the base, Z-up, flat colours,
and low enough to sit inside the 80,000-triangle scene budget alongside three
buildings and two characters.
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


def _lobe(bm, centre, radius, squash, material_index, subdivisions=1):
    """One faceted blob of foliage. An icosphere at subdivision 1 is 80 triangles
    and reads as leaves at village distance; anything smoother is wasted."""
    result = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    for vert in result["verts"]:
        vert.co.z *= squash
        vert.co += Vector(centre)
    faces = set()
    for vert in result["verts"]:
        faces.update(vert.link_faces)
    for face in faces:
        face.material_index = material_index


def build_tree_leafy():
    """A tapered trunk under three overlapping lobes.

    Three lobes rather than one sphere: a single ball on a stick reads as a
    lollipop, and the offsets are what give it a canopy.
    """
    trunk_material = kb.make_material("tree_trunk", (0.435, 0.302, 0.176), roughness=0.95)
    leaf_material = kb.make_material("tree_leaf", (0.153, 0.412, 0.227), roughness=0.9)

    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.00), (0.230, 0.02), (0.190, 0.55),
        (0.150, 1.35), (0.135, 2.05), (0.000, 2.20),
    ], 8, material_at=0)

    _lobe(bm, (0.00, 0.00, 2.55), 1.15, 0.82, 1)
    _lobe(bm, (-0.62, 0.30, 2.05), 0.82, 0.86, 1)
    _lobe(bm, (0.58, -0.26, 2.18), 0.74, 0.88, 1)

    obj = kb.mesh_from_bmesh("tree_leafy", bm, [trunk_material, leaf_material])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Flat, not smoothed. A gradient painted onto a smooth-shaded sphere is a
    # soft bloom; painted onto flat facets it is a low-poly canopy. The vertex
    # colours were doing their job long before this line was right - what was
    # wrong was that the normals were averaging the facets away.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.52, facet_jitter=0.07, seed=3)
    return obj


def build_tree_banana():
    """A banana palm: short ringed trunk, big drooping fronds, a hanging bunch.

    The fronds are the whole silhouette, so they are swept individually rather
    than approximated with a blob.
    """
    trunk_material = kb.make_material("banana_trunk", (0.420, 0.416, 0.243), roughness=0.95)
    leaf_material = kb.make_material("banana_leaf", (0.196, 0.478, 0.180), roughness=0.9)
    fruit_material = kb.make_material("banana_fruit", (0.855, 0.686, 0.098), roughness=0.8)

    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.00), (0.290, 0.02), (0.245, 0.45),
        (0.255, 0.90), (0.215, 1.45), (0.225, 1.90),
        (0.190, 2.35), (0.000, 2.45),
    ], 9, material_at=0)

    FRONDS = 6
    for index in range(FRONDS):
        yaw = math.tau * index / FRONDS + 0.24
        droop = 1.0 + 0.35 * math.sin(float(index) * 1.7)
        _frond(bm, yaw, 2.30, droop, leaf_material_index=1)

    # A hanging bunch, because a banana palm without bananas is just a big weed.
    kb.revolve(bm, [
        (0.000, 1.62), (0.170, 1.70), (0.215, 1.90),
        (0.180, 2.08), (0.000, 2.16),
    ], 8, material_at=2)

    obj = kb.mesh_from_bmesh("tree_banana", bm, [trunk_material, leaf_material, fruit_material])
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Flat, not smoothed. A gradient painted onto a smooth-shaded sphere is a
    # soft bloom; painted onto flat facets it is a low-poly canopy. The vertex
    # colours were doing their job long before this line was right - what was
    # wrong was that the normals were averaging the facets away.
    kb.shade(obj, 1.0)
    kb.bake_vertex_colours(obj, base=0.50, facet_jitter=0.08, seed=7)
    return obj


def _frond(bm, yaw, base_z, droop, leaf_material_index):
    """One banana leaf, swept along an arc that rises then falls away."""
    SAMPLES, RADIAL = 9, 6
    LENGTH = 2.15

    direction = Vector((math.cos(yaw), math.sin(yaw), 0.0))

    spine = []
    for i in range(SAMPLES):
        t = i / (SAMPLES - 1.0)
        reach = LENGTH * t
        # Up out of the crown, then over and down under its own weight.
        rise = math.sin(t * math.pi * 0.72) * 0.85 - (t ** 2.4) * droop
        position = direction * reach + Vector((0.0, 0.0, base_z + rise))
        step = 1.0 / (SAMPLES - 1.0)
        ahead = direction * (LENGTH * min(t + step, 1.0)) + Vector((
            0.0, 0.0, base_z + math.sin(min(t + step, 1.0) * math.pi * 0.72) * 0.85
            - (min(t + step, 1.0) ** 2.4) * droop))
        tangent = (ahead - position)
        if tangent.length < 1e-5:
            tangent = direction
        spine.append((t, position, tangent.normalized()))

    def section(t, theta):
        # Wide in the middle, pointed at the tip, and flat: a leaf, not a tube.
        width = 0.40 * math.sin(math.pi * min(max(t, 0.02), 0.995)) ** 0.55
        return kb.superellipse(theta, width, width * 0.09, squareness=2.6)

    kb.sweep(bm, spine, section, RADIAL, material_index=leaf_material_index, cap_ends=True)


BUILDERS = {
    "tree_leafy": build_tree_leafy,
    "tree_banana": build_tree_banana,
}


def report(obj, prop_id):
    triangles = kb.triangle_count(obj)
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    print("  %-13s %4d tris  %.2f x %.2f x %.2f m  %d mat  base %+0.4f" % (
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

    print("  %d props, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=4.5, height=420, elevation=0.34)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
