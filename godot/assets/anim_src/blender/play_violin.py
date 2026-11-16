# Blender CLI: looping "play the violin" clip for the Meshy crew rig (2.4 s): standing, violin under the chin on the left shoulder pointing ahead and a little
# left, left hand on the neck, right arm drawing the bow across the strings (+-0.19 m, two strokes per loop), head tilted onto the chin rest, slight sway.
# The violin and bow are props (violin.gd); this clip only places the hands: violin body centre about (0.07, -0.19, 1.50), neck 0.30 m to the left hand.
# blender -b --python play_violin.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 72

def main():
    rig = Rig()
    H0 = rig.H0
    feet = {"L": (Vector((0.20, H0["LeftFoot"].y - 0.04, H0["LeftFoot"].z)), Quaternion(), Vector((0.2, -1.0, 0.0))),
            "R": (Vector((-0.24, H0["RightFoot"].y + 0.06, H0["RightFoot"].z)), Quaternion(), Vector((-0.2, -1.0, 0.0)))}
    neck_dir = Vector((0.25, -0.95, 0.12)).normalized()
    body = Vector((0.07, -0.19, 1.50))
    def frame(u):
        w = 2 * math.pi * u
        hips = Vector((0.015 * math.sin(w), H0["Hips"].y, 1.07 + 0.005 * math.sin(2 * w)))
        k = {"Hips": 0.05, "Spine02": 0.2, "Spine01": 0.4, "Spine": 0.65, "neck": 0.9, "Head": 1.0}
        trunk = {n: trunk_q(-2.0 * math.sin(w) * f, 5.0 * f + 2.0 * math.sin(w) * f, 3.0 * f) for n, f in k.items()}
        trunk["Head"] = trunk_q(8.0, 10.0, 6.0)
        stroke = 0.19 * math.sin(2 * w)                          # bow position along x, two strokes per loop
        lh = body + neck_dir * 0.30
        hands = {"L": (lh, neck_dir, Vector((0.0, 0.0, 1.0)), Vector((0.6, 0.4, -0.7))),
                 "R": (Vector((-0.12 + stroke, -0.40, 1.30 + 0.015 * math.sin(w))), Vector((1.0, 0.0, 0.0)), Vector((0.0, 0.2, -1.0)), Vector((-0.7, 0.5, -0.7)))}
        D, _ = rig.solve(hips, trunk, hands, feet)
        return hips, D
    rig.key("play_violin", N, FPS, frame)

main()
