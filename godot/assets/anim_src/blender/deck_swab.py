# Blender CLI: looping "swab the deck" clip for the Meshy crew rig (1.6 s): two-handed grip on a 1.3 m mop pole, the mop head sweeps side to side
# (+-0.38 m) on the deck with a small push/pull, the crew leans forward over the front foot and twists with the sweep. Pole: head on the deck, right
# hand 0.90 m and left hand 1.15 m up the pole. blender -b --python deck_swab.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 48
D_R, D_L = 1.04, 1.22   # grip distances from the mop head along the pole

def main():
    rig = Rig()
    H0 = rig.H0
    def frame(u):
        w = 2 * math.pi * u
        sweep = math.sin(w)
        hips = Vector((0.07 * sweep, H0["Hips"].y - 0.16, 0.95 + 0.006 * math.cos(2 * w)))
        twist = 12.0 * sweep
        k = {"Hips": (0.1, 0.4), "Spine02": (0.3, 0.55), "Spine01": (0.5, 0.75), "Spine": (0.7, 0.9), "neck": (0.9, 1.0), "Head": (0.9, 0.5)}
        trunk = {n: trunk_q(3.0 * sweep * f[0], twist * f[0], 26.0 * f[1]) for n, f in k.items()}
        _, P0 = rig.solve(hips, trunk)
        head_pos = Vector((0.38 * sweep, -0.46 + 0.06 * math.cos(2 * w), 0.03))
        chest = P0["Spine"]
        g_l_want = chest + Vector((0.12 * sweep, -0.24, -0.05))
        dirv = (g_l_want - head_pos).normalized()          # head -> top of the pole
        A_toward_head = -dirv
        hands = {}
        for s, dist, pole, xs in (("R", D_R, Vector((-0.8, 0.6, -0.6)), -1), ("L", D_L, Vector((0.8, 0.6, -0.6)), 1)):
            grip = head_pos + dirv * dist
            N_side = Vector((-xs, 0, 0))   # towards the pole axis, from the palm (right hand at -x: +x)
            hands[s] = (grip, A_toward_head, N_side, pole)
        feet = {"L": (Vector((0.22, H0["LeftFoot"].y - 0.22, H0["LeftFoot"].z)), Quaternion(), Vector((0.2, -1.0, 0.1))),
                "R": (Vector((-0.24, H0["RightFoot"].y + 0.14, H0["RightFoot"].z)), Quaternion(), Vector((-0.2, -1.0, 0.1)))}
        D, _ = rig.solve(hips, trunk, hands, feet)
        if os.environ.get('SWAB_DEBUG'): print('[dbg] u=%.2f R=%.2f L=%.2f' % (u, rig.last_stretch['R'], rig.last_stretch['L']))
        return hips, D

    rig.key("deck_swab", N, FPS, frame)

main()
