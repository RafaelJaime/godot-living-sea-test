# Blender CLI: FBX (Poly Haven "Ship Pinnace" rig) -> glTF for Godot. Rebuilds materials from the 1k textures
# (diffuse with alpha, GL normal), keeps the armature and per-object meshes, alpha-clips the sails.
import bpy, os
import os
# Inputs (untracked refs) come from REFS_ROOT, the output goes to the checkout that runs the script.
REFS_ROOT = os.environ.get("REFS_ROOT", "<repo>/")
ROOT = REFS_ROOT
TEX = REFS_ROOT + "refs/sketchfab_pirate_ship_rigged/textures/"
OUT = os.path.dirname(os.path.abspath(__file__)) + "/godot/assets/ship/pinnace/barco_pinnace.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=ROOT + "refs/sketchfab_pirate_ship_rigged/source/fbx/ship_pinnace_1k.fbx")
# The FBX keeps the deployed (*_down) sails as hidden objects whose mesh data is local to the object's own location,
# but a parent-inverse matrix cancels that location (they collapse at the origin). Bake the object's local transform
# (matrix_basis) into the vertices so the skinned mesh lands on its yard; other meshes bake their world matrix.
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
bpy.context.view_layer.update()
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    if not any(m.type == 'ARMATURE' for m in o.modifiers):
        continue
    wt = o.matrix_world.translation.length
    bt = o.matrix_basis.translation.length
    collapsed = wt < 0.5 and bt > 2.0
    m = o.matrix_basis.copy() if collapsed else o.matrix_world.copy()
    print("BAKE", o.name, "collapsed" if collapsed else "world", round(wt, 2), round(bt, 2))
    o.data.transform(m)
    o.parent_type = 'OBJECT'
    o.matrix_parent_inverse.identity()
    o.matrix_basis.identity()
    o.hide_viewport = False
    o.hide_set(False)
bpy.context.view_layer.update()

# --- Split the ship's rowing boat out of the details mesh: the loose component whose bbox matches the boat. ---
import bmesh
BOAT_MIN = (-0.89, -6.26, 4.05)
BOAT_MAX = (0.90, -1.25, 5.06)
det = bpy.data.objects["geo_ship_pinnace_details"]
def components(bm):
    seen = set(); out = []
    for v in bm.verts:
        if v.index in seen: continue
        st = [v]; seen.add(v.index); comp = []
        while st:
            c = st.pop(); comp.append(c.index)
            for e in c.link_edges:
                w = e.other_vert(c)
                if w.index not in seen: seen.add(w.index); st.append(w)
        out.append(comp)
    return out
bm = bmesh.new(); bm.from_mesh(det.data); bm.verts.ensure_lookup_table()
boat_idx = None
for comp in components(bm):
    if len(comp) < 150: continue
    pts = [bm.verts[i].co for i in comp]
    mn = [min(p[i] for p in pts) for i in range(3)]; mx = [max(p[i] for p in pts) for i in range(3)]
    if all(abs(mn[i] - BOAT_MIN[i]) < 0.2 and abs(mx[i] - BOAT_MAX[i]) < 0.2 for i in range(3)):
        boat_idx = set(comp)
print("BOAT component vertices:", None if boat_idx is None else len(boat_idx))
if boat_idx:
    bm2 = bmesh.new(); bm2.from_mesh(det.data); bm2.verts.ensure_lookup_table()
    bmesh.ops.delete(bm2, geom=[v for v in bm2.verts if v.index not in boat_idx], context='VERTS')
    me2 = bpy.data.meshes.new("geo_ship_boat"); bm2.to_mesh(me2); bm2.free()
    for mat in det.data.materials: me2.materials.append(mat)
    boat = bpy.data.objects.new("geo_ship_boat", me2)
    bpy.context.scene.collection.objects.link(boat)
    boat.parent = arm
    boat.matrix_parent_inverse.identity()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in boat_idx], context='VERTS')
    bm.to_mesh(det.data)
bm.free()
bpy.context.view_layer.update()
for m in bpy.data.materials:
    base = m.name.split(".")[0]
    d = TEX + base + "_diff_1k.png"
    n = TEX + base + "_nor_gl_1k.png"
    print("MAT", m.name, os.path.exists(d), os.path.exists(n))
    if not os.path.exists(d):
        continue
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(d)
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if "sails" in base or "rigging" in base:
        nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
        m.blend_method = 'CLIP' if hasattr(m, "blend_method") else None
        try: m.alpha_threshold = 0.5
        except Exception: pass
    if os.path.exists(n):
        nt_img = nt.nodes.new("ShaderNodeTexImage"); nt_img.image = bpy.data.images.load(n)
        nt_img.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nt_img.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_apply=False,
    export_skins=True, export_animations=False, export_current_frame=True, export_image_format='AUTO', export_materials='EXPORT',
    export_texcoords=True, export_normals=True)
print("DONE", OUT)
