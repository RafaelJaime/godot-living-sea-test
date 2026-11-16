# Blender CLI: "comic fall" clip for the Meshy crew rig (3.0 s, not a loop, starts and ends standing in the same place): a trip (the left foot catches), arms windmill,
# a face-first fall onto the hands, a beat lying flat, then pushing back up and straightening. The body ends where it started (feet stay on their spots,
# the hips travel about 0.75 m ahead and come back as the crew gets up). blender -b --python comic_fall.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 90

def main():
    rig = Rig()
    H0 = rig.H0
    Lr, Rr = Vector(H0["LeftFoot"]), Vector(H0["RightFoot"])
    def frame(u):
        t = u * N / FPS
        hy = keys(t, [(0, 0.0), (0.5, 0.0), (1.0, -0.35), (1.35, -0.75), (1.9, -0.75), (2.4, -0.40), (2.8, -0.05), (3.0, 0.0)])
        hz = keys(t, [(0, 1.07), (0.5, 1.03), (0.9, 0.95), (1.3, 0.34), (1.9, 0.30), (2.3, 0.58), (2.7, 0.92), (3.0, 1.07)])
        pitch = keys(t, [(0, 0.0), (0.5, 12.0), (0.9, 45.0), (1.3, 84.0), (1.9, 84.0), (2.4, 50.0), (2.8, 8.0), (3.0, 0.0)])
        wf = keys(t, [(0, 0.0), (0.45, 0.0), (0.6, 1.0), (1.05, 1.0), (1.25, 0.0), (3.0, 0.0)])      # arms flailing
        wg = keys(t, [(0, 0.0), (1.05, 0.0), (1.3, 1.0), (1.95, 1.0), (2.25, 0.0), (3.0, 0.0)])        # hands on the deck
        hips = Vector((0.0, H0["Hips"].y + hy, hz))
        twist = 14.0 * math.sin(2 * math.pi * 1.6 * (t - 0.5)) * wf
        k = {"Hips": 0.8, "Spine02": 0.85, "Spine01": 0.9, "Spine": 0.95, "neck": 0.85, "Head": 0.45}
        trunk = {n: trunk_q(0.0, twist * f, pitch * f) for n, f in k.items()}
        _, P0 = rig.solve(hips, trunk)
        hands = {}
        for s, xs, pole, ph in (("R", -1, Vector((-0.7, 0.4, -0.6)), 0.0), ("L", 1, Vector((0.7, 0.4, -0.6)), math.pi)):
            sh = P0["RightArm" if s == "R" else "LeftArm"]
            hang = sh + Vector((xs * 0.09, 0.0, -0.56))
            ang = 2 * math.pi * 1.9 * (t - 0.5) + ph
            flail = sh + Vector((xs * 0.16, -0.20 + 0.24 * math.sin(ang), 0.0 + 0.24 * math.cos(ang)))
            ground = Vector((xs * 0.30, sh.y - 0.34, 0.05))
            grip = hang * (1.0 - wf - wg) + flail * wf + ground * wg
            F = Vector((0.0, -0.3, -0.95)) * (1.0 - wg) + Vector((0.0, -1.0, 0.0)) * wg
            Nn = Vector((-xs, 0.0, 0.0)) * (1.0 - wg) + Vector((0.0, 0.0, -1.0)) * wg
            hands[s] = (grip, F, Nn, pole, "FN")
        lf = keys(t, [(0, Lr), (0.4, Lr), (0.85, Vector((0.24, -0.52, Lr.z))), (1.0, Vector((0.24, -0.52, Lr.z))), (1.4, Vector((0.24, -0.22, Lr.z))), (2.3, Vector((0.24, -0.22, Lr.z))), (2.9, Lr)])
        feet = {"L": (lf, Quaternion(), Vector((0.2, -1.0, 0.2))), "R": (Rr, Quaternion(), Vector((-0.2, -1.0, 0.2)))}
        D, _ = rig.solve(hips, trunk, hands, feet)
        if os.environ.get('FALL_DEBUG'): print('[dbg] t=%.2f R=%.2f L=%.2f wf=%.2f wg=%.2f' % (t, rig.last_stretch['R'], rig.last_stretch['L'], wf, wg))
        return hips, D
    rig.key("comic_fall", N, FPS, frame)

main()
