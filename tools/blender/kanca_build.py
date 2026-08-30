"""Shared Blender helpers for Kanca's asset generators. Developer tool.

Imported by build_items.py and build_buildings.py. Holds the parts that every
asset needs regardless of what it is — materials, normals, origin placement,
export and icon rendering — while the shape-making helpers stay with the
generator that uses them, because a lathe and a roof have nothing in common.

The brief these enforce lives in docs/ART_STYLE.md:

  * 1 Blender unit = 1 metre
  * origin at the base, centred, so the game can place it by its feet
  * Z-up while modelling; the glTF exporter converts to Godot's Y-up
  * flat colour materials, no texture maps

Colours are pushed deeper and more saturated than the real object. Godot's filmic
tonemap lifts and desaturates, so a photographically "correct" colour arrives on
screen looking washed out.
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

X_AXIS = Vector((1.0, 0.0, 0.0))

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_to_linear(channel):
    """sRGB 0-1 to linear.

    Blender's Base Color input, and glTF's baseColorFactor, are both **linear**.
    Colours are chosen by eye as sRGB, the way a hex value reads. Handing an sRGB
    number straight to a linear input makes every surface render roughly 1.7x too
    light, which looks exactly like an over-exposed scene and sends you hunting
    through the lighting for a bug that is in the colour.
    """
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def linear_to_srgb(channel):
    """The inverse of srgb_to_linear. Needed because vertex colours and base
    colour factors do not live in the same space, however much they look alike.
    """
    if channel <= 0.0031308:
        return channel * 12.92
    return 1.055 * (channel ** (1.0 / 2.4)) - 0.055


def make_material(name, colour, roughness=0.85):
    """Flat colour, no maps. glTF exports this as a plain base-colour factor.

    `colour` is sRGB, as picked from a swatch or a hex value.
    """
    linear = tuple(srgb_to_linear(channel) for channel in colour)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    # Viewport colour stays sRGB while the BSDF gets linear. They are not in the
    # same space: handing the linear value to diffuse_color renders every preview
    # and icon far too dark. Verified by looking, not by reading the docs.
    material.diffuse_color = (*colour, 1.0)
    return material


# ---------------------------------------------------------------- shapes

def revolve(bm, profile, segments, material_at=0, section_at=None):
    """Lathes a profile around Z. `profile` is (radius, z) from bottom to top.

    A radius of zero is a pole, capped with a fan - which is what gives an apple
    its dimple and an egg its point without a single extra vertex.

    `material_at` is an index or a callable taking the band number.
    `section_at(theta)` scales the radius by angle: scallops and ridges.
    """
    def material_for(band):
        return material_at(band) if callable(material_at) else material_at

    levels = []
    for radius, z in profile:
        if radius <= 1e-6:
            levels.append(("pole", bm.verts.new((0.0, 0.0, z))))
            continue
        ring = []
        for step in range(segments):
            theta = math.tau * step / segments
            r = radius * (section_at(theta) if section_at else 1.0)
            ring.append(bm.verts.new((r * math.cos(theta), r * math.sin(theta), z)))
        levels.append(("ring", ring))

    bm.verts.ensure_lookup_table()

    for band in range(len(levels) - 1):
        kind_a, a = levels[band]
        kind_b, b = levels[band + 1]
        index = material_for(band)
        for step in range(segments):
            nxt = (step + 1) % segments
            if kind_a == "ring" and kind_b == "ring":
                face = bm.faces.new((a[step], a[nxt], b[nxt], b[step]))
            elif kind_a == "pole":
                face = bm.faces.new((a, b[step], b[nxt]))
            else:
                face = bm.faces.new((a[step], a[nxt], b))
            face.material_index = index

    return levels


def sweep(bm, spine, section_at, radial_segments, material_index=0, cap_ends=True):
    """Sweeps a closed cross-section along a spine.

    `spine` is a list of (t, position, tangent). `section_at(t, theta)` returns
    the (across, through) offset, so a section can be an ellipse, a rounded
    rectangle or a ridged tube - which is the difference between a bread loaf, a
    sachet and a banana.
    """
    rings = []
    for t, position, tangent in spine:
        normal = Vector((-tangent.z, 0.0, tangent.x))
        if normal.length < 1e-6:
            normal = Vector((1.0, 0.0, 0.0))
        normal.normalize()
        binormal = Vector((0.0, 1.0, 0.0))
        ring = []
        for step in range(radial_segments):
            theta = math.tau * step / radial_segments
            across, through = section_at(t, theta)
            ring.append(bm.verts.new(position + normal * across + binormal * through))
        rings.append(ring)

    bm.verts.ensure_lookup_table()

    for i in range(len(rings) - 1):
        for step in range(radial_segments):
            nxt = (step + 1) % radial_segments
            face = bm.faces.new((rings[i][step], rings[i][nxt],
                                 rings[i + 1][nxt], rings[i + 1][step]))
            face.material_index = material_index

    if cap_ends:
        for ring in (rings[0], rings[-1]):
            face = bm.faces.new(ring)
            face.material_index = material_index

    return rings


def cap_with_tip(bm, ring, tip_position, radial_segments, material_index, reverse=False):
    tip = bm.verts.new(tip_position)
    for step in range(radial_segments):
        nxt = (step + 1) % radial_segments
        verts = (ring[nxt], ring[step], tip) if reverse else (ring[step], ring[nxt], tip)
        face = bm.faces.new(verts)
        face.material_index = material_index


def superellipse(theta, half_across, half_through, squareness=4.0):
    """Rounded rectangle. squareness 2 is an ellipse, higher is boxier."""
    exponent = 2.0 / squareness
    cos_t, sin_t = math.cos(theta), math.sin(theta)
    across = half_across * math.copysign(abs(cos_t) ** exponent, cos_t)
    through = half_through * math.copysign(abs(sin_t) ** exponent, sin_t)
    return across, through


def straight_spine(length, samples, axis=X_AXIS):
    return [(i / (samples - 1.0), axis * ((i / (samples - 1.0) - 0.5) * length), axis)
            for i in range(samples)]



def add_blob(bm, centre, radius, material_index, squash=(1.0, 1.0, 1.0), subdivisions=1):
    """A faceted ball. Heads, hands and eyes are all this at different sizes."""
    result = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    for vert in result["verts"]:
        vert.co.x *= squash[0]
        vert.co.y *= squash[1]
        vert.co.z *= squash[2]
        vert.co += Vector(centre)
    faces = set()
    for vert in result["verts"]:
        faces.update(vert.link_faces)
    for face in faces:
        face.material_index = material_index


def add_box(bm, size, centre, material_index, bevel=0.0, bevel_segments=1, rotation=None):
    """A box, twelve triangles, or a few more with a bevel.

    Material goes on before the bevel: bevelling removes the original faces, and
    the new strips inherit the index from what they grew out of.
    """
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    local = [
        (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
        (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz),
    ]
    basis = Matrix.Rotation(rotation[0], 3, "X") if rotation else Matrix.Identity(3)
    coords = [Vector(centre) + basis @ Vector(point) for point in local]
    verts = [bm.verts.new(coord) for coord in coords]
    bm.verts.ensure_lookup_table()

    faces = []
    for quad in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
                 (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        face = bm.faces.new([verts[i] for i in quad])
        face.material_index = material_index
        faces.append(face)

    if bevel > 0.0:
        edges = set()
        for face in faces:
            edges.update(face.edges)
        bmesh.ops.bevel(bm, geom=list(edges), offset=bevel, segments=bevel_segments,
                        profile=0.5, affect="EDGES")


def finish_bm(bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()


def mesh_from_bmesh(name, bm, materials):
    finish_bm(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for material in materials:
        obj.data.materials.append(material)
    return obj


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def scale_to_longest_side(obj, target):
    bpy.context.view_layer.update()
    current = max(obj.dimensions)
    if current > 0.0:
        obj.scale = (target / current,) * 3
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def scale_to_fit(obj, size):
    """Scales uniformly so the object fits inside `size` without distorting it.

    Buildings have a declared footprint in data/minigames.json, and the model has
    to respect it: the collider and the approach trigger are both built from
    those numbers, so a model that overhangs them is a building a child can walk
    through.
    """
    bpy.context.view_layer.update()
    factors = [target / current for target, current in zip(size, obj.dimensions) if current > 1e-6]
    if factors:
        obj.scale = (min(factors),) * 3
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def place_origin_at_base(obj):
    """Origin at the bottom, centred in X and Y. The game places things by their
    feet; an origin at the centre of the bounding box buries half the model."""
    bpy.context.view_layer.update()
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    centre = sum((obj.matrix_world @ v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
    bpy.context.scene.cursor.location = Vector((centre.x, centre.y, lowest))
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.location = (0.0, 0.0, 0.0)
    bpy.context.scene.cursor.location = Vector((0.0, 0.0, 0.0))


def shade(obj, smooth_angle_degrees=55.0):
    """Smooth normals, but keep genuinely sharp edges sharp. This is what stops a
    low-poly model reading as faceted without adding a single triangle — and what
    keeps a roof ridge crisp while an apple stays round."""
    select_only(obj)
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle_degrees))
    except (AttributeError, RuntimeError):
        pass


def triangle_count(obj):
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def _material_base_colour(material):
    """The linear base colour a material was built with."""
    if material is None or not material.use_nodes:
        return (1.0, 1.0, 1.0)
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            value = node.inputs["Base Color"].default_value
            return (value[0], value[1], value[2])
    return (1.0, 1.0, 1.0)


def bake_vertex_colours(obj, base=0.62, facet_jitter=0.055, seed=0,
                        collapse_materials=True, z_range=None):
    """Bakes each material's colour, shaded by a vertical gradient, into vertex
    colours, then collapses the whole object onto one material.

    Two jobs that turn out to be the same job.

    The gradient is what stands in for texture. Every material here is one flat
    colour, and a flat colour on a low-poly model gives it no shape beyond what
    the light happens to catch - a tree canopy comes out as a green blob, a roof
    as a coloured card. Darkening the underside costs no texture memory, no UVs
    and no draw calls, and it is most of what the hand-painted look actually is.
    The per-facet jitter matters as much: two adjacent facets at the same height
    that share a colour read as one surface.

    Collapsing the materials is the reason it is worth doing this way rather than
    with a plain grey multiplier. A material is a surface is a draw call, and the
    village was spending eighteen of them on three buildings and six on one
    child. Once the colour lives in the mesh, six materials and one material look
    identical and cost six times less.

    The gradient runs from `base` up to exactly 1.0. Going above 1.0 would look
    better on a dark model and clips on a light one - glTF stores vertex colours
    as normalised integers, so a bright roof lifted to 1.1 comes back as 1.0 and
    loses its shading entirely.

    **Colours are written to the attribute in sRGB, not linear**, and that is not
    a mistake. Godot's Compatibility renderer - the one this project ships on,
    for the device reach in 4.2 - always treats mesh vertex colours as sRGB and
    converts them. `StandardMaterial3D.vertex_color_is_srgb` reads like the
    switch that decides this and is ignored: the docs note it applies only to
    Forward+ and Mobile. So a linear value written here arrives on screen having
    been through the transfer function twice, which is not a dimmer - it is a
    hue shift. Baked linear, the Warung's yellow sign came out orange and its
    mint roof came out bottle green.

    Blender reads the attribute as linear, so the material built below puts a
    gamma node in the way and the two disagree in exactly compensating
    directions. Previews and icons stay correct; so does the game.
    """
    mesh = obj.data
    if not mesh.polygons:
        return

    colours = [_material_base_colour(m) for m in mesh.materials] or [(1.0, 1.0, 1.0)]

    if z_range is None:
        lows = [v.co.z for v in mesh.vertices]
        lowest, highest = min(lows), max(lows)
    else:
        # Given explicitly when the model is built in pieces. Each piece has to
        # be shaded against the whole character's height or the parts disagree
        # about where "the bottom" is, and a leg comes out darker than the shoe
        # above it.
        lowest, highest = z_range
    span = max(highest - lowest, 1e-5)

    layer = mesh.color_attributes.get("Color")
    if layer is None:
        layer = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")

    for polygon in mesh.polygons:
        rgb = colours[min(polygon.material_index, len(colours) - 1)]
        # Deterministic per-face wobble: a rebuild has to produce the same file.
        wobble = math.sin((polygon.index + 1) * 12.9898 + seed * 78.233)
        jitter = 1.0 + wobble * facet_jitter
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index]
            t = (vertex.co.z - lowest) / span
            factor = min((base + (1.0 - base) * t) * jitter, 1.0)
            # Shade in linear, store in sRGB. Both halves matter and they pull in
            # opposite directions, which is why this line is the whole trick.
            layer.data[loop_index].color = (
                linear_to_srgb(rgb[0] * factor),
                linear_to_srgb(rgb[1] * factor),
                linear_to_srgb(rgb[2] * factor),
                1.0)

    if not collapse_materials:
        return

    roughness = 0.85
    if mesh.materials and mesh.materials[0] is not None and mesh.materials[0].use_nodes:
        for node in mesh.materials[0].node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                roughness = node.inputs["Roughness"].default_value
                break

    combined = _vertex_colour_material("%s_baked" % obj.name, roughness)
    mesh.materials.clear()
    mesh.materials.append(combined)
    for polygon in mesh.polygons:
        polygon.material_index = 0


def _vertex_colour_material(name, roughness):
    """One material whose base colour is read from the mesh.

    The Color Attribute node is not decoration: Blender's glTF exporter only
    writes COLOR_0 when a material actually reads it, and EEVEE previews would
    otherwise render the model white.
    """
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0

    attribute = tree.nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Color"

    # The attribute holds sRGB (see bake_vertex_colours) and Blender reads it as
    # linear, so it has to be converted on the way in or every preview and every
    # rendered icon comes out washed out. Gamma 2.2 rather than the exact sRGB
    # curve: the difference is under a colour step and Blender has no exact node.
    gamma = tree.nodes.new("ShaderNodeGamma")
    gamma.inputs["Gamma"].default_value = 2.2
    tree.links.new(attribute.outputs["Color"], gamma.inputs["Color"])
    tree.links.new(gamma.outputs["Color"], bsdf.inputs["Base Color"])
    material.diffuse_color = (0.7, 0.7, 0.7, 1.0)
    return material


def part_from_bmesh(name, bm, materials, pivot):
    """A child object whose origin sits at a joint, so rotating it swings.

    Built in character space and then re-origined, because the geometry is much
    easier to reason about in one coordinate system and the pivot is the only
    thing that has to move.
    """
    obj = mesh_from_bmesh(name, bm, materials)
    offset = Vector(pivot)
    for vertex in obj.data.vertices:
        vertex.co -= offset
    obj.location = offset
    return obj


def export_hierarchy(root, out_path):
    """Exports a parent and everything under it as one glTF."""
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = root

    def select(obj):
        obj.select_set(True)
        for child in obj.children:
            select(child)

    select(root)
    kwargs = dict(filepath=out_path, export_format="GLB", use_selection=True,
                  export_apply=True, export_yup=True, export_vertex_color="ACTIVE")
    for _attempt in range(3):
        try:
            bpy.ops.export_scene.gltf(**kwargs)
            return
        except TypeError:
            if "export_vertex_color" in kwargs:
                kwargs.pop("export_vertex_color")
            elif "export_apply" in kwargs:
                kwargs.pop("export_apply")
            else:
                raise


def _hierarchy_bounds(root):
    lowest, highest = float("inf"), -float("inf")
    for part in [root] + list(root.children):
        for vertex in part.data.vertices:
            z = (part.matrix_world @ vertex.co).z
            lowest = min(lowest, z)
            highest = max(highest, z)
    return lowest, highest


def fit_hierarchy(root, target_height):
    """Scales a parent and its children to `target_height`, then sets the lowest
    point to zero.

    The single-object versions of this (`scale_to_longest_side`,
    `place_origin_at_base`) only see the object they are handed, so once the legs
    became separate children they normalised the torso and left the character
    both sunk into the ground and taller than the number it was built to. Both
    faults are invisible in Blender and obvious in the game.
    """
    bpy.context.view_layer.update()
    lowest, highest = _hierarchy_bounds(root)
    span = max(highest - lowest, 1e-5)
    factor = target_height / span

    for part in [root] + list(root.children):
        for vertex in part.data.vertices:
            vertex.co *= factor
        if part is not root:
            part.location *= factor

    bpy.context.view_layer.update()
    lowest, _highest = _hierarchy_bounds(root)
    for part in [root] + list(root.children):
        if part is root:
            for vertex in part.data.vertices:
                vertex.co.z -= lowest
        else:
            part.location.z -= lowest
    bpy.context.view_layer.update()


def export_glb(obj, out_path):
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    select_only(obj)
    kwargs = dict(filepath=out_path, export_format="GLB", use_selection=True,
                  export_apply=True, export_yup=True,
                  # Default is "MATERIAL", which exports vertex colours only when
                  # a material node reads them. Every material here is a plain
                  # base colour, so the gradient painted by paint_gradient would
                  # be dropped on the way out without a word.
                  export_vertex_color="ACTIVE")
    for attempt in range(3):
        try:
            bpy.ops.export_scene.gltf(**kwargs)
            return
        except TypeError:
            # Older exporters know fewer of these arguments. Drop them one at a
            # time rather than giving up on the export.
            if "export_vertex_color" in kwargs:
                kwargs.pop("export_vertex_color")
            elif "export_apply" in kwargs:
                kwargs.pop("export_apply")
            else:
                raise


def _use_standard_view_transform(scene):
    # Blender's default view transform is AgX, which desaturates heavily. The
    # exported colour is unaffected, but a preview through AgX shows an olive
    # banana and invites "fixing" a colour that was never wrong.
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    except TypeError:
        pass


def _pick_eevee():
    """EEVEE's engine id moved between Blender versions."""
    for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            bpy.context.scene.render.engine = name
            return name
        except TypeError:
            continue
    return "BLENDER_WORKBENCH"


def render_icon(obj, icon_path, size=256, elevation=0.85, distance=2.0, fit_aspect=False,
                from_front=False):
    """Renders one object to a transparent PNG for the 2D UI.

    Icons are rendered from the models rather than drawn separately, because a
    child matching an order card against a shelf would otherwise be matching two
    different pictures of the same thing.

    Rendered in EEVEE, not Workbench. Workbench has its own stylised shading that
    ignores the real materials, and it came out about a third darker than Godot
    lights the same model - so the card and the shelf disagreed on colour even
    though they agreed on shape. EEVEE evaluates the same Principled BSDF the
    glTF carries, which is the only way the two ever match.

    `from_front` matters for anything with a face. The camera sits at -Y by
    default, which is correct for an item that has no front and photographs the
    back of anything that does: the first 48px test of the mascot came back as an
    unlit blob with a white patch on it, and the patch was his tail.
    """
    scene = bpy.context.scene
    _pick_eevee()
    # A square frame wastes most of its area on a wide, low subject. Matching the
    # frame to the subject's own proportions is what makes a building icon read
    # at sign size instead of floating in transparent margin.
    aspect = 1.0
    if fit_aspect and obj.dimensions.x > 1e-6:
        aspect = min(max(obj.dimensions.z / obj.dimensions.x, 0.42), 1.0)
    scene.render.resolution_x = size
    scene.render.resolution_y = max(int(size * aspect), 64)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = icon_path
    _use_standard_view_transform(scene)

    for other in bpy.context.collection.objects:
        other.hide_render = other is not obj

    reach = max(obj.dimensions) * distance
    centre = obj.location + Vector((0.0, 0.0, obj.dimensions.z * 0.5))

    # Key, fill and a soft ambient, roughly matching how the mini-games light a
    # shelf: one directional sun plus sky ambient.
    lights = []
    # Mirrored with the camera. A key light fixed at -Y turns every front-facing
    # subject into a silhouette.
    side = 1.0 if from_front else -1.0
    for name, offset, energy in (
        ("IconKey", Vector((-0.6 * -side, 1.0 * side, 1.1)), 4.0),
        ("IconFill", Vector((1.0 * -side, 0.7 * side, 0.2)), 1.6),
    ):
        light_data = bpy.data.lights.new(name, type="SUN")
        light_data.energy = energy
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        # A sun emits along its -Z, so +Z has to point back at where the light is
        # coming from. Negating this aims both lights away from the subject, and
        # everything then renders lit only by ambient - which is exactly how the
        # icons ended up a third too dark.
        light.rotation_euler = offset.to_track_quat("Z", "Y").to_euler()
        lights.append((light, light_data))

    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    previous_world = scene.world
    scene.world = world

    camera_data = bpy.data.cameras.new("IconCamera")
    camera_data.type = "ORTHO"
    # Frame on the widest axis so nothing is ever cropped, with a little air.
    camera_data.ortho_scale = max(obj.dimensions) * (1.06 if fit_aspect else 1.18)
    camera = bpy.data.objects.new("IconCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.location = centre + Vector((0.0, reach * side, reach * elevation * 0.5))
    camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.render.render(write_still=True)

    scene.world = previous_world
    bpy.data.worlds.remove(world, do_unlink=True)
    for light, light_data in lights:
        bpy.data.objects.remove(light, do_unlink=True)
        bpy.data.lights.remove(light_data, do_unlink=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.cameras.remove(camera_data, do_unlink=True)
    for other in bpy.context.collection.objects:
        other.hide_render = False


def _add_preview_lights(side=-1.0):
    """The same key-and-fill rig the icons use, so a contact sheet and an icon of
    the same model agree with each other.

    `side` is which way the camera is looking from. The icon rig assumes -Y,
    which is right for items and props; a character photographed from +Y with
    that rig is lit from behind and comes out a silhouette.
    """
    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("PreviewWorld")
        bpy.context.scene.world = world
    world.use_nodes = False
    world.color = (0.55, 0.57, 0.60)

    for name, direction, energy in (
        ("SheetKey", Vector((-0.6 * -side, 1.0 * side, 1.1)), 4.0),
        ("SheetFill", Vector((1.0 * -side, 0.7 * side, 0.2)), 1.6),
    ):
        light_data = bpy.data.lights.new(name, type="SUN")
        light_data.energy = energy
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        # A SUN emits along its own -Z, so +Z has to point back towards the
        # subject. Getting this backwards lights the scene with ambient only.
        light.rotation_euler = direction.normalized().to_track_quat("Z", "Y").to_euler()


def render_contact_sheet(objects, preview_path, span, height=340, elevation=0.6,
                         from_front=False, shaded=False):
    """A row of everything built, so a batch can be looked at in one go. Read the
    Godot screenshot too: this is a picture of the models, that is a picture of
    the game.

    `shaded=True` renders in EEVEE instead of Workbench. Workbench draws
    `material.diffuse_color` under its own studio shading, which is a different
    value in a different colour space from the Principled BSDF that actually gets
    exported - it is fine for reading silhouettes, and actively misleading about
    colour. Anything where the colours are the point wants `shaded`.
    """
    scene = bpy.context.scene
    if shaded:
        _pick_eevee()
        _add_preview_lights(1.0 if from_front else -1.0)
    else:
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = int(height * len(objects) * 1.05) + 200
    scene.render.resolution_y = height
    scene.render.film_transparent = False
    # Set, not inherited. These helpers are used on other people's .blend files
    # too, and the first one tried wrote a TIFF because that is what its scene
    # was configured for.
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = preview_path
    _use_standard_view_transform(scene)

    for index, obj in enumerate(objects):
        obj.location.x = (index - (len(objects) - 1) * 0.5) * span

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(len(objects) * span + span * 0.35, span)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera

    # Three-quarter view, not head on. A gable roof seen square is a rectangle,
    # and the whole point of three different roofs is the silhouette.
    reach = span * 4.0
    target = Vector((0.0, 0.0, span * 0.24))
    # People are built facing +Y, so a camera at -Y photographs the backs of
    # their heads. Props and buildings are fine either way.
    side = 1.0 if from_front else -1.0
    camera.location = Vector((reach * 0.42 * -side, reach * side, reach * elevation))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.render.render(write_still=True)
