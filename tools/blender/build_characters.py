"""Builds the village's people in Blender. Developer tool.

**Kanca is not built here any more.** He was `build_kanca()` in this file —
first upright, then on four legs — and became a supplied model on 2026-08-31;
see `tools/blender/import_mascot.py` and the AI-generated art section of
ASSETS.md. The builder was deleted rather than left unused, because it wrote to
the same `assets/models/characters/kanca.glb` the importer does, and `--all`
would have quietly replaced the shipped mascot with a kancil nobody asked for.

    blender --background --factory-startup --python tools/blender/build_characters.py -- \
        --all --out-dir assets/models/characters --preview /tmp/characters.png

One `_humanoid` builder, parameterised by height, palette and a few proportions.
The player avatar and the three Warung customers are the same construction with
different numbers, and building them from one function is what keeps them
looking like they come from the same village.

Kanca is here too, built by his own function rather than by `_humanoid` - he is a
kancil, not a small person. His design was an open decision (PLAN.md 16.2) until
the project owner asked for a procedural one on 2026-08-30; PLAN.md records that.
What he still does not have is the rig, the five animations and the four
expressions 11.1 asks for, and a procedural script does not give you those.

Proportions are stylised at roughly three and a half heads for the people, which
is a child's proportion exaggerated a little - a big head reads as young and
reads at distance, which is the whole job here. Kanca is nearer two and a half,
per 11.1.

Facing: a model's front is -Z in Godot, and Blender's +Y becomes Godot's -Z on
export, so everyone here is built looking down +Y.
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


# ---------------------------------------------------------------- helpers

def add_limb(bm, start, end, radius_start, radius_end, material_index,
             segments=8, squareness=2.0, flatten=1.0):
    """A tapered tube between two points, capped at both ends.

    `squareness` above 2 turns a round limb into a rounded box, which is what
    makes a torso read as a t-shirt rather than a sausage.
    """
    start_vector, end_vector = Vector(start), Vector(end)
    axis = end_vector - start_vector
    if axis.length < 1e-6:
        return
    tangent = axis.normalized()

    SAMPLES = 2
    spine = []
    for i in range(SAMPLES):
        t = i / (SAMPLES - 1.0)
        spine.append((t, start_vector + axis * t, tangent))

    def section(t, theta):
        radius = radius_start + (radius_end - radius_start) * t
        return kb.superellipse(theta, radius, radius * flatten, squareness=squareness)

    kb.sweep(bm, spine, section, segments, material_index=material_index, cap_ends=True)


def _humanoid(name, palette, height=1.15, head_ratio=0.29, hair="short", skirt=False,
              cap=False, sandals=False, trousers=False):
    """The shared body. Everything below is a fraction of `height`, so changing
    one number rescales a whole person without redrawing them."""
    skin = kb.make_material("%s_skin" % name, palette["skin"], roughness=0.75)
    top = kb.make_material("%s_top" % name, palette["top"], roughness=0.85)
    bottom = kb.make_material("%s_bottom" % name, palette["bottom"], roughness=0.85)
    hair_material = kb.make_material("%s_hair" % name, palette["hair"], roughness=0.8)
    eye_white = kb.make_material("%s_eye" % name, (0.976, 0.973, 0.965), roughness=0.4)
    eye_dark = kb.make_material("%s_pupil" % name, (0.129, 0.098, 0.086), roughness=0.35)
    # A peci is black like hair, so it needs its own tone or it disappears into
    # the head. Slightly cooler and flatter reads as felt beside hair.
    cap_material = kb.make_material("%s_cap" % name, (0.090, 0.086, 0.110), roughness=0.9)

    SKIN, TOP, BOTTOM, HAIR, WHITE, PUPIL, CAP = 0, 1, 2, 3, 4, 5, 6

    head_size = height * head_ratio
    head_centre = height - head_size * 0.52
    shoulder_z = head_centre - head_size * 0.72
    waist_z = shoulder_z - height * 0.20
    hip_z = waist_z - height * 0.07
    knee_z = hip_z * 0.52
    foot_z = height * 0.030
    half_hip = height * 0.062
    half_shoulder = height * 0.140

    bm = bmesh.new()

    # Legs go into their own meshes so they can be swung. Everything else is one
    # object: the walk this supports is two rigid legs pivoting at the hip, which
    # is the whole vocabulary a low-poly character of this size needs, and it
    # costs two extra draw calls rather than a skeleton.
    legs = []
    for side in (-1.0, 1.0):
        x = side * half_hip
        leg_bm = bmesh.new()
        add_limb(leg_bm, (x, 0.0, foot_z), (x * 0.96, 0.0, hip_z + height * 0.02),
                 height * 0.050, height * 0.058, BOTTOM if trousers else SKIN, segments=8)
        kb.add_blob(leg_bm, (x, height * 0.026, foot_z * 0.75), height * 0.064,
                 SKIN if not sandals else BOTTOM, squash=(1.0, 1.75, 0.66))
        legs.append((leg_bm, Vector((x, 0.0, hip_z))))

    # Hips, then the torso: squarer at the top so it reads as clothing.
    if skirt:
        add_limb(bm, (0.0, 0.0, hip_z - height * 0.16), (0.0, 0.0, waist_z + height * 0.02),
                 height * 0.150, height * 0.115, BOTTOM, segments=10, squareness=2.4, flatten=0.72)
    else:
        add_limb(bm, (0.0, 0.0, hip_z - height * 0.06), (0.0, 0.0, waist_z + height * 0.02),
                 height * 0.118, height * 0.112, BOTTOM, segments=10, squareness=3.0, flatten=0.72)

    add_limb(bm, (0.0, 0.0, waist_z - height * 0.01), (0.0, 0.0, shoulder_z + height * 0.02),
             height * 0.112, half_shoulder, TOP, segments=10, squareness=3.2, flatten=0.70)

    # Arms, hanging slightly out from the body.
    for side in (-1.0, 1.0):
        shoulder = Vector((side * (half_shoulder - height * 0.012), 0.0, shoulder_z))
        elbow = Vector((side * (half_shoulder + height * 0.020), height * 0.004, waist_z))
        hand = Vector((side * (half_shoulder + height * 0.036), height * 0.010, hip_z - height * 0.02))
        add_limb(bm, shoulder, elbow + (shoulder - elbow) * 0.45, height * 0.058, height * 0.052,
                 TOP, segments=7, squareness=2.6)
        add_limb(bm, elbow + (shoulder - elbow) * 0.45, hand, height * 0.046, height * 0.036,
                 SKIN, segments=7)
        kb.add_blob(bm, hand, height * 0.054, SKIN, squash=(0.9, 1.0, 1.1))

    # Neck and head.
    add_limb(bm, (0.0, 0.0, shoulder_z), (0.0, 0.0, shoulder_z + height * 0.055),
             height * 0.045, height * 0.042, SKIN, segments=8)
    kb.add_blob(bm, (0.0, 0.0, head_centre), head_size * 0.5, SKIN,
             squash=(1.0, 0.94, 1.06), subdivisions=2)

    # Ears, which do a surprising amount for the silhouette.
    for side in (-1.0, 1.0):
        kb.add_blob(bm, (side * head_size * 0.49, -head_size * 0.02, head_centre - head_size * 0.02),
                 head_size * 0.11, SKIN, squash=(0.55, 1.0, 1.35))

    _add_hair(bm, hair, head_centre, head_size, HAIR)
    if cap:
        _add_peci(bm, head_centre, head_size, CAP)

    # Eyes on the +Y face.
    #
    # A dark almond with one white highlight, not a white ball with a pupil in
    # it. Two reasons. The head is a sphere squashed to 0.94 in Y, so at the
    # eyes' X offset its surface sits at about 0.43 head_size — a ball placed
    # there is mostly *inside* the head, and the small cap left showing catches
    # almost no light, which is how the first pass ended up with grey sockets
    # that read as swimming goggles. And at sixty pixels tall a white sclera is
    # one or two pixels wide: it contributes nothing but noise. A dark shape
    # against skin is the only eye that survives the distance the game is
    # actually played at.
    for side in (-1.0, 1.0):
        eye = Vector((side * head_size * 0.20, head_size * 0.435, head_centre + head_size * 0.05))
        kb.add_blob(bm, eye, head_size * 0.115, PUPIL, squash=(0.92, 0.34, 1.30),
                 subdivisions=2)
        kb.add_blob(bm, eye + Vector((side * head_size * 0.035, head_size * 0.030,
                                   head_size * 0.045)),
                 head_size * 0.040, WHITE, squash=(1.0, 0.6, 1.0), subdivisions=2)

    kb.add_blob(bm, (0.0, head_size * 0.475, head_centre - head_size * 0.045), head_size * 0.078,
             SKIN, squash=(1.0, 0.8, 0.72))

    # A mouth. One dark blob, but the difference between a face and a mannequin.
    kb.add_blob(bm, (0.0, head_size * 0.435, head_centre - head_size * 0.20), head_size * 0.088,
             PUPIL, squash=(1.35, 0.32, 0.55), subdivisions=2)

    materials = [skin, top, bottom, hair_material, eye_white, eye_dark, cap_material]
    obj = kb.mesh_from_bmesh(name, bm, materials)

    # Every part shaded against the same range, so a leg and the body it hangs
    # from agree about where the bottom of the character is.
    z_range = (0.0, height)
    kb.select_only(obj)
    kb.shade(obj, 48.0)
    kb.bake_vertex_colours(obj, base=0.72, facet_jitter=0.035, seed=41, z_range=z_range)

    for index, (leg_bm, pivot) in enumerate(legs):
        leg = kb.part_from_bmesh("%s_leg_%s" % (name, "l" if index == 0 else "r"),
                                 leg_bm, list(materials), pivot)
        kb.select_only(leg)
        kb.shade(leg, 48.0)
        # Shaded in character space before the origin moves, so `z_range` still
        # means what it says.
        kb.bake_vertex_colours(leg, base=0.72, facet_jitter=0.035, seed=41,
                               z_range=(-pivot.z, height - pivot.z))
        leg.parent = obj
        leg.matrix_parent_inverse = obj.matrix_world.inverted()

    kb.fit_hierarchy(obj, height)
    return obj


def _add_hair(bm, style, head_centre, head_size, material_index):
    """A cap over the skull plus a couple of tufts. The tufts matter: a smooth
    helmet of hair reads as a swimming cap.

    The cap sits high and slightly back. The hub camera looks down at the player
    from behind, so the top of the head is most of what anyone ever sees - a cap
    that reaches past the eyes turns the whole character into a mushroom.
    """
    # Big enough to clear the crown: the skull top is 0.53 head_size above the
    # head centre, so a cap flatter than this leaves a bald patch. It reaches
    # almost as far forward as the face, which costs nothing - where the head is
    # wider than the cap, the cap is simply inside it and never drawn.
    kb.add_blob(bm, (0.0, -head_size * 0.050, head_centre + head_size * 0.105), head_size * 0.500,
             material_index, squash=(1.0, 0.95, 0.88), subdivisions=2)

    if style == "short":
        # A fringe across the forehead, cut straight. Reads as a haircut from
        # above, where two floating tufts just read as noise.
        #
        # It has to sit *on* the front of the skull, not inside it. The head is a
        # sphere of radius head_size/2 squashed to 0.94 in Y, so at forehead
        # height its surface is around 0.43 head_size forward - a bar placed at
        # 0.17 is buried, which is why the first version of this had no fringe at
        # all and a bare forehead above the eyes.
        add_limb(bm, (-head_size * 0.28, head_size * 0.285, head_centre + head_size * 0.265),
                 (head_size * 0.28, head_size * 0.285, head_centre + head_size * 0.265),
                 head_size * 0.170, head_size * 0.170, material_index,
                 segments=7, squareness=2.6, flatten=0.92)
        kb.add_blob(bm, (head_size * 0.06, -head_size * 0.16, head_centre + head_size * 0.46),
                 head_size * 0.125, material_index, squash=(0.85, 0.9, 1.25))
    elif style == "bob":
        # Longer at the sides, framing the face.
        for side in (-1.0, 1.0):
            kb.add_blob(bm, (side * head_size * 0.44, -head_size * 0.06, head_centre - head_size * 0.16),
                     head_size * 0.22, material_index, squash=(0.7, 0.95, 1.5))
        kb.add_blob(bm, (0.0, -head_size * 0.40, head_centre - head_size * 0.12),
                 head_size * 0.30, material_index, squash=(1.0, 0.7, 1.2))


def _add_peci(bm, head_centre, head_size, material_index):
    """The flat cap an Indonesian man often wears. One shape, instantly read -
    provided it is wider than the hair underneath it.

    The first version had a radius of 0.46 head_size against a hair cap of 0.50,
    so it sat entirely inside the head and the only man in the village went
    bare-headed. Straight-sided and slightly proud of the skull is what makes it
    read as felt rather than as more hair.
    """
    add_limb(bm, (0.0, -head_size * 0.02, head_centre + head_size * 0.18),
             (0.0, -head_size * 0.02, head_centre + head_size * 0.70),
             head_size * 0.545, head_size * 0.525, material_index,
             segments=10, squareness=2.6)


# ---------------------------------------------------------------- people

def build_player():
    """The child's avatar: yellow tee, blue shorts, bare feet.

    Deliberately neutral. PLAN.md 7.1 asks for "a simple, neutral child
    character" - this is who the player is, not a character with opinions.
    """
    return _humanoid("player", {
        "skin": (0.847, 0.612, 0.408),
        "top": (0.965, 0.796, 0.145),
        "bottom": (0.129, 0.400, 0.749),
        "hair": (0.098, 0.086, 0.086),
    }, height=1.15, head_ratio=0.345, hair="short")


def build_customer_anak():
    """The child customer. Shortest, biggest head, and the only one in shorts.

    Palettes track the `colour` field each variant carries in
    data/levels/warung.json, so the roster and the models agree about who is who
    - that colour is still what the generated stand-in uses when a model is
    missing, and two different pinks for the same customer would be worse than
    one.
    """
    return _humanoid("cust_anak", {
        "skin": (0.808, 0.588, 0.416),
        "top": (0.949, 0.545, 0.510),
        "bottom": (0.318, 0.404, 0.596),
        "hair": (0.110, 0.098, 0.094),
    }, height=0.95, head_ratio=0.360, hair="short")


def build_customer_ibu():
    """The woman. Long skirt, bobbed hair, sandals.

    Adult proportions mean a smaller head relative to the body - about a quarter
    rather than a third. That single number is most of what separates a grown-up
    from a child here, and it does more work than the height does.
    """
    return _humanoid("cust_ibu", {
        "skin": (0.839, 0.639, 0.451),
        "top": (0.702, 0.616, 0.859),
        "bottom": (0.376, 0.302, 0.529),
        "hair": (0.094, 0.082, 0.078),
    }, height=1.32, head_ratio=0.255, hair="bob", skirt=True, sandals=True)


def build_customer_bapak():
    """The man. Tallest, peci, sandals."""
    return _humanoid("cust_bapak", {
        "skin": (0.784, 0.573, 0.384),
        "top": (0.502, 0.796, 0.769),
        "bottom": (0.294, 0.325, 0.361),
        "hair": (0.086, 0.075, 0.071),
    }, height=1.42, head_ratio=0.238, hair="short", cap=True, sandals=True,
        trousers=True)


def _spine(points):
    """(position, ...) samples along a curve -> the (t, position, tangent) list
    `kb.sweep` wants, with tangents from central differences."""
    positions = [Vector(point) for point in points]
    spine = []
    for index, position in enumerate(positions):
        ahead = positions[min(index + 1, len(positions) - 1)]
        behind = positions[max(index - 1, 0)]
        tangent = ahead - behind
        if tangent.length < 1e-6:
            tangent = Vector((0.0, 1.0, 0.0))
        spine.append((index / (len(positions) - 1.0), position, tangent.normalized()))
    return spine


def _tapered(table, squareness=2.1):
    """(t, half_width, half_height) samples -> a section function for kb.sweep.

    A body is not a tube of constant radius and it is not a cone either. What
    makes an animal read is where it is deepest and where it pinches, and this is
    the cheapest way to say so: five numbers down the length.
    """
    def section(t, theta):
        for index in range(len(table) - 1):
            low_t, low_w, low_h = table[index]
            high_t, high_w, high_h = table[index + 1]
            if t <= high_t or index == len(table) - 2:
                span = max(high_t - low_t, 1e-6)
                k = min(max((t - low_t) / span, 0.0), 1.0)
                # Smoothstep, so the joins between samples do not show as creases.
                k = k * k * (3.0 - 2.0 * k)
                return kb.superellipse(theta, low_w + (high_w - low_w) * k,
                                       low_h + (high_h - low_h) * k,
                                       squareness=squareness)
        return kb.superellipse(theta, table[-1][1], table[-1][2], squareness=squareness)
    return section


BUILDERS = {
    "cust_anak": build_customer_anak,
    "cust_bapak": build_customer_bapak,
    "cust_ibu": build_customer_ibu,
    "player": build_player,
}


def report(obj, character_id):
    """Measures the whole hierarchy, not the parent mesh.

    Once the legs became separate objects, `obj.dimensions` stopped describing
    the character: it reported the torso, and a player whose feet were on the
    ground looked like a model floating a quarter of a metre up.
    """
    triangles = kb.triangle_count(obj)
    lowest = float("inf")
    highest = -float("inf")
    reach = [float("inf"), float("inf"), -float("inf"), -float("inf")]
    materials = set()

    for part in [obj] + list(obj.children):
        if part is not obj:
            triangles += kb.triangle_count(part)
        materials.update(m.name for m in part.data.materials if m is not None)
        for vertex in part.data.vertices:
            point = part.matrix_world @ vertex.co
            lowest = min(lowest, point.z)
            highest = max(highest, point.z)
            reach[0] = min(reach[0], point.x)
            reach[1] = min(reach[1], point.y)
            reach[2] = max(reach[2], point.x)
            reach[3] = max(reach[3], point.y)
    flag = "  <-- over budget" if triangles > 3000 else ""
    print("  %-11s %5d tris  %.2f x %.2f x %.2f m  %d part  %d mat  base %+0.4f%s" % (
        character_id, triangles, reach[2] - reach[0], reach[3] - reach[1],
        highest - lowest, 1 + len(obj.children), len(materials), lowest, flag))
    return triangles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--character", choices=sorted(BUILDERS))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--out-dir")
    parser.add_argument("--preview", default="")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    ids = sorted(BUILDERS) if args.all else ([args.character] if args.character else [])
    if not ids:
        parser.error("pass --character <id> or --all")

    kb.reset_scene()
    built = []
    total = 0
    for character_id in ids:
        obj = BUILDERS[character_id]()
        total += report(obj, character_id)
        out_path = args.out if args.out else os.path.join(args.out_dir, "%s.glb" % character_id)
        kb.export_hierarchy(obj, out_path)
        built.append(obj)

    print("  %d characters, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=1.75, height=520, elevation=0.20,
                                from_front=True, shaded=True)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
