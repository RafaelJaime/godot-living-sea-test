#!/usr/bin/env python3
"""Writes ship_stations.tscn: Marker3D stations and navigation nodes in Ship/Pivot space (+x starboard, -z bow, y up from the waterline).
Positions come from odd/evidence/npc-crew-jobs/H1/deck_survey.md (deck levels: poop 6.4-6.8, quarterdeck 4.9 -> 3.85, waist 1.85, forecastle 3.5).
Marker metadata: kind, slots, facing_deg (0 = -Z bow, +90 = -X port), anim_tag, must_staff, and for nav nodes edge_to = "name[:type],..." (type defaults to edge_type).
Run:  python3 godot/ship/gen_ship_stations.py > godot/ship/ship_stations.tscn   (hand edits are fine too: this file is only the starting point)."""

# (name, kind, (x, y, z), facing_deg, slots, anim_tag, must_staff)
STATIONS = [
    ("helm", "helm", (0.0, 6.85, 17.0), 0.0, 1, "steer", True),
    ("spyglass_post", "spyglass_post", (0.0, 3.9, -9.6), 0.0, 1, "spyglass", False),
    ("crows_nest", "crows_nest", (0.0, 23.4, 2.8), 0.0, 1, "lookout", False),
    ("ratline_port", "ratline_path", (-2.1, 1.9, 0.5), -90.0, 1, "climb", False),
    ("ratline_starboard", "ratline_path", (2.1, 1.9, 0.5), 90.0, 1, "climb", False),
    ("chart_table", "chart_table", (-2.4, 4.45, 10.5), 90.0, 1, "chart", False),
    ("violin_seat", "violin_seat", (0.0, 4.09, -10.6), 180.0, 1, "violin", False),
    ("listen_spot_0", "listen_spot", (-1.8, 3.55, -8.3), -30.0, 1, "listen", False),
    ("listen_spot_1", "listen_spot", (1.8, 3.55, -8.3), 30.0, 1, "listen", False),
    ("listen_spot_2", "listen_spot", (0.0, 3.55, -7.2), 0.0, 1, "listen", False),
    ("social_spot_0", "social_spot", (-1.2, 1.85, 1.2), -90.0, 1, "talk", False),
    ("social_spot_1", "social_spot", (1.2, 1.85, 1.2), 90.0, 1, "talk", False),
    ("fishing_rail_0", "fishing_rail", (3.0, 1.85, -1.0), -90.0, 1, "fish", False),
    ("fishing_rail_1", "fishing_rail", (-3.0, 1.85, -1.0), 90.0, 1, "fish", False),
    ("repair_spot_0", "repair_spot", (2.2, 1.85, 0.5), 0.0, 1, "repair", False),
    ("repair_spot_1", "repair_spot", (-1.6, 1.85, -4.8), 0.0, 1, "repair", False),
    ("mop_zone_0", "mop_zone", (0.0, 1.85, 0.8), 0.0, 2, "mop", False),
    ("mop_zone_1", "mop_zone", (0.0, 4.55, 12.0), 0.0, 2, "mop", False),
    ("boat_check", "boat_check", (-1.6, 1.85, -2.8), -90.0, 1, "inspect", False),
]
# Mast bases the reef lines (one per sail, created in code) hang on: (name, x unused, y, z)
REEF_PINS = [("reef_pin_fore", (0.0, 3.55, -8.1)), ("reef_pin_main", (0.0, 1.85, 0.5)), ("reef_pin_mizzen", (0.0, 4.6, 11.9))]
# Access markers (not stations): stairs mid-points and the stand-in for the missing cabin door.
ACCESS = [
    ("stairs_poop", "stairs", (0.0, 5.7, 14.5)),
    ("stairs_waist", "stairs", (0.0, 2.9, 4.4)),
    ("stairs_forecastle", "stairs", (0.0, 2.7, -4.9)),
    ("door_companionway", "door", (0.0, 4.2, 9.0)),
]
# Navigation nodes: (name, (x, y, z), edge_to). Edge list "other[:type]". Types: walk (default), stairs, rope, ladder.
NAV = [
    ("n_poop_c", (0.0, 6.75, 17.0), "n_poop_top"),
    ("n_poop_top", (0.0, 6.5, 15.4), "n_quarter_a:stairs"),
    ("n_quarter_a", (0.0, 4.9, 13.5), "n_quarter_mid"),
    ("n_quarter_mid", (0.0, 4.5, 11.0), "n_quarter_b"),
    ("n_quarter_b", (0.0, 4.0, 6.0), "n_quarter_end"),
    ("n_quarter_end", (0.0, 3.85, 5.0), "n_waist_a:stairs"),
    ("n_waist_a", (0.0, 1.85, 3.5), "n_waist_b"),
    ("n_waist_b", (0.0, 1.85, 1.0), "n_waist_p,n_waist_s,n_ratline_p,n_ratline_s"),
    ("n_waist_p", (-1.6, 1.85, -2.8), "n_waist_f,n_lad_p_a"),
    ("n_waist_s", (1.6, 1.85, -2.8), "n_waist_f,n_lad_s_a"),
    ("n_waist_f", (0.0, 1.85, -4.0), "n_fore_a:stairs:6"),   # the foot of the central flight is inside the lashed boat: x6 cost so the crew takes the side ladders
    ("n_fore_a", (0.0, 3.5, -6.5), "n_fore_b"),
    ("n_fore_b", (0.0, 3.55, -8.5), "n_fore_bow"),
    ("n_fore_bow", (0.0, 3.9, -10.0), ""),
    ("n_ratline_p", (-2.1, 1.9, 0.5), "n_shroud_p:rope"),
    ("n_ratline_s", (2.1, 1.9, 0.5), "n_shroud_s:rope"),
    ("n_shroud_p", (-1.6, 9.0, 1.3), "n_nest:rope"),
    ("n_shroud_s", (1.6, 9.0, 1.3), "n_nest:rope"),
    ("n_nest", (0.0, 23.4, 2.8), ""),
]


# ---- aloft crew (yards, tops, braces) -------------------------------------------------------------------------------------------------------
# Yard of each sail (index = PinnaceRig sail order = ship.sail_defs): (idx, mast, yard bone centre y, yard bone centre z, half length). Measured with `--yard-survey`
# on the rest pose (yards square to the ship; braced yards move up to ~1 m in z at the stations, documented in the README). The spritsail (idx 9) has no aloft station.
YARDS = [
    (0, "fore", 19.67, -8.67, 2.2), (1, "fore", 15.74, -8.71, 3.2), (2, "fore", 9.88, -8.48, 3.65),
    (3, "main", 10.47, 2.43, 4.3), (4, "main", 17.11, 2.31, 3.6), (5, "main", 22.83, 2.51, 2.5),
    (6, "mizzen", 10.98, 12.34, 3.6), (7, "mizzen", 20.46, 12.43, 2.1), (8, "mizzen", 16.68, 12.27, 3.0),
]
FOOTROPE_DROP = 1.15   # footrope height below the yard
FOOTROPE_AFT = 0.45    # the crew stands on the aft side of the yard, facing the bow, hands on the yard
FOOTROPE_X = 0.55      # fraction of the half length from the mast
# Brace pins on deck, one per side and mast: (name, mast, (x, y, z)). Starboard (x > 0) faces outboard (-90), port faces +90.
BRACES = [
    ("brace_fore_p", "fore", (-3.0, 3.55, -6.8)), ("brace_fore_s", "fore", (3.0, 3.55, -6.8)),
    ("brace_main_p", "main", (-3.0, 1.85, 3.2)), ("brace_main_s", "main", (3.0, 1.85, 3.2)),
    ("brace_mizzen_p", "mizzen", (-3.0, 4.6, 13.4)), ("brace_mizzen_s", "mizzen", (3.0, 4.6, 13.4)),
]
# Extra navigation nodes for climbing: per mast base (deck node, ratline foot, shroud, top, tops of the upper stages). edge_to lists use "rope" for the climbs.
NAV_ALOFT = [
    # side ladders of the forecastle break (rungs at x +-3.0, z -5.16): foot on the waist deck, top on the forecastle deck, then to the forecastle walk node
    ("n_lad_p_a", (-2.9, 1.85, -4.3), "n_lad_p_b:ladder"), ("n_lad_s_a", (2.9, 1.85, -4.3), "n_lad_s_b:ladder"),
    ("n_lad_p_b", (-2.9, 3.55, -5.9), "n_fore_a"), ("n_lad_s_b", (2.9, 3.55, -5.9), "n_fore_a"),
    ("n_fore_rat_p", (-2.6, 3.55, -7.4), "n_fore_shroud_p:rope"), ("n_fore_rat_s", (2.6, 3.55, -7.4), "n_fore_shroud_s:rope"),
    ("n_fore_shroud_p", (-1.5, 9.4, -8.3), "n_top_fore:rope"), ("n_fore_shroud_s", (1.5, 9.4, -8.3), "n_top_fore:rope"),
    ("n_top_fore", (0.0, 11.9, -8.55), "n_fore_up_p:rope,n_fore_up_s:rope"),
    ("n_fore_up_p", (-1.5, 15.3, -8.6), "n_fore_tg_p:rope"), ("n_fore_up_s", (1.5, 15.3, -8.6), "n_fore_tg_s:rope"),
    ("n_fore_tg_p", (-1.2, 19.1, -8.6), ""), ("n_fore_tg_s", (1.2, 19.1, -8.6), ""),
    ("n_top_main", (0.0, 13.0, 2.4), "n_main_up_p:rope,n_main_up_s:rope"),
    ("n_main_up_p", (-1.5, 15.9, 2.4), "n_main_tg_p:rope"), ("n_main_up_s", (1.5, 15.9, 2.4), "n_main_tg_s:rope"),
    ("n_main_tg_p", (-1.2, 21.5, 2.5), "n_nest:rope"), ("n_main_tg_s", (1.2, 21.5, 2.5), "n_nest:rope"),
    ("n_miz_rat_p", (-2.4, 4.6, 11.4), "n_miz_shroud_p:rope"), ("n_miz_rat_s", (2.4, 4.6, 11.4), "n_miz_shroud_s:rope"),
    ("n_miz_shroud_p", (-1.5, 9.4, 12.2), "n_top_miz:rope"), ("n_miz_shroud_s", (1.5, 9.4, 12.2), "n_top_miz:rope"),
    ("n_top_miz", (0.0, 12.9, 12.4), "n_miz_up_p:rope,n_miz_up_s:rope"),
    ("n_miz_up_p", (-1.4, 15.9, 12.3), "n_miz_tg_p:rope"), ("n_miz_up_s", (1.4, 15.9, 12.3), "n_miz_tg_s:rope"),
    ("n_miz_tg_p", (-1.1, 19.7, 12.4), ""), ("n_miz_tg_s", (1.1, 19.7, 12.4), ""),
]
# Existing nodes that gain edges: name -> extra edge_to entries
NAV_EXTRA_EDGES = {
    "n_fore_b": "n_fore_rat_p,n_fore_rat_s", "n_quarter_mid": "n_miz_rat_p,n_miz_rat_s",
    "n_shroud_p": "n_top_main:rope", "n_shroud_s": "n_top_main:rope",
}

def tr(p):
    return "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, %g, %g)" % p

out = []
out.append('[gd_scene load_steps=2 format=3]\n')
out.append('[ext_resource type="Script" path="res://scripts/ship_stations.gd" id="1_stations"]\n')
out.append('[node name="ShipStations" type="Node3D"]\n')
out.append('[node name="Markers" type="Node3D" parent="."]\n')
for name, kind, p, f, slots, anim, staff in STATIONS:
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"%s"\nmetadata/slots = %d\nmetadata/facing_deg = %g\nmetadata/anim_tag = &"%s"\nmetadata/must_staff = %s\n' % (name, tr(p), kind, slots, f, anim, "true" if staff else "false"))
for name, p in REEF_PINS:
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"reef_pin"\n' % (name, tr(p)))
for name, kind, p in ACCESS:
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"%s"\n' % (name, tr(p), kind))
for name, p, edges in NAV:
    if name in NAV_EXTRA_EDGES:
        edges = (edges + "," if edges else "") + NAV_EXTRA_EDGES[name]
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"nav"\nmetadata/edge_to = "%s"\nmetadata/edge_type = &"walk"\n' % (name, tr(p), edges))
for name, p, edges in NAV_ALOFT:
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"nav"\nmetadata/edge_to = "%s"\nmetadata/edge_type = &"walk"\n' % (name, tr(p), edges))
for idx, mast, yy, yz, half in YARDS:
    for side, sx in (("p", -1.0), ("s", 1.0)):
        x = sx * half * FOOTROPE_X
        p = (x, yy - FOOTROPE_DROP, yz + FOOTROPE_AFT)
        hl = (x - 0.3, yy, yz - 0.05)   # facing the bow: the character's left hand is on the port side (-x)
        hr = (x + 0.3, yy, yz - 0.05)
        out.append('[node name="yard_aloft_%d_%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"yard_aloft"\nmetadata/slots = 1\nmetadata/facing_deg = 0\nmetadata/anim_tag = &"furl_aloft"\nmetadata/must_staff = false\nmetadata/sail_idx = %d\nmetadata/side = &"%s"\nmetadata/mast = &"%s"\nmetadata/ik_hand_l = Vector3(%g, %g, %g)\nmetadata/ik_hand_r = Vector3(%g, %g, %g)\n' % (idx, side, tr(p), idx, side, mast, hl[0], hl[1], hl[2], hr[0], hr[1], hr[2]))
for name, mast, p in BRACES:
    f = -90.0 if p[0] > 0 else 90.0
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"brace"\nmetadata/slots = 1\nmetadata/facing_deg = %g\nmetadata/anim_tag = &"haul"\nmetadata/must_staff = false\nmetadata/mast = &"%s"\nmetadata/side = &"%s"\n' % (name, tr(p), f, mast, name[-1]))
out.append('[node name="Provider" type="Node" parent="."]\nscript = ExtResource("1_stations")\n')
print("\n".join(out))
