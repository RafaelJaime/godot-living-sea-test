# Hand props (chosen set)

Grip-ready scenes for the crew: add `res://assets/props/<id>_prop.tscn` as a child of a `BoneAttachment3D` on the **right hand** bone (`RightHand` of the 24-bone Meshy rig). `hand_prop.gd` puts the prop in the hand (grip point, rotation and scale are exported data, solved by `build_hand_props.gd`; units: bone-local offsets are cm because the Armature has scale 0.01). Lantern: `upright` keeps the world orientation and only the grip follows the hand.

| scene | prop | real length | source | licence | clip it was tested with |
|-------|------|-------------|--------|---------|-------------------------|
| `fishing_rod_prop.tscn` | fishing rod, no reel (Quaternius `rod_q1`) | 2.0 m | Quaternius via poly.pizza (m/0YAR0Lg58p) | CC0 1.0 | `baked_fishing_cast` |
| `hammer_prop.tscn` | wooden hammer (Poly Haven `wooden_hammer_01`) | 0.28 m | https://polyhaven.com/a/wooden_hammer_01 | CC0 | `baked_hammering` |
| `saw_prop.tscn` | hand saw (Poly Haven `handsaw_wood`) | 0.63 m | https://polyhaven.com/a/handsaw_wood | CC0 | `baked_sawing` |
| `lantern_prop.tscn` | wooden lantern (Poly Haven `wooden_lantern_01`) | 0.35 m (authored 0.53, scaled 0.66) | https://polyhaven.com/a/wooden_lantern_01 | CC0 | `baked_idle_lantern` |
| `spyglass_prop.tscn` | brass spyglass, 3 tubes (generated, cylinders) | 0.45 m extended | own | CC0 | `spyglass_look` (authored) |
| `mop_prop.tscn` | rope-head swab (generated, cylinders) | 1.3 m | own | CC0 | `deck_swab` (authored) |

Clips (Blender-authored, `godot/assets/anim_src/blender/`): `spyglass_look.res` (2.4 s loop, right hand at the right eye, left hand under the tube, +-12 deg pan) and `deck_swab.res` (1.6 s loop, two-handed pole grip, +-0.38 m sweep, lunge), plus `ratline_climb.res`. Spyglass: eyepiece grip 0.18 m / support 0.30 m from the eye end, tube 7 deg above the horizon. Swab: right hand 1.04 m and left hand 1.22 m from the mop head.
All clips are in place; `ratline_climb_bake.gd -- <name>` bakes any `<name>.json` into `<name>.res`.

Which hand each clip uses (travel of each wrist over the clip, `props_cand/hand_motion.gd` in the candidates branch): hammering R 184 cm vs L 80 (hammer in R, L steadies); sawing R 146 vs L 22; fishing cast R 220 vs L 112, reeling L 112 vs R 11 (R holds the rod, L cranks); idle_lantern R raised forward (h 146 cm), L at the hip: lantern in R.

Regenerate the scenes: `godot --headless --path godot --script res://assets/props/build_hand_props.gd`. Captures: `props_final_capture.tscn` (`odd/evidence/npc-crew-jobs/C4/props_final_*.png`). Orientation search: `grip_solve.gd -- <clip(s)> Right <want_u> <want_v|none>`.

Known limits: hands have no fingers (mittens, no wrap); the saw's teeth-down orientation comes from a grid search against the sawing clip (mean 11 deg off), not from a hand-authored grip; the hammer and rod grips are plausible but not frame-accurate in every phase; the Poly Haven models are 1k textures.
