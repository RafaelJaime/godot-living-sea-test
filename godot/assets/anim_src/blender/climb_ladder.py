# Blender CLI: vertical ladder climb for the Meshy crew rig, two clips: `climb_ladder` (1.2 s loop, in place: the body stays at the same ladder height and the rungs slide
# down at RISE_PER_CYCLE per cycle, 0.40 m/s, rung spacing 0.24 m: each limb advances two rungs per cycle, three limbs in contact most of the time) and `climb_ladder_off`
# (1.0 s, not a loop: from the climbing pose to standing on the deck above, the hips move 0.35 m ahead and 0.07 m up, feet and hands release the rungs).
# Ladder geometry: rungs 0.24 m apart in the plane y = -0.42 (character faces -y), hands at x +-0.20, feet at x +-0.13 with the ball of the foot on the rung.
# blender -b --python climb_ladder.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N, N_OFF = 30, 36, 30
STANCE = 0.75
STRIDE = 0.36
RISE = STRIDE / STANCE          # 0.48 m per cycle = two rungs
HIPS_Y, HIPS_Z = -0.06, 1.00
LEAN = 5.0
HAND_Y, HAND_X, HAND_Z_HI = -0.42, 0.20, 1.70
FOOT_Y, FOOT_X, FOOT_Z_HI = -0.28, 0.13, 0.62


def hermite(z0, z1, m0, m1, t):
    return (2 * t ** 3 - 3 * t ** 2 + 1) * z0 + (t ** 3 - 2 * t ** 2 + t) * m0 + (-2 * t ** 3 + 3 * t ** 2) * z1 + (t ** 3 - t ** 2) * m1


def limb(s, z_hi):
    """(body-frame height, out-of-plane arc 0..1) of a limb at its own phase s."""
    if s < STANCE:
        return z_hi - RISE * s, 0.0
    t = (s - STANCE) / (1.0 - STANCE)
    m = -RISE * (1.0 - STANCE)
    return hermite(z_hi - STRIDE, z_hi, m, m, t), math.sin(math.pi * t)


def climb_state(rig, u):
    """Targets of the climbing pose at cycle phase u: hips, trunk deltas, hand specs, foot specs."""
    ph = {"RH": 0.0, "LF": 0.0, "LH": 0.5, "RF": 0.5}
    s = {k: (u - v) % 1.0 for k, v in ph.items()}
    w = 2 * math.pi * u
    hips = Vector((-0.012 * math.cos(w - 0.8), HIPS_Y, HIPS_Z + 0.012 * math.cos(2 * w + 0.6)))
    twist = 4.0 * math.sin(w - 0.5)
    k = {"Hips": (0.0, 0.2), "Spine02": (0.35, 0.4), "Spine01": (0.6, 0.65), "Spine": (0.9, 0.85), "neck": (1.0, 0.95), "Head": (0.9, 0.2)}
    trunk = {n: trunk_q(-2.0 * math.cos(w - 0.8) * f[0], twist * f[0], LEAN * f[1]) for n, f in k.items()}
    hands, feet = {}, {}
    for side, key, xs, pole in (("R", "RH", -1, Vector((-0.7, 0.55, -0.9))), ("L", "LH", 1, Vector((0.7, 0.55, -0.9)))):
        z, arc = limb(s[key], HAND_Z_HI)
        hands[side] = (Vector((xs * HAND_X, HAND_Y + 0.06 * arc, z)), Vector((0.0, -0.2, -0.98)), Vector((0.0, -0.98, 0.2)), pole, "FN")
    for side, key, xs, p in (("R", "RF", -1, "Right"), ("L", "LF", 1, "Left")):
        z, arc = limb(s[key], FOOT_Z_HI)
        pd = 24.0 - 38.0 * arc
        fd = Vector((xs * 0.12, -math.cos(math.radians(pd)), -math.sin(math.radians(pd)))).normalized()
        fdelta = rig.rest_dir(p + "Foot", p + "ToeBase").rotation_difference(fd)
        feet[side] = (Vector((xs * FOOT_X, FOOT_Y + 0.10 * arc, z + 0.05 * arc)), fdelta, Vector((xs * 0.25, -1.0, 0.1)))
    return hips, trunk, hands, feet


def main():
    rig = Rig()
    def loop(u):
        hips, trunk, hands, feet = climb_state(rig, u)
        D, _ = rig.solve(hips, trunk, hands, feet)
        return hips, D
    rig.key("climb_ladder", N, FPS, loop)
    print("[climb_ladder] rise per cycle %.3f m, speed %.3f m/s, rung spacing %.2f m" % (RISE, RISE * FPS / N, RISE / 2))

    rig2 = Rig()
    H0 = rig2.H0
    h0, t0, hands0, feet0 = climb_state(rig2, 0.0)
    # standing on the deck above: feet at the rest ankles of the rig, hands hanging, trunk upright
    stand_hips = Vector((0.0, HIPS_Y - 0.35, 1.07))
    def off(u):
        a = ease(u * N_OFF / FPS / 1.0)       # N_OFF frames over 1.0 s
        hips = h0 * (1.0 - a) + stand_hips * a
        k = {"Hips": 0.1, "Spine02": 0.3, "Spine01": 0.5, "Spine": 0.7, "neck": 0.9, "Head": 1.0}
        trunk = {n: t0[n].slerp(Quaternion(), a) for n in t0}
        _, P0 = rig2.solve(hips, trunk)
        hands = {}
        for s_, hs in hands0.items():
            sh = P0["LeftArm" if s_ == "L" else "RightArm"]
            xs = 1 if s_ == "L" else -1
            hang = sh + Vector((xs * 0.09, 0.0, -0.56))
            rel = ease(max(0.0, (a - 0.15) / 0.5)) if s_ == "R" else ease(max(0.0, (a - 0.0) / 0.5))   # the left hand lets go first
            grip = hs[0] * (1.0 - rel) + hang * rel
            F = hs[1] * (1.0 - rel) + Vector((0.0, -0.3, -0.95)) * rel
            Nn = hs[2] * (1.0 - rel) + Vector((-xs, 0.0, 0.0)) * rel
            hands[s_] = (grip, F, Nn, hs[3], "FN")
        feet = {}
        for s_, fs in feet0.items():
            p = "Left" if s_ == "L" else "Right"
            rest = Vector(H0[p + "Foot"])
            tgt = fs[0] * (1.0 - a) + (rest + Vector((0.0, -0.35, 0.0))) * a
            fd = fs[1].slerp(Quaternion(), a)
            feet[s_] = (tgt, fd, fs[2])
        D, _ = rig2.solve(hips, trunk, hands, feet)
        return hips, D
    rig2.key("climb_ladder_off", N_OFF, FPS, off)

main()
