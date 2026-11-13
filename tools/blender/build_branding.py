"""Brand renders, taken from the mascot model itself.

PLAN.md 11.1 requires one signature colour running through the icon, the loading
screen and the primary buttons, and the icon to be Kanca. The only way to keep
that promise is to photograph the model rather than draw a picture of him: a
hand-drawn icon and a rendered mascot drift apart the first time either changes,
and the icon is the one place a child recognises the app before they can read.

This script renders; it composes nothing. Backgrounds, the wordmark and every
final canvas size are assembled by `tools/build_brand_images.gd`, in Godot, so
that what ships is composited by the same rasteriser that draws the game.

    & "D:/Program Files/Blender/blender.exe" --background --factory-startup `
      --python tools/blender/build_branding.py -- --out-dir assets/ui/brand
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import kanca_build as kb  # noqa: E402


# Rendered large and downscaled at composition time. Every brand canvas is a
# different size — 432 for the adaptive icon, 512 for Play, 1024 for the feature
# graphic — and one oversized master resampled down beats six renders that each
# have to be re-approved.
MASTER = 1024

# Degrees off face-on. Fifty-eight was right for the quadruped it was set for:
# head-on, a four-legged animal hides its own body length behind its chest. This
# mascot stands up and his whole design is in his face and the neckerchief under
# it, so the camera comes most of the way back round — far enough to keep the
# snout in profile and the ears apart, near enough that both eyes and the knot
# read.
AZIMUTH = 26.0


def _bounds(obj):
    """World-space bounding box of the whole hierarchy."""
    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    for part in [obj] + list(obj.children):
        for vertex in part.data.vertices:
            point = part.matrix_world @ vertex.co
            for axis in range(3):
                low[axis] = min(low[axis], point[axis])
                high[axis] = max(high[axis], point[axis])
    return low, high


def _render(obj, out_path, size, target, ortho_scale, azimuth=0.0, elevation=7.0):
    """One transparent PNG of `obj`, framed on `target` at `ortho_scale` metres.

    `kb.render_icon` frames whatever it is given and is right for an item; a
    portrait needs the frame placed by hand, because where the bottom edge falls
    across his body is the whole difference between a bust and a beheading.

    Azimuth is degrees around +Z from straight ahead. Zero is face-on, which is
    what the icon wants — a mascot at three-quarters reads as a character in a
    scene, and at 48 px a symmetrical head reads as a mark.
    """
    scene = bpy.context.scene
    kb._pick_eevee()
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = out_path
    # Godot's Compatibility renderer and Blender's Standard view transform agree;
    # AgX does not, and an AgX icon beside an in-game Kanca is two different
    # animals (see kb._use_standard_view_transform).
    kb._use_standard_view_transform(scene)

    yaw = math.radians(azimuth)
    pitch = math.radians(elevation)
    view = Vector((math.sin(yaw) * math.cos(pitch),
                   math.cos(yaw) * math.cos(pitch),
                   math.sin(pitch)))

    lights = []
    # Both lights are placed relative to the camera, not to the world, so the
    # face is lit whichever way the model is turned. A key fixed to an axis is
    # what turned the first mascot icon into a silhouette.
    right = view.cross(Vector((0.0, 0.0, 1.0))).normalized()
    for name, direction, energy in (
        ("BrandKey", (view * 0.9 - right * 0.55 + Vector((0.0, 0.0, 0.75))).normalized(), 4.2),
        ("BrandFill", (view * 0.6 + right * 0.9 + Vector((0.0, 0.0, 0.1))).normalized(), 1.7),
    ):
        light_data = bpy.data.lights.new(name, type="SUN")
        light_data.energy = energy
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        # A sun emits along its own -Z, so +Z points back at where the light is.
        light.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
        lights.append((light, light_data))

    world = bpy.data.worlds.new("BrandWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    previous_world = scene.world
    scene.world = world

    camera_data = bpy.data.cameras.new("BrandCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ortho_scale
    camera_data.clip_end = 100.0
    camera = bpy.data.objects.new("BrandCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.location = target + view * 8.0
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.render.render(write_still=True)

    scene.world = previous_world
    bpy.data.worlds.remove(world, do_unlink=True)
    for light, light_data in lights:
        bpy.data.objects.remove(light, do_unlink=True)
        bpy.data.lights.remove(light_data, do_unlink=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.cameras.remove(camera_data, do_unlink=True)


def _load_mascot(path):
    """The shipped model, not a rebuilt one.

    This used to call `build_characters.build_kanca()` and photograph what came
    back, which was right while the mascot was procedural: the icon was the
    mascot because both came out of the same function. He is a supplied model
    now (ASSETS.md), so the only way to keep that promise is to photograph the
    file the game loads.

    Only the idle pose. The other two are in the same file and would otherwise
    stand in frame beside him.
    """
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    poses = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not poses:
        raise RuntimeError("no meshes in %s" % path)
    idle = next((o for o in poses if o.name.lower().startswith("idle")), poses[0])
    for other in poses:
        if other is not idle:
            bpy.data.objects.remove(other, do_unlink=True)
    idle.parent = None
    bpy.context.view_layer.update()
    return idle


def _assert_rendered(path):
    """Refuses a blank frame.

    EEVEE needs a GPU even in background mode, and on this machine's driver it
    intermittently comes back having drawn nothing at all: the render succeeds,
    the PNG is written at full size with noise in the colour channels, and every
    pixel of it is transparent. Nothing errors. That image then gets composited
    into the app icon and the boot splash, which is a blank cream screen shipped
    to a device before anybody notices.

    A tool that reports success when the thing it made is empty is worse than no
    tool, because it is trusted.
    """
    image = bpy.data.images.load(path)
    try:
        pixels = list(image.pixels)
        covered = sum(1 for index in range(3, len(pixels), 4) if pixels[index] > 0.5)
        if covered * 400 < len(pixels):
            raise RuntimeError(
                "%s came back blank - %d opaque pixels. EEVEE drew nothing; this is "
                "the GPU, not the model. Run it again." % (path, covered))
    finally:
        bpy.data.images.remove(image)


def render_full(obj, out_path, azimuth=AZIMUTH, elevation=8.0):
    """Head to hoof, with a little air.

    The frame comes from projecting the eight corners of the bounding box onto
    the camera's own axes, not from taking the larger of the world width and
    height. That shortcut held while the mascot was upright and roughly as deep
    as he was wide. The moment he went onto four legs and the camera went round
    to the side, a metre of animal was being framed against sixty centimetres of
    world X, and the render came back with his nose and his tail cut off.
    """
    low, high = _bounds(obj)

    yaw = math.radians(azimuth)
    pitch = math.radians(elevation)
    view = Vector((math.sin(yaw) * math.cos(pitch),
                   math.cos(yaw) * math.cos(pitch),
                   math.sin(pitch)))
    right = view.cross(Vector((0.0, 0.0, 1.0)))
    if right.length < 1e-6:
        right = Vector((1.0, 0.0, 0.0))
    right.normalize()
    up = right.cross(view).normalized()

    centre = (low + high) * 0.5
    across = [float("inf"), float("-inf")]
    vertical = [float("inf"), float("-inf")]
    for x in (low.x, high.x):
        for y in (low.y, high.y):
            for z in (low.z, high.z):
                offset = Vector((x, y, z)) - centre
                across[0] = min(across[0], offset.dot(right))
                across[1] = max(across[1], offset.dot(right))
                vertical[0] = min(vertical[0], offset.dot(up))
                vertical[1] = max(vertical[1], offset.dot(up))

    span = max(across[1] - across[0], vertical[1] - vertical[0]) * 1.08
    target = (centre
              + right * ((across[0] + across[1]) * 0.5)
              + up * ((vertical[0] + vertical[1]) * 0.5))
    _render(obj, out_path, MASTER, target, span, azimuth=azimuth, elevation=elevation)
    _assert_rendered(out_path)
    return span


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--mascot",
                        default="assets/models/characters/kanca.glb")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)

    # Absolute, because Blender resolves a relative render path against its own
    # notion of the current file rather than the shell's working directory. A
    # relative --out-dir renders happily and writes nothing you can find, and the
    # stale image left behind is what gets composited.
    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    kb.reset_scene()

    kanca = _load_mascot(args.mascot)
    low, high = _bounds(kanca)
    print("  kanca %.3f x %.3f x %.3f m, %d tris" % (
        high.x - low.x, high.y - low.y, high.z - low.z,
        kb.triangle_count(kanca) + sum(kb.triangle_count(part) for part in kanca.children)))

    full_path = os.path.join(out_dir, "kanca_full.png")
    print("  full  %s  (%.3f m across)" % (full_path, render_full(kanca, full_path)))


if __name__ == "__main__":
    main()
