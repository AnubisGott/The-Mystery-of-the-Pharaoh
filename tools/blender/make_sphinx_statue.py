"""Convert the Crystal Palace sphinx scan into the Level 1 monument.

Run: blender --background --python tools/blender/make_sphinx_statue.py
Source: "Crystal Palace Sphinx" by artfletch (Sketchfab), CC-BY 4.0,
expected at C:/Users/anubi/Downloads/crystal_palace_sphinx.glb — a
photogrammetry scan of the northernmost Victorian sphinx at Crystal
Palace, London (a copy of the Louvre's red-granite sphinx).

The 2M-triangle scan (18 chunks, one 1024px photo texture) is joined,
decimated to game size with UVs preserved, height-matched to the previous
sphinx and sunk into the sand. The pink-granite photo texture is
desaturated and re-tinted to the mean color of the dune sand and pyramid
sandstone textures so the monument matches the desert. A ground-level
passage is carved through the base between the front paws; the printed
wall/corridor numbers position the doorway, exit sign and win zone at the
chest end of that passage in levels/path.tscn.
"""
import bpy
import numpy as np
import os
from mathutils import Vector

PROJECT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = r"C:\Users\anubi\Downloads\crystal_palace_sphinx.glb"
OLD_GLB = os.path.join(PROJECT, "models", "sphinx.glb")
OUT_GLB = os.path.join(PROJECT, "models", "sphinx_statue.glb")

TARGET_TRIS = 200000
SINK = 0.35  # bury the base bottom below the undulating sand
# Passage carved through the base between the front paws (final coords,
# sand level = 0): x/y/z min..max. Reaches from beyond the base front to
# just before the chest, wide as the paw gap, high enough for the door.
CUT_X = (-0.72, 0.62)
CUT_Y = (-8.5, -2.52)
CUT_Z = (-1.0, 2.6)


def clear_scene() -> None:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def combined_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, world))
            hi = Vector(map(max, hi, world))
    return lo, hi


clear_scene()

# --- the old sphinx defines the target box (front = -Y after import) ----
bpy.ops.import_scene.gltf(filepath=OLD_GLB)
old_lo, old_hi = combined_bbox([o for o in bpy.data.objects if o.type == 'MESH'])
print("OLD bbox lo=%s hi=%s height=%.2f" % (tuple(old_lo), tuple(old_hi), old_hi.z - old_lo.z))
clear_scene()

# --- import the scan, join the chunks ------------------------------------
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
statue = bpy.context.view_layer.objects.active
statue.name = "SphinxStatue"
statue.data.name = "SphinxStatue"
# Detach from the glTF node hierarchy without losing its world transform,
# then bake that transform into the vertices.
world = statue.matrix_world.copy()
statue.parent = None
statue.matrix_world = world
for obj in list(bpy.data.objects):
    if obj is not statue:
        bpy.data.objects.remove(obj)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = statue
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# The scan lies along +X with the head at +X; turn the head to -Y (the
# game front, Godot +Z). glTF imports use quaternion mode, where setting
# rotation_euler would be silently ignored.
statue.rotation_mode = 'XYZ'
statue.rotation_euler.z = -1.5707963
bpy.ops.object.transform_apply(rotation=True)
lo, hi = combined_bbox([statue])
mid = (lo.y + hi.y) / 2.0
front_max = max(v.co.z for v in statue.data.vertices if v.co.y < mid)
back_max = max(v.co.z for v in statue.data.vertices if v.co.y >= mid)
assert front_max > back_max, "head is not at -Y after rotation"

# --- weld the chunk seams, fix normals, then decimate --------------------
# The Sketchfab export splits the scan into 18 chunks with duplicated
# seam vertices; decimating without welding tears the surface apart
# (dark triangle confetti in Godot).
bpy.context.view_layer.objects.active = statue
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
print("after weld: %d tris" % len(statue.data.polygons))

tris = len(statue.data.polygons)
collapse = statue.modifiers.new("collapse", 'DECIMATE')
collapse.decimate_type = 'COLLAPSE'
collapse.ratio = TARGET_TRIS / float(tris)
bpy.ops.object.modifier_apply(modifier=collapse.name)
print("decimated %d -> %d tris" % (tris, len(statue.data.polygons)))

# --- height-match the old sphinx, front aligned, base deck at sand -------
lo, hi = combined_bbox([statue])
scale = (old_hi.z - old_lo.z) / (hi.z - lo.z)
statue.scale = (scale, scale, scale)
bpy.ops.object.transform_apply(scale=True)
# A 10% wider stance; length and height stay true to the scan.
statue.scale = (1.10, 1.0, 1.0)
bpy.ops.object.transform_apply(scale=True)
lo, hi = combined_bbox([statue])
statue.location = Vector((
    (old_lo.x + old_hi.x) / 2.0 - (lo.x + hi.x) / 2.0,
    old_lo.y - lo.y,
    -lo.z - SINK,
))
bpy.ops.object.transform_apply(location=True)

# --- carve the walk-through passage between the front paws ---------------
bpy.ops.mesh.primitive_cube_add(
    location=((CUT_X[0] + CUT_X[1]) / 2.0, (CUT_Y[0] + CUT_Y[1]) / 2.0,
              (CUT_Z[0] + CUT_Z[1]) / 2.0),
    scale=((CUT_X[1] - CUT_X[0]) / 2.0, (CUT_Y[1] - CUT_Y[0]) / 2.0,
           (CUT_Z[1] - CUT_Z[0]) / 2.0))
cutter = bpy.context.active_object
carve = statue.modifiers.new("carve", 'BOOLEAN')
carve.operation = 'DIFFERENCE'
carve.solver = 'EXACT'
carve.object = cutter
bpy.context.view_layer.objects.active = statue
bpy.ops.object.modifier_apply(modifier=carve.name)
bpy.data.objects.remove(cutter)
print("passage carved: %d tris" % len(statue.data.polygons))

# --- re-tint the photo texture to desert sandstone ------------------------
def mean_color(path):
    img = bpy.data.images.load(path)
    buf = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    rgb = buf.reshape(-1, 4)[:, :3].mean(axis=0)
    bpy.data.images.remove(img)
    return rgb


base = (mean_color(os.path.join(PROJECT, "textures", "aerial_sand_diff_1k.jpg"))
        + mean_color(os.path.join(PROJECT, "textures", "old_sandstone_02_diff_1k.jpg"))) / 2.0
# Raw photo-texture means read too pale next to the sun-lit pyramid;
# warm them up but keep the value low — the desert sun adds a lot of
# brightness on top of the albedo.
import colorsys
h, s, v = colorsys.rgb_to_hsv(*base)
tint = np.array(colorsys.hsv_to_rgb(h, s * 0.95, v * 0.55),
                dtype=np.float32)
print("sandstone tint: (%.3f, %.3f, %.3f)" % tuple(tint))

material = statue.data.materials[0]
tex_node = next(n for n in material.node_tree.nodes if n.type == 'TEX_IMAGE')
src_img = tex_node.image
n_px = src_img.size[0] * src_img.size[1]
buf = np.empty(n_px * 4, dtype=np.float32)
src_img.pixels.foreach_get(buf)
px = buf.reshape(-1, 4)
gray = px[:, :3] @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
# Normalize against the statue's surface only: the atlas contains dark
# unused padding that would drag the mean down and leave the visible
# texels far brighter than the tint.
mask = gray > 0.15
gray /= max(gray[mask].mean(), 1e-6)
# The photos baked real-world shading into the albedo (the back of the
# head is nearly black and reads like a wrong shadow in game). Compress
# everything below the mean to 45% of its darkness — deep baked shade
# flattens hard, highlights stay — then re-center on the tint.
gray = np.where(gray < 1.0, 1.0 - (1.0 - gray) * 0.25, gray).astype(np.float32)
gray /= max(gray[mask].mean(), 1e-6)
for c in range(3):
    px[:, c] = np.clip(gray * tint[c], 0.0, 1.0)
tinted = bpy.data.images.new("SphinxSandstone", src_img.size[0], src_img.size[1], alpha=False)
tinted.pixels.foreach_set(np.ascontiguousarray(px).ravel())
tinted.filepath_raw = os.path.join(bpy.app.tempdir, "sphinx_sandstone.png")
tinted.file_format = 'PNG'
tinted.save()
tinted.source = 'FILE'
tinted.filepath = tinted.filepath_raw
tinted.pack()

# Replace the scan's spec-gloss material outright: a plain matte
# Principled setup exports cleanly and adds no sun sheen on top of the
# albedo.
matte = bpy.data.materials.new("SphinxSandstone")
matte.use_nodes = True
new_bsdf = next(n for n in matte.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
new_tex = matte.node_tree.nodes.new('ShaderNodeTexImage')
new_tex.image = tinted
matte.node_tree.links.new(new_tex.outputs['Color'], new_bsdf.inputs['Base Color'])
new_bsdf.inputs['Roughness'].default_value = 1.0
statue.data.materials.clear()
statue.data.materials.append(matte)
print("texture re-tinted")

# --- collision: a simplified twin with Godot's -colonly import hint ------
# The importer turns it into an invisible StaticBody3D trimesh, so the
# player cannot walk through the statue while the passage stays open.
col = statue.copy()
col.data = statue.data.copy()
col.name = "SphinxStatueCol-colonly"
col.data.name = "SphinxStatueCol"
bpy.context.scene.collection.objects.link(col)
col.data.materials.clear()
simplify = col.modifiers.new("simplify", 'DECIMATE')
simplify.decimate_type = 'COLLAPSE'
simplify.ratio = 4000.0 / len(col.data.polygons)
bpy.ops.object.select_all(action='DESELECT')
col.select_set(True)
bpy.context.view_layer.objects.active = col
bpy.ops.object.modifier_apply(modifier=simplify.name)
print("collision mesh: %d tris" % len(col.data.polygons))

# --- report the door geometry (for levels/path.tscn) ----------------------
lo, hi = combined_bbox([statue])
print("NEW bbox lo=(%.2f, %.2f, %.2f) hi=(%.2f, %.2f, %.2f)" % (*lo, *hi))
for h in [0.4, 0.9, 1.4, 1.9, 2.4]:
    hit, loc, _n, _i = statue.ray_cast(Vector((0.0, -14.0, h)), Vector((0, 1, 0)))
    wall = ("y=%.2f (godot z=%.2f)" % (loc.y, -96.9 - loc.y)) if hit else "open"
    print("front wall at h=%.1f: %s" % (h, wall))
probe_y = lo.y + 2.0
for h in [0.5, 1.0, 1.5, 2.0]:
    hit_l, loc_l, _n, _i = statue.ray_cast(Vector((0.0, probe_y, h)), Vector((-1, 0, 0)))
    hit_r, loc_r, _n2, _i2 = statue.ray_cast(Vector((0.0, probe_y, h)), Vector((1, 0, 0)))
    print("corridor at h=%.1f (y=%.1f): x %s .. %s" % (
        h, probe_y,
        ("%.2f" % loc_l.x) if hit_l else "open", ("%.2f" % loc_r.x) if hit_r else "open"))

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.shade_smooth()
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB')
print("EXPORTED", OUT_GLB)
