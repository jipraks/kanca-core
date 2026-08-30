"""Builds the three village buildings in Blender. Developer tool.

    blender --background --factory-startup --python tools/blender/build_buildings.py -- \
        --all --out-dir assets/models/environment --icon-dir assets/ui/buildings \
        --preview /tmp/buildings.png

PLAN.md 7.1 asks for three buildings that are "visually distinct and instantly
readable". At the hub camera a child sees them from across the village, so the
thing that has to differ is the **silhouette**, not the colour:

    Warung   gable roof, two slopes, open counter facing the visitor
    Dapur    hip roof, four slopes, open-sided pavilion on a stone platform
    Kebun    no roof at all - a fenced plot with an entrance arch

Footprints come from data/minigames.json and are not negotiable: the collider and
the approach trigger are both built from those numbers, so a model that overhangs
them is a building a child can walk through.

Orientation is the fiddly part. A model's forward is -Z in Godot, and Blender's
+Y becomes Godot's -Z on export, so a building's front is authored facing
Blender +Y. The hub then turns each one towards the village with
hub_rotation_degrees.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kanca_build as kb  # noqa: E402

# Godot's building_size is (width, height, depth); Blender wants (width, depth,
# height). Kept here rather than read from JSON so the generator has no runtime
# dependency on the game's data files.
FOOTPRINTS = {
    "warung": (6.0, 5.0, 3.2),
    "dapur": (6.0, 5.5, 3.0),
    "kebun": (7.0, 6.0, 2.6),
}


# ---------------------------------------------------------------- geometry

def add_slab(bm, points, drop, material_index):
    """A flat polygon given real thickness by dropping a copy straight down.

    Dropping vertically rather than perpendicular is deliberate: it leaves a
    vertical face at the eave, which is exactly the fascia a real roof has, and
    it is that edge - not the slope - that makes a roof read as a roof instead of
    a sheet of card.
    """
    top = [bm.verts.new(point) for point in points]
    bottom = [bm.verts.new(Vector(point) - Vector((0.0, 0.0, drop))) for point in points]
    bm.verts.ensure_lookup_table()

    bm.faces.new(top).material_index = material_index
    bm.faces.new(list(reversed(bottom))).material_index = material_index
    for i in range(len(points)):
        j = (i + 1) % len(points)
        bm.faces.new((top[i], top[j], bottom[j], bottom[i])).material_index = material_index


def add_gable_roof(bm, width, depth, base_z, rise, thickness, material_index,
                   ribs=0, rib_depth=0.0, offset=(0.0, 0.0)):
    """Two slopes meeting at a ridge.

    `ribs` splits each slope into alternating raised strips - corrugated iron for
    the price of a few quads, and far more legible at village distance than a
    flat green plane.
    """
    hw, hd = width * 0.5, depth * 0.5
    ridge_z = base_z + rise
    count = max(ribs, 1)

    for sign in (1.0, -1.0):
        for i in range(count):
            x0 = -hw + width * i / count
            x1 = -hw + width * (i + 1) / count
            lift = rib_depth if (ribs > 1 and i % 2 == 0) else 0.0
            ox, oy = offset
            add_slab(bm, [
                (ox + x0, oy + sign * hd, base_z + lift), (ox + x1, oy + sign * hd, base_z + lift),
                (ox + x1, oy, ridge_z + lift), (ox + x0, oy, ridge_z + lift),
            ], thickness + lift, material_index)


def add_hip_roof(bm, width, depth, base_z, rise, thickness, material_index,
                 ridge_ratio=0.25, rows=0, row_step=0.0, offset=(0.0, 0.0)):
    """Four slopes: two trapezoids and two triangular hips.

    `rows` bands each long slope and steps each band, which reads as overlapping
    roof tiles.
    """
    hw, hd = width * 0.5, depth * 0.5
    rw = hw * ridge_ratio
    ridge_z = base_z + rise

    def edge_at(t, sign):
        """Half-width, depth and height at `t` along the slope, 0 at the eave."""
        return (hw + (rw - hw) * t, sign * hd * (1.0 - t), base_z + rise * t)

    count = max(rows, 1)
    for sign in (1.0, -1.0):
        for i in range(count):
            t0, t1 = i / count, (i + 1) / count
            half0, y0, z0 = edge_at(t0, sign)
            half1, y1, z1 = edge_at(t1, sign)
            lift = row_step * (count - 1 - i) if rows > 1 else 0.0
            ox, oy = offset
            add_slab(bm, [
                (ox - half0, oy + y0, z0 + lift), (ox + half0, oy + y0, z0 + lift),
                (ox + half1, oy + y1, z1 + lift), (ox - half1, oy + y1, z1 + lift),
            ], thickness + lift, material_index)

    for sign in (1.0, -1.0):
        add_slab(bm, [
            (offset[0] + sign * hw, offset[1] - hd, base_z),
            (offset[0] + sign * hw, offset[1] + hd, base_z),
            (offset[0] + sign * rw, offset[1], ridge_z),
        ], thickness, material_index)


def add_ridge_beam(bm, width, base_z, rise, thickness, size, material_index):
    """The capping beam along a ridge. Small, and the thing your eye lands on."""
    kb.add_box(bm, (width, size, size), (0.0, 0.0, base_z + rise + thickness * 0.35),
            material_index, bevel=size * 0.22)


def add_railing(bm, x_from, x_to, y, base_z, height, material_index, posts=5):
    """Posts with a top rail. Turns an open edge into somewhere you stand."""
    for i in range(posts):
        x = x_from + (x_to - x_from) * i / float(max(posts - 1, 1))
        kb.add_box(bm, (0.09, 0.09, height), (x, y, base_z + height * 0.5), material_index)
    kb.add_box(bm, (abs(x_to - x_from) + 0.09, 0.10, 0.09),
            ((x_from + x_to) * 0.5, y, base_z + height), material_index)


def add_steps(bm, width, y, base_z, count, rise, run, material_index):
    """A short flight down from a platform. Without it a raised building looks
    like it is hovering."""
    for i in range(count):
        kb.add_box(bm, (width, run, rise),
                (0.0, y + run * (i + 0.5), base_z - rise * (i + 0.5)), material_index)


def add_posts(bm, positions, size, base_z, height, material_index):
    for x, y in positions:
        kb.add_box(bm, (size, size, height), (x, y, base_z + height * 0.5), material_index)


def add_fence_run(bm, start, end, post_spacing, post_size, height, material_index):
    """Posts at intervals with two rails between them. A real boundary, which is
    what lets the Kebun keep a solid collider without it reading as an invisible
    wall (PLAN.md 7.1)."""
    start_vector, end_vector = Vector(start), Vector(end)
    run = end_vector - start_vector
    length = run.length
    if length < 1e-6:
        return
    count = max(int(length / post_spacing), 1)

    for i in range(count + 1):
        point = start_vector + run * (i / float(count))
        kb.add_box(bm, (post_size, post_size, height), (point.x, point.y, height * 0.5), material_index)

    direction = run.normalized()
    thickness = post_size * 0.7
    across = (abs(direction.x) * thickness + abs(direction.y) * length,
              abs(direction.y) * thickness + abs(direction.x) * length)
    centre = (start_vector + end_vector) * 0.5
    for rail_z in (height * 0.38, height * 0.78):
        kb.add_box(bm, (across[1] if abs(direction.x) > 0.5 else thickness,
                     across[1] if abs(direction.y) > 0.5 else thickness,
                     post_size * 0.6),
                (centre.x, centre.y, rail_z), material_index)


# ---------------------------------------------------------------- buildings

def build_warung():
    """An open-fronted stall you can see into.

    The counter and the stocked shelves behind it are the whole point: it is the
    only building in the village whose inside is visible, and that is what says
    "shop" from across the field. The roof is corrugated iron, ribbed rather than
    flat, because a plain green plane reads as a lid.
    """
    WIDTH, DEPTH, HEIGHT = FOOTPRINTS["warung"]

    dark = kb.make_material("warung_frame", (0.361, 0.227, 0.114), roughness=0.9)
    light = kb.make_material("warung_wall", (0.788, 0.596, 0.353), roughness=0.9)
    counter = kb.make_material("warung_counter", (0.898, 0.702, 0.412), roughness=0.85)
    roof = kb.make_material("warung_roof", (0.208, 0.463, 0.259), roughness=0.7)
    sign = kb.make_material("warung_sign", (0.949, 0.635, 0.086), roughness=0.7)
    goods = kb.make_material("warung_goods", (0.867, 0.278, 0.239), roughness=0.75)

    bm = bmesh.new()

    kb.add_box(bm, (WIDTH, DEPTH, 0.34), (0.0, 0.0, 0.17), 0, bevel=0.04)
    add_steps(bm, WIDTH * 0.42, DEPTH * 0.5, 0.34, 2, 0.15, 0.34, 0)

    # Back wall in two plank tones, so the timber reads as boards rather than a
    # painted slab.
    for index, z in enumerate((0.62, 1.18, 1.74)):
        kb.add_box(bm, (WIDTH - 0.28, 0.20, 0.52), (0.0, -DEPTH * 0.5 + 0.16, z),
                1 if index % 2 == 0 else 0)
    for side in (-1.0, 1.0):
        kb.add_box(bm, (0.20, DEPTH - 0.36, 1.90), (side * (WIDTH * 0.5 - 0.14), -0.1, 1.24), 1)

    # Two stocked shelves. Small coloured blocks, but at village distance that is
    # exactly what a shelf of goods looks like.
    for level, shelf_z in enumerate((1.36, 1.92)):
        kb.add_box(bm, (WIDTH - 1.0, 0.42, 0.09), (0.0, -DEPTH * 0.5 + 0.44, shelf_z), 0)
        for slot in range(5):
            x = (slot - 2) * (WIDTH - 1.6) / 4.0
            kb.add_box(bm, (0.26, 0.24, 0.30), (x, -DEPTH * 0.5 + 0.44, shelf_z + 0.19),
                    5 if (slot + level) % 2 == 0 else 2, bevel=0.03)

    kb.add_box(bm, (WIDTH - 0.7, 0.72, 1.02), (0.0, DEPTH * 0.5 - 0.75, 0.85), 2, bevel=0.03)
    kb.add_box(bm, (WIDTH - 0.3, 0.96, 0.14), (0.0, DEPTH * 0.5 - 0.75, 1.43), 0, bevel=0.05)

    add_posts(bm, [(-WIDTH * 0.5 + 0.18, -DEPTH * 0.5 + 0.18),
                   (WIDTH * 0.5 - 0.18, -DEPTH * 0.5 + 0.18),
                   (-WIDTH * 0.5 + 0.18, DEPTH * 0.5 - 0.18),
                   (WIDTH * 0.5 - 0.18, DEPTH * 0.5 - 0.18)],
              0.24, 0.34, 2.06, 0)

    # Steeper than a temperate roof, which is what a tropical one is.
    eave_z = 2.40
    rise = HEIGHT - eave_z + 0.55
    add_gable_roof(bm, WIDTH + 1.1, DEPTH + 1.2, eave_z, rise, 0.14, 3, ribs=11, rib_depth=0.05)
    add_ridge_beam(bm, WIDTH + 1.2, eave_z, rise, 0.14, 0.17, 0)

    # Goods hanging under the eave, the detail that makes a warung a warung.
    for hang_x in (-WIDTH * 0.30, WIDTH * 0.30):
        kb.add_box(bm, (0.06, 0.06, 0.34), (hang_x, DEPTH * 0.5 - 0.05, eave_z - 0.17), 0)
        kb.add_box(bm, (0.30, 0.22, 0.34), (hang_x, DEPTH * 0.5 - 0.05, eave_z - 0.50), 4, bevel=0.09)

    kb.add_box(bm, (WIDTH * 0.46, 0.14, 0.56), (0.0, DEPTH * 0.5 + 0.34, eave_z + 0.30), 4, bevel=0.06)

    obj = kb.mesh_from_bmesh("warung", bm, [dark, light, counter, roof, sign, goods])
    return _finalise(obj, "warung")


def build_dapur():
    """An open-sided pavilion on a stone platform.

    Four tiled roof slopes against the Warung's two, so the two never read as the
    same shape in a different colour. The stove is lit and there are pots hanging
    from the beam: a kitchen nobody is cooking in is a shed.
    """
    WIDTH, DEPTH, HEIGHT = FOOTPRINTS["dapur"]

    stone = kb.make_material("dapur_stone", (0.596, 0.588, 0.545), roughness=0.95)
    stone_dark = kb.make_material("dapur_hearth", (0.396, 0.388, 0.373), roughness=0.95)
    wood = kb.make_material("dapur_wood", (0.435, 0.286, 0.153), roughness=0.9)
    roof = kb.make_material("dapur_roof", (0.769, 0.322, 0.161), roughness=0.85)
    fire = kb.make_material("dapur_fire", (0.980, 0.514, 0.086), roughness=0.35)
    pot = kb.make_material("dapur_pot", (0.318, 0.353, 0.376), roughness=0.6)

    bm = bmesh.new()

    kb.add_box(bm, (WIDTH, DEPTH, 0.42), (0.0, 0.0, 0.21), 0, bevel=0.05)
    add_steps(bm, WIDTH * 0.40, DEPTH * 0.5, 0.42, 2, 0.19, 0.36, 0)

    kb.add_box(bm, (WIDTH - 0.2, 0.24, 1.05), (0.0, -DEPTH * 0.5 + 0.16, 0.95), 0, bevel=0.04)
    kb.add_box(bm, (0.24, DEPTH - 0.5, 0.92), (-WIDTH * 0.5 + 0.16, -0.15, 0.88), 0, bevel=0.04)

    add_posts(bm, [(-WIDTH * 0.5 + 0.26, -DEPTH * 0.5 + 0.26),
                   (WIDTH * 0.5 - 0.26, -DEPTH * 0.5 + 0.26),
                   (-WIDTH * 0.5 + 0.26, DEPTH * 0.5 - 0.26),
                   (WIDTH * 0.5 - 0.26, DEPTH * 0.5 - 0.26)],
              0.26, 0.42, 1.98, 2)

    # Stove: block, firebox, pot, and a chimney hood over it.
    kb.add_box(bm, (2.10, 1.15, 0.98), (-1.55, -1.50, 0.91), 1, bevel=0.06)
    kb.add_box(bm, (0.92, 0.20, 0.46), (-1.55, -0.94, 0.76), 4)
    kb.add_box(bm, (0.74, 0.74, 0.42), (-1.55, -1.50, 1.61), 5, bevel=0.15, bevel_segments=2)
    kb.add_box(bm, (0.28, 0.28, 0.30), (-1.55, -1.50, 1.92), 5, bevel=0.08)
    kb.add_box(bm, (1.30, 0.90, 0.34), (-1.55, -1.55, 2.12), 1, bevel=0.06)

    kb.add_box(bm, (2.20, 1.00, 0.13), (1.45, -0.40, 1.28), 2, bevel=0.03)
    for leg_x, leg_y in ((0.50, -0.80), (2.40, -0.80), (0.50, 0.00), (2.40, 0.00)):
        kb.add_box(bm, (0.13, 0.13, 0.80), (leg_x, leg_y, 0.82), 2)
    for bowl in range(2):
        kb.add_box(bm, (0.34, 0.34, 0.20), (1.05 + bowl * 0.80, -0.40, 1.45), 5, bevel=0.08)

    # A beam across the front with pots hanging off it.
    beam_z = 2.02
    kb.add_box(bm, (WIDTH - 0.7, 0.14, 0.14), (0.0, DEPTH * 0.5 - 0.5, beam_z), 2)
    for hook in (-1.3, -0.2, 0.9):
        kb.add_box(bm, (0.05, 0.05, 0.22), (hook, DEPTH * 0.5 - 0.5, beam_z - 0.16), 2)
        kb.add_box(bm, (0.30, 0.30, 0.24), (hook, DEPTH * 0.5 - 0.5, beam_z - 0.38), 5, bevel=0.09)

    eave_z = 2.34
    rise = HEIGHT - eave_z + 0.62
    add_hip_roof(bm, WIDTH + 1.2, DEPTH + 1.2, eave_z, rise, 0.13, 3,
                 ridge_ratio=0.24, rows=5, row_step=0.045)

    obj = kb.mesh_from_bmesh("dapur", bm, [stone, stone_dark, wood, roof, fire, pot])
    return _finalise(obj, "dapur")


def build_kebun():
    """Not a building: a fenced plot with raised beds and a roofed entrance arch.

    The fence is load-bearing, not decoration. The hub gives every building a
    solid box collider, and PLAN.md 7.1 forbids invisible walls - so the boundary
    has to be something a child can see themselves bumping into.
    """
    WIDTH, DEPTH, HEIGHT = FOOTPRINTS["kebun"]

    wood = kb.make_material("kebun_wood", (0.663, 0.478, 0.259), roughness=0.9)
    wood_dark = kb.make_material("kebun_post", (0.478, 0.325, 0.169), roughness=0.92)
    soil = kb.make_material("kebun_soil", (0.310, 0.196, 0.114), roughness=0.98)
    grass = kb.make_material("kebun_grass", (0.400, 0.639, 0.259), roughness=0.95)
    plant = kb.make_material("kebun_plant", (0.239, 0.545, 0.212), roughness=0.9)
    roof = kb.make_material("kebun_roof", (0.769, 0.322, 0.161), roughness=0.85)

    bm = bmesh.new()

    kb.add_box(bm, (WIDTH, DEPTH, 0.14), (0.0, 0.0, 0.07), 3)

    for bed_x in (-1.65, 1.65):
        for bed_y in (-1.35, 0.75):
            kb.add_box(bm, (2.70, 1.70, 0.36), (bed_x, bed_y, 0.29), 0, bevel=0.04)
            kb.add_box(bm, (2.42, 1.42, 0.14), (bed_x, bed_y, 0.46), 2)
            # Two rows of three at mixed heights: a bed of identical stubs reads
            # as a pattern rather than as plants.
            for row_index, row in enumerate((-0.85, 0.0, 0.85)):
                for offset in (-0.32, 0.32):
                    tall = 0.30 + 0.16 * ((row_index + int(offset > 0.0)) % 2)
                    kb.add_box(bm, (0.17, 0.17, tall),
                            (bed_x + row, bed_y + offset, 0.53 + tall * 0.5), 4, bevel=0.05)

    half_w, half_d = WIDTH * 0.5 - 0.12, DEPTH * 0.5 - 0.12
    add_fence_run(bm, (-half_w, -half_d), (half_w, -half_d), 1.25, 0.15, 0.95, 1)
    add_fence_run(bm, (-half_w, -half_d), (-half_w, half_d), 1.25, 0.15, 0.95, 1)
    add_fence_run(bm, (half_w, -half_d), (half_w, half_d), 1.25, 0.15, 0.95, 1)
    add_fence_run(bm, (-half_w, half_d), (-1.45, half_d), 1.20, 0.15, 0.95, 1)
    add_fence_run(bm, (1.45, half_d), (half_w, half_d), 1.20, 0.15, 0.95, 1)

    # A roofed gate. Without it this is a field; with it, somewhere you go in.
    for arch_x in (-1.20, 1.20):
        kb.add_box(bm, (0.24, 0.24, 2.05), (arch_x, half_d, 1.03), 1)
    kb.add_box(bm, (2.95, 0.28, 0.24), (0.0, half_d, 2.14), 1, bevel=0.04)
    add_gable_roof(bm, 3.30, 1.30, 2.26, 0.46, 0.10, 5, offset=(0.0, half_d))

    # A water barrel by the gate, and a spare stake leaning on the fence.
    kb.add_box(bm, (0.62, 0.62, 0.72), (2.35, half_d - 0.75, 0.50), 1, bevel=0.16, bevel_segments=2)
    kb.add_box(bm, (0.10, 0.10, 1.55), (-2.55, half_d - 0.30, 0.72), 1,
            rotation=(math.radians(14.0),))

    obj = kb.mesh_from_bmesh("kebun", bm, [wood, wood_dark, soil, grass, plant, roof])
    return _finalise(obj, "kebun")


def _finalise(obj, building_id):
    # Deliberately not scaled to fit. Every builder already works in real metres,
    # and the only thing exceeding the footprint is the roof overhang - which is
    # what a roof does. Shrinking the whole building to tuck the eaves inside the
    # collider made all three noticeably shorter than their declared height.
    kb.select_only(obj)
    kb.place_origin_at_base(obj)
    # Low angle: roof slopes and posts are meant to stay crisp. Only the bevels
    # should round off.
    kb.shade(obj, 28.0)
    kb.bake_vertex_colours(obj, base=0.74, facet_jitter=0.045, seed=31)
    return obj


BUILDERS = {
    "kebun": build_kebun,
    "warung": build_warung,
    "dapur": build_dapur,
}


# ---------------------------------------------------------------- output

def report(obj, building_id):
    triangles = kb.triangle_count(obj)
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    flag = "  <-- over budget" if triangles > 4000 else ""
    print("  %-8s %5d tris  %.2f x %.2f x %.2f m  %d mat  base %+0.4f%s" % (
        building_id, triangles, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z,
        len(obj.data.materials), lowest, flag))
    return triangles


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--building", choices=sorted(BUILDERS))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--out")
    parser.add_argument("--out-dir")
    parser.add_argument("--icon-dir", default="")
    parser.add_argument("--preview", default="")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    ids = ["kebun", "warung", "dapur"] if args.all else ([args.building] if args.building else [])
    if not ids:
        parser.error("pass --building <id> or --all")

    kb.reset_scene()
    built = []
    total = 0
    for building_id in ids:
        obj = BUILDERS[building_id]()
        total += report(obj, building_id)
        out_path = args.out if args.out else os.path.join(args.out_dir, "%s.glb" % building_id)
        kb.export_glb(obj, out_path)
        if args.icon_dir:
            os.makedirs(args.icon_dir, exist_ok=True)
            kb.render_icon(obj, os.path.join(args.icon_dir, "%s.png" % building_id),
                           size=384, elevation=1.1, distance=1.7, fit_aspect=True)
        built.append(obj)

    print("  %d buildings, %d triangles total" % (len(built), total))

    if args.preview:
        kb.render_contact_sheet(built, args.preview, span=8.0, height=420, elevation=0.42)
        print("  preview %s" % args.preview)


if __name__ == "__main__":
    main()
