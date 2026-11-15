#!/usr/bin/env python3
"""One-off generator: splits the `Ship` subtree of main.tscn into ship/ship.tscn and replaces it in main.tscn by an instance named Ship.
Textual on purpose (a headless Godot script cannot load the scripts that use the autoloads Waves/Quality/WorldState, so packing would drop them).
Run from godot/ on the pre-refactor main.tscn: python3 ship/gen_ship_scene.py"""
import re, sys
src = open("main.tscn").read()
head, *blocks = re.split(r"(?m)^(?=\[node )", src)
ext = re.findall(r'(?m)^\[ext_resource [^\n]*\]', head)
ship_blocks, other_blocks, in_ship = [], [], False
for b in blocks:
    m = re.match(r'\[node name="([^"]+)"[^\n]*?(?: parent="([^"]*)")?', b)
    name = m.group(1); parent = re.search(r' parent="([^"]*)"', b.split("\n")[0])
    parent = parent.group(1) if parent else None
    if name == "Ship" and parent == ".":
        in_ship = True
    elif parent == "." and in_ship:
        in_ship = False
    (ship_blocks if in_ship else other_blocks).append(b)
ship_text = "".join(ship_blocks)
used = set(re.findall(r'ExtResource\("([^"]+)"\)', ship_text))
ship_ext = [e for e in ext if re.search(r'id="([^"]+)"', e).group(1) in used]
# re-root: Ship becomes the scene root
def reroot(b):
    first, rest = b.split("\n", 1)
    if first.startswith('[node name="Ship" '):
        first = first.replace(' parent="."', "")
    else:
        first = re.sub(r' parent="Ship/', ' parent="', first)
        first = re.sub(r' parent="Ship"', ' parent="."', first)
    return first + "\n" + rest
ship_out = '[gd_scene format=3]\n\n' + "\n".join(ship_ext) + "\n\n" + "".join(reroot(b) for b in ship_blocks).rstrip("\n") + "\n"
open("ship/ship.tscn", "w").write(ship_out)
ship_id = "100_shipscene"
main_ext = [e for e in ext if re.search(r'id="([^"]+)"', e).group(1) not in used] + ['[ext_resource type="PackedScene" path="res://ship/ship.tscn" id="%s"]' % ship_id]
inst = '[node name="Ship" parent="." instance=ExtResource("%s")]\n\n' % ship_id
out_blocks = []
placed = False
for b in blocks:
    if b in ship_blocks:
        if not placed:
            out_blocks.append(inst); placed = True
        continue
    out_blocks.append(b)
n_ext = len(main_ext)
head_new = re.sub(r"load_steps=\d+", "load_steps=%d" % (n_ext + 1), head.split("\n")[0]) + "\n\n" + "\n".join(main_ext) + "\n\n"
open("main.tscn", "w").write(head_new + "".join(out_blocks))
print("ship.tscn nodes:", len(ship_blocks), "| main ext:", n_ext, "| ship ext:", len(ship_ext))
