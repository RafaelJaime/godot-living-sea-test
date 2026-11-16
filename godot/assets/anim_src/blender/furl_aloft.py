# Blender CLI: looping "furl a sail from the footrope" clip for the Meshy crew rig (1.6 s): the crew stands on the footrope facing the yard, belly leaning on it,
# and gathers canvas with both hands, alternating hand over hand: each hand reaches down and out over the sail, hooks it and hauls it up and in. In place,
# feet planted on the rope (ankles at the rest height, pivot of the station = the footrope). blender -b --python furl_aloft.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 48

def main():
    rig = Rig()
    H0 = rig.H0
    feet = {"L": (Vector((0.16, -0.20, H0["LeftFoot"].z)), Quaternion(), Vector((0.1, -1.0, 0.0))),
            "R": (Vector((-0.16, -0.20, H0["RightFoot"].z)), Quaternion(), Vector((-0.1, -1.0, 0.0)))}
    def frame(u):
        w = 2 * math.pi * u
        hips = Vector((0.0, H0["Hips"].y + 0.17, 0.95 + 0.012 * math.sin(2 * w)))
        k = {"Hips": (0.0, 0.2), "Spine02": (0.3, 0.45), "Spine01": (0.6, 0.7), "Spine": (0.9, 0.9), "neck": (1.0, 1.0), "Head": (0.9, 0.35)}
        twist = 6.0 * math.sin(w)
        trunk = {n: trunk_q(2.0 * math.sin(w) * f[0], twist * f[0], 24.0 * f[1] + 2.0 * math.sin(2 * w)) for n, f in k.items()}
        hands = {}
        for s, ph, xs, pole in (("R", 0.0, -1, Vector((-0.7, 0.5, -0.8))), ("L", 0.5, 1, Vector((0.7, 0.5, -0.8)))):
            q = (u - ph) % 1.0
            p = ease(q / 0.6) if q < 0.6 else 1.0 - ease((q - 0.6) / 0.4)
            grip = Vector((xs * 0.28, -0.52 + 0.20 * p, 1.08 + 0.26 * p))
            hands[s] = (grip, Vector((0.0, -0.7, -0.7)), Vector((0.0, 0.7, -0.7)), pole, "FN")
        D, _ = rig.solve(hips, trunk, hands, feet)
        return hips, D
    rig.key("furl_aloft", N, FPS, frame)

main()
