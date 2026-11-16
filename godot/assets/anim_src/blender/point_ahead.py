# Blender CLI: "point ahead" gesture for the Meshy crew rig (2.4 s, not a loop): the right arm rises to point at the horizon off the bow (slightly up), holds with a
# small tremble while the head follows, and lowers; the left hand rests on the hip. Starts and ends in the standing pose. blender -b --python point_ahead.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 72

def main():
    rig = Rig()
    H0 = rig.H0
    feet = {"L": (rig.H0["LeftFoot"], Quaternion(), Vector((0.2, -1.0, 0.0))), "R": (rig.H0["RightFoot"], Quaternion(), Vector((-0.2, -1.0, 0.0)))}
    def frame(u):
        t = u * N / FPS
        raise_ = keys(t, [(0.0, 0.0), (0.7, 1.0), (1.75, 1.0), (2.4, 0.0)])
        hips = Vector((0.0, H0["Hips"].y, 1.065))
        yaw = 8.0 * raise_
        k = {"Hips": 0.1, "Spine02": 0.3, "Spine01": 0.5, "Spine": 0.7, "neck": 0.9, "Head": 1.0}
        trunk = {n: trunk_q(0.0, -yaw * f, -2.0 * raise_ * f) for n, f in k.items()}
        trunk["Head"] = trunk_q(0.0, -yaw * 0.6, -4.0 * raise_)
        _, P0 = rig.solve(hips, trunk)
        sh = P0["RightArm"]
        tremble = 0.012 * math.sin(2 * math.pi * 5 * t) * raise_
        dirv = (rotz(-yaw) @ Vector((0.0, -0.95, 0.32))).normalized()
        rest = Vector((sh.x - 0.12, sh.y - 0.04, sh.z - 0.56))             # hanging arm
        point = sh + dirv * 0.56 + Vector((0.0, 0.0, tremble))
        grip = rest * (1.0 - raise_) + point * raise_
        hands = {"R": (grip, dirv, Vector((0.0, 0.0, -1.0)), Vector((-0.5, 0.6, -0.7)), "FN"),
                 "L": (Vector((0.30, H0["Hips"].y - 0.12, 1.02)), Vector((-0.5, -0.2, -0.85)), Vector((-0.8, 0.6, 0.0)), Vector((0.9, 0.6, -0.3)), "FN")}
        D, _ = rig.solve(hips, trunk, hands, feet)
        return hips, D
    rig.key("point_ahead", N, FPS, frame)

main()
