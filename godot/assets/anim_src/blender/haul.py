# Blender CLI: looping "haul a brace" clip for the Meshy crew rig (1.5 s): feet planted wide, leaning back, hand over hand on a line that leads up and ahead (the
# brace pin on the rail): the right hand hauls down and back while the left reaches up and ahead, then they swap. In place. blender -b --python haul.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 45

def main():
    rig = Rig()
    H0 = rig.H0
    feet = {"L": (Vector((0.28, H0["LeftFoot"].y - 0.30, H0["LeftFoot"].z)), Quaternion(), Vector((0.2, -1.0, 0.0))),
            "R": (Vector((-0.30, H0["RightFoot"].y + 0.20, H0["RightFoot"].z)), Quaternion(), Vector((-0.2, -1.0, 0.0)))}
    rope_dir = Vector((0.0, -0.45, 0.89)).normalized()   # up and ahead
    def frame(u):
        w = 2 * math.pi * u
        pull = 0.5 - 0.5 * math.cos(2 * w)               # body rocks back on each haul
        hips = Vector((0.0, H0["Hips"].y + 0.10 + 0.07 * pull, 0.97 - 0.03 * pull))
        k = {"Hips": (0.0, 0.1), "Spine02": (0.3, 0.3), "Spine01": (0.6, 0.55), "Spine": (0.9, 0.8), "neck": (1.0, 0.9), "Head": (0.9, 0.4)}
        trunk = {n: trunk_q(2.5 * math.sin(w) * f[0], 5.0 * math.sin(w) * f[0], (-8.0 * pull + 6.0) * f[1]) for n, f in k.items()}
        hands = {}
        for s, ph, xs, pole in (("R", 0.0, -1, Vector((-0.7, 0.4, -0.8))), ("L", 0.5, 1, Vector((0.7, 0.4, -0.8)))):
            q = (u - ph) % 1.0
            p = ease(q / 0.55) if q < 0.55 else 1.0 - ease((q - 0.55) / 0.45)   # 1 = hauled all the way down and back
            grip = Vector((xs * 0.13, -0.48 + 0.34 * p, 1.52 - 0.56 * p))
            hands[s] = (grip, rope_dir, Vector((-xs, 0.0, 0.0)), pole)
        D, _ = rig.solve(hips, trunk, hands, feet)
        return hips, D
    rig.key("haul", N, FPS, frame)

main()
