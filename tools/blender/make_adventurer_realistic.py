# Builds the realistic Level-1 adventurer: an MPFB/MakeHuman body dressed
# in CC0 MakeHuman community clothes, with the Quaternius Universal
# Animation Library (CC0) retargeted onto its game_engine rig. Exports a
# GLB whose animation clips use the same canonical names as the KayKit
# character (models/adventurer.glb), so player.gd drives both.
#
# Run headless (requires the MPFB extension to be installed in Blender):
#   blender --background --python tools/blender/make_adventurer_realistic.py -- models/adventurer_realistic.glb
#
# Inputs (committed under tools/blender/assets/):
#   ual_animation_library.glb  - Quaternius UAL, Godot flavour (CC0)
#   mhclo/...                  - MakeHuman community clothes (CC0)
#
# Hard-won pitfalls encoded below:
#   * create_human must keep detailed helpers/vertex groups ON: the rig is
#     fitted to the mesh via joint-cube helper geometry. Without it the
#     skeleton silently lands ~0.86 below the flesh and every pose shears.
#   * Never rely on depsgraph animation evaluation in background mode;
#     the source clips are sampled straight from their fcurves.
#   * The A-pose/T-pose difference is handled at calibration: minimal-arc
#     alignment per bone, elbows straightened around their anatomical
#     hinge axis (skew-plane arcs would twist the elbow), toes rigid.
#   * Quaternion keys must stay on one hemisphere or interpolation breaks.
#   * glTF ignores node transforms of skinned meshes: all object
#     transforms are applied before the bake.
#   * export_apply must stay off, or the armature modifier is baked into
#     the vertices and the pose is applied twice at runtime.
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
UAL_GLB = os.path.join(ASSETS, "ual_animation_library.glb")

from bl_ext.blender_org.mpfb.services.exportservice import ExportService
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

# (source UAL bone, target game_engine bone, copy world location) in
# hierarchy order. Fingers stay at their rest pose.
BONE_MAP = [
    ("root", "Root", True),
    ("DEF-hips", "pelvis", True),
    ("DEF-spine.001", "spine_01", False),
    ("DEF-spine.002", "spine_02", False),
    ("DEF-spine.003", "spine_03", False),
    ("DEF-neck", "neck_01", False),
    ("DEF-head", "head", False),
    ("DEF-shoulder.L", "clavicle_l", False),
    ("DEF-upper_arm.L", "upperarm_l", False),
    ("DEF-forearm.L", "lowerarm_l", False),
    ("DEF-hand.L", "hand_l", False),
    ("DEF-shoulder.R", "clavicle_r", False),
    ("DEF-upper_arm.R", "upperarm_r", False),
    ("DEF-forearm.R", "lowerarm_r", False),
    ("DEF-hand.R", "hand_r", False),
    ("DEF-thigh.L", "thigh_l", False),
    ("DEF-shin.L", "calf_l", False),
    ("DEF-foot.L", "foot_l", False),
    ("DEF-toe.L", "ball_l", False),
    ("DEF-thigh.R", "thigh_r", False),
    ("DEF-shin.R", "calf_r", False),
    ("DEF-foot.R", "foot_r", False),
    ("DEF-toe.R", "ball_r", False),
]

# canonical clip name (same as the KayKit adventurer) -> UAL action name
CLIP_MAP = {
    "Idle": "Idle_Loop",
    "Walking_A": "Walk_Loop",
    "Running_A": "Sprint_Loop",
    "Jump_Start": "Jump_Start",
    "Jump_Idle": "Jump_Loop",
    "Jump_Land": "Jump_Land",
    "Crouch_Idle": "Crouch_Idle_Loop",
    "Crouch_Walk": "Crouch_Fwd_Loop",
    "Death_B": "Death01",
    "Hit_A": "Hit_Chest",
    "T-Pose": "A_TPose",
}

# Archaeologist outfit: MakeHuman community assets (all CC0). No hat
# asset: its delete-group hides the head vertices, which the helper bake
# makes permanent — the fedora is built procedurally instead.
CLOTHES = [
    os.path.join(ASSETS, "mhclo", "namuhekam_male_polo_shirt", "namuhekam_male_polo_shirt.mhclo"),
    os.path.join(ASSETS, "mhclo", "cortu_cargo_pants", "cortu_cargo_pants.mhclo"),
    # Tall boots (not the ankle pair) so the pants tuck into them cleanly.
    os.path.join(ASSETS, "mhclo", "culturalibre_hero_boots_1", "culturalibre_hero_boots_1.mhclo"),
]

# Flat desert-palette materials, matching the stylized look of the game
# (and exporting deterministically, unlike procedural MakeSkin shaders).
# Assigned by matching substrings against object names.
PANTS_COLOR = (0.45, 0.38, 0.24)       # brown-khaki; backpack matches it
MATERIAL_COLORS = [
    ("polo", (0.76, 0.65, 0.44)),      # khaki shirt
    ("cargo", PANTS_COLOR),            # pants
    ("boot", (0.24, 0.15, 0.09)),      # dark leather boots
    ("belt", (0.30, 0.19, 0.10)),      # brown leather belt
    ("buckle", (0.62, 0.52, 0.24)),    # brass buckle
    ("backpack", PANTS_COLOR),         # backpack matches the pants
    ("bedroll", (0.58, 0.48, 0.32)),   # tan rolled bedroll on top
    ("strap", (0.30, 0.19, 0.10)),     # brown leather straps
    ("hatband", (0.19, 0.11, 0.06)),   # dark band
    ("hat", (0.38, 0.23, 0.11)),       # brown fedora
    ("Human", (0.85, 0.62, 0.45)),     # skin
]


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def build_human():
    macro = {
        "gender": 1.0, "age": 0.5, "muscle": 0.65, "weight": 0.55,
        "height": 0.52, "proportions": 0.7, "cupsize": 0.5, "firmness": 0.5,
        "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0},
    }
    # Helpers must be on: the rig and the clothes are fitted via the
    # helper/joint-cube geometry. They are baked away again below.
    basemesh = HumanService.create_human(
            mask_helpers=True, detailed_helpers=True,
            extra_vertex_groups=True, feet_on_ground=True,
            scale=0.1, macro_detail_dict=macro)
    # Bake the macro shape keys BEFORE fitting the rig: the joint-cube
    # fitting must see the final mesh shape, or the skeleton binds at the
    # wrong height and every engine that honours inverse bind matrices
    # (i.e. not Blender, but Godot) renders body parts offset.
    TargetService.bake_targets(basemesh)
    rig = HumanService.add_builtin_rig(basemesh, "game_engine", import_weights=True)
    pelvis_z = (rig.matrix_world @ rig.data.bones["pelvis"].head_local.to_4d()).z
    if pelvis_z < 0.5:
        raise RuntimeError(f"rig not fitted to mesh (pelvis at z={pelvis_z:.2f})")

    for mhclo in CLOTHES:
        if os.path.exists(mhclo):
            HumanService.add_mhclo_asset(mhclo, basemesh, asset_type="Clothes",
                    subdiv_levels=0, material_type="MAKESKIN", set_up_rigging=True)
            print("dressed:", os.path.basename(mhclo))
        else:
            print("MISSING clothes asset:", mhclo)

    def zrange(label):
        zs = [(basemesh.matrix_world @ v.co.to_4d()).z for v in basemesh.data.vertices]
        print(f"BODY {label}: verts={len(zs)} z=[{min(zs):.2f}, {max(zs):.2f}]")

    zrange("after dressing")
    ExportService.bake_modifiers_remove_helpers(
            basemesh, bake_masks=True, bake_subdiv=True,
            remove_helpers=True, also_proxy=True)
    zrange("after helper bake")

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for mesh in meshes:
        # Exactly one armature modifier per mesh; duplicates double the pose.
        mods = [m for m in mesh.modifiers if m.type == "ARMATURE"]
        for extra in mods[1:]:
            mesh.modifiers.remove(extra)

    # glTF ignores the node transform of skinned meshes: everything must
    # live at identity. Unparent (keeping transforms), then apply.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + [rig]:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Tuck: shirt hem cut at the waist, pant legs cut to tuck into the
    # boots; a belt (added in main) covers the junction. Transforms are
    # identity here, so world Z == local Z.
    boot_top = max((m.matrix_world @ v.co).z for m in meshes
            if "boot" in m.name.lower() for v in m.data.vertices)
    # Cut the shirt below the waist bone (not at the pants line): it then
    # keeps overlapping the pants, so when it rides up during a stride it
    # never exposes the midriff. The belt covers the overlap.
    waist_z = (rig.matrix_world @ rig.data.bones["pelvis"].head_local).z
    for m in meshes:
        n = m.name.lower()
        if "polo" in n:
            trim_below(m, waist_z)
        elif "cargo" in n:
            trim_below(m, boot_top - 0.06)
        elif "boot" in n:
            offset_along_normals(m, 0.006)
    print("boot_top:", round(boot_top, 3), "waist_z:", round(waist_z, 3))
    return basemesh, rig, meshes


def add_fedora(rig, basemesh, meshes) -> None:
    # Procedural fedora skinned to the head bone (the character faces -Y).
    # Placed relative to the actual mesh top and centered over the skull
    # crown, NOT the body axis: the head sits ~7 cm forward (-Y) of the
    # axis, and a hat centered on the axis hovers behind/above the head.
    z_max = max(v.co.z for v in basemesh.data.vertices)
    head_top = z_max - 0.015
    crown = [v.co for v in basemesh.data.vertices if v.co.z > z_max - 0.03]
    cx = sum(c.x for c in crown) / len(crown)
    cy = sum(c.y for c in crown) / len(crown)
    print("hat: head_top =", round(head_top, 4),
            "center =", (round(cx, 4), round(cy, 4)))
    parts = [
        ("HatBrim", 0.175, 0.022, head_top + 0.011),
        ("HatCrown", 0.105, 0.095, head_top + 0.06),
        ("HatBand", 0.11, 0.028, head_top + 0.038),
    ]
    for name, radius, depth, z in parts:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth,
                vertices=24, location=(cx, cy, z))
        obj = bpy.context.active_object
        obj.name = name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.shade_auto_smooth(angle=1.0)
        group = obj.vertex_groups.new(name="head")
        group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        mod = obj.modifiers.new("skin", "ARMATURE")
        mod.object = rig
        obj.parent = rig
        meshes.append(obj)


def _skin_prop(obj, rig, bone, meshes) -> None:
    # Rigidly skin a procedural prop to one bone (like the fedora).
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_auto_smooth(angle=1.0)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("skin", "ARMATURE")
    mod.object = rig
    obj.parent = rig
    meshes.append(obj)


def _bevel(obj, width) -> None:
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("bev", "BEVEL")
    mod.width = width
    mod.segments = 2
    bpy.ops.object.modifier_apply(modifier="bev")


def trim_below(mesh_obj, z_cut) -> None:
    # Delete vertices below a world Z, so a garment ends higher (shirt
    # tucked at the waist; pant legs cut to tuck into the boots). The open
    # bottom is hidden inside the pants / boots.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh_obj.data)
    victims = [v for v in bm.verts if (mesh_obj.matrix_world @ v.co).z < z_cut]
    bmesh.ops.delete(bm, geom=victims, context="VERTS")
    bm.to_mesh(mesh_obj.data)
    bm.free()
    mesh_obj.data.update()


def offset_along_normals(mesh_obj, dist) -> None:
    me = mesh_obj.data
    for v in me.vertices:
        v.co = v.co + v.normal * dist
    me.update()


def add_belt(rig, meshes) -> None:
    # Brown leather belt (torus) with a small buckle, at the waist.
    belt_z = (rig.matrix_world @ rig.data.bones["pelvis"].head_local).z + 0.05
    bpy.ops.mesh.primitive_torus_add(major_radius=0.15, minor_radius=0.042,
            location=(0.0, 0.0, belt_z), major_segments=28, minor_segments=8)
    belt = bpy.context.active_object
    belt.name = "Belt"
    belt.scale = (1.02, 0.82, 1.0)  # oval to match the torso cross-section
    _skin_prop(belt, rig, "pelvis", meshes)
    # Buckle at the front (the character faces -Y).
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0.0, -0.135, belt_z))
    buckle = bpy.context.active_object
    buckle.name = "Buckle"
    buckle.scale = (0.07, 0.02, 0.05)
    _skin_prop(buckle, rig, "pelvis", meshes)


def _prop_box(name, dims, loc, rig, bone, meshes, bevel=0.0, rot=(0.0, 0.0, 0.0)) -> None:
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = dims
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(scale=True)  # bake scale first so bevels are even
    if bevel > 0.0:
        _bevel(obj, bevel)
    _skin_prop(obj, rig, bone, meshes)


def add_backpack(rig, meshes) -> None:
    # Rucksack on the upper back (character faces -Y, so +Y is behind).
    # Rounded body + top flap/buckle + rolled bedroll + side pockets, plus
    # shoulder straps that sit on the OUTSIDE of the chest (front surface
    # is near y=-0.14, so straps go slightly beyond that) and over the
    # shoulders. Body/pockets/flap skin to spine_02, straps to spine_03.
    z = (rig.matrix_world @ rig.data.bones["spine_02"].head_local).z + 0.05
    shoulder_z = (rig.matrix_world @ rig.data.bones["clavicle_l"].head_local).z
    by = 0.17  # behind the back

    _prop_box("Backpack", (0.25, 0.15, 0.34), (0.0, by, z), rig, "spine_02", meshes, bevel=0.05)
    _prop_box("BackpackFlap", (0.26, 0.08, 0.20), (0.0, by + 0.045, z + 0.08),
            rig, "spine_02", meshes, bevel=0.04)
    for s in (-1.0, 1.0):
        _prop_box("BackpackPocket", (0.08, 0.12, 0.17), (0.145 * s, by, z - 0.04),
                rig, "spine_02", meshes, bevel=0.035)
    _prop_box("Buckle", (0.045, 0.02, 0.035), (0.0, by + 0.085, z + 0.02), rig, "spine_02", meshes)

    # Rolled bedroll strapped across the top.
    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.28, vertices=18,
            location=(0.0, by, z + 0.20), rotation=(0.0, math.pi / 2.0, 0.0))
    roll = bpy.context.active_object
    roll.name = "Bedroll"
    _skin_prop(roll, rig, "spine_02", meshes)

    # Thin shoulder straps: arch over each shoulder (at clavicle height),
    # then down the front of the chest to the belt.
    for s, tag in ((-1.0, "L"), (1.0, "R")):
        _prop_box("StrapOver" + tag, (0.045, 0.40, 0.03), (0.11 * s, 0.02, shoulder_z),
                rig, "spine_03", meshes, bevel=0.008)
        _prop_box("Strap" + tag, (0.045, 0.035, 0.42), (0.10 * s, -0.135, z + 0.03),
                rig, "spine_03", meshes, bevel=0.008, rot=(0.08, 0.0, 0.0))


def apply_flat_materials(meshes) -> None:
    for mesh in meshes:
        rgb = next((color for key, color in MATERIAL_COLORS
                if key.lower() in mesh.name.lower()), (0.6, 0.6, 0.6))
        mat = bpy.data.materials.new("flat_" + mesh.name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        linear = tuple(c ** 2.2 for c in rgb)
        bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
        mat.diffuse_color = (*linear, 1.0)
        mesh.data.materials.clear()
        mesh.data.materials.append(mat)


def import_ual():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=UAL_GLB)
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == "ARMATURE")
    for obj in new:
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    for track in src.animation_data.nla_tracks:
        track.mute = True
    # Prefix source action names so the baked clips can take the clean
    # canonical names (Jump_Start/Jump_Land exist in both sets). Iterate
    # a snapshot: renaming re-sorts the live collection.
    for action in list(bpy.data.actions):
        if not action.name.startswith("SRC_"):
            action.name = "SRC_" + action.name
    return src


class Calibration:
    pass


def compute_calibration(src, dst):
    cal = Calibration()
    src_mw3 = src.matrix_world.to_3x3()
    dst_mw3 = dst.matrix_world.to_3x3()

    # The UAL rig's rest pose IS its T-pose; calibrate the source side
    # from rest matrices.
    src_rot_t = {}
    for s_name, _d, _l in BONE_MAP:
        src_rot_t[s_name] = (src_mw3 @ src.data.bones[s_name].matrix_local.to_3x3()).normalized()
    src_hip_t = (src.matrix_world @ src.data.bones["DEF-hips"].matrix_local.translation.to_4d()).xyz.copy()

    mapped = {d for _s, d, _l in BONE_MAP}
    cal.rest_local = {}
    cal.parents = {}
    for _s, d_name, _l in BONE_MAP:
        bone = dst.data.bones[d_name]
        parent = bone.parent
        while parent is not None and parent.name not in mapped:
            parent = parent.parent
        cal.parents[d_name] = parent.name if parent else None
        if parent:
            cal.rest_local[d_name] = parent.matrix_local.inverted() @ bone.matrix_local
        else:
            cal.rest_local[d_name] = bone.matrix_local.copy()

    # Target calibration pose, pure math: per bone the minimal-arc world
    # rotation aligning its direction with the source rest direction.
    # Forearms straighten around the anatomical elbow hinge instead (the
    # normal of the bent A-pose arm plane); toes follow the foot rigidly.
    rigid = {"ball_l", "ball_r"}
    hinge = {"lowerarm_l", "lowerarm_r"}
    cal.r_off = {}
    desired = {}
    for s_name, d_name, _l in BONE_MAP:
        parent = cal.parents[d_name]
        pred = (desired[parent] @ cal.rest_local[d_name]) if parent \
                else cal.rest_local[d_name]
        cur_rot = (dst_mw3 @ pred.to_3x3()).normalized()
        d_dir = (cur_rot @ Vector((0.0, 1.0, 0.0))).normalized()
        s_dir = (src_rot_t[s_name] @ Vector((0.0, 1.0, 0.0))).normalized()
        if d_name in rigid:
            rot_world = cur_rot
        elif d_name in hinge:
            parent_rot = (dst_mw3 @ desired[parent].to_3x3()).normalized()
            parent_dir = (parent_rot @ Vector((0.0, 1.0, 0.0))).normalized()
            axis = parent_dir.cross(d_dir)
            if axis.length < 1e-5:
                axis = (cur_rot @ Vector((1.0, 0.0, 0.0))).normalized()
            else:
                axis.normalize()
            dp = (d_dir - axis * d_dir.dot(axis)).normalized()
            sp = (s_dir - axis * s_dir.dot(axis)).normalized()
            angle = dp.angle(sp)
            if axis.dot(dp.cross(sp)) < 0.0:
                angle = -angle
            rot_world = Matrix.Rotation(angle, 3, axis) @ cur_rot
        else:
            rot_world = d_dir.rotation_difference(s_dir).to_matrix() @ cur_rot
        desired[d_name] = Matrix.LocRotScale(
                pred.translation, (dst_mw3.inverted() @ rot_world).to_quaternion(), None)
        cal.r_off[d_name] = src_rot_t[s_name].inverted() @ rot_world

    # Affine hip mapping: scale by leg-length ratio, anchor rest to rest.
    src_foot = (src.matrix_world @ src.data.bones["DEF-foot.L"].matrix_local.translation.to_4d()).xyz
    dst_hip = (dst.matrix_world @ dst.data.bones["pelvis"].matrix_local.translation.to_4d()).xyz
    dst_foot = (dst.matrix_world @ dst.data.bones["foot_l"].matrix_local.translation.to_4d()).xyz
    cal.ratio = (dst_hip.z - dst_foot.z) / (src_hip_t.z - src_foot.z)
    cal.l_off = dst_hip - src_hip_t * cal.ratio
    print("retarget ratio:", round(cal.ratio, 4),
            "offset:", tuple(round(c, 4) for c in cal.l_off))
    return cal


def action_fcurves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def index_action_channels(action):
    channels = {}
    for fc in action_fcurves(action):
        if not fc.data_path.startswith('pose.bones["'):
            continue
        bone = fc.data_path.split('"')[1]
        prop = fc.data_path.rsplit(".", 1)[1]
        channels.setdefault(bone, {}).setdefault(prop, {})[fc.array_index] = fc
    return channels


def sample_src_pose(src, channels, frame):
    # Armature-space pose matrices straight from the action's fcurves —
    # depsgraph animation evaluation is unreliable in background mode.
    mats = {}
    for s_name, _d, _l in BONE_MAP:
        bone = src.data.bones[s_name]
        parent = bone.parent
        rest_local = (parent.matrix_local.inverted() @ bone.matrix_local) \
                if parent else bone.matrix_local.copy()
        ch = channels.get(s_name, {})

        def ev(prop, idx, default):
            fc = ch.get(prop, {}).get(idx)
            return fc.evaluate(frame) if fc is not None else default

        quat = Quaternion((ev("rotation_quaternion", 0, 1.0),
                ev("rotation_quaternion", 1, 0.0),
                ev("rotation_quaternion", 2, 0.0),
                ev("rotation_quaternion", 3, 0.0))).normalized()
        loc = Vector((ev("location", 0, 0.0), ev("location", 1, 0.0),
                ev("location", 2, 0.0)))
        local = rest_local @ Matrix.LocRotScale(loc, quat, None)
        mats[s_name] = (mats[parent.name] @ local) if parent else local
    return mats


def retarget_clip(src, dst, src_action_name, new_name, cal):
    new_act = bpy.data.actions.new(new_name)
    dst.animation_data.action = new_act
    action = bpy.data.actions["SRC_" + src_action_name]
    channels = index_action_channels(action)

    end = action.frame_range[1]
    frames = [float(f) for f in range(int(end) + 1)]
    if end - int(end) > 1e-3:
        frames.append(end)

    src_mw = src.matrix_world
    dst_mw_inv = dst.matrix_world.inverted()
    dst_rot_inv = dst_mw_inv.to_3x3()

    prev_q = {}
    for frame in frames:
        src_pose = sample_src_pose(src, channels, frame)
        desired = {}
        for s_name, d_name, copy_loc in BONE_MAP:
            m_src_world = src_mw @ src_pose[s_name]
            rot_world = m_src_world.to_3x3().normalized() @ cal.r_off[d_name]
            parent = cal.parents[d_name]
            pred = (desired[parent] @ cal.rest_local[d_name]) if parent \
                    else cal.rest_local[d_name]
            if copy_loc:
                pos = dst_mw_inv @ (m_src_world.translation * cal.ratio + cal.l_off)
            else:
                pos = pred.translation
            m_arm = Matrix.LocRotScale(pos, (dst_rot_inv @ rot_world).to_quaternion(), None)
            desired[d_name] = m_arm

            basis = pred.inverted() @ m_arm
            pb = dst.pose.bones[d_name]
            loc, rot_q, _scale = basis.decompose()
            # Keep quaternion keys on one hemisphere: q and -q encode the
            # same rotation, but interpolating across the flip mangles
            # every in-between frame.
            if d_name in prev_q and rot_q.dot(prev_q[d_name]) < 0.0:
                rot_q = -rot_q
            prev_q[d_name] = rot_q
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = rot_q
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if copy_loc:
                pb.location = loc
                pb.keyframe_insert("location", frame=frame)
    return new_act


def stash(arm, action):
    track = arm.animation_data.nla_tracks.new()
    track.name = action.name
    track.mute = True
    strip = track.strips.new(action.name, 0, action)
    if action.slots:
        strip.action_slot = action.slots[0]


def clear_pose(arm):
    for pb in arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def main() -> None:
    out_path = sys.argv[sys.argv.index("--") + 1]
    clear_scene()

    basemesh, rig, meshes = build_human()
    add_fedora(rig, basemesh, meshes)
    add_belt(rig, meshes)
    add_backpack(rig, meshes)
    apply_flat_materials(meshes)
    src = import_ual()
    rig.animation_data_create()

    cal = compute_calibration(src, rig)
    for new_name, src_name in CLIP_MAP.items():
        act = retarget_clip(src, rig, src_name, new_name, cal)
        stash(rig, act)
        print("baked:", new_name, "frames:", tuple(act.frame_range))

    # Backward death: the UAL ships only one death clip, reuse it.
    death_a = bpy.data.actions["Death_B"].copy()
    death_a.name = "Death_A"
    stash(rig, death_a)

    rig.animation_data.action = None
    clear_pose(rig)
    keep = set(CLIP_MAP.keys()) | {"Death_A"}
    bpy.data.objects.remove(src, do_unlink=True)
    for action in list(bpy.data.actions):
        if action.name not in keep:
            bpy.data.actions.remove(action, do_unlink=True)

    # export_apply must stay off: with it, the exporter bakes the armature
    # modifier into the vertices (pose applied twice at runtime).
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            export_animation_mode="ACTIONS")
    print("exported:", out_path)


main()
