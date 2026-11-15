# Blender CLI: looping "look through the spyglass" clip for the Meshy crew rig (2.4 s): the right hand brings the brass spyglass to the right eye,
# the left hand supports it near the objective, the body pans slowly along the horizon (+-12 deg) with a breath bob. Spyglass: 0.45 m, eyepiece at the
# right eye, tube pointing 7 deg above the horizon in the head's direction. blender -b --python spyglass_look.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from clip_lib import *

FPS, N = 30, 72
TUBE_R, TUBE_L = 0.18, 0.30   # grip distances from the eyepiece
EYE_OFF = Vector((-0.032, -0.085, 0.11))   # right eye relative to the Head bone head, in the head frame

def main():
    rig = Rig()
    H0 = rig.H0
    feet_rest = {"L": H0["LeftFoot"], "R": H0["RightFoot"]}

    def frame(u):
        pan = 12.0 * math.sin(2 * math.pi * u)
        breath = 0.004 * math.sin(2 * math.pi * u * 3)
        hips = Vector((0.0, H0["Hips"].y + 0.02, 1.07 + breath))
        k = {"Hips": 0.15, "Spine02": 0.3, "Spine01": 0.5, "Spine": 0.7, "neck": 0.9, "Head": 1.0}
        trunk = {n: trunk_q(0.0, pan * f, -3.0 * f) for n, f in k.items()}
        trunk["Head"] = trunk_q(0.0, pan, 2.0)
        # a first pass without hands gives the head position/orientation
        _, P0 = rig.solve(hips, trunk)
        eye = P0["Head"] + trunk["Head"] @ EYE_OFF
        d0 = Vector((0, -math.cos(math.radians(7)), math.sin(math.radians(7))))
        D_t = (rotz(pan) @ d0).normalized()
        up = Vector((0, 0, 1))
        Nn = (up - D_t * up.dot(D_t)).normalized()
        hands = {"R": (eye + D_t * TUBE_R, D_t, Nn, Vector((-0.6, 0.6, -0.8))),
                 "L": (eye + D_t * TUBE_L, D_t, Nn, Vector((0.6, 0.5, -0.8)))}
        feet = {"L": (feet_rest["L"], Quaternion(), Vector((0.2, -1.0, 0.0))),
                "R": (feet_rest["R"], Quaternion(), Vector((-0.2, -1.0, 0.0)))}
        D, _ = rig.solve(hips, trunk, hands, feet)
        return hips, D

    rig.key("spyglass_look", N, FPS, frame)

main()
