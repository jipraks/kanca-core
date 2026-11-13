"""Turns one supplied character model into something the game can walk around.

    & "D:/Program Files/Blender/blender.exe" --background --factory-startup `
      --python tools/blender/import_character.py -- `
      --source "C:/path/stylized boy character 3d model.glb" `
      --out assets/models/characters/player.glb --height 1.15

The sibling of `import_mascot.py`, for a file that holds one figure rather than a
pose sheet. Both do the same four repairs — see ASSETS.md for why a generated
`.glb` always needs them — and both share the work with `kanca_build`.

The one thing this adds is a **skeleton**. Every character built by
`build_characters.py` carries its legs as separate objects with the pivot at the
hip, and `WalkCycle` rotates those. A supplied model is one continuous shell:
there is no leg to rotate, and cutting one out leaves a hole at the hip that
opens every time it swings. `kb.rig_legs` binds the mesh to three bones instead,
so the child walks rather than skates.
"""

import argparse
import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import kanca_build as kb  # noqa: E402


## The child's height in metres (PLAN.md §7.1 — he is four to six years old).
HEIGHT = 1.15

## Triangles after decimation.
##
## §11 budgets 3,000 for a character and the supplied model arrives with a
## quarter of a million per figure. 6,500 is what is left once the village, its
## undergrowth and the mascot have taken theirs — and it is measured, not
## guessed: the hub came out 2,230 triangles over the §4.2 ceiling at 9,000,
## because a character that casts a shadow is drawn twice.
##
## Below about 4,000 the collapse starts flattening his face and opening seams
## along the UV islands. There is no LOD here, so this one number has to serve
## the shot where he fills the screen and the shot where he is forty pixels tall.
TRIANGLES = 6500

## Longest side of the atlas, in texels. The supplied model brings 4096, which
## for a child a couple of hundred pixels high on a phone is half the §4.2
## texture budget spent on one character.
TEXTURE = 1024


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--height", type=float, default=HEIGHT)
    parser.add_argument("--triangles", type=int, default=TRIANGLES)
    parser.add_argument("--no-rig", action="store_true")
    parser.add_argument("--texture", type=int, default=TEXTURE)
    parser.add_argument("--figure", type=int, default=0,
                        help="which figure to keep if the source is a sheet")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(args.source))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("expected one mesh, got %d" % len(meshes))
    obj = meshes[0]
    obj.name = os.path.splitext(os.path.basename(args.out))[0]

    triangles = sum(max(len(p.vertices) - 2, 0) for p in obj.data.polygons)
    print("  source  %d tris, %.3f x %.3f x %.3f units" % (
        triangles, obj.dimensions.x, obj.dimensions.y, obj.dimensions.z))

    # Generators hand back turnaround sheets as readily as single figures, and
    # nothing in the file says which you have. Splitting on the empty columns
    # answers it: no gaps means one figure and the mesh is left alone.
    figures = kb.split_figures(obj)
    if len(figures) > 1:
        print("  sheet   %d figures, keeping #%d" % (len(figures), args.figure + 1))
        chosen = figures[min(args.figure, len(figures) - 1)]
        for other in figures:
            if other is not chosen:
                bpy.data.objects.remove(other, do_unlink=True)
        bpy.data.objects.remove(obj, do_unlink=True)
        obj = chosen
        obj.name = os.path.splitext(os.path.basename(args.out))[0]

    kept = []
    for material in obj.data.materials:
        atlas = kb.strip_pbr(material)
        if atlas is None:
            continue
        kept.append(atlas)
        was = atlas.size[0]
        wide, high = kb.resize_atlas(atlas, args.texture)
        if wide != was:
            print("  atlas   %d -> %d square" % (was, wide))
        before, after = kb.dilate(atlas)
        print("  atlas   %dx%d, gutter %d px -> %d px" % (
            atlas.size[0], atlas.size[1], before, after))
    for image in list(bpy.data.images):
        if image not in kept and image.name != "Render Result":
            print("  dropped %s (%dx%d)" % (image.name, image.size[0], image.size[1]))
            bpy.data.images.remove(image)

    before, after = kb.decimate(obj, args.triangles)
    print("  decimate %d -> %d tris" % (before, after))

    kb.place_character(obj, args.height)
    print("  placed  %.2f x %.2f x %.2f m, facing +Y, origin at the feet" % (
        obj.dimensions.x, obj.dimensions.y, obj.dimensions.z))

    out_path = os.path.abspath(args.out)
    if args.no_rig:
        kb.export_glb(obj, out_path)
    else:
        rig = kb.rig_legs(obj)
        print("  rigged  %d bones, weights computed at the hip" % len(rig.data.bones))
        kb.export_hierarchy(rig, out_path, apply_modifiers=False)

    print("  wrote   %s (%.0f KB)" % (args.out, os.path.getsize(out_path) / 1024.0))


if __name__ == "__main__":
    main()
