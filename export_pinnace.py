# Blender CLI: FBX (Poly Haven "Ship Pinnace" rig) -> glTF for Godot. Rebuilds materials from the 1k textures
# (diffuse with alpha, GL normal), keeps the armature and per-object meshes, alpha-clips the sails.
import bpy, os
ROOT = "/Users/rafael/Documents/workspace/autonomo/el-terraria-blender/"
TEX = ROOT + "refs/sketchfab_pirate_ship_rigged/textures/"
OUT = ROOT + "godot/assets/ship/pinnace/barco_pinnace.glb"
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
