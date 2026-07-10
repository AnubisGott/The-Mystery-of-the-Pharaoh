# Builds a stylized adventurer figure and exports it as GLB.
#
# Run headless:
#   blender --background --python tools/blender/make_adventurer.py -- models/adventurer.glb
#
# Coordinates: Blender Z-up, the figure faces +Y (glTF export maps that to
# Godot -Z, the player's forward direction; the camera sits behind at +Z).
# Limb objects keep their origin at the joint (hip/shoulder) so the game
# can swing them by rotating the imported nodes. Ground is z=0; the game
# places the model so z=0 sits on the capsule bottom.
import sys

import bpy


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def material(name: str, rgb: tuple, roughness: float = 0.9) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    # Colors are given as familiar sRGB values; the shader wants linear.
    linear = tuple(c ** 2.2 for c in rgb)
    bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def finish(obj: bpy.types.Object, name: str, mat: bpy.types.Material,
		origin: tuple = None, bevel: float = 0.0) -> bpy.types.Object:
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(scale=True)

    if bevel > 0.0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier="bevel")
    bpy.ops.object.shade_auto_smooth(angle=1.0)

    if origin is not None:
        bpy.context.scene.cursor.location = origin
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return obj


def box(name: str, dims: tuple, loc: tuple, mat: bpy.types.Material,
		origin: tuple = None, bevel: float = 0.0) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.scale = dims
    return finish(obj, name, mat, origin, bevel)


def cylinder(name: str, radius: float, depth: float, loc: tuple,
		mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=24, location=loc)
    obj = bpy.context.active_object
    return finish(obj, name, mat, None, 0.0)


def build_adventurer() -> None:
    pants = material("pants", (0.35, 0.24, 0.15))
    shirt = material("shirt", (0.62, 0.48, 0.28))
    skin = material("skin", (0.85, 0.62, 0.45))
    hat = material("hat", (0.38, 0.23, 0.11))
    leather = material("leather", (0.45, 0.28, 0.14))

    # Legs pivot at the hips (z=0.9), arms at the shoulders (z=1.62).
    box("LegL", (0.26, 0.3, 0.86), (-0.17, 0.0, 0.47), pants, origin=(-0.17, 0.0, 0.9), bevel=0.05)
    box("LegR", (0.26, 0.3, 0.86), (0.17, 0.0, 0.47), pants, origin=(0.17, 0.0, 0.9), bevel=0.05)
    box("Torso", (0.68, 0.42, 0.78), (0.0, 0.0, 1.27), shirt, bevel=0.09)
    box("ArmL", (0.17, 0.22, 0.68), (-0.45, 0.0, 1.29), shirt, origin=(-0.45, 0.0, 1.62), bevel=0.05)
    box("ArmR", (0.17, 0.22, 0.68), (0.45, 0.0, 1.29), shirt, origin=(0.45, 0.0, 1.62), bevel=0.05)
    box("Head", (0.4, 0.38, 0.42), (0.0, 0.02, 1.9), skin, bevel=0.11)
    box("Backpack", (0.5, 0.24, 0.56), (0.0, -0.34, 1.32), leather, bevel=0.07)
    cylinder("HatBrim", 0.36, 0.06, (0.0, 0.03, 2.13), hat)
    cylinder("HatCrown", 0.21, 0.2, (0.0, 0.03, 2.23), hat)


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()
    build_adventurer()
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB")
    print("exported:", out_path)


main()
