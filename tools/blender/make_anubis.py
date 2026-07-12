# Builds the Level-4 Anubis statue (jackal on its pedestal) and exports
# it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_anubis.py -- models/anubis.glb
#
# The mesh is lofted from textures/anubis/Anubis-low-res-all.jpg — a
# four-view artwork sheet: FRONT (top-left), BACK (top-right), SIDE
# facing image-left (bottom-left) and TOP (bottom-right), all on a
# neutral checkerboard, so the subject is segmented by CHROMA.
#
# The pedestal is a vertical loft with boxy rings (front view widths,
# side view depths), textured by projecting the sheet view each face
# points at. The jackal on top is a decimated museum scan: "Statuette
# of a Jackal" by the Art Institute of Chicago (sketchfab.com), CC
# Attribution 4.0, committed as requirements/jackal-scan.glb.
#
# Blender Z-up, the statue faces -Y; the glTF exporter turns -Y into
# +Z, so in Godot it faces +Z. Origin: center of the pedestal base.
import math
import os
import sys

import bmesh
import bpy
import numpy as np

IMAGE_PATH = "textures/anubis/Anubis-low-res-all.jpg"
JACKAL_SCAN = "requirements/jackal-scan.glb"
JACKAL_LENGTH = 1.95    # nose-to-tail, sized to the pedestal top
JACKAL_DECIMATE = 0.12  # ~12.7k -> ~1.5k triangles
TARGET_HEIGHT = 2.6
PED_SECTIONS = 8        # vertical slices of the pedestal loft
RING_POINTS = 12        # vertices per slice ring
TEXTURE_HEIGHT = 256
CHROMA_THRESHOLD = 0.09  # gray background vs. the gold/black statue
UV_INSET = 0.96         # sample slightly inside the outline
PEDESTAL_BOX = 0.35     # superellipse exponent: boxy pedestal rings


class Trace:
    """Subject mask and per-row extents inside one quadrant of the sheet.

    Blender image row 0 is the BOTTOM row, which matches z-up directly.
    """

    def __init__(self, pixels: np.ndarray, cols: tuple, rows: tuple):
        rgb = pixels[:, :, :3]
        chroma = rgb.max(axis=2) - rgb.min(axis=2)
        raw = chroma > CHROMA_THRESHOLD
        raw[:, :cols[0] + 4] = False
        raw[:, cols[1] - 4:] = False
        raw[:rows[0] + 4, :] = False
        raw[rows[1] - 4:, :] = False
        # One-pixel erosion kills JPEG fringe and checkerboard speckle.
        self.bright = raw & np.roll(raw, 1, 0) & np.roll(raw, -1, 0) \
                & np.roll(raw, 1, 1) & np.roll(raw, -1, 1)
        height = self.bright.shape[0]
        span_min = (cols[1] - cols[0]) * 0.02
        self.mins = np.zeros(height, dtype=np.float32)
        self.maxs = np.zeros(height, dtype=np.float32)
        row_list = []
        centers = []
        for r in range(rows[0], rows[1]):
            c = np.where(self.bright[r])[0]
            if c.size > span_min:
                row_list.append(r)
                self.mins[r], self.maxs[r] = c[0], c[-1]
                centers.append((c[0] + c[-1]) / 2.0)
        self.r0, self.r1 = min(row_list), max(row_list)
        self.center = float(np.median(centers))
        for r in range(self.r0 + 1, self.r1 + 1):
            if self.maxs[r] == 0.0:
                self.mins[r], self.maxs[r] = self.mins[r - 1], self.maxs[r - 1]
        self.scale = TARGET_HEIGHT / (self.r1 - self.r0)   # meters per pixel

    def extents(self, frac: float) -> tuple:
        r = int(round(self.r0 + frac * (self.r1 - self.r0)))
        lo = max(r - 2, self.r0)
        hi = min(r + 3, self.r1 + 1)
        left = (self.center - float(np.median(self.mins[lo:hi]))) * self.scale
        right = (float(np.median(self.maxs[lo:hi])) - self.center) * self.scale
        return left, right

    def uv(self, offset: float, frac: float, size: tuple) -> tuple:
        u = (self.center + UV_INSET * offset / self.scale) / size[0]
        v = (self.r0 + frac * (self.r1 - self.r0)) / size[1]
        return u, v

    # Subject bounding box in pixels (columns then rows).
    def bbox(self) -> tuple:
        sel = self.maxs > 0.0
        return (float(self.mins[sel].min()), float(self.maxs.max()),
                float(self.r0), float(self.r1))


def _smooth(values: list) -> list:
    return [float(np.mean(values[max(i - 2, 0):i + 3])) for i in range(len(values))]


# The biggest width step going up the front profile is the pedestal's
# top ledge.
def find_pedestal_top(front: Trace) -> float:
    widths = []
    samples = 40
    for i in range(samples + 1):
        left, right = front.extents(i / samples)
        widths.append(left + right)
    best_i = int(samples * 0.45)
    best_drop = 0.0
    for i in range(int(samples * 0.15), int(samples * 0.75)):
        drop = widths[i] - widths[i + 1]
        if drop > best_drop:
            best_drop = drop
            best_i = i
    return (best_i + 0.5) / samples


def _ring_quads(bm: bmesh.types.BMesh, rings: list) -> None:
    for i in range(len(rings) - 1):
        for j in range(RING_POINTS):
            k = (j + 1) % RING_POINTS
            bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))


def build_pedestal(bm: bmesh.types.BMesh, front: Trace, side: Trace,
        ped_frac: float) -> None:
    rings = []
    for i in range(PED_SECTIONS + 1):
        frac = ped_frac * i / PED_SECTIONS
        left, right = front.extents(frac)
        a = max((left + right) / 2.0, 0.05)
        fwd, back = side.extents(frac)
        cy = (back - fwd) / 2.0
        b = max((fwd + back) / 2.0, 0.05)
        ring = []
        for j in range(RING_POINTS):
            t = math.tau * j / RING_POINTS
            x = a * math.copysign(abs(math.cos(t)) ** PEDESTAL_BOX, math.cos(t))
            y = cy + b * math.copysign(abs(math.sin(t)) ** PEDESTAL_BOX, math.sin(t))
            ring.append(bm.verts.new((x, y, frac * TARGET_HEIGHT)))
        rings.append(ring)
    _ring_quads(bm, rings)
    bm.faces.new(reversed(rings[0]))
    bm.faces.new(rings[-1])   # the pedestal's visible gold top


def _gold_material() -> bpy.types.Material:
    gold = bpy.data.materials.new("anubis_gold")
    gold.use_nodes = True
    bsdf = gold.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.68, 0.35, 0.05, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Metallic"].default_value = 0.6
    return gold


# Centroid and points of the mesh vertices inside a z band (optionally
# one x side only) — used to find the neck and the ears.
def _zone(mesh: bpy.types.Object, z_lo: float, z_hi: float,
        x_sign: float = 0.0) -> tuple:
    pts = [v.co.copy() for v in mesh.data.vertices
            if z_lo <= v.co.z <= z_hi and v.co.x * x_sign >= 0.0]
    n = len(pts)
    center = (sum(p.x for p in pts) / n, sum(p.y for p in pts) / n,
            sum(p.z for p in pts) / n)
    return center, pts


# The lying jackal from the museum scan: decimated, recolored deep
# black, rescaled onto the pedestal top (z0), and dressed with a gold
# collar and gold inner-ear inlays fitted to the detected neck/ears.
# The scan already faces -Y like the rest of the project.
def build_jackal(z0: float) -> list:
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(JACKAL_SCAN))
    imported = [o for o in bpy.data.objects if o not in existing]
    mesh = None
    for obj in imported:
        if obj.type == "MESH":
            mesh = obj
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in imported:
        if obj is not mesh:
            bpy.data.objects.remove(obj)

    mod = mesh.modifiers.new("decimate", "DECIMATE")
    mod.ratio = JACKAL_DECIMATE
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_flat()

    # Deep black instead of the scan's bronze patina.
    mesh.data.materials.clear()
    black = bpy.data.materials.new("anubis_body")
    black.use_nodes = True
    bsdf = black.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.012, 0.011, 0.012, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.4
    mesh.data.materials.append(black)

    # Rescale to the pedestal (x/y centered, paws at z0).
    xs = [v.co.x for v in mesh.data.vertices]
    ys = [v.co.y for v in mesh.data.vertices]
    zs = [v.co.z for v in mesh.data.vertices]
    s = JACKAL_LENGTH / (max(ys) - min(ys))
    cx = (max(xs) + min(xs)) / 2.0
    cy = (max(ys) + min(ys)) / 2.0
    for v in mesh.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        v.co.z = (v.co.z - min(zs)) * s + z0
    parts = [mesh]
    gold = _gold_material()
    height = max(v.co.z for v in mesh.data.vertices) - z0

    # The collar is PAINTED: the jackal's own faces in a band around
    # the neck get the gold material, like the ear inlays' painted-on
    # look. The z band also crosses the snout tip (in front) and the
    # long back (behind): split it into clusters along y and take the
    # first SUBSTANTIAL one — the snout is a handful of points, the
    # neck a real cross-section.
    def neck_band(z_lo: float, z_hi: float) -> tuple:
        _, pts = _zone(mesh, z_lo, z_hi)
        pts.sort(key=lambda p: p.y)
        clusters = [[pts[0]]]
        for p in pts[1:]:
            if p.y - clusters[-1][-1].y > 0.1:
                clusters.append([])
            clusters[-1].append(p)
        neck = next((c for c in clusters if len(c) >= 20),
                max(clusters, key=len))
        n = len(neck)
        center = (sum(p.x for p in neck) / n, sum(p.y for p in neck) / n,
                sum(p.z for p in neck) / n)
        return center, neck

    mesh.data.materials.append(gold)   # slot 1 on the jackal itself
    band_lo = z0 + 0.48 * height
    band_hi = z0 + 0.60 * height
    neck_c, neck_pts = neck_band(band_lo, band_hi)
    radius = max(math.hypot(p.x - neck_c[0], p.y - neck_c[1]) for p in neck_pts)
    for poly in mesh.data.polygons:
        pc = poly.center
        if band_lo <= pc.z <= band_hi \
                and math.hypot(pc.x - neck_c[0], pc.y - neck_c[1]) <= radius * 1.25:
            poly.material_index = 1

    # Golden inner ears: rounded inlays sunk into each ear's front
    # face, tilted with the ear.
    for sign in (-1.0, 1.0):
        lo_ear, _ = _zone(mesh, z0 + 0.80 * height, z0 + 0.9 * height, sign)
        hi_ear, _ = _zone(mesh, z0 + 0.9 * height, z0 + height, sign)
        ear_c, ear_pts = _zone(mesh, z0 + 0.80 * height, z0 + height, sign)
        ear_tilt = math.atan2(-(hi_ear[1] - lo_ear[1]), hi_ear[2] - lo_ear[2])
        width = (max(p.x for p in ear_pts) - min(p.x for p in ear_pts)) * 0.4
        tall = (max(p.z for p in ear_pts) - min(p.z for p in ear_pts)) * 0.55
        mid = [p for p in ear_pts if abs(p.z - ear_c[2]) < 0.08]
        front_y = min(p.y for p in mid)
        bpy.ops.mesh.primitive_cube_add(size=1,
                location=(ear_c[0], front_y + 0.015, ear_c[2]),
                rotation=(ear_tilt, 0.0, 0.0))
        inlay = bpy.context.active_object
        inlay.name = "ear_inlay"
        inlay.scale = (width, 0.04, tall)
        bpy.ops.object.transform_apply(scale=True)
        inlay.data.materials.append(gold)
        sub = inlay.modifiers.new("subsurf", "SUBSURF")
        sub.levels = 1
        bpy.ops.object.shade_smooth()
        bpy.context.view_layer.objects.active = inlay
        bpy.ops.object.modifier_apply(modifier=sub.name)
        parts.append(inlay)
    return parts


# Each face samples the sheet quadrant it points at. The top view maps
# by the statue's footprint: its columns run along the body (head at
# image-right), its rows across the width.
def project_uvs(bm: bmesh.types.BMesh, front: Trace, back: Trace,
        side: Trace, top: Trace, size: tuple) -> None:
    t_c0, t_c1, t_r0, t_r1 = top.bbox()
    max_depth = 0.0
    max_width = 0.0
    for i in range(21):
        left, right = side.extents(i / 20.0)
        max_depth = max(max_depth, left + right)
        left, right = front.extents(i / 20.0)
        max_width = max(max_width, left + right)
    len_scale = (t_c1 - t_c0) / max_depth    # pixels per meter along the body
    wid_scale = (t_r1 - t_r0) / max_width

    uv_layer = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            frac = min(max(co.z / TARGET_HEIGHT, 0.0), 1.0)
            if az >= ax and az >= ay:
                u = ((t_c0 + t_c1) / 2.0 - co.y * len_scale * UV_INSET) / size[0]
                v = ((t_r0 + t_r1) / 2.0 + co.x * wid_scale * UV_INSET) / size[1]
                loop[uv_layer].uv = (u, v)
            elif ax > ay:
                loop[uv_layer].uv = side.uv(co.y, frac, size)
            elif n.y < 0.0:
                loop[uv_layer].uv = front.uv(co.x, frac, size)
            else:
                loop[uv_layer].uv = back.uv(-co.x, frac, size)


def restyle_image(img: bpy.types.Image) -> None:
    w, h = img.size
    img.scale(max(int(w * TEXTURE_HEIGHT / h), 8), TEXTURE_HEIGHT)
    img.pack()


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    img = bpy.data.images.load(os.path.abspath(IMAGE_PATH))
    size = (img.size[0], img.size[1])
    pixels = np.array(img.pixels[:], dtype=np.float32).reshape(size[1], size[0], 4)
    half_x = size[0] // 2
    half_y = size[1] // 2
    # Sheet layout (Blender rows count from the bottom): FRONT top-left,
    # BACK top-right, SIDE bottom-left, TOP bottom-right.
    front = Trace(pixels, cols=(0, half_x), rows=(half_y, size[1]))
    back = Trace(pixels, cols=(half_x, size[0]), rows=(half_y, size[1]))
    side = Trace(pixels, cols=(0, half_x), rows=(0, half_y))
    top = Trace(pixels, cols=(half_x, size[0]), rows=(0, half_y))

    ped_frac = find_pedestal_top(front)
    bm = bmesh.new()
    build_pedestal(bm, front, side, ped_frac)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    project_uvs(bm, front, back, side, top, size)

    mesh_data = bpy.data.meshes.new("Anubis")
    bm.to_mesh(mesh_data)
    bm.free()
    pedestal = bpy.data.objects.new("Anubis", mesh_data)
    bpy.context.collection.objects.link(pedestal)

    restyle_image(img)
    material = bpy.data.materials.new("anubis_paint")
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.1
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mesh_data.materials.append(material)

    jackal_parts = build_jackal(ped_frac * TARGET_HEIGHT)

    bpy.ops.object.select_all(action="DESELECT")
    pedestal.select_set(True)
    for part in jackal_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = pedestal
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = "Anubis"
    print("pedestal top fraction: %.2f" % ped_frac)
    print("triangles:", sum(len(p.vertices) - 2 for p in mesh_data.polygons))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            use_selection=True)
    print("exported:", out_path)


main()
