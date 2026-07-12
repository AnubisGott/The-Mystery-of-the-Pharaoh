# Builds the Level-4 sarcophagus of Tut-Ench-Amun and exports it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_sarcophagus.py -- models/sarcophagus.glb
#
# The mesh is lofted from textures/frontAndSideView-TAAS.jpg — a single
# stylized artwork holding the FRONT view in its left half and the SIDE
# view (statue facing image-right) in its right half. The front half
# gives the width profile, the side half the depth profile (face and
# feet jut forward, the back is flat). The same image is the texture:
# front/back faces project from the left half, flanks from the right
# half. The background is a neutral checkerboard, so the subject is
# segmented by CHROMA, not brightness.
#
# Blender Z-up, the statue faces -Y; the glTF exporter turns -Y into +Z,
# so in Godot it faces +Z — toward the player entering the burial
# chamber. Origin: center of the base.
import math
import os
import sys

import bmesh
import bpy
import numpy as np

IMAGE_PATH = "textures/frontAndSideView-TAAS.jpg"
TARGET_HEIGHT = 3.2
SECTIONS = 30           # horizontal slices of the loft
RING_POINTS = 12        # vertices per slice ring
TEXTURE_HEIGHT = 256
CHROMA_THRESHOLD = 0.09  # gray background vs. the gold/teal statue
UV_INSET = 0.96         # sample slightly inside the outline
DESATURATE = 0.0        # the artwork already matches the game palette
GAMMA = 1.0
GAIN = 1.0


class Trace:
    """Per-row [min, max] pixel columns of the colorful subject inside
    one column range of the image.

    Blender image row 0 is the BOTTOM row, which matches z-up directly.
    """

    def __init__(self, pixels: np.ndarray, cols: tuple, bottom_trim: float = 0.1):
        rgb = pixels[:, :, :3]
        chroma = rgb.max(axis=2) - rgb.min(axis=2)
        raw = chroma > CHROMA_THRESHOLD
        # Keep only this view's half, kill borders, then erode one pixel
        # so JPEG fringe and speckle cannot widen the outline.
        raw[:, :cols[0]] = False
        raw[:, cols[1]:] = False
        raw[:4, :] = False
        raw[-4:, :] = False
        bright = raw & np.roll(raw, 1, 0) & np.roll(raw, -1, 0) \
                & np.roll(raw, 1, 1) & np.roll(raw, -1, 1)
        height = bright.shape[0]
        span_min = (cols[1] - cols[0]) * 0.03
        self.mins = np.zeros(height, dtype=np.float32)
        self.maxs = np.zeros(height, dtype=np.float32)
        rows = []
        centers = []
        for r in range(height):
            c = np.where(bright[r])[0]
            if c.size > span_min:
                rows.append(r)
                self.mins[r], self.maxs[r] = c[0], c[-1]
                centers.append((c[0] + c[-1]) / 2.0)
        self.r0, self.r1 = min(rows), max(rows)
        self.center = float(np.median(centers))
        # Dark rows inside the subject left zeros behind; fill them from
        # the row below so the medians never mix in "width 0" rows.
        for r in range(self.r0 + 1, self.r1 + 1):
            if self.maxs[r] == 0.0:
                self.mins[r], self.maxs[r] = self.mins[r - 1], self.maxs[r - 1]
        # Trim any thin tail (shadows, ground reflections).
        spans = self.maxs - self.mins
        max_span = float(spans.max())
        while spans[self.r0] < max_span * bottom_trim:
            self.r0 += 1
        while spans[self.r1] < max_span * 0.03:
            self.r1 -= 1
        self.scale = TARGET_HEIGHT / (self.r1 - self.r0)   # meters per pixel

    # Median-smoothed [left, right] extents (meters off-axis) at a
    # 0..1 height fraction.
    def extents(self, frac: float) -> tuple:
        r = int(round(self.r0 + frac * (self.r1 - self.r0)))
        lo = max(r - 2, self.r0)
        hi = min(r + 3, self.r1 + 1)
        left = (self.center - float(np.median(self.mins[lo:hi]))) * self.scale
        right = (float(np.median(self.maxs[lo:hi])) - self.center) * self.scale
        return left, right

    # Image-space UV for a world offset (meters off-axis, sign flipped
    # for the side view where the statue faces image-right) and height.
    def uv(self, offset: float, frac: float, size: tuple) -> tuple:
        u = (self.center + UV_INSET * offset / self.scale) / size[0]
        v = (self.r0 + frac * (self.r1 - self.r0)) / size[1]
        return u, v


def _smooth(values: list) -> list:
    return [float(np.mean(values[max(i - 2, 0):i + 3])) for i in range(len(values))]


def build_mesh(front: Trace, side: Trace) -> bmesh.types.BMesh:
    # Sample both profiles per section, then smooth across sections:
    # spiky rows otherwise turn into shelves, and rows whose side
    # silhouette sits off-axis pinch the ring into a black disk.
    widths = []
    fwds = []
    backs = []
    for i in range(SECTIONS + 1):
        frac = i / SECTIONS
        left, right = front.extents(frac)
        widths.append((left + right) / 2.0)
        # The side view faces image-RIGHT: its right edge is the front.
        back, fwd = side.extents(frac)
        fwds.append(fwd)
        backs.append(back)
    widths = _smooth(widths)
    fwds = _smooth(fwds)
    backs = _smooth(backs)

    bm = bmesh.new()
    rings = []
    for i in range(SECTIONS + 1):
        frac = i / SECTIONS
        a = max(widths[i], 0.03)
        fwd = max(fwds[i], 0.03)
        back = max(backs[i], 0.03)
        cy = (back - fwd) / 2.0
        b = max((fwd + back) / 2.0, a * 0.25, 0.05)
        ring = []
        for j in range(RING_POINTS):
            t = math.tau * j / RING_POINTS
            ring.append(bm.verts.new(
                    (a * math.cos(t), cy + b * math.sin(t), frac * TARGET_HEIGHT)))
        rings.append(ring)

    for i in range(SECTIONS):
        for j in range(RING_POINTS):
            k = (j + 1) % RING_POINTS
            bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    bm.faces.new(reversed(rings[0]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# Every face projects from the view it points at: flank faces from the
# side half, the rest from the front half (the back gets the mirrored
# front). One shared texture, so the seams stay quiet.
def project_uvs(bm: bmesh.types.BMesh, front: Trace, side: Trace,
        size: tuple) -> None:
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        # Flank faces point along X (the statue faces -Y).
        sideways = abs(face.normal.x) > abs(face.normal.y)
        for loop in face.loops:
            co = loop.vert.co
            frac = co.z / TARGET_HEIGHT
            if sideways:
                # Image-right is the statue's front (-Y): flip the sign.
                loop[uv_layer].uv = side.uv(-co.y, frac, size)
            else:
                loop[uv_layer].uv = front.uv(co.x, frac, size)


def restyle_image(img: bpy.types.Image) -> None:
    w, h = img.size
    img.scale(max(int(w * TEXTURE_HEIGHT / h), 8), TEXTURE_HEIGHT)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = np.clip(np.clip(px[:, :3], 0.0, 1.0) ** GAMMA * GAIN, 0.0, 1.0)
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    px[:, :3] = rgb * (1.0 - DESATURATE) + luminance[:, None] * DESATURATE
    img.pixels.foreach_set(px.ravel())
    img.pack()


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    img = bpy.data.images.load(os.path.abspath(IMAGE_PATH))
    size = (img.size[0], img.size[1])
    pixels = np.array(img.pixels[:], dtype=np.float32).reshape(size[1], size[0], 4)
    half = size[0] // 2
    front = Trace(pixels, cols=(0, half))
    side = Trace(pixels, cols=(half, size[0]))

    bm = build_mesh(front, side)
    project_uvs(bm, front, side, size)
    mesh_data = bpy.data.meshes.new("Sarcophagus")
    bm.to_mesh(mesh_data)
    bm.free()
    obj = bpy.data.objects.new("Sarcophagus", mesh_data)
    bpy.context.collection.objects.link(obj)

    restyle_image(img)
    material = bpy.data.materials.new("sarcophagus_paint")
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.1
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mesh_data.materials.append(material)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    print("triangles:", sum(len(p.vertices) - 2 for p in mesh_data.polygons))
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            use_selection=True)
    print("exported:", out_path)


main()
