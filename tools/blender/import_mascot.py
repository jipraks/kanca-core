"""Turns the supplied three-pose mascot sheet into three usable models.

    & "D:/Program Files/Blender/blender.exe" --background --factory-startup `
      --python tools/blender/import_mascot.py -- `
      --source "C:/path/Meshy_AI_Cheerful_Little_Deer.glb" `
      --out-dir assets/models/characters

Like `import_village.py`, this repairs a model rather than building one, and the
same four predictable faults apply — see ASSETS.md. What is different here is
that the file is not one character. It is the reference sheet, modelled: three
poses standing side by side in a single mesh, 83,050 triangles between them.

- **Three poses in one mesh.** Split on the empty columns between them rather
  than on a hardcoded coordinate, so a re-generated sheet with different spacing
  still splits. Loose parts are no use — the remesh has 251 disconnected islands
  and none of them is a character.
- **83,050 triangles**, against the 3,000 ART_STYLE.md budgets for a mascot who
  is on every screen. Decimated; the collapse decimator works here where it
  failed on the supplied trees, because a body is one continuous surface and
  foliage was thousands of leaf islands.
- **Full PBR set** and **an atlas with no padding**, both handled by the shared
  helpers in `kanca_build`.
- **Facing the wrong way.** He is modelled looking down -Y. Every character in
  this project is authored looking down +Y, because glTF export maps that to
  Godot's -Z, which is what Godot calls forward.

**He does not walk.** `WalkCycle` swings legs that are separate objects with
their pivots at the hip, and there is no way to cut a leg out of a continuous
remeshed shell without leaving a hole at the hip and a gap that opens every time
it swings. What the sheet gives instead is worth more than a walk: three of the
five poses §11.1 asks for — idle, point and celebrate — as three models the
companion swaps between.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import kanca_build as kb  # noqa: E402


## Left to right on the sheet. The order is the order the poses are drawn in and
## the only thing tying a slice of geometry to a name.
POSES = ["idle", "point", "celebrate"]

## Kanca's height in metres. ART_STYLE.md says 0.85; this one is chunkier and
## squarer than the model that number was written for, so he reads bigger at the
## same height. Beside a 1.15m child he wants to be clearly smaller and clearly
## not a toddler.
HEIGHT = 0.80

## Triangles per pose after decimation.
##
## ART_STYLE.md budgets 3,000 for the mascot, written when the village cost
## 64,000 of the 80,000 §4.2 allows. The village is a model now and the whole
## hub measures 56,000, so there is room — and at 3,000 the collapse decimator
## starts eating the eyebrows, which are the whole reason this mascot was
## chosen. Only one pose is ever in the scene at a time.
TRIANGLES = 6000


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--height", type=float, default=HEIGHT)
    parser.add_argument("--triangles", type=int, default=TRIANGLES)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(args.source))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("expected one mesh, got %d" % len(meshes))
    sheet = meshes[0]

    triangles = sum(max(len(p.vertices) - 2, 0) for p in sheet.data.polygons)
    print("  source  %d tris, %.3f x %.3f x %.3f units" % (
        triangles, sheet.dimensions.x, sheet.dimensions.y, sheet.dimensions.z))

    kept = []
    for material in sheet.data.materials:
        atlas = kb.strip_pbr(material)
        if atlas is None:
            continue
        kept.append(atlas)
        before, after = kb.dilate(atlas)
        print("  atlas   %dx%d, gutter %d px -> %d px" % (
            atlas.size[0], atlas.size[1], before, after))
    for image in list(bpy.data.images):
        if image not in kept and image.name != "Render Result":
            print("  dropped %s (%dx%d)" % (image.name, image.size[0], image.size[1]))
            bpy.data.images.remove(image)

    parts = kb.split_on_gaps(sheet, POSES)
    bpy.data.objects.remove(sheet, do_unlink=True)

    # One file with three children rather than three files. They share a
    # material, so they share the 2048 atlas — exported separately that is three
    # copies of the same 16MB of texture memory for a mascot who is only ever in
    # one pose at a time, against the 128MB §4.2 allows for the whole scene.
    root = bpy.data.objects.new("kanca", None)
    bpy.context.collection.objects.link(root)

    for part in parts:
        before, after = kb.decimate(part, args.triangles)
        kb.place_character(part, args.height)
        print("  %-10s %6d -> %5d tris, %.2f x %.2f x %.2f m" % (
            part.name, before, after,
            part.dimensions.x, part.dimensions.y, part.dimensions.z))
        part.parent = root
        part.matrix_parent_inverse = root.matrix_world.inverted()

    out_path = os.path.join(out_dir, "kanca.glb")
    kb.export_hierarchy(root, out_path)
    print("  wrote   %s (%.0f KB, %d poses, one shared atlas)" % (
        out_path, os.path.getsize(out_path) / 1024.0, len(parts)))


if __name__ == "__main__":
    main()
