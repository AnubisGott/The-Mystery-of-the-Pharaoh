# Builds a stepped pyramid and exports it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_pyramid.py -- models/pyramid.glb
#
# Same footprint and height as the prism placeholder it replaces:
# 70 wide (x), 45 deep (Blender y / Godot z), 30 tall. Base sits at z=0.
import sys

import bpy

STEPS = 8
WIDTH = 70.0
DEPTH = 45.0
HEIGHT = 30.0


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def build_pyramid() -> None:
    step_height = HEIGHT / STEPS
    for i in range(STEPS):
        shrink = float(STEPS - i) / STEPS
        bpy.ops.mesh.primitive_cube_add(
            size=1,
            location=(0.0, 0.0, step_height * i + step_height / 2.0),
        )
        obj = bpy.context.active_object
        obj.name = "step_%d" % i
        obj.scale = (WIDTH * shrink, DEPTH * shrink, step_height)
        bpy.ops.object.transform_apply(scale=True)

        # Slightly worn edges so the steps do not look laser-cut.
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = 0.3
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier="bevel")
        bpy.ops.object.shade_auto_smooth(angle=1.0)


def join_and_export(out_path: str) -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.data.objects["step_0"]
    bpy.ops.object.join()
    pyramid = bpy.context.active_object
    pyramid.name = "Pyramid"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB")
    print("exported:", out_path)


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()
    build_pyramid()
    join_and_export(out_path)


main()
