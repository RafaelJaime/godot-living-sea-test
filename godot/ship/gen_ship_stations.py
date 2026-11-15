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
    ("stairs_forecastle", "stairs", (0.0, 2.7, -5.5)),
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
    ("n_waist_p", (-1.6, 1.85, -2.8), "n_waist_f"),
    ("n_waist_s", (1.6, 1.85, -2.8), "n_waist_f"),
    ("n_waist_f", (0.0, 1.85, -5.0), "n_fore_a:stairs"),
    ("n_fore_a", (0.0, 3.5, -6.5), "n_fore_b"),
    ("n_fore_b", (0.0, 3.55, -8.5), "n_fore_bow"),
    ("n_fore_bow", (0.0, 3.9, -10.0), ""),
    ("n_ratline_p", (-2.1, 1.9, 0.5), "n_shroud_p:rope"),
    ("n_ratline_s", (2.1, 1.9, 0.5), "n_shroud_s:rope"),
    ("n_shroud_p", (-1.6, 9.0, 1.3), "n_nest:rope"),
    ("n_shroud_s", (1.6, 9.0, 1.3), "n_nest:rope"),
    ("n_nest", (0.0, 23.4, 2.8), ""),
]

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
    out.append('[node name="%s" type="Marker3D" parent="Markers"]\ntransform = %s\nmetadata/kind = &"nav"\nmetadata/edge_to = "%s"\nmetadata/edge_type = &"walk"\n' % (name, tr(p), edges))
out.append('[node name="Provider" type="Node" parent="."]\nscript = ExtResource("1_stations")\n')
print("\n".join(out))
