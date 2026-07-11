# Builds the stylized low-poly crocodile and exports it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_crocodile.py -- models/crocodile.glb
#
# Coordinates: Blender Z-up, the croc faces +Y. The glTF exporter converts
# to Y-up with +Y becoming -Z, so in Godot the croc faces -Z — matching the
# old box-built crocodile in hazards/crocodile.gd. Origin: the waterline;
# the game floats the node so the back deck sits just above the water.
# Footprint mirrors the old boxes (~3.7 nose-to-tail, 0.95 wide, back at
# ~+0.2) so the unchanged BoxShape3D collision still fits.
#
# The eyes are a SEPARATE object named "Eyes": the game finds that mesh and
# drives its material's emission for the pre-dive warning glow.
import sys

import bpy


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_material(name: str, color: tuple, roughness: float = 0.9) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def add_box(name: str, dims: tuple, loc: tuple, material: bpy.types.Material,
        subsurf: int = 0, bevel: float = 0.0,
        rot: tuple = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = dims
    obj.rotation_euler = rot
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    obj.data.materials.append(material)

    if subsurf > 0:
        mod = obj.modifiers.new("subsurf", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf
        bpy.ops.object.shade_smooth()
    elif bevel > 0.0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.shade_auto_smooth(angle=1.0)
    return obj


# Pinch the part beyond a y threshold: the snout narrows toward the nose,
# the tail toward its tip.
def taper_beyond_y(obj: bpy.types.Object, y_limit: float, forward: bool,
        x_factor: float, z_factor: float) -> None:
    for v in obj.data.vertices:
        if (forward and v.co.y > y_limit) or (not forward and v.co.y < y_limit):
            v.co.x *= x_factor
            v.co.z *= z_factor


def build_crocodile() -> None:
    green = make_material("croc_green", (0.045, 0.095, 0.022))
    belly = make_material("croc_belly", (0.11, 0.13, 0.05))
    dark = make_material("croc_dark", (0.012, 0.022, 0.006))
    eye = make_material("croc_eye", (0.01, 0.015, 0.005), roughness=0.4)

    body_parts = []

    # Chunky low-poly forms: subsurf 1 keeps the boxes readable instead
    # of melting them into flat blobs, and generous overlaps make the
    # parts read as one animal.
    torso = add_box("torso", (0.95, 1.7, 0.5), (0.0, 0.05, 0.0), green, subsurf=1)
    taper_beyond_y(torso, -0.5, False, 0.88, 0.92)
    body_parts.append(torso)
    body_parts.append(add_box("belly", (0.78, 1.45, 0.34), (0.0, 0.0, -0.12),
            belly, subsurf=1))

    # Head and the long tapering snout with a nostril bump at the tip.
    body_parts.append(add_box("head", (0.6, 0.55, 0.3), (0.0, 1.05, 0.02),
            green, subsurf=1))
    snout = add_box("snout", (0.4, 0.7, 0.18), (0.0, 1.5, -0.04), green, subsurf=1)
    taper_beyond_y(snout, 1.6, True, 0.7, 0.8)
    body_parts.append(snout)
    body_parts.append(add_box("nostrils", (0.16, 0.14, 0.09), (0.0, 1.72, 0.04),
            green, subsurf=1))

    # Tail: three shrinking, strongly overlapping segments that curve.
    body_parts.append(add_box("tail_1", (0.6, 0.7, 0.32), (0.02, -0.95, -0.02),
            green, subsurf=1))
    body_parts.append(add_box("tail_2", (0.42, 0.65, 0.22), (-0.03, -1.35, -0.05),
            green, subsurf=1))
    tail_tip = add_box("tail_3", (0.26, 0.6, 0.15), (0.04, -1.72, -0.08),
            green, subsurf=1)
    taper_beyond_y(tail_tip, -1.8, False, 0.55, 0.7)
    body_parts.append(tail_tip)

    # Four stubby legs splayed at the waterline.
    for side in (-1.0, 1.0):
        body_parts.append(add_box("leg_front", (0.36, 0.24, 0.2),
                (side * 0.52, 0.55, -0.1), green, subsurf=1,
                rot=(0.0, 0.0, side * 0.5)))
        body_parts.append(add_box("leg_back", (0.38, 0.26, 0.2),
                (side * 0.5, -0.5, -0.1), green, subsurf=1,
                rot=(0.0, 0.0, -side * 0.5)))

    # Two rows of back scutes sunk into the torso, one line down the tail.
    for side in (-1.0, 1.0):
        for i in range(5):
            y = 0.65 - i * 0.34
            size = 0.12 - 0.008 * i
            body_parts.append(add_box("scute", (0.1, 0.17, size),
                    (side * 0.15, y, 0.2), dark, bevel=0.025))
    for i, (y, z) in enumerate(((-0.95, 0.14), (-1.3, 0.08), (-1.6, 0.02))):
        body_parts.append(add_box("tail_scute", (0.09, 0.15, 0.11 - 0.015 * i),
                (0.0, y, z), dark, bevel=0.025))

    # The eyes: separate bulges the game makes glow before a dive.
    eye_parts = []
    for side in (-1.0, 1.0):
        eye_parts.append(add_box("eye", (0.13, 0.14, 0.12),
                (side * 0.2, 0.92, 0.16), eye, subsurf=1))

    apply_all_modifiers()
    join_objects(body_parts, "Croc")
    join_objects(eye_parts, "Eyes")


def apply_all_modifiers() -> None:
    for obj in list(bpy.data.objects):
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)


def join_objects(objs: list, name: str) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return joined


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()
    build_crocodile()
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB")
    print("exported:", out_path)


main()
