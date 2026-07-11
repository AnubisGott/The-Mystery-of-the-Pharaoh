# Builds the Level-2 tactical-explorer character: an MPFB/MakeHuman body
# (caucasian male, ~35, 178 cm, slightly athletic) dressed in a modern
# tactical outfit, with the Quaternius Universal Animation Library (CC0)
# retargeted onto its game_engine rig. Exports a GLB whose clips use the
# same canonical names as the other characters, so player.gd drives it.
#
# Run headless (requires the MPFB extension installed in Blender):
#   blender --background --python tools/blender/make_adventurer_tactical.py -- models/adventurer_tactical.glb
#
# This is a sibling of make_adventurer_realistic.py; the whole retarget
# machinery is identical (and carries the same pitfall notes). Only the
# body macro, the outfit, and a few outfit-specific fixes differ:
#   * A real hat asset (trilby) is used instead of a procedural fedora.
#     Hat mhclos hide the scalp via a "Delete" MASK modifier that the
#     helper bake would make permanent (headless character), so those
#     masks are stripped before baking — see neutralize_head_deletes.
#   * The tactical vest sits over an undershirt; both are fitted to the
#     body and would z-fight, so the vest is pushed out along its normals.
#   * The finished body is scaled to exactly TARGET_HEIGHT.
#   * The body uses a real CC0 MakeHuman skin texture (Skins 02) as a
#     plain diffuse (+ normal) on a Principled BSDF; clothes stay flat.
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
UAL_GLB = os.path.join(ASSETS, "ual_animation_library.glb")
# A committed MakeHuman skin folder (CC0 Skins 02) — its .mhmat + textures
# give the body a natural diffuse/normal instead of a flat skin color.
# If absent, the body falls back to the flat skin tone below.
SKIN_DIR = os.path.join(ASSETS, "skin")
TARGET_HEIGHT = 1.78

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

# canonical clip name (same as the other characters) -> UAL action name.
# Level 2 uses a real walk cycle for walking and a jog for running (the
# archaeologist still uses jog/sprint); pacing is tuned via the stride
# speeds in player_tactical.tscn.
CLIP_MAP = {
    "Idle": "Idle_Loop",
    "Walking_A": "Walk_Loop",
    "Running_A": "Jog_Fwd_Loop",
    "Jump_Start": "Jump_Start",
    "Jump_Idle": "Jump_Loop",
    "Jump_Land": "Jump_Land",
    "Crouch_Idle": "Crouch_Idle_Loop",
    "Crouch_Walk": "Crouch_Fwd_Loop",
    "Death_B": "Death01",
    "Hit_A": "Hit_Chest",
    "T-Pose": "A_TPose",
}


def clothes_path(folder, name=None):
    return os.path.join(ASSETS, "mhclo", folder, (name or folder) + ".mhclo")


# Tactical-explorer outfit. Undershirt/pants/boots are CC0; the vest,
# trilby and sling bag are CC-BY (credited in models/CREDITS.md). Order
# matters: the vest loads over the undershirt.
CLOTHES = [
    clothes_path("elvs_crude_t-shirt_male"),
    clothes_path("mindfront_tactical_vest_male"),
    clothes_path("cortu_cargo_pants"),
    clothes_path("culturalibre_hero_boots_1"),
    clothes_path("elvs_sling_purse1"),
    clothes_path("elvs_male_trilby_hat"),
]

# Flat materials, keyed by substring against the object name (garment
# keys first, "Human" last so it only catches the bare body/skin).
MATERIAL_COLORS = [
    ("shirt", (0.72, 0.66, 0.50)),    # light khaki undershirt
    ("vest", (0.28, 0.31, 0.20)),     # olive-drab tactical vest
    ("cargo", (0.42, 0.38, 0.26)),    # tan cargo pants
    ("hero", (0.20, 0.14, 0.09)),     # dark leather boots
    ("purse", (0.30, 0.20, 0.12)),    # brown leather bag
    ("trilby", (0.36, 0.22, 0.11)),   # brown trilby
    ("Human", (0.85, 0.62, 0.45)),    # skin
]


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def neutralize_head_deletes(basemesh) -> None:
    # A hat mhclo hides the scalp via a MASK modifier keyed to a "Delete"
    # vertex group; the helper bake (bake_masks=True) would apply it and
    # permanently remove the head. Strip those masks and the group so the
    # head survives under the hat. The helper-hiding mask (vertex_group
    # "body") is left intact.
    for mod in list(basemesh.modifiers):
        if mod.type == "MASK" and mod.vertex_group and mod.vertex_group != "body":
            basemesh.modifiers.remove(mod)
    for vg in list(basemesh.vertex_groups):
        if vg.name.lower().startswith("delete"):
            basemesh.vertex_groups.remove(vg)


def offset_along_normals(mesh_obj, dist) -> None:
    me = mesh_obj.data
    for v in me.vertices:
        v.co = v.co + v.normal * dist
    me.update()


def build_human():
    # Caucasian male, ~35 (age 0.58), average weight, slightly athletic.
    macro = {
        "gender": 1.0, "age": 0.58, "muscle": 0.45, "weight": 0.5,
        "height": 0.5, "proportions": 0.5, "cupsize": 0.5, "firmness": 0.5,
        "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0},
    }
    # Helpers must stay on: the rig and clothes fit via helper/joint-cube
    # geometry. They are baked away below.
    basemesh = HumanService.create_human(
            mask_helpers=True, detailed_helpers=True,
            extra_vertex_groups=True, feet_on_ground=True,
            scale=0.1, macro_detail_dict=macro)
    # Bake macro shape keys BEFORE fitting the rig, or the skeleton binds
    # at the wrong height and Godot (which honours inverse bind matrices)
    # renders body parts offset.
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

    neutralize_head_deletes(basemesh)
    ExportService.bake_modifiers_remove_helpers(
            basemesh, bake_masks=True, bake_subdiv=True,
            remove_helpers=True, also_proxy=True)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for mesh in meshes:
        # Exactly one armature modifier per mesh; duplicates double the pose.
        mods = [m for m in mesh.modifiers if m.type == "ARMATURE"]
        for extra in mods[1:]:
            mesh.modifiers.remove(extra)

    # glTF ignores node transforms of skinned meshes: everything must live
    # at identity. Unparent (keeping transforms), then apply.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + [rig]:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Normalize to exactly TARGET_HEIGHT (feet already near z=0). All
    # origins are at world 0 after the apply, so a uniform scale shares
    # one pivot across rig + meshes.
    zs = [(m.matrix_world @ v.co.to_4d()).z for m in meshes for v in m.data.vertices]
    factor = TARGET_HEIGHT / (max(zs) - min(zs))
    print("body height:", round(max(zs) - min(zs), 3), "-> scale", round(factor, 4))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + [rig]:
        obj.scale = (factor, factor, factor)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Lift the vest clear of the undershirt to stop z-fighting.
    for mesh in meshes:
        if "vest" in mesh.name.lower():
            offset_along_normals(mesh, 0.012)
    return basemesh, rig, meshes


def find_skin_textures():
    # Parse the committed skin's .mhmat for its diffuse and normal texture
    # paths; return (diffuse, normal|None) or (None, None) if no skin.
    if not os.path.isdir(SKIN_DIR):
        return None, None
    mhmats = [f for f in os.listdir(SKIN_DIR) if f.endswith(".mhmat")]
    if not mhmats:
        return None, None
    diffuse = normal = None
    with open(os.path.join(SKIN_DIR, mhmats[0]), encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 2:
                continue
            key = parts[0].lower()
            tex = os.path.join(SKIN_DIR, os.path.basename(" ".join(parts[1:]).strip()))
            if key == "diffusetexture":
                diffuse = tex
            elif key in ("normalmaptexture", "bumpmaptexture"):
                normal = tex
    return diffuse, normal


def apply_materials(meshes) -> None:
    skin_diffuse, skin_normal = find_skin_textures()
    for mesh in meshes:
        key = next((k for k, _c in MATERIAL_COLORS if k.lower() in mesh.name.lower()), None)
        mat = bpy.data.materials.new("mat_" + mesh.name)
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        bsdf = nodes["Principled BSDF"]
        if key == "Human" and skin_diffuse and os.path.exists(skin_diffuse):
            # Natural skin: real diffuse (+ normal) on a plain Principled
            # BSDF, which exports cleanly to glTF (unlike MakeSkin's SSS
            # node tree). The body keeps the MakeHuman UVs.
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(skin_diffuse)
            links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = 0.6
            if skin_normal and os.path.exists(skin_normal):
                ntex = nodes.new("ShaderNodeTexImage")
                ntex.image = bpy.data.images.load(skin_normal)
                ntex.image.colorspace_settings.name = "Non-Color"
                nmap = nodes.new("ShaderNodeNormalMap")
                links.new(ntex.outputs["Color"], nmap.inputs["Color"])
                links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
            print("skin texture:", os.path.basename(skin_diffuse))
        else:
            rgb = next((c for k, c in MATERIAL_COLORS if k.lower() in mesh.name.lower()),
                    (0.6, 0.6, 0.6))
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
    apply_materials(meshes)
    src = import_ual()
    rig.animation_data_create()

    cal = compute_calibration(src, rig)
    for new_name, src_name in CLIP_MAP.items():
        act = retarget_clip(src, rig, src_name, new_name, cal)
        stash(rig, act)
        print("baked:", new_name, "frames:", tuple(act.frame_range))

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

    # export_apply off, or the armature modifier is baked into the
    # vertices and the pose is applied twice at runtime.
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB",
            export_animation_mode="ACTIONS")
    print("exported:", out_path)


main()
