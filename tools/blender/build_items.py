"""Builds Kanca's item models procedurally in Blender. Developer tool.

    blender --background --factory-startup --python tools/blender/build_items.py -- \
        --all --out-dir assets/models/items --preview /tmp/items.png

    blender --background --factory-startup --python tools/blender/build_items.py -- \
        --item pisang --out assets/models/items/pisang.glb

Why a script rather than modelling by hand: fifteen items have to agree on scale,
origin, orientation, polygon budget and material style, and every one of those is
a spec in docs/ART_STYLE.md rather than a matter of taste. A script keeps them
honest, re-running it after a spec change is free, and the result is
unambiguously authored work - there is no provenance question to answer later.

Everything here follows the model brief:

  * 1 Blender unit = 1 metre, longest side ~0.22 m
  * origin at the base, centred, so the game can place it by its feet
  * Z-up while modelling; the glTF exporter converts to Godot's Y-up
  * flat colour materials, no texture maps
  * 200-600 triangles

Blender is Z-up and Godot is Y-up. Model here with Z as up and let the exporter
do the conversion - hand-rotating the mesh instead is how models end up lying on
their side in game.

Colours are pushed deeper and more saturated than the real object. Godot's filmic
tonemap lifts and desaturates, so a photographically "correct" colour arrives on
screen looking washed out, against a section 11 brief asking for bright and
saturated.
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

# ---------------------------------------------------------------- setup

# At the Warung camera roughly 250px = 1m, so this lands each item near 80px.
# 0.22 was true to life and read as a speck. The shelf touch box is 0.5m and the
# slot spacing 0.85m, so there is room for this without breaking section 3.3.
ITEM_LONGEST_SIDE = 0.32

# Modest variation so a sweet is not the size of a sack of rice. Kept narrow on
# purpose: every item still has to be equally easy to see and tap (section 3.3).
LONGEST_SIDE = {
    "permen": 0.240,
    "sabun": 0.270,
    "telur": 0.270,
    "biskuit": 0.290,
    "beras": 0.350,
    "minyak": 0.356,
    "es_krim": 0.342,
}


# ---------------------------------------------------------------- geometry

def rounded_box(bm, size, bevel_width, material_index=0, segments=2, offset=None):
    """A bevelled cube. The bevel is what stops a soap bar looking like a brick."""
    result = bmesh.ops.create_cube(bm, size=1.0)
    verts = result["verts"]
    for vert in verts:
        vert.co.x *= size[0]
        vert.co.y *= size[1]
        vert.co.z *= size[2]
        if offset is not None:
            vert.co += offset

    # Material goes on before the bevel, not after: bevelling removes the original
    # vertices, so anything still holding a reference to them throws. Bevel
    # inherits the material index from the faces it grew out of, so the new
    # rounded strips come out right on their own.
    faces = set()
    for vert in verts:
        faces.update(vert.link_faces)
    for face in faces:
        face.material_index = material_index

    # Bevel wants each element once. Collecting edges face by face hands it the
    # shared ones twice, which it rejects outright.
    edges = set()
    for face in faces:
        edges.update(face.edges)
    bmesh.ops.bevel(bm, geom=list(edges), offset=bevel_width, segments=segments,
                    profile=0.5, affect="EDGES")


def apply_scale(obj):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def finalise(obj, item_id, smooth_angle_degrees=55.0):
    """Scale to spec, drop the origin to the base, and smooth the shading.

    Called for every item so none of them can drift from the brief.
    """
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.context.view_layer.update()
    dimensions = obj.dimensions
    current = max(dimensions.x, dimensions.y, dimensions.z)
    target = LONGEST_SIDE.get(item_id, ITEM_LONGEST_SIDE)
    if current > 0.0:
        obj.scale = (target / current,) * 3
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Origin at the base, centred in X and Y: the game places items by their feet.
    bpy.context.view_layer.update()
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    centre = sum((obj.matrix_world @ v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
    bpy.context.scene.cursor.location = Vector((centre.x, centre.y, lowest))
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.location = (0.0, 0.0, 0.0)
    bpy.context.scene.cursor.location = Vector((0.0, 0.0, 0.0))

    # Smooth normals, but keep genuinely sharp edges sharp. This is what stops a
    # low-poly model reading as faceted without adding a single triangle - and
    # what keeps a carton's corners crisp while an apple stays round.
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle_degrees))
    except (AttributeError, RuntimeError):
        pass

    return obj


# ---------------------------------------------------------------- builders

def build_pisang():
    """Tapered, three-ridged tube swept along an arc.

    The ridges matter. A smooth tube reads as a sausage; the three soft edges are
    what make it a banana at 48px, and section 11 asks every item to be tellable
    apart by silhouette rather than colour alone.
    """
    RINGS, RADIAL = 13, 10
    ARC_HALF_ANGLE, BODY_RADIUS, RIDGE_DEPTH = 1.02, 0.207, 0.155

    body = kb.make_material("pisang_body", (0.980, 0.706, 0.055), roughness=0.72)
    tip = kb.make_material("pisang_tip", (0.361, 0.235, 0.086), roughness=0.9)

    def frame(t):
        angle = (t * 2.0 - 1.0) * ARC_HALF_ANGLE
        return (Vector((math.sin(angle), 0.0, -math.cos(angle))),
                Vector((math.cos(angle), 0.0, math.sin(angle))).normalized())

    def section(t, theta):
        radius = BODY_RADIUS * (1.0 - abs(2.0 * t - 1.0) ** 3.0) ** 0.45
        radius *= 1.0 + RIDGE_DEPTH * math.cos(3.0 * theta + math.pi)
        return math.cos(theta) * radius, math.sin(theta) * radius

    spine = []
    for i in range(RINGS):
        t = (i + 0.5) / (RINGS + 1.0)
        position, tangent = frame(t)
        spine.append((t, position, tangent))

    bm = bmesh.new()
    rings = kb.sweep(bm, spine, section, RADIAL, material_index=0, cap_ends=False)
    start_position, start_tangent = frame(0.0)
    end_position, end_tangent = frame(1.0)
    kb.cap_with_tip(bm, rings[0], start_position - start_tangent * 0.035, RADIAL, 1, reverse=True)
    kb.cap_with_tip(bm, rings[-1], end_position + end_tangent * 0.055, RADIAL, 1)

    return finalise(kb.mesh_from_bmesh("pisang", bm, [body, tip]), "pisang", 60.0)


def _fruit(name, body_colour, profile, segments, stem_height, squash=1.0):
    """Shared apple/orange body: a lathed silhouette with a stem and one leaf.

    The dimple at both poles comes free from ending the profile on a pole vertex
    that sits lower than the ring below it.
    """
    body = kb.make_material("%s_body" % name, body_colour, roughness=0.62)
    stem = kb.make_material("%s_stem" % name, (0.310, 0.196, 0.086), roughness=0.9)
    leaf_material = kb.make_material("%s_leaf" % name, (0.243, 0.600, 0.196), roughness=0.8)

    bm = bmesh.new()
    kb.revolve(bm, profile, segments, material_at=0)

    top_z = profile[-1][1]
    kb.revolve(bm, [
        (0.000, top_z - 0.02),
        (0.035, top_z + 0.01),
        (0.030, top_z + stem_height * 0.7),
        (0.026, top_z + stem_height),
        (0.000, top_z + stem_height + 0.015),
    ], 6, material_at=1)

    base = Vector((0.02, 0.0, top_z + stem_height * 0.80))
    blade = [bm.verts.new(base + Vector(point)) for point in
             ((0.02, 0.0, 0.0), (0.13, 0.055, 0.045), (0.25, 0.0, 0.030), (0.13, -0.055, 0.045))]
    bm.verts.ensure_lookup_table()
    bm.faces.new(blade).material_index = 2

    obj = kb.mesh_from_bmesh(name, bm, [body, stem, leaf_material])
    if squash != 1.0:
        obj.scale.z = squash
        apply_scale(obj)
    return finalise(obj, name, 62.0)


def build_apel():
    return _fruit("apel", (0.855, 0.145, 0.145), [
        (0.000, 0.075), (0.280, 0.015), (0.440, 0.105), (0.500, 0.265),
        (0.505, 0.455), (0.470, 0.625), (0.390, 0.760), (0.250, 0.855),
        (0.000, 0.805),
    ], 14, stem_height=0.16)


def build_jeruk():
    return _fruit("jeruk", (0.965, 0.494, 0.055), [
        (0.000, 0.070), (0.300, 0.010), (0.470, 0.115), (0.525, 0.290),
        (0.530, 0.470), (0.470, 0.640), (0.280, 0.755), (0.000, 0.710),
    ], 14, stem_height=0.075, squash=0.92)


def build_telur():
    """An ovoid. One lathed silhouette and one material - an egg has no features,
    so anything else would be decoration."""
    shell = kb.make_material("telur_shell", (0.976, 0.898, 0.741), roughness=0.55)
    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.000), (0.155, 0.045), (0.290, 0.155), (0.365, 0.335),
        (0.380, 0.535), (0.350, 0.735), (0.250, 0.900), (0.000, 1.000),
    ], 14, material_at=0)
    return finalise(kb.mesh_from_bmesh("telur", bm, [shell]), "telur", 62.0)


def build_roti():
    """A loaf: a rounded-rectangle section swept along a straight spine, domed by
    the taper, with three scored ridges on top."""
    crust = kb.make_material("roti_crust", (0.812, 0.510, 0.165), roughness=0.85)
    score = kb.make_material("roti_score", (0.949, 0.769, 0.427), roughness=0.85)

    LENGTH, SAMPLES, RADIAL = 1.0, 11, 14

    def section(t, theta):
        taper = (1.0 - abs(2.0 * t - 1.0) ** 2.6) ** 0.30
        across, through = kb.superellipse(theta, 0.30 * taper, 0.26 * taper, squareness=3.0)
        # Flat-bottomed: a loaf sits on a shelf, it does not roll.
        if through < 0.0:
            through *= 0.62
        return across, through

    bm = bmesh.new()
    kb.sweep(bm, kb.straight_spine(LENGTH, SAMPLES), section, RADIAL, material_index=0)

    # Three shallow scores across the top, the mark that says "bread" rather
    # than "brown box".
    for offset in (-0.24, 0.0, 0.24):
        rounded_box(bm, (0.050, 0.30, 0.045), 0.016, material_index=1, segments=1,
                    offset=Vector((offset, 0.0, 0.205)))

    return finalise(kb.mesh_from_bmesh("roti", bm, [crust, score]), "roti", 45.0)


def build_susu():
    """A gable-top carton. Every edge is over the auto-smooth angle, so the
    corners stay crisp while everything else in the shop stays round."""
    blue = kb.make_material("susu_blue", (0.098, 0.404, 0.812), roughness=0.8)
    white = kb.make_material("susu_white", (0.949, 0.953, 0.941), roughness=0.8)

    HALF, RIDGE = 0.26, 1.0
    bands = [(0.00, 0), (0.20, 1), (0.44, 0), (0.62, 0)]

    bm = bmesh.new()
    rings = []
    for z, _material in bands:
        rings.append([bm.verts.new((x * HALF, y * HALF, z))
                      for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    bm.verts.ensure_lookup_table()

    for i in range(len(rings) - 1):
        for step in range(4):
            nxt = (step + 1) % 4
            face = bm.faces.new((rings[i][step], rings[i][nxt],
                                 rings[i + 1][nxt], rings[i + 1][step]))
            face.material_index = bands[i][1]

    bm.faces.new(rings[0]).material_index = 0

    top = rings[-1]
    ridge_a = bm.verts.new((-HALF, 0.0, RIDGE))
    ridge_b = bm.verts.new((HALF, 0.0, RIDGE))
    bm.faces.new((top[0], top[1], ridge_b, ridge_a)).material_index = 1
    bm.faces.new((top[2], top[3], ridge_a, ridge_b)).material_index = 1
    bm.faces.new((top[1], top[2], ridge_b)).material_index = 1
    bm.faces.new((top[3], top[0], ridge_a)).material_index = 1

    return finalise(kb.mesh_from_bmesh("susu", bm, [blue, white]), "susu", 30.0)


def build_permen():
    """A wrapped sweet: fat middle, pinched twists at both ends. The pinch is the
    whole silhouette - without it this is a red ball."""
    wrapper = kb.make_material("permen_wrapper", (0.898, 0.145, 0.180), roughness=0.45)
    twist = kb.make_material("permen_twist", (0.729, 0.098, 0.137), roughness=0.5)

    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.000), (0.105, 0.045), (0.130, 0.135), (0.085, 0.235),
        (0.330, 0.350), (0.420, 0.495), (0.420, 0.640), (0.330, 0.785),
        (0.085, 0.900), (0.130, 1.000), (0.105, 1.090), (0.000, 1.135),
    ], 12, material_at=lambda band: 0 if 3 <= band <= 6 else 1)
    return finalise(kb.mesh_from_bmesh("permen", bm, [wrapper, twist]), "permen", 48.0)


def build_biskuit():
    """Three scalloped discs, each turned against the one below so the stack
    reads as separate biscuits rather than one striped cylinder."""
    biscuit = kb.make_material("biskuit_body", (0.929, 0.729, 0.325), roughness=0.9)

    SEGMENTS, THICKNESS = 18, 0.16
    bm = bmesh.new()
    for index in range(3):
        base = index * (THICKNESS + 0.012)
        phase = index * (math.tau / SEGMENTS) * 0.5
        offset_x = (index - 1) * 0.024

        def section(theta, phase=phase):
            return 1.0 + 0.055 * math.cos(SEGMENTS * (theta + phase))

        first = len(bm.verts)
        kb.revolve(bm, [
            (0.000, base),
            (0.420, base + 0.020),
            (0.450, base + THICKNESS * 0.5),
            (0.420, base + THICKNESS - 0.020),
            (0.000, base + THICKNESS),
        ], SEGMENTS, material_at=0, section_at=section)
        bm.verts.ensure_lookup_table()
        for vert in bm.verts[first:]:
            vert.co.x += offset_x

    return finalise(kb.mesh_from_bmesh("biskuit", bm, [biscuit]), "biskuit", 40.0)


def _bottle(name, liquid_colour, cap_colour, profile, label_bands, segments=14):
    """Body, label band and cap from one lathed profile. The ribs are notches in
    that profile - six faces each, and the difference between a bottle and a
    tube."""
    liquid = kb.make_material("%s_body" % name, liquid_colour, roughness=0.35)
    cap = kb.make_material("%s_cap" % name, cap_colour, roughness=0.6)
    label = kb.make_material("%s_label" % name, (0.949, 0.953, 0.957), roughness=0.85)

    def material_for(band):
        if band in label_bands:
            return 2
        return 1 if band >= len(profile) - 5 else 0

    bm = bmesh.new()
    kb.revolve(bm, profile, segments, material_at=material_for)
    return finalise(kb.mesh_from_bmesh(name, bm, [liquid, cap, label]), name, 40.0)


def build_air_mineral():
    return _bottle("air_mineral", (0.443, 0.769, 0.937), (0.098, 0.404, 0.812), [
        (0.000, 0.000), (0.200, 0.010), (0.225, 0.045),
        (0.225, 0.170), (0.192, 0.215), (0.225, 0.260),
        (0.225, 0.380), (0.225, 0.520),
        (0.192, 0.565), (0.225, 0.610),
        (0.225, 0.700), (0.185, 0.790), (0.105, 0.860),
        (0.100, 0.905), (0.120, 0.920), (0.120, 1.000), (0.000, 1.005),
    ], label_bands={6})


def build_minyak():
    return _bottle("minyak", (0.965, 0.729, 0.055), (0.980, 0.855, 0.180), [
        (0.000, 0.000), (0.175, 0.010), (0.200, 0.045),
        (0.200, 0.190), (0.170, 0.235), (0.200, 0.280),
        (0.200, 0.430), (0.200, 0.600),
        (0.170, 0.645), (0.200, 0.690),
        (0.200, 0.790), (0.160, 0.880), (0.092, 0.935),
        (0.088, 0.970), (0.108, 0.982), (0.108, 1.050), (0.000, 1.055),
    ], label_bands={6})


def build_sabun():
    """A bar of soap: a bevelled box, and nothing else. The bevel is the model."""
    soap = kb.make_material("sabun_body", (0.522, 0.812, 0.278), roughness=0.4)
    bm = bmesh.new()
    rounded_box(bm, (0.62, 0.42, 0.22), 0.075, material_index=0, segments=3)
    return finalise(kb.mesh_from_bmesh("sabun", bm, [soap]), "sabun", 50.0)


def _pouch(name, colour, half_length, half_across, half_height,
           squareness=3.4, pinch_power=2.2):
    """A sealed sachet: a flattened rounded-rectangle section swept end to end,
    pinched flat at both ends where the seal is.

    `squareness` is what separates a soft noodle packet from a blocky sugar bag.
    """
    body = kb.make_material("%s_body" % name, colour, roughness=0.45)

    SAMPLES, RADIAL = 13, 12

    def section(t, theta):
        pinch = (1.0 - abs(2.0 * t - 1.0) ** pinch_power) ** 0.42
        flat = 0.18 + 0.82 * pinch
        return kb.superellipse(theta, half_across * flat, half_height * pinch, squareness=squareness)

    bm = bmesh.new()
    kb.sweep(bm, kb.straight_spine(half_length * 2.0, SAMPLES), section, RADIAL, material_index=0)
    return finalise(kb.mesh_from_bmesh(name, bm, [body]), name, 42.0)


def build_mie_instan():
    return _pouch("mie_instan", (0.965, 0.396, 0.075), 0.50, 0.30, 0.15)


def build_gula():
    # Blockier and squarer than the noodle packet, so the two flat pouches on the
    # shelf are not the same silhouette in two colours (section 11).
    return _pouch("gula", (0.961, 0.929, 0.847), 0.40, 0.30, 0.25, squareness=4.6, pinch_power=3.2)


def build_beras():
    """A sack: bulging body pulled in to a tied neck, then gathered above it."""
    sack = kb.make_material("beras_sack", (0.820, 0.671, 0.435), roughness=0.95)
    tie = kb.make_material("beras_tie", (0.522, 0.388, 0.216), roughness=0.95)

    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.000), (0.290, 0.010), (0.350, 0.105),
        (0.395, 0.300), (0.395, 0.520), (0.345, 0.680),
        (0.235, 0.790), (0.140, 0.850), (0.135, 0.895),
        (0.215, 0.960), (0.150, 1.010), (0.000, 1.030),
    ], 14, material_at=lambda band: 1 if band in (7, 8) else 0)
    return finalise(kb.mesh_from_bmesh("beras", bm, [sack, tie]), "beras", 52.0)


def build_es_krim():
    """Cone plus scoop. The waffle is a scalloped cone rather than a texture -
    section 4.2 keeps texture memory for things that need it."""
    cone = kb.make_material("es_krim_cone", (0.847, 0.588, 0.235), roughness=0.9)
    scoop = kb.make_material("es_krim_scoop", (0.965, 0.353, 0.635), roughness=0.55)

    SEGMENTS = 14
    bm = bmesh.new()
    kb.revolve(bm, [
        (0.000, 0.000), (0.090, 0.130), (0.190, 0.310),
        (0.270, 0.480), (0.320, 0.570),
    ], SEGMENTS, material_at=0,
        section_at=lambda theta: 1.0 + 0.05 * math.cos(7.0 * theta))

    # The scoop has to outweigh the cone, or this reads as an empty wafer.
    kb.revolve(bm, [
        (0.000, 0.505), (0.250, 0.560), (0.380, 0.680),
        (0.420, 0.830), (0.375, 0.975), (0.225, 1.080), (0.000, 1.130),
    ], SEGMENTS, material_at=1)

    return finalise(kb.mesh_from_bmesh("es_krim", bm, [cone, scoop]), "es_krim", 55.0)


BUILDERS = {
    "air_mineral": build_air_mineral,
    "apel": build_apel,
    "beras": build_beras,
    "biskuit": build_biskuit,
    "es_krim": build_es_krim,
    "gula": build_gula,
    "jeruk": build_jeruk,
    "mie_instan": build_mie_instan,
    "minyak": build_minyak,
    "permen": build_permen,
    "pisang": build_pisang,
    "roti": build_roti,
    "sabun": build_sabun,
    "susu": build_susu,
    "telur": build_telur,
}


# ---------------------------------------------------------------- output

def report(obj, item_id):
    mesh = obj.data
    triangles = sum(len(polygon.vertices) - 2 for polygon in mesh.polygons)
    lowest = min((obj.matrix_world @ v.co).z for v in mesh.vertices)
    flag = "  <-- over budget" if triangles > 600 else ""
    print("  %-12s %4d tris  %.3f x %.3f x %.3f m  %d mat  base %+0.4f%s" % (
        item_id, triangles, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z,
        len(mesh.materials), lowest, flag))
    return triangles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--item", choices=sorted(BUILDERS))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--out-dir")
    parser.add_argument("--preview", default="")
    parser.add_argument("--icon-dir", default="",
                        help="also render each item to a transparent PNG here")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    item_ids = sorted(BUILDERS) if args.all else ([args.item] if args.item else [])
    if not item_ids:
        parser.error("pass --item <id> or --all")

    kb.reset_scene()
    built = []
    total = 0
    for item_id in item_ids:
        obj = BUILDERS[item_id]()
        total += report(obj, item_id)
        out_path = args.out if args.out else os.path.join(args.out_dir, "%s.glb" % item_id)
        kb.export_glb(obj, out_path)
        if args.icon_dir:
            os.makedirs(args.icon_dir, exist_ok=True)
            kb.render_icon(obj, os.path.join(args.icon_dir, "%s.png" % item_id))
        built.append(obj)

    print("  %d items, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=0.30, height=340, elevation=0.55)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
