"""Turns the supplied village diorama into something the game can stand in.

    & "D:/Program Files/Blender/blender.exe" --background --factory-startup `
      --python tools/blender/import_village.py -- `
      --source "C:/path/Meshy_AI_Sunny_Village_Market.glb" `
      --out assets/models/environment/village_market.glb

Unlike everything else in `tools/blender/`, this does not build a model - it
repairs one. The source is generated (Meshy), and generated `.glb` files are
wrong in the four predictable ways ASSETS.md lists. Three of them apply here and
each is fixed below; the fourth, geometry quality, cannot be fixed by a script
and is a decision the project owner took with the render in front of them.

What arrives:

- **One mesh in 3,844 disconnected fragments.** Not a village of buildings: a
  remeshed shell where the Warung's roof and the grass under it are the same
  surface. Nothing here tries to separate them. The hub does not need to - a
  child never enters a building from the village, they walk up, a prompt
  appears, and the router loads a different scene (PLAN.md 6.3, 7.1). Buildings
  need a position and a collider, which `data/minigames.json` and `Building`
  already provide.
- **A full PBR set**: 2048 base colour, 4096 metallic-roughness, 2048 normal.
  ART_STYLE.md allows none of that, and the two maps it forbids are four fifths
  of the file. Dropped.
- **An atlas with no UV padding.** 3,844 islands with bare black between them.
  Left alone that is invisible on a desktop at full resolution and ruinous on a
  phone: mipmapping and ETC2 both average across the gap, so every edge in the
  village grows a black fringe. Dilated below.
- **Diorama scale**: 1.9 units across and modelled to be looked at from above.
  Scaled so the village is 30m and its buildings land in the 5-7m ART_STYLE.md
  asks for, and dropped so the grass sits at y=0.

The base plate underneath is left alone. It is below the ground the child walks
on and the fence stops them long before the edge.
"""

import argparse
import math
import os
import sys

import bpy
import numpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import kanca_build as kb  # noqa: E402


## How wide the village should be, in metres. Thirty rather than the forty the
## procedural village used: the buildings are a fixed fraction of the tile, and
## at forty they came out nearer ten metres across than seven.
VILLAGE_SPAN = 30.0

## Degrees between face normals above which an edge stays sharp. See flat_shade.
SMOOTH_ANGLE = 30.0


def flat_shade(obj, angle_degrees):
    """Re-shades the mesh so its facets read.

    The source arrives smooth-shaded with custom split normals, which is the
    right choice for the high-poly sculpt it was remeshed from and the wrong one
    for ten thousand triangles standing in for a village. Averaged normals across
    a low-poly surface do not make it look smooth, they make it look melted -
    every roof plane, every tree facet and every fence post blends into its
    neighbour and the whole village goes soft. It is the same finding ASSETS.md
    records about the foliage, where the vertex gradient was correct in the file
    and invisible on screen because the normals were averaging the facets away.

    The custom normals have to go first. They override whatever shading is set
    afterwards, so clearing them is the whole operation and shade_auto_smooth is
    just what fills the gap.

    Not fully flat. The ground is a remeshed plane with a centimetre of noise in
    it, and at one degree every triangle of the lawn draws its own shade of green.
    Thirty keeps the lawn a lawn and still breaks the roofs, the trunks and the
    canopies into planes.
    """
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except RuntimeError:
        pass
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle_degrees))
    except (AttributeError, RuntimeError):
        pass


def ground_level(obj, bin_size=0.02):
    """Where the grass is: the commonest height in the middle of the tile.

    Not the lowest point, which is the underside of the base plate. Not the
    median either - that was the first attempt and it landed a quarter of a metre
    under the grass, because the middle of a village contains a base plate below
    it and market stalls above it and the median sits between them. The grass is
    the one surface with most of the vertices on it, so the mode is what
    describes it.
    """
    world = numpy.array([(obj.matrix_world @ v.co)[:] for v in obj.data.vertices])
    reach = numpy.abs(world[:, :2]).max() * 0.45
    middle = world[(numpy.abs(world[:, 0]) < reach) & (numpy.abs(world[:, 1]) < reach)]
    if not len(middle):
        return float(world[:, 2].min())
    heights = middle[:, 2]
    bins = numpy.round(heights / bin_size).astype(numpy.int64)
    values, counts = numpy.unique(bins, return_counts=True)
    return float(values[counts.argmax()] * bin_size)


def report_buildings(obj, scale):
    """Prints where the tall things inside the fence ended up.

    Not a check - a convenience. `data/minigames.json` carries a hub_position
    per building and those have to agree with wherever this model happens to put
    them, so the numbers are printed in Godot's axes ready to paste.
    """
    world = numpy.array([(obj.matrix_world @ v.co)[:] for v in obj.data.vertices])
    reach = numpy.abs(world[:, :2]).max()
    inner = world[(numpy.abs(world[:, 0]) < reach * 0.78)
                  & (numpy.abs(world[:, 1]) < reach * 0.78)]
    tall = inner[inner[:, 2] > numpy.percentile(inner[:, 2], 97)]
    print("  tall geometry inside the fence: %d vertices above %.2fm"
          % (len(tall), float(numpy.percentile(inner[:, 2], 97))))
    print("  (Godot x, z) = (blender_x, -blender_y); village spans %.1fm" % (
        reach * 2.0))
    del scale


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--span", type=float, default=VILLAGE_SPAN)
    parser.add_argument("--smooth-angle", type=float, default=SMOOTH_ANGLE)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(args.source))

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("expected one mesh, got %d" % len(meshes))
    obj = meshes[0]
    obj.name = "village_market"

    triangles = sum(max(len(p.vertices) - 2, 0) for p in obj.data.polygons)
    print("  source  %d tris, %.2f x %.2f x %.2f units" % (
        triangles, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z))

    kept = []
    for material in obj.data.materials:
        atlas = kb.strip_pbr(material)
        if atlas is None:
            continue
        kept.append(atlas)
        before, after = kb.dilate(atlas)
        print("  atlas   %dx%d, gutter %d px -> %d px" % (
            atlas.size[0], atlas.size[1], before, after))

    # The maps are unreachable from the BSDF now, so the exporter would not write
    # them - but an unreferenced 4096-square image left in the file is one
    # careless change away from being written again. Unlinking the datablock is
    # safe where deleting the node was not.
    for image in list(bpy.data.images):
        if image not in kept and image.name != "Render Result":
            print("  dropped %s (%dx%d)" % (image.name, image.size[0], image.size[1]))
            bpy.data.images.remove(image)

    factor = args.span / max(obj.dimensions.x, obj.dimensions.y)
    obj.scale = (factor, factor, factor)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    flat_shade(obj, args.smooth_angle)
    print("  shading re-set, custom normals cleared, sharp above %.0f deg"
          % args.smooth_angle)

    grass = ground_level(obj)
    for vertex in obj.data.vertices:
        vertex.co.z -= grass
    bpy.context.view_layer.update()
    print("  scaled  x%.2f -> %.1f x %.1f x %.1f m, grass dropped %.2fm" % (
        factor, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z, grass))

    report_buildings(obj, factor)

    kb.export_glb(obj, os.path.abspath(args.out))
    size = os.path.getsize(os.path.abspath(args.out)) / 1024.0 / 1024.0
    print("  wrote   %s (%.1f MB)" % (args.out, size))


if __name__ == "__main__":
    main()
