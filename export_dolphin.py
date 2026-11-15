# Blender CLI: Sketchfab "Dolphin" by Alex_Pfe (CC BY 4.0, https://sketchfab.com/3d-models/dolphin-c24dc835a6aa4d3c827450513525cdb8)
# FBX -> glTF for Godot. Drops the 540 tiny bubble cubes (188k of the 188k triangles are mostly bubbles + lashes), keeps the armature,
# the body and the skinned parts, rebuilds one material from 1k textures and exports the swim action.
#   SRC=<dir with source/LPP.fbx and textures/> blender -b -P export_dolphin.py
import bpy, os
SRC = os.environ["SRC"]
OUT = os.path.dirname(os.path.abspath(__file__)) + "/godot/assets/ambient/dolphin/dolphin.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC + "/source/LPP.fbx")
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("Cube")]:
    bpy.data.objects.remove(o, do_unlink=True)
def img(name, srgb):
    im = bpy.data.images.load(SRC + "/textures/LPP_TT_checker_2048x2048_UV_GRID_" + name + ".png")
    im.scale(1024, 1024)
    im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    im.pack()
    return im
mat = bpy.data.materials.new("dolphin")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    if n.type != 'OUTPUT_MATERIAL': nt.nodes.remove(n)
out = [n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'][0]
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
nt.links.new(bsdf.outputs[0], out.inputs[0])
def tex(name, srgb, y):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = img(name, srgb); t.location = (-600, y); return t
b = tex("BaseColor", True, 300); nt.links.new(b.outputs[0], bsdf.inputs["Base Color"])
r = tex("Roughness", False, 0); nt.links.new(r.outputs[0], bsdf.inputs["Roughness"])
nm = tex("Normal", False, -300); nmap = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(nm.outputs[0], nmap.inputs["Color"]); nt.links.new(nmap.outputs[0], bsdf.inputs["Normal"])
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.materials.clear(); o.data.materials.append(mat)
        print("KEEP", o.name, len(o.data.polygons))
for a in list(bpy.data.actions):
    if a.name.startswith("Armature"):
        a.name = "swim"
    else:
        bpy.data.actions.remove(a)
for a in bpy.data.actions: print("ACTION", a.name, tuple(a.frame_range), "fps", bpy.context.scene.render.fps)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', export_image_format='JPEG', export_jpeg_quality=85, export_apply=False, export_yup=True)
print("EXPORTED", OUT, os.path.getsize(OUT))
