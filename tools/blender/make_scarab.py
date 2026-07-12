# Prepares the puzzle-dial scarab ornament from a CC-BY museum scan and
# exports it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_scarab.py -- models/scarab.glb
#
# Source: "Egyptian scarab beetle" by Kudo (sketchfab.com), CC
# Attribution 4.0, committed as requirements/scarab-scan.glb. The
# ~500k-triangle scan is decimated to a few thousand flat-shaded
# triangles and its texture shrunk; the carved stone look survives.
# Origin: center of the base; sized to sit on the dial drum.
import os
import sys
import tempfile

import bpy

SCAN_PATH = "requirements/scarab-scan.glb"
SCARAB_LENGTH = 0.5     # longest side, meters
DECIMATE_RATIO = 0.005  # ~500k -> ~2.5k triangles
TEXTURE_SIZE = 256


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    bpy.ops.import_scene.gltf(filepath=os.path.abspath(SCAN_PATH))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    mesh = bpy.context.active_object
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.data.objects):
        if obj is not mesh:
            bpy.data.objects.remove(obj)

    mod = mesh.modifiers.new("decimate", "DECIMATE")
    mod.ratio = DECIMATE_RATIO
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_flat()

    for material in mesh.data.materials:
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        bsdf = None
        for node in nodes:
            if node.type == "BSDF_PRINCIPLED":
                bsdf = node
        keep = None
        frontier = [bsdf.inputs["Base Color"]]
        seen = set()
        while frontier and keep is None:
            socket = frontier.pop()
            for link in links:
                if link.to_socket == socket:
                    if link.from_node.type == "TEX_IMAGE":
                        keep = link.from_node
                        break
                    if link.from_node not in seen:
                        seen.add(link.from_node)
                        frontier.extend(link.from_node.inputs)
        # bpy wraps the same node in fresh Python objects per access, so
        # identity ("is") never matches — compare with != instead.
        for node in list(nodes):
            if node.type == "TEX_IMAGE" and node != keep:
                nodes.remove(node)
        bsdf.inputs["Roughness"].default_value = 0.8
        if keep is not None:
            links.new(keep.outputs["Color"], bsdf.inputs["Base Color"])
            # Scaling a GLB-embedded image invalidates its packed data
            # and the exporter drops the texture: save the scaled image
            # to a real file so it has a valid source again.
            img = keep.image
            w, h = img.size
            factor = TEXTURE_SIZE / max(w, h)
            img.scale(max(int(w * factor), 8), max(int(h * factor), 8))
            img.filepath_raw = os.path.join(tempfile.gettempdir(),
                    "scarab_basecolor.png")
            img.file_format = "PNG"
            img.save()

    # Recenter (x/y centered, base at z=0) and scale by the longest side.
    xs = [v.co.x for v in mesh.data.vertices]
    ys = [v.co.y for v in mesh.data.vertices]
    zs = [v.co.z for v in mesh.data.vertices]
    s = SCARAB_LENGTH / max(max(xs) - min(xs), max(ys) - min(ys))
    cx = (max(xs) + min(xs)) / 2.0
    cy = (max(ys) + min(ys)) / 2.0
    for v in mesh.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        v.co.z = (v.co.z - min(zs)) * s

    mesh.name = "Scarab"
    print("triangles:", sum(len(p.vertices) - 2 for p in mesh.data.polygons))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            use_selection=True)
    print("exported:", out_path)


main()
