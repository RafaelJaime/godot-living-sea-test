# Blender CLI: hand-authored looping ratline (shroud) climb for the 24-bone Meshy crew rig.
#   blender -b --python ratline_climb.py [-- --preview <dir>]
# The clip is authored procedurally in the rig's own space: alternating hands and feet (diagonal pairs), two-bone IK for arms and
# legs against ratline targets, a body that leans into the ropes and sways onto the stance foot. The clip is IN PLACE: in the body
# frame the stance limbs slide down the ropes at the body's rise speed; the game moves the body up the ratline at RISE_PER_CYCLE / CYCLE_S.
# Outputs next to this script: ratline_climb.blend (crew rig copy + baked action), ratline_climb.json (GLOBAL bone rotations per frame,
# independent of any bone orientation convention; ratline_climb_bake.gd turns them into an Animation for the Meshy skeleton).
# The crew glb is only read, assets/characters is never modified.
import bpy, os, sys, json, math
from mathutils import Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
CREW = os.path.abspath(os.path.join(HERE, "..", "..", "characters", "papi_fuego.glb"))
FPS = 30
N = 42                    # frames of one loop (1.4 s), frame N would equal frame 0 and is not stored
CYCLE_S = N / FPS
STANCE = 0.6              # fraction of the cycle a limb is in contact
STRIDE = 0.40             # m a stance limb slides down in the body frame
RISE_PER_CYCLE = STRIDE / STANCE   # m the body climbs per cycle (0.667 m, rung spacing = half of it)
RUNG_SPACING = RISE_PER_CYCLE / 2.0

# geometry in metres, armature space (character faces -Y, +X is the character's left, rest hips at (0,-0.152,1.095))
HIPS_Y, HIPS_Z = -0.02, 1.03
LEAN_DEG = 11.0           # forward lean of the trunk into the ropes
HAND_Y = -0.43            # shroud plane
HAND_X = 0.22
HAND_Z_HI = 1.78          # wrist height when the hand grabs (body frame)
FOOT_Y = -0.20            # ankle y while the ball of the foot is on the rung
FOOT_X = 0.13
FOOT_Z_HI = 0.60          # ankle height at touchdown


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * x * (x * (x * 6 - 15) + 10)


def hermite(z0, z1, m0, m1, t):
    h00 = 2 * t ** 3 - 3 * t ** 2 + 1
    h10 = t ** 3 - 2 * t ** 2 + t
    h01 = -2 * t ** 3 + 3 * t ** 2
    h11 = t ** 3 - t ** 2
    return h00 * z0 + h10 * m0 + h01 * z1 + h11 * m1


def limb_height(s, z_hi):
    """Body-frame height of a limb at its own cycle phase s in [0,1): stance slides down STRIDE, swing returns up with the contact velocity."""
    v = -RISE_PER_CYCLE            # m per cycle
    if s < STANCE:
        return z_hi - RISE_PER_CYCLE * s, 0.0
    t = (s - STANCE) / (1.0 - STANCE)
    z0 = z_hi - STRIDE
    z = hermite(z0, z_hi, v * (1 - STANCE), v * (1 - STANCE), t)
    return z, math.sin(math.pi * t) ** 1.0   # (height, out-of-plane arc 0..1..0)


def rotx(a): return Quaternion((1, 0, 0), math.radians(a))
def roty(a): return Quaternion((0, 1, 0), math.radians(a))
def rotz(a): return Quaternion((0, 0, 1), math.radians(a))


def two_bone(root, target, pole, a, b):
    d = target - root
    dist = d.length
    reach = a + b
    clamped = False
    if dist > reach * 0.995:
        dist = reach * 0.995
        clamped = True
    dist = max(dist, abs(a - b) + 1e-3)
    axis = d.normalized()
    x = (a * a - b * b + dist * dist) / (2 * dist)
    h = math.sqrt(max(a * a - x * x, 0.0))
    pp = pole - axis * pole.dot(axis)
    pp = pp.normalized() if pp.length > 1e-6 else Vector((0, 0, 1))
    elbow = root + axis * x + pp * h
    wrist = root + axis * dist
    return elbow, wrist, clamped


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=CREW)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    return arm


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
    arm = build()
    bones = arm.data.bones
    M = 0.01  # armature local units are cm
    H0 = {b.name: Vector(b.head_local) * M for b in bones}
    RB = {b.name: b.matrix_local.to_quaternion() for b in bones}
    parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
    order = [b.name for b in bones]   # parents come before children in the glTF import

    def blen(a, b): return (H0[b] - H0[a]).length
    LEN = {"L": (blen("LeftArm", "LeftForeArm"), blen("LeftForeArm", "LeftHand"), blen("LeftUpLeg", "LeftLeg"), blen("LeftLeg", "LeftFoot")),
           "R": (blen("RightArm", "RightForeArm"), blen("RightForeArm", "RightHand"), blen("RightUpLeg", "RightLeg"), blen("RightLeg", "RightFoot"))}
    print("[ratline] limb lengths (m)", {k: [round(x, 3) for x in v] for k, v in LEN.items()})

    def rest_dir(a, b): return (H0[b] - H0[a]).normalized()
    foot_rest = {"L": rest_dir("LeftFoot", "LeftToeBase"), "R": rest_dir("RightFoot", "RightToeBase")}

    stats = {"clamp": {}, "min_knee": 999, "max_reach": {}}

    def pose(u):
        D = {}
        # --- limb phases: right hand + left foot (pair A, phase 0), left hand + right foot (pair B, phase .5)
        ph = {"RH": 0.0, "LF": 0.0, "LH": 0.5, "RF": 0.5}
        s = {k: (u - v) % 1.0 for k, v in ph.items()}
        # --- body
        sway = -0.032 * math.cos(2 * math.pi * (u - 0.8))            # weight over the stance foot (LF swings around u=.8)
        bob = 0.010 * math.cos(4 * math.pi * u + 0.6)
        hips = Vector((sway, HIPS_Y, HIPS_Z + bob))
        twist = 5.0 * math.sin(2 * math.pi * (u - 0.55))              # shoulders turn towards the reaching hand
        roll = -4.0 * math.cos(2 * math.pi * (u - 0.8))               # hips roll with the sway
        D["Hips"] = roll_q(roll * 0.8, -twist * 0.4, 3.0)
        for name, k, pitch in (("Spine02", 0.45, 0.35), ("Spine01", 0.7, 0.62), ("Spine", 1.0, 0.85), ("neck", 1.05, 0.95)):
            D[name] = roll_q(roll * (1.0 - k * 0.6), twist * k, LEAN_DEG * pitch)
        D["Head"] = roll_q(roll * 0.1, -twist * 0.3, LEAN_DEG * 0.15)   # look up the ropes: head leans less than the trunk
        # --- hands (wrist targets) and feet (ankle targets)
        tgt = {}
        for side, key, xs in (("R", "RH", -1), ("L", "LH", 1)):
            z, arc = limb_height(s[key], HAND_Z_HI)
            tgt["H" + side] = Vector((xs * HAND_X, HAND_Y + 0.07 * arc, z))
        for side, key, xs in (("R", "RF", -1), ("L", "LF", 1)):
            z, arc = limb_height(s[key], FOOT_Z_HI)
            tgt["F" + side] = Vector((xs * FOOT_X, FOOT_Y + 0.12 * arc, z + 0.05 * arc))
            tgt["a" + side] = arc
        # --- FK head positions for the trunk
        P = {}
        def head_of(name):
            if name in P: return P[name]
            par = parent[name]
            if par is None: P[name] = hips
            else: P[name] = head_of(par) + D[par] @ (H0[name] - H0[par])
            return P[name]
        for n in ("Hips", "Spine02", "Spine01", "Spine", "neck", "Head"):
            head_of(n)
        D["head_end"] = D["Head"]; D["headfront"] = D["Head"]
        D["LeftShoulder"] = D["Spine"]; D["RightShoulder"] = D["Spine"]
        # shoulder girdle lifts a bit when the arm reaches high
        for side, nm in (("L", "LeftShoulder"), ("R", "RightShoulder")):
            z = tgt["H" + side].z
            lift = max(0.0, (z - 1.45)) * 14.0
            D[nm] = D["Spine"] @ roty(-lift if side == "L" else lift)
        for n in ("LeftShoulder", "RightShoulder"):
            head_of(n)
        pre = "L" if True else ""
        for side, p in (("L", "Left"), ("R", "Right")):
            xs = 1 if side == "L" else -1
            a, b, c, d = LEN[side]
            # arm: elbows flare out and down
            root = head_of(p + "Arm")
            elbow, wrist, cl = two_bone(root, tgt["H" + side], Vector((xs * 0.7, 0.55, -0.9)), a, b)
            stats["clamp"][p + "Hand"] = stats["clamp"].get(p + "Hand", 0) + (1 if cl else 0)
            D[p + "Arm"] = rest_dir(p + "Arm", p + "ForeArm").rotation_difference(elbow - root)
            D[p + "ForeArm"] = rest_dir(p + "ForeArm", p + "Hand").rotation_difference(wrist - elbow)
            D[p + "Hand"] = D[p + "ForeArm"]
            # leg: knees point forward (into the ropes) and slightly out
            lroot = head_of(p + "UpLeg")
            knee, ankle, cl = two_bone(lroot, tgt["F" + side], Vector((xs * 0.25, -1.0, 0.1)), c, d)
            stats["clamp"][p + "Foot"] = stats["clamp"].get(p + "Foot", 0) + (1 if cl else 0)
            D[p + "UpLeg"] = rest_dir(p + "UpLeg", p + "Leg").rotation_difference(knee - lroot)
            D[p + "Leg"] = rest_dir(p + "Leg", p + "Foot").rotation_difference(ankle - knee)
            arc = tgt["a" + side]
            pitch_down = 24.0 - 38.0 * arc            # ball of the foot on the rung while in contact, toes lift in the swing
            fd = Vector((xs * 0.16, -math.cos(math.radians(pitch_down)), -math.sin(math.radians(pitch_down)))).normalized()
            D[p + "Foot"] = foot_rest[side].rotation_difference(fd)
            D[p + "ToeBase"] = D[p + "Foot"]
            stats["min_knee"] = min(stats["min_knee"], (knee - lroot).normalized().dot((ankle - knee).normalized()))
        return D, hips, tgt

    def roll_q(roll_deg, twist_deg, pitch_deg):
        return rotz(twist_deg) @ roty(roll_deg) @ rotx(pitch_deg)

    # --- key the action
    arm.animation_data_create()
    act = bpy.data.actions.new("ratline_climb")
    arm.animation_data.action = act
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = N - 1
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    out = {"fps": FPS, "frames": N, "cycle_s": CYCLE_S, "rise_per_cycle_m": RISE_PER_CYCLE, "rung_spacing_m": RUNG_SPACING,
           "hips_rest_m": list(H0["Hips"]), "bones": order, "delta": [], "hips_offset_m": []}
    for f in range(N):
        u = f / N
        D, hips, tgt = pose(u)
        for n in order:
            pb = arm.pose.bones[n]
            par = parent[n]
            dq = D.get(n, Quaternion())
            dp = D.get(par, Quaternion()) if par else Quaternion()
            if n not in D:   # bones with no explicit delta follow the parent rigidly
                dq = dp
                D[n] = dq
            B = RB[n].inverted() @ dp.inverted() @ dq @ RB[n]
            pb.rotation_quaternion = B
            if par is None:
                loc_m = RB[n].inverted() @ (hips - H0[n])
                pb.location = loc_m / M
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if par is None:
                pb.keyframe_insert("location", frame=f)
        out["delta"].append({n: [D[n].w, D[n].x, D[n].y, D[n].z] for n in order})
        out["hips_offset_m"].append(list(hips - H0["Hips"]))
    for fc in act.fcurves if hasattr(act, "fcurves") else []:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    print("[ratline] IK clamp counts (reach limit hit)", stats["clamp"], "min leg straightness dot", round(stats["min_knee"], 3))
    with open(os.path.join(HERE, "ratline_climb.json"), "w") as fh:
        json.dump(out, fh)
    if preview:
        render_preview(arm, tgt_fn=pose, outdir=preview)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "src", "ratline_climb.blend"), compress=True)


def render_preview(arm, tgt_fn, outdir):
    import bmesh
    os.makedirs(outdir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'SINGLE'
    sc.display.shading.single_color = (0.75, 0.55, 0.4)
    sc.world = bpy.data.worlds.new('w')
    sc.world.color = (0.25, 0.3, 0.38)
    sc.display.shading.background_type = 'WORLD'
    sc.render.resolution_x, sc.render.resolution_y = 480, 640
    # ratline reference: two shrouds and rungs that slide down at the body's rise speed
    def box(name, size, loc, col):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        o = bpy.context.active_object
        o.name = name
        o.scale = size
        mat = bpy.data.materials.new(name + "m")
        mat.diffuse_color = col
        o.data.materials.append(mat)
        return o
    for sx in (-1, 1):
        box("shroud%d" % sx, (0.012, 0.012, 3.0), (sx * HAND_X, HAND_Y, 1.0), (1.0, 0.9, 0.1, 1))
    rungs = []
    for k in range(-3, 9):
        rungs.append(box("rung%d" % k, (0.46, 0.014, 0.014), (0, FOOT_Y - 0.115, 0), (0.1, 0.9, 0.2, 1)))
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.4
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    sc.camera = cam
    views = {"side": ((6, -0.2, 1.0), (math.radians(90), 0, math.radians(90))),
             "front": ((-0.2, 6, 1.0), (math.radians(90), 0, math.radians(180))),
             "threeq": ((-3.5, 3.5, 1.4), (math.radians(80), 0, math.radians(225)))}
    cam_data.ortho_scale = 2.2
    for f in (0, 5, 11, 16, 21, 26, 32, 37):
        sc.frame_set(f)
        u = f / N
        for i, r in enumerate(rungs):
            k = i - 3
            r.location.z = ((k * RUNG_SPACING - RISE_PER_CYCLE * u + 0.0) % (RUNG_SPACING * 12)) - RUNG_SPACING * 3 + 0.03 - 0.0
        for vn, (loc, rot) in views.items():
            cam.location = loc
            cam.rotation_euler = rot
            sc.render.filepath = os.path.join(outdir, "rl_%s_%02d.png" % (vn, f))
            bpy.ops.render.render(write_still=True)


main()
