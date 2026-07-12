# Prepares the Nile steamship from a CC-BY model and exports it as GLB
# (the Level-6 jetty boat and the Level-7 credits stage).
#
# Run headless:
#   blender --background --python tools/blender/make_steamship.py -- models/steamship.glb
#
# Source: "Steamship sultana." by Bunnysalad (sketchfab.com), CC
# Attribution 4.0, committed as requirements/steamship-scan.glb. The
# scene ships with a huge water plane and a wake trail — both are
# dropped; the ship itself is flat-colored low poly and needs no
# decimation. Origin: waterline center; sized like the old procedural
# boat so the levels' placements keep working.
import sys

import bpy
from mathutils import Vector

SCAN_PATH = "requirements/steamship-scan.glb"
SHIP_LENGTH = 12.0
HULL_DRAFT = 0.55       # how deep the hull sits below the origin
SCENERY_EXTENT = 5.0    # meshes wider than this are water/wake, not ship


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    import os
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(SCAN_PATH))

    # Drop the water plane and the wake (anything implausibly wide) and
    # the model's blocky smoke puff (a tiny cube floating over the
    # funnels — the game has its own particle smoke).
    meshes = []
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        lo = [1e9, 1e9, 1e9]
        hi = [-1e9, -1e9, -1e9]
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            for k in range(3):
                lo[k] = min(lo[k], w[k])
                hi[k] = max(hi[k], w[k])
        dims = [hi[k] - lo[k] for k in range(3)]
        if dims[0] > SCENERY_EXTENT or dims[1] > SCENERY_EXTENT \
                or max(dims) < 0.15:
            bpy.data.objects.remove(obj)
        else:
            meshes.append(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ship = bpy.context.active_object
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.data.objects):
        if obj is not ship:
            bpy.data.objects.remove(obj)

    # Rescale by length and set the origin: x/y centered, the waterline
    # HULL_DRAFT above the hull bottom. The source bow — the end with the
    # funnels, riverboat-style — points +Y, which the glTF export maps to
    # Godot -Z (the direction the credits boat drives), so no rotation is
    # needed. (The pointed aft deck is the stern; easily mistaken.)
    xs = [v.co.x for v in ship.data.vertices]
    ys = [v.co.y for v in ship.data.vertices]
    zs = [v.co.z for v in ship.data.vertices]
    s = SHIP_LENGTH / max(max(xs) - min(xs), max(ys) - min(ys))
    cx = (max(xs) + min(xs)) / 2.0
    cy = (max(ys) + min(ys)) / 2.0
    for v in ship.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        v.co.z = (v.co.z - min(zs)) * s - HULL_DRAFT

    ship.name = "Ship"
    print("triangles:", sum(len(p.vertices) - 2 for p in ship.data.polygons))
    print("size: %.2f x %.2f x %.2f" % (
            (max(xs) - min(xs)) * s, (max(ys) - min(ys)) * s, (max(zs) - min(zs)) * s))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            use_selection=True)
    print("exported:", out_path)


main()
