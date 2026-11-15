import bpy, mathutils
OUT = "<repo>/godot/assets/placeholder/"
rig = bpy.data.objects['Ship_Rig']
rig.animation_data_clear()
rig.location = (0, 0, 0); rig.rotation_euler = (0, 0, 0); rig.scale = (1, 1, 1)
bpy.context.view_layer.update()

def all_objs(col):
    s = set(col.objects)
    for c in col.children: s |= all_objs(c)
    return s

def unparent_keep(objs):
    for o in objs:
        if o.parent is not None and o.parent not in objs:
            m = o.matrix_world.copy(); o.parent = None; o.matrix_world = m
    bpy.context.view_layer.update()

def export(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objs))
    bpy.ops.export_scene.gltf(filepath=OUT + name + ".glb", export_format='GLB',
        use_selection=True, export_animations=False, export_apply=True, export_yup=True)
    print("EXPORTED", name, len(objs))

ship_col = bpy.data.collections['Ship']
ship = {o for o in all_objs(ship_col) if o.type in ('MESH',)}
# rig is an EMPTY parent: baked into world already via unparent_keep
unparent_keep(ship)
export(ship, "ship_placeholder")

for name in ["Papi_Fuego", "Papi_Diagnostica", "El_Salchipapa", "Don_Omar"]:
    objs = {o for o in all_objs(bpy.data.collections[name]) if o.type == 'MESH'}
    unparent_keep(objs)
    pts = [o.matrix_world @ mathutils.Vector(c) for o in objs for c in o.bound_box]
    minz = min(p.z for p in pts)
    cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
    cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
    print(name, "feet", cx, cy, minz, "height", max(p.z for p in pts) - minz)
    # roots only
    for o in objs:
        if o.parent is None:
            o.location = o.location - mathutils.Vector((cx, cy, minz))
    bpy.context.view_layer.update()
    export(objs, name)
    print(name, "world feet offset was", cx, cy, minz)
