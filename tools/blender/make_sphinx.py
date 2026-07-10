# Builds a stylized sphinx and exports it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_sphinx.py -- models/sphinx.glb
#
# Coordinates: Blender Z-up, the sphinx faces -Y. The glTF exporter converts
# to Y-up with -Y becoming +Z, so in Godot the sphinx faces +Z (toward the
# player walking in -Z direction). Origin: center of the entrance at ground
# level. The entrance passage between the front legs must stay clear: the
# game clamps the player to |x| <= 1.5 around the path center line.
import sys

import bpy


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def add_box(name: str, dims: tuple, loc: tuple, subsurf: int = 0, bevel: float = 0.0) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = dims
    bpy.ops.object.transform_apply(scale=True)

    if subsurf > 0:
        mod = obj.modifiers.new("subsurf", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf
        bpy.ops.object.shade_smooth()
    elif bevel > 0.0:
        # Flat faces with rounded edges: reads as carved stone.
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.shade_auto_smooth(angle=1.0)
    return obj


def taper_top(obj: bpy.types.Object, x_factor: float, y_factor: float) -> None:
    for v in obj.data.vertices:
        if v.co.z > 0.0:
            v.co.x *= x_factor
            v.co.y *= y_factor


def build_sphinx() -> None:
    # Statue-like: big forms are beveled blocks (carved stone), only the
    # head is organic via subsurf. Ground-touching parts extend a bit
    # below z=0 so nothing floats.
    add_box("rear", (7.4, 5.2, 4.4), (0.0, 2.4, 1.9), bevel=0.5)
    add_box("chest", (7.0, 3.0, 3.2), (0.0, -1.2, 4.1), bevel=0.4)

    # Front legs frame the entrance; keep |x| <= 1.9 free.
    add_box("leg_l", (1.8, 5.2, 2.2), (-2.8, -2.3, 0.7), bevel=0.3)
    add_box("leg_r", (1.8, 5.2, 2.2), (2.8, -2.3, 0.7), bevel=0.3)
    add_box("paw_l", (2.0, 1.8, 1.2), (-2.8, -5.4, 0.2), bevel=0.3)
    add_box("paw_r", (2.0, 1.8, 1.2), (2.8, -5.4, 0.2), bevel=0.3)

    # Head with nemes headdress (trapezoid flaring downward) and nose.
    # The nemes is wider than the head so the side wings read clearly.
    add_box("head", (2.4, 2.2, 2.6), (0.0, -1.7, 6.9), subsurf=2)
    nemes = add_box("nemes", (5.2, 2.4, 2.8), (0.0, -0.9, 6.7), bevel=0.2)
    taper_top(nemes, 0.5, 0.7)
    add_box("nose", (0.5, 0.7, 0.7), (0.0, -2.9, 6.7), subsurf=1)


def apply_modifiers_and_join() -> None:
    for obj in list(bpy.data.objects):
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)

    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.data.objects["rear"]
    bpy.ops.object.join()
    sphinx = bpy.context.active_object
    sphinx.name = "Sphinx"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()
    build_sphinx()
    apply_modifiers_and_join()
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB")
    print("exported:", out_path)


main()
