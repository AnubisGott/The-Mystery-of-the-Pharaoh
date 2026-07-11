# Builds the Level-2 adventurer from a downloaded, ready-made human: the
# "Adventurer" from Quaternius' Ultimate Modular Men pack (CC0, fetched
# from Poly Pizza, committed as tools/blender/assets/umm_adventurer.glb).
# The model keeps its own textured meshes; the Quaternius Universal
# Animation Library (CC0) is retargeted onto its rig and exported under
# the same canonical clip names as the other characters, so player.gd
# needs no changes.
#
# Run headless:
#   blender --background --python tools/blender/make_adventurer_modular.py -- models/adventurer_modular.glb
#
# The retarget machinery is a self-contained copy of the proven code in
# make_adventurer_realistic.py (kept separate so this script runs without
# the MPFB extension). Pipeline pitfalls encoded there apply here too:
# fcurve sampling instead of depsgraph evaluation, minimal-arc calibration
# with elbow-hinge straightening, quaternion hemisphere continuity,
# identity object transforms before baking, ACTIONS export, no
# export_apply.
#
# Rig quirks of this pack, handled below:
#   * The armature hangs under a "RootNode" empty with scale 100.
#   * Feet are IK-style bones parented to Root (not to the legs), so they
#     get world-location keys like the hips, each anchored at its own
#     rest position.
#   * Legs hang from "Body", not "Hips" — UAL hip motion maps to Body.
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
UAL_GLB = os.path.join(ASSETS, "ual_animation_library.glb")
BODY_GLB = os.path.join(ASSETS, "umm_adventurer.glb")
TARGET_HEIGHT = 1.75

# (source UAL bone, target bone, copy world location) in hierarchy order.
# Fingers and pole targets stay at rest.
BONE_MAP = [
    ("root", "Root", True),
    ("DEF-hips", "Body", True),
    ("DEF-spine.001", "Abdomen", False),
    ("DEF-spine.002", "Torso", False),
    ("DEF-spine.003", "Chest", False),
    ("DEF-neck", "Neck", False),
    ("DEF-head", "Head", False),
    ("DEF-shoulder.L", "Shoulder.L", False),
    ("DEF-upper_arm.L", "UpperArm.L", False),
    ("DEF-forearm.L", "LowerArm.L", False),
    ("DEF-hand.L", "Wrist.L", False),
    ("DEF-shoulder.R", "Shoulder.R", False),
    ("DEF-upper_arm.R", "UpperArm.R", False),
    ("DEF-forearm.R", "LowerArm.R", False),
    ("DEF-hand.R", "Wrist.R", False),
    ("DEF-thigh.L", "UpperLeg.L", False),
    ("DEF-shin.L", "LowerLeg.L", False),
    ("DEF-thigh.R", "UpperLeg.R", False),
    ("DEF-shin.R", "LowerLeg.R", False),
    ("DEF-foot.L", "Foot.L", True),
    ("DEF-foot.R", "Foot.R", True),
]

# canonical clip name (same as the other characters) -> UAL action name
CLIP_MAP = {
    "Idle": "Idle_Loop",
    "Walking_A": "Jog_Fwd_Loop",
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


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def import_body():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BODY_GLB)
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    meshes = []
    for obj in new:
        if obj.type == "MESH":
            if obj.name.startswith("Icosphere"):
                bpy.data.objects.remove(obj, do_unlink=True)
            else:
                meshes.append(obj)

    # Drop the pack's own animations; everything is retargeted from the
    # UAL for consistency with the Level-1 character.
    if rig.animation_data:
        for track in list(rig.animation_data.nla_tracks):
            rig.animation_data.nla_tracks.remove(track)
        rig.animation_data.action = None
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)

    # Normalize: unparent from the scaled RootNode empty (keeping world
    # transforms), apply everything, then scale the character to game
    # height and apply again. All this happens before any animation
    # exists, so baking bone rests is safe.
    for obj in meshes + [rig]:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
    for obj in [o for o in bpy.data.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + [rig]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    zs = [(m.matrix_world @ v.co.to_4d()).z for m in meshes for v in m.data.vertices]
    height = max(zs) - min(zs)
    factor = TARGET_HEIGHT / height
    print("native height:", round(height, 3), "-> scaling by", round(factor, 4))
    for obj in meshes + [rig]:
        obj.scale = (factor, factor, factor)
        obj.location.z -= min(zs) * factor  # feet on ground
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return rig, meshes


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
    # Iterate a snapshot: renaming re-sorts the live collection.
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
    src_rest_pos = {}
    for s_name, _d, _l in BONE_MAP:
        src_rot_t[s_name] = (src_mw3 @ src.data.bones[s_name].matrix_local.to_3x3()).normalized()
        src_rest_pos[s_name] = (src.matrix_world
                @ src.data.bones[s_name].matrix_local.translation.to_4d()).xyz.copy()

    mapped = {d for _s, d, _l in BONE_MAP}
    cal.rest_local = {}
    cal.parents = {}
    dst_rest_pos = {}
    for _s, d_name, _l in BONE_MAP:
        bone = dst.data.bones[d_name]
        parent = bone.parent
        while parent is not None and parent.name not in mapped:
            parent = parent.parent
        cal.parents[d_name] = parent.name if parent else None
        # rest_local spans skipped unmapped bones (e.g. Body between Root
        # and the legs) so the basis math stays consistent.
        if parent:
            cal.rest_local[d_name] = dst.data.bones[parent.name].matrix_local.inverted() \
                    @ bone.matrix_local
        else:
            cal.rest_local[d_name] = bone.matrix_local.copy()
        dst_rest_pos[d_name] = (dst.matrix_world
                @ bone.matrix_local.translation.to_4d()).xyz.copy()

    # Target calibration pose, pure math: minimal-arc direction alignment
    # per bone; elbows straighten around their anatomical hinge.
    hinge = {"LowerArm.L", "LowerArm.R"}
    cal.r_off = {}
    desired = {}
    for s_name, d_name, _l in BONE_MAP:
        parent = cal.parents[d_name]
        pred = (desired[parent] @ cal.rest_local[d_name]) if parent \
                else cal.rest_local[d_name]
        cur_rot = (dst_mw3 @ pred.to_3x3()).normalized()
        d_dir = (cur_rot @ Vector((0.0, 1.0, 0.0))).normalized()
        s_dir = (src_rot_t[s_name] @ Vector((0.0, 1.0, 0.0))).normalized()
        if d_name in hinge:
            parent_rot = (dst_mw3 @ desired[parent].to_3x3()).normalized()
            parent_dir = (parent_rot @ Vector((0.0, 1.0, 0.0))).normalized()
            axis = parent_dir.cross(d_dir)
            if axis.length < 1e-5:
                arc = d_dir.rotation_difference(s_dir).to_matrix()
            else:
                axis.normalize()
                dp = (d_dir - axis * d_dir.dot(axis)).normalized()
                sp = (s_dir - axis * s_dir.dot(axis)).normalized()
                angle = dp.angle(sp)
                if axis.dot(dp.cross(sp)) < 0.0:
                    angle = -angle
                arc = Matrix.Rotation(angle, 3, axis)
        else:
            arc = d_dir.rotation_difference(s_dir).to_matrix()
        rot_world = arc @ cur_rot
        desired[d_name] = Matrix.LocRotScale(
                pred.translation, (dst_mw3.inverted() @ rot_world).to_quaternion(), None)
        cal.r_off[d_name] = src_rot_t[s_name].inverted() @ rot_world

    # Location mapping: scale world translations by the leg-length ratio,
    # anchored per bone at its own rest position (hips at hips, feet at
    # feet, so ground contact survives differing proportions).
    src_hip = src_rest_pos["DEF-hips"]
    src_foot = src_rest_pos["DEF-foot.L"]
    dst_hip = dst_rest_pos["Body"]
    dst_foot = dst_rest_pos["Foot.L"]
    cal.ratio = (dst_hip.z - dst_foot.z) / (src_hip.z - src_foot.z)
    cal.anchors = {}
    for s_name, d_name, copy_loc in BONE_MAP:
        if copy_loc:
            cal.anchors[d_name] = (src_rest_pos[s_name], dst_rest_pos[d_name])
    print("retarget ratio:", round(cal.ratio, 4))
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
                src_anchor, dst_anchor = cal.anchors[d_name]
                pos_world = (m_src_world.translation - src_anchor) * cal.ratio + dst_anchor
                pos = dst_mw_inv @ pos_world
            else:
                pos = pred.translation
            m_arm = Matrix.LocRotScale(pos, (dst_rot_inv @ rot_world).to_quaternion(), None)
            desired[d_name] = m_arm

            basis = pred.inverted() @ m_arm
            pb = dst.pose.bones[d_name]
            loc, rot_q, _scale = basis.decompose()
            # Keep quaternion keys on one hemisphere: interpolating across
            # a sign flip mangles every in-between frame.
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

    rig, meshes = import_body()
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
