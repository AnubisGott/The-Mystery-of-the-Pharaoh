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

    # The head (with its own nemes) comes from a CC-BY photogrammetry
    # scan, grafted in import_scan_head().


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


# The head comes from "The Great Sphinx of Giza - Egypt" by Chenzoss
# (sketchfab.com, CC Attribution). The scan is one mesh: crop the head
# region, normalize it, and place it on the shoulders as a SEPARATE
# object so the game keeps its photo texture (the procedural body gets
# the triplanar sandstone override).
SCAN_PATH = "requirements/sphinx-scan.glb"
HEAD_CROP_MIN_Z = 0.47
HEAD_CROP_MAX_Y = 0.40
HEAD_TARGET_WIDTH = 4.6
HEAD_LOCATION = (0.0, -0.45, 5.3)


def import_scan_head() -> None:
    import bmesh

    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SCAN_PATH)
    imported = [o for o in bpy.data.objects if o not in existing]

    head = None
    for obj in imported:
        if obj.type == "MESH":
            head = obj
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    for obj in imported:
        if obj is not head:
            bpy.data.objects.remove(obj)

    bm = bmesh.new()
    bm.from_mesh(head.data)
    doomed = [v for v in bm.verts if v.co.z < HEAD_CROP_MIN_Z or v.co.y > HEAD_CROP_MAX_Y]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(head.data)
    bm.free()

    # Recenter (x centered, y centered, neck bottom at z=0) and scale to
    # the game head size.
    xs = [v.co.x for v in head.data.vertices]
    ys = [v.co.y for v in head.data.vertices]
    zs = [v.co.z for v in head.data.vertices]
    scale = HEAD_TARGET_WIDTH / (max(xs) - min(xs))
    cx = (max(xs) + min(xs)) / 2.0
    cy = (max(ys) + min(ys)) / 2.0
    for v in head.data.vertices:
        v.co.x = (v.co.x - cx) * scale
        v.co.y = (v.co.y - cy) * scale
        v.co.z = (v.co.z - min(zs)) * scale

    head.name = "SphinxHead"
    head.location = HEAD_LOCATION
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    print("head scaled by %.2f, size: %.2f x %.2f x %.2f"
            % (scale, dims[0] * scale, dims[1] * scale, dims[2] * scale))


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()
    build_sphinx()
    apply_modifiers_and_join()
    import_scan_head()
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB")
    print("exported:", out_path)


main()
