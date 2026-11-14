"""Build the 'La tripulacion de Pirat' pirate ship scene.

Run:  blender -b -P build_ship_scene.py
Outputs barco_tripulacion.blend (+ preview.png) next to this script.

Blockout scene meant as a base for Higgsfield (Blender plugin) generations:
ocean, stylised galleon and the four crew members as simple proxy figures,
each in its own area of the ship. Ship bobs/rolls; ocean animates (240 frames).
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = 240

# ---------------------------------------------------------------- reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.frame_start, scene.frame_end = 1, FRAMES
scene.render.fps = 24


def coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or scene.collection).children.link(c)
    return c


def link(obj, c):
    for uc in obj.users_collection:
        uc.objects.unlink(obj)
    c.objects.link(obj)
    return obj


_mats = {}


def mat(name, color, rough=0.6, metal=0.0, emit=0.0):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        for key in ("Emission Color", "Emission"):
            if key in p.inputs:
                p.inputs[key].default_value = (*color, 1)
                break
        p.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*color, 1)
    _mats[name] = m
    return m


def setmat(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)
    return obj


def prim(kind, c, m, name, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), **kw):
    ops = {
        "cube": bpy.ops.mesh.primitive_cube_add,
        "cyl": bpy.ops.mesh.primitive_cylinder_add,
        "cone": bpy.ops.mesh.primitive_cone_add,
        "sphere": bpy.ops.mesh.primitive_uv_sphere_add,
        "torus": bpy.ops.mesh.primitive_torus_add,
        "plane": bpy.ops.mesh.primitive_plane_add,
    }
    ops[kind](location=loc, rotation=rot, **kw)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    if kind in ("sphere", "cyl", "cone", "torus"):
        bpy.ops.object.shade_smooth()
    setmat(o, m)
    return link(o, c)


def look_rot(direction):
    """Euler rotation that points local +Z along direction."""
    return Vector(direction).to_track_quat("Z", "Y").to_euler()


def limb(c, m, name, a, b, r):
    a, b = Vector(a), Vector(b)
    d = b - a
    return prim("cyl", c, m, name, loc=(a + b) / 2, rot=look_rot(d),
                radius=r, depth=d.length, vertices=12)


# ---------------------------------------------------------------- materials
WOOD = mat("Wood_Hull", (0.23, 0.12, 0.05), 0.7)
WOOD_D = mat("Wood_Deck", (0.45, 0.30, 0.15), 0.8)
WOOD_L = mat("Wood_Trim", (0.55, 0.38, 0.18), 0.6)
GOLD = mat("Gold", (0.95, 0.70, 0.20), 0.3, 1.0)
IRON = mat("Iron", (0.25, 0.25, 0.27), 0.4, 1.0)
STEEL = mat("Steel", (0.80, 0.82, 0.85), 0.2, 1.0)
SAIL = mat("Sail", (0.93, 0.89, 0.78), 0.9)
FLAG = mat("Flag_Black", (0.02, 0.02, 0.02), 0.8)
RED = mat("Pirat_Red", (0.70, 0.05, 0.05), 0.5)
ROPE = mat("Rope", (0.55, 0.45, 0.30), 0.9)

SKIN_PALE = mat("Skin_Pale", (0.95, 0.76, 0.64), 0.5)
SKIN_TAN = mat("Skin_Tan", (0.72, 0.50, 0.35), 0.5)
SKIN_DARK = mat("Skin_Dark", (0.32, 0.18, 0.10), 0.5)
HAIR_LAV = mat("Hair_Lavender", (0.70, 0.62, 0.80), 0.6)
HAIR_WHITE = mat("Hair_White", (0.95, 0.95, 0.95), 0.5)
HAIR_YEL = mat("Hair_Yellow", (1.00, 0.85, 0.05), 0.5)
HAIR_ORA = mat("Hair_Orange", (1.00, 0.35, 0.02), 0.5)
FIRE = mat("Fire", (1.00, 0.40, 0.05), 0.5, 0.0, 8.0)
MAGIC = mat("Magic_Blue", (0.20, 0.60, 1.00), 0.5, 0.0, 6.0)

# ---------------------------------------------------------------- world / light
world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
wn = world.node_tree.nodes
bg = wn.get("Background")
try:
    sky = wn.new("ShaderNodeTexSky")
    for t in ("MULTIPLE_SCATTERING", "NISHITA", "HOSEK_WILKIE"):
        try:
            sky.sky_type = t
            break
        except TypeError:
            continue
    if hasattr(sky, "sun_elevation"):
        sky.sun_elevation = math.radians(18)
        sky.sun_rotation = math.radians(200)
    world.node_tree.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.12
except Exception:  # fallback: flat warm sky
    bg.inputs["Color"].default_value = (0.55, 0.70, 0.95, 1)

bpy.ops.object.light_add(type="SUN", rotation=(math.radians(60), 0, math.radians(200)))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 3.0
sun.data.color = (1.0, 0.92, 0.80)

# ---------------------------------------------------------------- ocean
c_env = coll("Ocean")
bpy.ops.mesh.primitive_plane_add(size=2)
ocean = link(bpy.context.active_object, c_env)
ocean.name = "Ocean"
om = ocean.modifiers.new("Ocean", "OCEAN")
om.resolution = 12
om.spatial_size = 120
om.size = 1.0
om.wave_scale = 0.8
om.choppiness = 1.2
om.wind_velocity = 14
om.repeat_x = om.repeat_y = 4
ocean.location = (-180, -180, 0)  # centre the generated 480 m ocean on the ship
water = mat("Water", (0.01, 0.10, 0.16), 0.12)
wp = water.node_tree.nodes.get("Principled BSDF")
if "Transmission Weight" in wp.inputs:
    wp.inputs["Transmission Weight"].default_value = 0.0
setmat(ocean, water)
bpy.ops.object.shade_smooth()
om.time = 1.0
om.keyframe_insert("time", frame=1)
om.time = 1.0 + FRAMES / 24 * 0.8
om.keyframe_insert("time", frame=FRAMES)

# ---------------------------------------------------------------- ship rig
bpy.ops.object.empty_add(type="ARROWS", location=(0, 0, 0))
rig = bpy.context.active_object
rig.name = "Ship_Rig"
c_ship = coll("Ship")
link(rig, c_ship)

L, W, D = 14.0, 2.6, 2.2  # length, half-width, depth
DECK_Z = 1.2              # deck height above water at midship
N, P = 28, 14             # sections, profile points


def hull_shape(u):
    if u >= 0.4:
        f = math.sqrt(max(0.015, 1 - ((u - 0.4) / 0.6) ** 2))
    else:
        f = 1 - 0.4 * ((0.4 - u) / 0.4) ** 2
    sheer = 0.9 * ((u - 0.45) * 2) ** 2
    return f, sheer


bm = bmesh.new()
rings, deck_pts = [], []
for i in range(N + 1):
    u = i / N
    x = -L / 2 + u * L
    f, sheer = hull_shape(u)
    w, d = W * f, D * (0.55 + 0.45 * f)
    top = DECK_Z + sheer
    ring = [bm.verts.new((x, -w, top + 0.6))]
    for k in range(P + 1):
        t = -math.pi / 2 + math.pi * k / P
        ring.append(bm.verts.new((x, w * math.sin(t), top - d * math.cos(t) * 1.0 + 0.0)))
    ring.append(bm.verts.new((x, w, top + 0.6)))
    rings.append(ring)
    deck_pts.append((x, w * 0.97, top))
for i in range(N):
    a, b = rings[i], rings[i + 1]
    for k in range(len(a) - 1):
        bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
bm.faces.new(list(reversed(rings[0])))  # stern transom
hull_me = bpy.data.meshes.new("Hull")
bm.to_mesh(hull_me)
bm.free()
hull = bpy.data.objects.new("Hull", hull_me)
c_ship.objects.link(hull)
setmat(hull, WOOD)
sol = hull.modifiers.new("Thickness", "SOLIDIFY")
sol.thickness = 0.08
hull.modifiers.new("Bevel", "BEVEL").width = 0.02

# deck
bm = bmesh.new()
left = [bm.verts.new((x, -w, z)) for x, w, z in deck_pts]
right = [bm.verts.new((x, w, z)) for x, w, z in deck_pts]
for i in range(N):
    bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
deck_me = bpy.data.meshes.new("Deck")
bm.to_mesh(deck_me)
bm.free()
deck = bpy.data.objects.new("Deck", deck_me)
c_ship.objects.link(deck)
setmat(deck, WOOD_D)


def deck_z(x):
    return DECK_Z + hull_shape((x + L / 2) / L)[1]


# gold trim stripe
for side in (-1, 1):
    pts = [(x, side * (w + 0.05), z + 0.3) for x, w, z in deck_pts]
    curve = bpy.data.curves.new(f"Trim_{side}", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.06
    sp = curve.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for p, (x, y, z) in zip(sp.points, pts):
        p.co = (x, y, z, 1)
    o = bpy.data.objects.new(f"Trim_{side}", curve)
    o.data.materials.append(GOLD)
    c_ship.objects.link(o)

# stern castle (quarterdeck) + wheel
SX = -L / 2 + 2.0
QZ = deck_z(SX) + 1.3
prim("cube", c_ship, WOOD, "Quarterdeck", loc=(SX - 0.3, 0, QZ - 0.65), scale=(1.9, W * 0.62, 0.65))
prim("cube", c_ship, WOOD_D, "Quarterdeck_Floor", loc=(SX - 0.3, 0, QZ + 0.02), scale=(1.95, W * 0.64, 0.03))
for y in (-1, 1):
    prim("cube", c_ship, WOOD_L, f"Quarter_Rail_{y}", loc=(SX - 0.3, y * W * 0.62, QZ + 0.45), scale=(1.9, 0.05, 0.05))
for k in range(9):
    for y in (-1, 1):
        prim("cyl", c_ship, WOOD_L, f"Baluster_{y}_{k}", loc=(SX - 2.1 + k * 0.45, y * W * 0.62, QZ + 0.22),
             radius=0.03, depth=0.45, vertices=8)
WX, WZ = SX + 1.1, QZ + 1.0
prim("cyl", c_ship, WOOD_L, "Wheel_Post", loc=(WX - 0.15, 0, QZ + 0.5), radius=0.08, depth=1.0)
prim("torus", c_ship, WOOD_L, "Ship_Wheel", loc=(WX, 0, WZ), rot=(0, math.radians(90), 0),
     major_radius=0.55, minor_radius=0.05)
for k in range(8):
    a = k * math.pi / 4
    p = Vector((WX, math.cos(a) * 0.75, WZ + math.sin(a) * 0.75))
    limb(c_ship, WOOD_L, f"Wheel_Spoke_{k}", (WX, 0, WZ), p, 0.03)
prim("sphere", c_ship, GOLD, "Stern_Lantern", loc=(-L / 2 + 0.1, 0, QZ + 1.2), radius=0.2)

# masts, yards, sails
c_sails = coll("Sails", c_ship)


def mast(name, x, h, sails):
    z0 = deck_z(x)
    prim("cyl", c_ship, WOOD_L, name, loc=(x, 0, z0 + h / 2), radius=0.18, depth=h)
    for j, (sz, sw, sh) in enumerate(sails):
        prim("cyl", c_ship, WOOD_L, f"{name}_Yard_{j}", loc=(x, 0, z0 + sz + sh / 2),
             rot=(math.radians(90), 0, 0), radius=0.07, depth=sw * 2.2)
        bpy.ops.mesh.primitive_grid_add(x_subdivisions=10, y_subdivisions=10, size=1,
                                        location=(x + 0.05, 0, z0 + sz),
                                        rotation=(math.radians(90), 0, math.radians(90)))
        s = link(bpy.context.active_object, c_sails)
        s.name = f"{name}_Sail_{j}"
        s.scale = (sw * 2, sh, 1)
        setmat(s, SAIL)
        # billow forward
        for v in s.data.vertices:
            gx, gy = v.co.x * 2, v.co.y * 2
            v.co.z -= 0.35 * (1 - gx * gx) * (1 - gy * gy) / max(s.scale.x, 0.01) * 2
        s.modifiers.new("Thick", "SOLIDIFY").thickness = 0.02
        bpy.ops.object.shade_smooth()
    return z0 + h


fore_top = mast("Foremast", 3.6, 9.5, [(2.6, 1.9, 2.4), (5.4, 1.5, 2.0)])
main_top = mast("Mainmast", -0.6, 11.5, [(2.8, 2.3, 2.8), (6.0, 1.9, 2.4), (8.6, 1.4, 1.6)])
NEST_Z = deck_z(-0.6) + 9.4
prim("cyl", c_ship, WOOD, "Crows_Nest", loc=(-0.6, 0, NEST_Z), radius=0.75, depth=0.7)

# flag
bpy.ops.mesh.primitive_grid_add(x_subdivisions=12, y_subdivisions=6, size=1,
                                location=(-0.6 - 1.0, 0, main_top - 0.5), rotation=(math.radians(90), 0, 0))
flag = link(bpy.context.active_object, c_ship)
flag.name = "Pirate_Flag"
flag.scale = (2.0, 1.3, 1)
for v in flag.data.vertices:
    v.co.z += 0.15 * math.sin((v.co.x + 0.5) * 9)
setmat(flag, FLAG)
prim("cube", c_ship, RED, "Flag_Emblem", loc=(-0.6 - 1.0, -0.03, main_top - 0.5), scale=(0.35, 0.01, 0.42))
prim("cube", c_ship, GOLD, "Flag_Crown", loc=(-0.6 - 1.0, -0.04, main_top - 0.0), scale=(0.25, 0.01, 0.08))

# bowsprit + figurehead
BX = L / 2 - 0.3
bz = deck_z(BX)
limb(c_ship, WOOD_L, "Bowsprit", (BX - 1.5, 0, bz + 0.2), (BX + 4.0, 0, bz + 2.2), 0.12)
prim("sphere", c_ship, GOLD, "Figurehead", loc=(BX + 0.2, 0, bz - 0.2), radius=0.35)

# ropes (stays)
for k, (a, b) in enumerate([
    ((-0.6, 0, main_top - 0.3), (BX + 3.8, 0, bz + 2.1)),
    ((3.6, 0, fore_top - 0.3), (BX + 3.9, 0, bz + 2.15)),
    ((-0.6, 0, main_top - 0.3), (-L / 2 + 0.3, 0, QZ + 0.5)),
]):
    limb(c_ship, ROPE, f"Stay_{k}", a, b, 0.025)
for x, top in ((3.6, fore_top), (-0.6, main_top)):
    for y in (-1, 1):
        for j in range(3):
            limb(c_ship, ROPE, f"Shroud_{x}_{y}_{j}", (x, 0, top - 2.5),
                 (x - 0.8 + j * 0.8, y * W * 0.95, deck_z(x) + 0.6), 0.02)

# cannons
for k, x in enumerate((-3.0, -1.2, 0.8, 2.4)):
    for y in (-1, 1):
        prim("cyl", c_ship, IRON, f"Cannon_{k}_{y}", loc=(x, y * (W * 0.92), deck_z(x) + 0.3),
             rot=(math.radians(90), 0, 0), radius=0.13, depth=0.9)

# barrels
for k, (x, y) in enumerate(((1.2, 1.4), (1.6, 1.3), (1.4, 0.95))):
    prim("cyl", c_ship, WOOD_L, f"Barrel_{k}", loc=(x, y, deck_z(x) + 0.45), radius=0.35, depth=0.9)

# ---------------------------------------------------------------- crew
c_crew = coll("Crew")


def figure(name, base, skin, coat, pants, h=1.8, face=0.0, sit=False):
    """Simple proxy body. Returns (collection, head_center, hand_r, hand_l)."""
    c = coll(name, c_crew)
    bx, by, bz = base
    s = h / 1.8 * 1.35  # stylised: crew oversized for readability
    fx, fy = math.cos(face), math.sin(face)   # forward
    rx, ry = -fy, fx                           # left
    hip = bz + (0.55 if sit else 0.9) * s
    if sit:
        for side in (-1, 1):
            k = (bx + rx * side * 0.14 * s, by + ry * side * 0.14 * s, hip)
            knee = (k[0] + fx * 0.45 * s, k[1] + fy * 0.45 * s, hip)
            limb(c, pants, f"{name}_Thigh_{side}", k, knee, 0.09 * s)
            limb(c, pants, f"{name}_Shin_{side}", knee, (knee[0], knee[1], bz), 0.08 * s)
    else:
        for side in (-1, 1):
            limb(c, pants, f"{name}_Leg_{side}", (bx + rx * side * 0.14 * s, by + ry * side * 0.14 * s, hip),
                 (bx + rx * side * 0.2 * s, by + ry * side * 0.2 * s, bz), 0.09 * s)
    chest = hip + 0.6 * s
    prim("cone", c, coat, f"{name}_Torso", loc=(bx, by, (hip + chest) / 2 - 0.05 * s),
         radius1=0.3 * s, radius2=0.24 * s, depth=0.75 * s, vertices=16)
    head = Vector((bx, by, chest + 0.28 * s))
    prim("sphere", c, skin, f"{name}_Head", loc=head, radius=0.2 * s, segments=24, ring_count=16)
    sh_r = Vector((bx - rx * 0.3 * s, by - ry * 0.3 * s, chest - 0.05 * s))
    sh_l = Vector((bx + rx * 0.3 * s, by + ry * 0.3 * s, chest - 0.05 * s))
    return c, head, sh_r, sh_l, s, Vector((fx, fy, 0)), Vector((rx, ry, 0))


def arm(c, name, shoulder, hand, coat, skin, s):
    limb(c, coat, f"{name}", shoulder, hand, 0.07 * s)
    prim("sphere", c, skin, f"{name}_Hand", loc=hand, radius=0.08 * s)


# 1) PAPI FUEGO -- captain at the wheel (quarterdeck, stern)
c, head, shr, shl, s, fw, lf = figure("Papi_Fuego", (WX - 0.85, 0, QZ), SKIN_DARK,
                                      RED, mat("Pants_Black", (0.05, 0.05, 0.06)), h=1.85)
prim("torus", c, HAIR_WHITE, "Papi_Fuego_SideHair", loc=head + Vector((0, 0, -0.02)),
     major_radius=0.17 * s, minor_radius=0.06 * s)   # bald on top, white ring at sides
prim("cone", c, RED, "Papi_Fuego_CoatCape", loc=(head.x - 0.12, head.y, head.z - 0.9 * s),
     radius1=0.55 * s, radius2=0.3 * s, depth=1.3 * s, vertices=20)
hr = shr + fw * 0.45 + Vector((0, 0, 0.05))
hl = shl + fw * 0.45 + Vector((0, 0, 0.05))
arm(c, "Papi_Fuego_ArmR", shr, hr, RED, SKIN_DARK, s)
arm(c, "Papi_Fuego_ArmL", shl, hl, RED, SKIN_DARK, s)
for side, hnd in (("R", hr), ("L", hl)):
    limb(c, IRON, f"Papi_Fuego_Pistol_{side}", hnd, hnd + fw * 0.35 + Vector((0, 0, 0.12)), 0.035)
    prim("sphere", c, FIRE, f"Papi_Fuego_Flame_{side}", loc=hnd + fw * 0.45 + Vector((0, 0, 0.16)), radius=0.1)

# 2) PAPI DIAGNOSTICA -- shipwright at the foremast with a giant anchor (midship-fore)
DX = 2.6
c, head, shr, shl, s, fw, lf = figure("Papi_Diagnostica", (DX, -1.0, deck_z(DX)), SKIN_TAN,
                                      mat("Vest_Brown", (0.35, 0.22, 0.10)), mat("Pants_Cream", (0.85, 0.80, 0.65)),
                                      h=2.0, face=math.radians(-60))
for k in range(26):  # enormous spiky white mane down to the waist
    a = math.radians(-120 + k * 240 / 25)
    back = -fw * 0.18
    root = head + back + Vector((0, 0, 0.12)) + lf * math.sin(a) * 0.12
    tip = root - fw * (0.25 + 0.2 * (k % 3)) + lf * math.sin(a) * 0.55 + Vector((0, 0, -0.4 - 0.6 * abs(math.cos(a))))
    prim("cone", c, HAIR_WHITE, f"Papi_Diagnostica_Mane_{k}", loc=(root + tip) / 2, rot=look_rot(tip - root),
         radius1=0.13 * s, radius2=0.0, depth=(tip - root).length, vertices=8)
hr = shr + Vector((0, 0, 0.75))
hl = shl + Vector((0, 0, 0.7))
arm(c, "Papi_Diagnostica_ArmR", shr, hr, SKIN_TAN, SKIN_TAN, s)
arm(c, "Papi_Diagnostica_ArmL", shl, hl, SKIN_TAN, SKIN_TAN, s)
anc = (hr + hl) / 2 + Vector((0, 0, 0.6))
prim("cyl", c, IRON, "Anchor_Shank", loc=anc + Vector((0, 0, 0.2)), radius=0.07, depth=1.6)
prim("torus", c, IRON, "Anchor_Ring", loc=anc + Vector((0, 0, 1.05)), rot=(0, math.radians(90), 0),
     major_radius=0.18, minor_radius=0.04)
prim("torus", c, IRON, "Anchor_Arms", loc=anc + Vector((0, 0, -0.35)), rot=(0, math.radians(90), 0),
     major_radius=0.55, minor_radius=0.07)
limb(c, IRON, "Anchor_Stock", anc + Vector((0, -0.55, 0.85)), anc + Vector((0, 0.55, 0.85)), 0.05)

# 3) EL SALCHIPAPA -- out on the bowsprit with three swords
SPX = BX + 1.6
c, head, shr, shl, s, fw, lf = figure("El_Salchipapa", (SPX, 0, bz + 0.85), SKIN_PALE,
                                      mat("Jacket_Studded", (0.04, 0.04, 0.04), 0.3, 0.6),
                                      mat("Pants_Plaid", (0.55, 0.08, 0.08)), h=1.8, face=math.radians(180))
for k in range(9):  # mohawk: yellow -> orange spikes along the head midline
    t = k / 8
    p = head + fw * (0.17 - 0.34 * t) + Vector((0, 0, 0.16))
    prim("cone", c, HAIR_YEL if k < 5 else HAIR_ORA, f"El_Salchipapa_Mohawk_{k}",
         loc=p + Vector((0, 0, 0.18)), rot=look_rot(Vector((0, 0, 1)) - fw * (0.5 - t)),
         radius1=0.06 * s, radius2=0.0, depth=0.45 * s, vertices=8)
for k in range(8):  # studs on the jacket
    a = k * math.pi / 4
    prim("sphere", c, STEEL, f"El_Salchipapa_Stud_{k}",
         loc=(SPX + math.cos(a) * 0.29, math.sin(a) * 0.29, head.z - 0.55), radius=0.035)
hr = shr + lf * -0.45 + Vector((0, 0, 0.35))
hl = shl + lf * 0.45 + Vector((0, 0, 0.35))
arm(c, "El_Salchipapa_ArmR", shr, hr, mat("Jacket_Studded", (0.04, 0.04, 0.04)), SKIN_PALE, s)
arm(c, "El_Salchipapa_ArmL", shl, hl, mat("Jacket_Studded", (0.04, 0.04, 0.04)), SKIN_PALE, s)
for side, hnd, d in (("R", hr, -lf), ("L", hl, lf)):
    tip = hnd + d * 0.5 + Vector((0, 0, 0.8))
    prim("cube", c, STEEL, f"El_Salchipapa_Sword_{side}", loc=(hnd + tip) / 2, rot=look_rot(tip - hnd),
         scale=(0.02, 0.06, (tip - hnd).length / 2))
mouth = head + fw * 0.2 + Vector((0, 0, -0.05))
prim("cube", c, STEEL, "El_Salchipapa_Sword_Mouth", loc=mouth, rot=(0, 0, math.radians(90) + math.radians(180)),
     scale=(0.6, 0.02, 0.04))

# 4) DON OMAR -- navigator sitting on the barrels, violin glowing with magic
OX = 1.4
c, head, shr, shl, s, fw, lf = figure("Don_Omar", (OX, 0.95, deck_z(OX) + 0.9), SKIN_TAN,
                                      mat("Coat_Navy", (0.05, 0.10, 0.30)), mat("Pants_Black", (0.05, 0.05, 0.06)),
                                      h=1.85, face=math.radians(-90), sit=True)
for side in (-1, 1):  # two furry "eggs" on top of the head
    prim("sphere", c, HAIR_LAV, f"Don_Omar_Egg_{side}", loc=head + lf * side * 0.14 + Vector((0, 0, 0.22)),
         radius=0.17 * s, scale=(1, 1, 1.25))
prim("cyl", c, HAIR_LAV, "Don_Omar_HairCurtain", loc=head + Vector((0, 0, -0.45)),
     radius=0.23 * s, depth=1.3 * s, vertices=24)   # long straight hair hiding the eyes
hr = shr + fw * 0.35 + lf * 0.2 + Vector((0, 0, 0.15))
hl = shl + fw * 0.3 + Vector((0, 0, 0.3))
arm(c, "Don_Omar_ArmR", shr, hr, mat("Coat_Navy", (0.05, 0.10, 0.30)), SKIN_TAN, s)
arm(c, "Don_Omar_ArmL", shl, hl, mat("Coat_Navy", (0.05, 0.10, 0.30)), SKIN_TAN, s)
prim("sphere", c, WOOD_L, "Don_Omar_Violin", loc=hl + lf * -0.15, scale=(0.12, 0.25, 0.06), radius=1)
limb(c, MAGIC, "Don_Omar_MagicBow", hr, hr + lf * 0.6 + Vector((0, 0, 0.1)), 0.02)
prim("sphere", c, MAGIC, "Don_Omar_MagicOrb", loc=hl + Vector((0, 0, 0.45)), radius=0.12)

# ---------------------------------------------------------------- parent everything to the rig
for o in list(c_ship.all_objects) + list(c_crew.all_objects):
    if o is not rig and o.parent is None:
        o.parent = rig

# bob / roll animation via noise modifiers
rig.location.z = -1.25
rig.keyframe_insert("location", frame=1)
rig.keyframe_insert("rotation_euler", frame=1)
for path, idx, strength, scale in (("location", 2, 0.35, 40), ("rotation_euler", 0, 0.06, 55),
                                   ("rotation_euler", 1, 0.035, 70)):
    fc = rig.animation_data.action.fcurves.find(path, index=idx) if hasattr(rig.animation_data.action, "fcurves") else None
    if fc is None:
        for layer in getattr(rig.animation_data.action, "layers", []):
            for strip in layer.strips:
                for bag in strip.channelbags:
                    fc = fc or bag.fcurves.find(path, index=idx)
    if fc:
        n = fc.modifiers.new("NOISE")
        n.strength, n.scale = strength * 2, scale

# ---------------------------------------------------------------- camera
bpy.ops.object.empty_add(location=(1.5, 0, 2.6))
target = bpy.context.active_object
target.name = "Camera_Target"
link(target, c_env)
bpy.ops.object.camera_add(location=(10.5, -10.5, 3.2))
cam = bpy.context.active_object
cam.name = "Camera_Hero"
cam.data.lens = 26
tc = cam.constraints.new("TRACK_TO")
tc.target = target
scene.camera = cam

# ---------------------------------------------------------------- render
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        continue
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in
                                                         scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"

blend = os.path.join(HERE, "barco_tripulacion.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend)
print("SAVED", blend)

if os.environ.get("PREVIEW", "1") == "1":
    scene.frame_set(60)
    scene.render.resolution_percentage = 50
    scene.render.filepath = os.path.join(HERE, "preview.png")
    bpy.ops.render.render(write_still=True)
    scene.render.resolution_percentage = 100
    print("PREVIEW", scene.render.filepath)
