# Builds a stylized archaeologist on the KayKit Adventurers rig (CC0,
# tools/blender/assets/kaykit_rig.glb) and exports it as GLB, keeping the
# pack's professional animations (Idle, Walking_A, Running_A, Jump_*,
# Death_A/B, Hit_A) and deriving the two missing crouch clips from
# Idle/Walking_A.
#
# Run headless:
#   blender --background --python tools/blender/make_adventurer.py -- models/adventurer.glb
#
# Coordinates: Blender Z-up. The KayKit rig faces -Y and is kept that way:
# rotating the armature corrupts the bone-local animation data (Z-aligned
# bones keep their roll, so their frames do not follow the flip). The
# meshes are therefore built facing -Y too, and player.tscn turns the
# whole Visual node 180 degrees so the character faces Godot's -Z.
# Ground is z=0. Mesh parts are rigid-skinned: one vertex group per part,
# named after the bone that drives it. Object transforms are applied so
# vertex data lives in armature space (skinned meshes with non-identity
# object transforms export unreliably).
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion

RIG_ASSET = os.path.join(os.path.dirname(os.path.abspath(__file__)),
        "assets", "kaykit_rig.glb")

# Animations kept in the export; everything else in the pack is pruned to
# keep the GLB small. Death_A falls backwards, Death_B falls forwards.
KEEP_ACTIONS = (
    "Idle", "Walking_A", "Running_A",
    "Jump_Start", "Jump_Idle", "Jump_Land",
    "Death_A", "Death_B", "Hit_A", "T-Pose",
    "Crouch_Idle", "Crouch_Walk",
)


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
    # Viewport display color so Workbench preview renders show the palette.
    mat.diffuse_color = (*linear, 1.0)
    return mat


def finish(obj: bpy.types.Object, name: str, mat: bpy.types.Material,
        bevel: float = 0.0) -> bpy.types.Object:
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if bevel > 0.0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier="bevel")
    bpy.ops.object.shade_auto_smooth(angle=1.0)
    return obj


def box(name: str, dims: tuple, loc: tuple, mat: bpy.types.Material,
        bevel: float = 0.0, rot: tuple = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = dims
    return finish(obj, name, mat, bevel)


def cylinder(name: str, radius: float, depth: float, loc: tuple,
        mat: bpy.types.Material, rot: tuple = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=24,
            location=loc, rotation=rot)
    obj = bpy.context.active_object
    return finish(obj, name, mat)


def torus(name: str, major: float, minor: float, loc: tuple,
        mat: bpy.types.Material, rot: tuple = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
            location=loc, rotation=rot, major_segments=20, minor_segments=8)
    obj = bpy.context.active_object
    return finish(obj, name, mat)


def skin_to_bone(obj: bpy.types.Object, arm: bpy.types.Object, bone: str) -> None:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("skin", "ARMATURE")
    mod.object = arm
    obj.parent = arm


def import_rig() -> bpy.types.Object:
    bpy.ops.import_scene.gltf(filepath=RIG_ASSET)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

    # Drop the Rogue's meshes and weapons; only skeleton + actions stay.
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        bpy.data.objects.remove(obj, do_unlink=True)
    return arm


def build_archaeologist(arm: bpy.types.Object) -> None:
    # Palette: khaki explorer clothes, brown leather, sun-tanned skin.
    shirt = material("shirt", (0.76, 0.65, 0.44))
    pants = material("pants", (0.45, 0.38, 0.24))
    vest = material("vest", (0.35, 0.22, 0.12))
    leather = material("leather", (0.42, 0.26, 0.13))
    boots = material("boots", (0.24, 0.15, 0.09))
    sole = material("sole", (0.13, 0.09, 0.06))
    skin = material("skin", (0.85, 0.62, 0.45))
    stubble = material("stubble", (0.58, 0.42, 0.31))
    eyes = material("eyes", (0.10, 0.08, 0.07), roughness=0.4)
    hat = material("hat", (0.38, 0.23, 0.11))
    hatband = material("hatband", (0.19, 0.11, 0.06))
    brass = material("brass", (0.71, 0.56, 0.22), roughness=0.4)
    canteen = material("canteen", (0.48, 0.50, 0.52), roughness=0.5)
    rope = material("rope", (0.72, 0.60, 0.40))

    def part(obj: bpy.types.Object, bone: str) -> None:
        skin_to_bone(obj, arm, bone)

    # The rig faces -Y, so "front" coordinates below are negative Y.
    # --- legs & boots (hip joints at z=0.519, knees 0.292, ankles 0.145)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        x = 0.171 * sx
        part(box(f"Thigh{side}", (0.19, 0.22, 0.26), (x, 0.0, 0.41), pants,
                bevel=0.03), f"upperleg.{side.lower()}")
        part(box(f"BootShaft{side}", (0.17, 0.20, 0.18), (x, -0.01, 0.22), boots,
                bevel=0.03), f"lowerleg.{side.lower()}")
        part(box(f"Boot{side}", (0.16, 0.34, 0.10), (x, -0.07, 0.085), boots,
                bevel=0.03), f"foot.{side.lower()}")
        part(box(f"Sole{side}", (0.17, 0.36, 0.04), (x, -0.07, 0.02), sole,
                bevel=0.01), f"foot.{side.lower()}")

    # --- pelvis, belt with gear (hips bone head z=0.406)
    part(box("Hips", (0.40, 0.26, 0.20), (0.0, 0.0, 0.50), pants, bevel=0.04), "hips")
    part(box("Belt", (0.42, 0.28, 0.07), (0.0, 0.0, 0.615), leather, bevel=0.02), "hips")
    part(box("Buckle", (0.07, 0.03, 0.05), (0.0, -0.145, 0.615), brass, bevel=0.01), "hips")
    part(box("PouchL", (0.10, 0.06, 0.11), (0.13, -0.15, 0.56), leather, bevel=0.02), "hips")
    part(box("PouchR", (0.10, 0.06, 0.11), (-0.13, -0.15, 0.56), leather, bevel=0.02), "hips")
    part(cylinder("Canteen", 0.07, 0.10, (-0.24, 0.0, 0.57), canteen,
            rot=(0.0, math.pi / 2.0, 0.0)), "hips")
    part(torus("RopeCoil", 0.09, 0.03, (0.0, 0.17, 0.55), rope,
            rot=(math.pi / 2.0, 0.0, 0.0)), "hips")
    # Satchel bag hanging on the right hip, strap runs over the torso.
    part(box("Satchel", (0.20, 0.10, 0.17), (0.24, -0.06, 0.52), leather,
            bevel=0.03), "hips")

    # --- torso (spine 0.598-0.973, chest 0.973-1.224)
    part(box("TorsoLower", (0.44, 0.27, 0.37), (0.0, 0.0, 0.79), shirt,
            bevel=0.05), "spine")
    part(box("TorsoUpper", (0.50, 0.29, 0.28), (0.0, 0.0, 1.10), shirt,
            bevel=0.05), "chest")
    # Open vest: two front panels and a back panel, slightly proud of the shirt.
    part(box("VestFrontL", (0.16, 0.035, 0.30), (0.15, -0.15, 1.08), vest,
            bevel=0.02), "chest")
    part(box("VestFrontR", (0.16, 0.035, 0.30), (-0.15, -0.15, 1.08), vest,
            bevel=0.02), "chest")
    part(box("VestBack", (0.46, 0.035, 0.30), (0.0, 0.155, 1.08), vest,
            bevel=0.02), "chest")
    # Satchel strap across the chest (left shoulder to right hip).
    part(box("StrapFront", (0.06, 0.03, 0.42), (0.0, -0.16, 1.05), leather,
            rot=(0.0, -0.5, 0.0)), "chest")
    part(box("StrapBack", (0.06, 0.03, 0.42), (0.0, 0.16, 1.05), leather,
            rot=(0.0, 0.5, 0.0)), "chest")
    part(cylinder("Neck", 0.07, 0.09, (0.0, 0.0, 1.26), skin), "chest")

    # --- arms (T-pose along X: shoulders +-0.212, elbows 0.454, wrists 0.787)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        lo = side.lower()
        part(box(f"Sleeve{side}", (0.21, 0.17, 0.17), (0.32 * sx, -0.007, 1.107),
                shirt, bevel=0.03), f"upperarm.{lo}")
        part(box(f"Cuff{side}", (0.06, 0.19, 0.19), (0.44 * sx, -0.007, 1.107),
                shirt, bevel=0.02), f"upperarm.{lo}")
        part(box(f"Forearm{side}", (0.30, 0.13, 0.13), (0.615 * sx, -0.007, 1.107),
                skin, bevel=0.03), f"lowerarm.{lo}")
        part(box(f"Hand{side}", (0.13, 0.15, 0.15), (0.855 * sx, 0.0, 1.107),
                skin, bevel=0.03), f"hand.{lo}")

    # --- head & fedora (head bone 1.241-1.492)
    part(box("Head", (0.34, 0.34, 0.38), (0.0, -0.02, 1.46), skin, bevel=0.06), "head")
    part(box("Jaw", (0.35, 0.35, 0.11), (0.0, -0.02, 1.33), stubble, bevel=0.03), "head")
    part(box("EyeL", (0.05, 0.02, 0.06), (0.075, -0.185, 1.50), eyes), "head")
    part(box("EyeR", (0.05, 0.02, 0.06), (-0.075, -0.185, 1.50), eyes), "head")
    part(cylinder("HatBrim", 0.31, 0.05, (0.0, -0.02, 1.645), hat), "head")
    part(cylinder("HatCrown", 0.19, 0.17, (0.0, -0.02, 1.74), hat), "head")
    part(cylinder("HatBand", 0.20, 0.05, (0.0, -0.02, 1.685), hatband), "head")


def action_fcurves(action: bpy.types.Action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def bone_local_delta(arm: bpy.types.Object, bone: str,
        world_x_degrees: float) -> Quaternion:
    # Convert "rotate this bone by an angle around the world X axis" into
    # the bone's rest-local frame, so left/right bones with mirrored axes
    # get the correct sign automatically.
    rest = arm.data.bones[bone].matrix_local.to_3x3()
    world = Matrix.Rotation(math.radians(world_x_degrees), 3, "X")
    return (rest.inverted() @ world @ rest).to_quaternion()


# The crouch pose, as per-bone rotations around the world X axis (the
# character faces -Y, so negative angles pitch things forward). Legs and
# spine animate around the same axes in the source clips, so composing the
# offsets with the existing keyframes is order-independent.
CROUCH_DROP = 0.10  # hips down, along the hips bone's local Y (world up)
CROUCH_POSE = {
    "upperleg.l": -50.0, "upperleg.r": -50.0,  # thighs forward
    "lowerleg.l": 75.0, "lowerleg.r": 75.0,    # knees bent back
    "foot.l": -25.0, "foot.r": -25.0,          # feet back to level
    "chest": 14.0,                             # lean forward
    "head": -12.0,                             # keep looking ahead
}


def derive_crouch_action(arm: bpy.types.Object, source: str, name: str) -> None:
    src = bpy.data.actions[source]
    act = src.copy()
    act.name = name

    # Group the copied fcurves per bone/property for keyframe surgery.
    curves = {}
    for fc in action_fcurves(act):
        curves.setdefault((fc.data_path, fc.array_index), fc)

    hips_up = curves.get(('pose.bones["hips"].location', 1))
    if hips_up is not None:
        for kp in hips_up.keyframe_points:
            kp.co[1] -= CROUCH_DROP
        hips_up.update()

    for bone, degrees in CROUCH_POSE.items():
        delta = bone_local_delta(arm, bone, degrees)
        path = f'pose.bones["{bone}"].rotation_quaternion'
        quat_curves = [curves.get((path, i)) for i in range(4)]
        if any(fc is None for fc in quat_curves):
            continue
        for index in range(len(quat_curves[0].keyframe_points)):
            old = Quaternion([quat_curves[i].keyframe_points[index].co[1]
                    for i in range(4)])
            new = delta @ old
            for i in range(4):
                quat_curves[i].keyframe_points[index].co[1] = new[i]
        for fc in quat_curves:
            fc.update()

    # Stash on an NLA track so the glTF exporter picks the clip up.
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, act)
    strip.action_slot = act.slots[0]


def prune_actions(arm: bpy.types.Object) -> None:
    for track in list(arm.animation_data.nla_tracks):
        keep = any(s.action and s.action.name in KEEP_ACTIONS
                for s in track.strips)
        if not keep:
            arm.animation_data.nla_tracks.remove(track)
    for action in list(bpy.data.actions):
        if action.name not in KEEP_ACTIONS:
            bpy.data.actions.remove(action, do_unlink=True)
    arm.animation_data.action = None


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()
    arm = import_rig()
    build_archaeologist(arm)
    derive_crouch_action(arm, "Idle", "Crouch_Idle")
    derive_crouch_action(arm, "Walking_A", "Crouch_Walk")
    prune_actions(arm)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            export_animation_mode="NLA_TRACKS")
    print("exported:", out_path)


main()
