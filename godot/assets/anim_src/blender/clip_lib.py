# Shared helpers for the hand-authored clips (spyglass_look.py, deck_swab.py): the 24-bone Meshy crew rig is imported from a copy of papi_fuego.glb,
# poses are expressed as GLOBAL bone rotations (independent of any bone orientation convention), two-bone IK drives arms and legs, and the result is
# keyed on the Blender rig (.blend) and written to <name>.json for clip_bake.gd. Same maths and file format as ratline_climb.py.
# Hand frame: F = fingers (forearm -> hand), N = palm normal (towards the body centre line), A = h*(F x N) pointing forward at rest, so a grip can be
# authored as "A' = axis of the held object, N' = direction from the palm to it", the same convention props_attach.gd uses for the BoneAttachment3D.
import bpy, os, sys, json, math
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
CREW = os.path.abspath(os.path.join(HERE, "..", "..", "characters", "papi_fuego.glb"))
M = 0.01
PALM_F, PALM_N = 0.045, 0.015   # grip point = wrist + F*PALM_F + N*PALM_N (metres)


def rotx(a): return Quaternion((1, 0, 0), math.radians(a))
def roty(a): return Quaternion((0, 1, 0), math.radians(a))
def rotz(a): return Quaternion((0, 0, 1), math.radians(a))
def trunk_q(roll, twist, pitch): return rotz(twist) @ roty(roll) @ rotx(pitch)


def two_bone(root, target, pole, a, b):
    d = target - root
    dist = d.length
    clamped = dist > (a + b) * 0.995
    dist = min(dist, (a + b) * 0.995)
    dist = max(dist, abs(a - b) + 1e-3)
    axis = d.normalized()
    x = (a * a - b * b + dist * dist) / (2 * dist)
    h = math.sqrt(max(a * a - x * x, 0.0))
    pp = pole - axis * pole.dot(axis)
    pp = pp.normalized() if pp.length > 1e-6 else Vector((0, 0, 1))
    return root + axis * x + pp * h, root + axis * dist, clamped


class Rig:
    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=CREW)
        self.arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
        for a in list(bpy.data.actions):
            bpy.data.actions.remove(a)
        bones = self.arm.data.bones
        self.H0 = {b.name: Vector(b.head_local) * M for b in bones}
        self.RB = {b.name: b.matrix_local.to_quaternion() for b in bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.order = [b.name for b in bones]
        bl = lambda a, b: (self.H0[b] - self.H0[a]).length
        self.LEN = {}
        for s, p in (("L", "Left"), ("R", "Right")):
            self.LEN[s] = (bl(p + "Arm", p + "ForeArm"), bl(p + "ForeArm", p + "Hand"), bl(p + "UpLeg", p + "Leg"), bl(p + "Leg", p + "Foot"))
        self.clamps = {}
        self.reach = {}   # worst wrist-target distance / arm length (1.0 = fully stretched)
        # hand frames at rest
        self.hand_rest = {}
        for s, p in (("L", "Left"), ("R", "Right")):
            F = self.rest_dir(p + "ForeArm", p + "Hand")
            N = Vector((-1, 0, 0)) if s == "L" else Vector((1, 0, 0))
            N = (N - F * N.dot(F)).normalized()
            A = F.cross(N)
            h = 1.0 if A.dot(Vector((0, -1, 0))) > 0 else -1.0
            self.hand_rest[s] = (F, N, h * F.cross(N), h)

    def rest_dir(self, a, b): return (self.H0[b] - self.H0[a]).normalized()

    def hand_basis(self, s, A, N):
        """Matrix whose columns are (F, N, A) for a hand holding along A with palm normal N (orthonormalised)."""
        h = self.hand_rest[s][3]
        A = A.normalized()
        N = (N - A * N.dot(A)).normalized()
        F = h * N.cross(A)
        return Matrix((F, N, A)).transposed()

    def hand_basis_FN(self, s, F, N):
        """Same as hand_basis but the hand is given by its finger direction F and palm normal N (A = h * F x N)."""
        h = self.hand_rest[s][3]
        F = F.normalized()
        N = (N - F * N.dot(F)).normalized()
        return Matrix((F, N, h * F.cross(N))).transposed()

    def hand_delta_FN(self, s, F, N):
        F0, N0, A0, h = self.hand_rest[s]
        m0 = Matrix((F0, N0, A0)).transposed()
        return (self.hand_basis_FN(s, F, N) @ m0.inverted()).to_quaternion()

    def hand_delta(self, s, A, N):
        F0, N0, A0, h = self.hand_rest[s]
        m0 = Matrix((F0, N0, A0)).transposed()
        return (self.hand_basis(s, A, N) @ m0.inverted()).to_quaternion()

    def grip_to_wrist(self, s, grip, A, N):
        B = self.hand_basis(s, A, N)
        F = B.col[0].to_3d(); Nn = B.col[1].to_3d()
        return grip - (F * PALM_F + Nn * PALM_N)

    def solve(self, hips, trunk, hands=None, feet=None, poles=None):
        """trunk: dict of global rotations for Hips, Spine02, Spine01, Spine, neck, Head.
        hands: {"L"/"R": (grip point, A, N, pole)}; feet: {"L"/"R": (ankle target, foot delta quaternion, pole)}. Returns (D, P) global rotations / head positions."""
        D = dict(trunk)
        P = {}
        def head_of(n):
            if n in P: return P[n]
            par = self.parent[n]
            P[n] = hips if par is None else head_of(par) + D[par] @ (self.H0[n] - self.H0[par])
            return P[n]
        for n in ("Hips", "Spine02", "Spine01", "Spine", "neck", "Head"):
            head_of(n)
        D["head_end"] = D["Head"]; D["headfront"] = D["Head"]
        for n in ("LeftShoulder", "RightShoulder"):
            D[n] = D["Spine"]
            head_of(n)
        for s, p in (("L", "Left"), ("R", "Right")):
            a, b, c, d = self.LEN[s]
            xs = 1 if s == "L" else -1
            root = head_of(p + "Arm")
            if hands and s in hands:
                spec = hands[s]
                grip, A, N, pole = spec[:4]
                fn = len(spec) > 4 and spec[4] == "FN"   # (grip, F, N, pole, "FN"): the hand is given by fingers + palm normal
                B = self.hand_basis_FN(s, A, N) if fn else self.hand_basis(s, A, N)
                wrist_t = grip - (B.col[0].to_3d() * PALM_F + B.col[1].to_3d() * PALM_N)
                elbow, wrist, cl = two_bone(root, wrist_t, pole, a, b)
                self.clamps[p + "Hand"] = self.clamps.get(p + "Hand", 0) + (1 if cl else 0)
                self.last_stretch = getattr(self, 'last_stretch', {})
                self.last_stretch[s] = (wrist_t - root).length / (a + b)
                self.reach[s] = max(self.reach.get(s, 0), self.last_stretch[s])
                D[p + "Arm"] = self.rest_dir(p + "Arm", p + "ForeArm").rotation_difference(elbow - root)
                D[p + "ForeArm"] = self.rest_dir(p + "ForeArm", p + "Hand").rotation_difference(wrist - elbow)
                D[p + "Hand"] = self.hand_delta_FN(s, A, N) if fn else self.hand_delta(s, A, N)
            else:
                # relaxed arm: hang from the shoulder
                D[p + "Arm"] = D["Spine"]; D[p + "ForeArm"] = D["Spine"]; D[p + "Hand"] = D["Spine"]
            lroot = head_of(p + "UpLeg")
            if feet and s in feet:
                ankle_t, fdelta, pole = feet[s]
                knee, ankle, cl = two_bone(lroot, ankle_t, pole, c, d)
                self.clamps[p + "Foot"] = self.clamps.get(p + "Foot", 0) + (1 if cl else 0)
                D[p + "UpLeg"] = self.rest_dir(p + "UpLeg", p + "Leg").rotation_difference(knee - lroot)
                D[p + "Leg"] = self.rest_dir(p + "Leg", p + "Foot").rotation_difference(ankle - knee)
                D[p + "Foot"] = fdelta
                D[p + "ToeBase"] = fdelta
            else:
                D[p + "UpLeg"] = D["Hips"]; D[p + "Leg"] = D["Hips"]; D[p + "Foot"] = D["Hips"]; D[p + "ToeBase"] = D["Hips"]
        for n in self.order:
            if n not in D:
                D[n] = D[self.parent[n]]
        return D, P

    def key(self, name, n, fps, frames_fn, preview_fn=None):
        """frames_fn(u) -> (hips, D). Keys the action on the rig and writes <name>.json (+ saves src/<name>.blend)."""
        arm = self.arm
        arm.animation_data_create()
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        sc = bpy.context.scene
        sc.render.fps = fps; sc.frame_start = 0; sc.frame_end = n - 1
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'
        out = {"fps": fps, "frames": n, "cycle_s": n / fps, "hips_rest_m": list(self.H0["Hips"]), "bones": self.order, "delta": [], "hips_offset_m": []}
        for f in range(n):
            hips, D = frames_fn(f / n)
            for nm in self.order:
                pb = arm.pose.bones[nm]
                par = self.parent[nm]
                dp = D[par] if par else Quaternion()
                pb.rotation_quaternion = self.RB[nm].inverted() @ dp.inverted() @ D[nm] @ self.RB[nm]
                if par is None:
                    pb.location = (self.RB[nm].inverted() @ (hips - self.H0[nm])) / M
                pb.keyframe_insert("rotation_quaternion", frame=f)
                if par is None:
                    pb.keyframe_insert("location", frame=f)
            out["delta"].append({nm: [D[nm].w, D[nm].x, D[nm].y, D[nm].z] for nm in self.order})
            out["hips_offset_m"].append(list(hips - self.H0["Hips"]))
        with open(os.path.join(HERE, name + ".json"), "w") as fh:
            json.dump(out, fh)
        print("[%s] IK reach clamps" % name, self.clamps, "worst arm stretch", {k: round(v, 2) for k, v in self.reach.items()})
        os.makedirs(os.path.join(HERE, "src"), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "src", name + ".blend"), compress=True)


def ease(x):
    x = max(0.0, min(1.0, x))
    return x * x * x * (x * (x * 6 - 15) + 10)


def keys(t, ks):
    """Smooth interpolation of keyed values ks = [(time, value), ...] (floats or Vectors) at time t; clamps outside."""
    if t <= ks[0][0]:
        return ks[0][1]
    for (t0, v0), (t1, v1) in zip(ks, ks[1:]):
        if t <= t1:
            a = ease((t - t0) / (t1 - t0))
            return v0 * (1.0 - a) + v1 * a
    return ks[-1][1]
