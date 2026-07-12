# Builds the Level-4 Bastet cat statue and exports it as GLB — the
# counterpart to the Anubis statue on the other side of the sarcophagus.
# The cat stands on a plain stone dais built by the level (like the
# sarcophagus's), so the model is just the cat itself.
#
# Run headless:
#   blender --background --python tools/blender/make_cat.py -- models/cat.glb
#
# The cat is a lightly decimated CC-BY model: "Egyptian Cat Statue" by
# Ankledot (sketchfab.com), committed as requirements/cat-scan.glb —
# already black with gold engravings, so its own texture is kept
# (shrunk; the normal/metallic maps are dropped).
#
# The scan faces -Y in Blender; the glTF exporter turns -Y into +Z, so
# in Godot it faces +Z. Origin: center of the base.
import os
import sys
import tempfile

import bpy

CAT_SCAN = "requirements/cat-scan.glb"
CAT_HEIGHT = 1.9
CAT_DECIMATE = 0.5      # ~4.6k -> ~2.3k triangles
TEXTURE_HEIGHT = 256


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    bpy.ops.import_scene.gltf(filepath=os.path.abspath(CAT_SCAN))
    mesh = None
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            mesh = obj
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.data.objects):
        if obj is not mesh:
            bpy.data.objects.remove(obj)

    mod = mesh.modifiers.new("decimate", "DECIMATE")
    mod.ratio = CAT_DECIMATE
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_flat()

    for material in mesh.data.materials:
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        bsdf = None
        for node in nodes:
            if node.type == "BSDF_PRINCIPLED":
                bsdf = node
        # The base-color texture may sit behind mix nodes: walk the
        # links upstream from Base Color until an image turns up.
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
        bsdf.inputs["Roughness"].default_value = 0.45
        if keep is not None:
            links.new(keep.outputs["Color"], bsdf.inputs["Base Color"])
            # Scaling a GLB-embedded image invalidates its packed data
            # and the exporter drops the texture: save the scaled image
            # to a real file so it has a valid source again.
            img = keep.image
            w, h = img.size
            factor = TEXTURE_HEIGHT / max(w, h)
            img.scale(max(int(w * factor), 8), max(int(h * factor), 8))
            img.filepath_raw = os.path.join(tempfile.gettempdir(),
                    "cat_basecolor.png")
            img.file_format = "PNG"
            img.save()

    # Recenter (x/y centered, base at z=0) and scale to the game height.
    xs = [v.co.x for v in mesh.data.vertices]
    ys = [v.co.y for v in mesh.data.vertices]
    zs = [v.co.z for v in mesh.data.vertices]
    s = CAT_HEIGHT / (max(zs) - min(zs))
    cx = (max(xs) + min(xs)) / 2.0
    cy = (max(ys) + min(ys)) / 2.0
    for v in mesh.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        v.co.z = (v.co.z - min(zs)) * s

    mesh.name = "Cat"
    print("triangles:", sum(len(p.vertices) - 2 for p in mesh.data.polygons))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            use_selection=True)
    print("exported:", out_path)


main()
