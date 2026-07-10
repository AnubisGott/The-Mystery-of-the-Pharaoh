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


def add_box(name: str, dims: tuple, loc: tuple, subsurf: int = 0, bevel: float = 0.0,
		rot: tuple = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = dims
    obj.rotation_euler = rot
    bpy.ops.object.transform_apply(rotation=True, scale=True)

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
    # below z=0 so nothing floats. Proportions follow the classic lying
    # lion: long body, raised haunches, tail around the right hip.
    # The "rear" front face at y=-0.2 is the passage back wall; the level
    # places the dark exit opening against it, so keep that plane.
    add_box("rear", (7.4, 5.2, 4.4), (0.0, 2.4, 1.9), bevel=0.5)
    add_box("chest", (7.0, 3.0, 3.2), (0.0, -1.2, 4.1), bevel=0.4)
    add_box("rump", (6.2, 4.0, 3.6), (0.0, 5.4, 1.5), bevel=0.4)
    add_box("haunch_l", (1.9, 3.4, 3.8), (-2.5, 4.6, 1.8), subsurf=2)
    add_box("haunch_r", (1.9, 3.4, 3.8), (2.5, 4.6, 1.8), subsurf=2)
    add_box("tail", (0.5, 3.4, 0.5), (2.95, 5.6, 0.45), subsurf=1, rot=(0.0, 0.0, 0.12))
    add_box("tail_tip", (0.55, 1.0, 0.55), (3.25, 3.8, 0.4), subsurf=1)

    # Long front legs with toed paws frame the entrance; keep |x| <= 1.9 free.
    add_box("leg_l", (1.8, 6.4, 2.0), (-2.8, -2.9, 0.6), bevel=0.3)
    add_box("leg_r", (1.8, 6.4, 2.0), (2.8, -2.9, 0.6), bevel=0.3)
    add_box("paw_l", (1.9, 1.8, 1.1), (-2.8, -6.6, 0.15), bevel=0.25)
    add_box("paw_r", (1.9, 1.8, 1.1), (2.8, -6.6, 0.15), bevel=0.25)
    for side in (-1.0, 1.0):
        for toe in (-0.62, 0.0, 0.62):
            add_box("toe", (0.5, 0.9, 1.0), (side * 2.8 + toe, -7.35, 0.1), subsurf=1)

    # Taller oval head; the nemes hood dominates it like the reference:
    # a wide flaring trapezoid behind plus angled side wings that sweep
    # from the crown down toward the shoulders.
    add_box("head", (2.4, 2.1, 3.0), (0.0, -1.7, 7.0), subsurf=2)
    nemes = add_box("nemes", (6.4, 2.6, 3.2), (0.0, -0.9, 6.9), bevel=0.2)
    taper_top(nemes, 0.45, 0.7)
    add_box("wing_l", (0.7, 2.2, 3.8), (-2.35, -1.5, 5.7), bevel=0.15, rot=(0.0, 0.5, 0.0))
    add_box("wing_r", (0.7, 2.2, 3.8), (2.35, -1.5, 5.7), bevel=0.15, rot=(0.0, -0.5, 0.0))

    nose = add_box("nose", (0.4, 0.55, 0.7), (0.0, -2.78, 6.7), subsurf=1)
    taper_top(nose, 0.6, 0.85)

    # Carved face details: they protrude from the head's front surface
    # (y ~ -2.6 after subdivision shrink) so light and shadow model them.
    add_box("brow", (1.9, 0.45, 0.28), (0.0, -2.68, 7.55), subsurf=1)
    add_box("eye_l", (0.5, 0.22, 0.26), (-0.62, -2.7, 7.22), subsurf=1)
    add_box("eye_r", (0.5, 0.22, 0.26), (0.62, -2.7, 7.22), subsurf=1)
    add_box("mouth", (0.78, 0.26, 0.2), (0.0, -2.74, 6.2), subsurf=1)
    add_box("ear_l", (0.28, 0.5, 0.7), (-1.15, -2.0, 7.05), subsurf=1)
    add_box("ear_r", (0.28, 0.5, 0.7), (1.15, -2.0, 7.05), subsurf=1)

    # Nemes band across the forehead with the uraeus sitting on it.
    add_box("band", (2.3, 0.45, 0.45), (0.0, -2.55, 7.9), bevel=0.1)
    add_box("uraeus", (0.22, 0.3, 0.5), (0.0, -2.72, 7.96), subsurf=1)

    # Segmented false beard, flaring wider toward the bottom.
    for i in range(4):
        add_box("beard_seg", (0.34 + i * 0.045, 0.36, 0.3),
                (0.0, -2.62, 5.6 - i * 0.34), bevel=0.05)

    # Nemes lappets falling onto the chest, like the reference statue.
    add_box("lappet_l", (0.9, 0.5, 2.4), (-1.55, -2.75, 5.35), bevel=0.12, rot=(0.12, 0.0, 0.0))
    add_box("lappet_r", (0.9, 0.5, 2.4), (1.55, -2.75, 5.35), bevel=0.12, rot=(0.12, 0.0, 0.0))


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
