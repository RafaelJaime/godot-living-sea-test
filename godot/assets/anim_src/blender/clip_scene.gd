extends Node3D
## Capture of authored clips on a crew model: `-- --clips=a,b,c`, 8 evenly spaced phases per clip from two cameras (3/4 front-right and side, orthographic),
## saved as res://_shots/clip_<name>_<view>_<k>.png. The clips are res://assets/anim_src/blender/<name>.res.
const CREW := "res://assets/characters/papi_fuego.glb"
var ap: AnimationPlayer
var cam: Camera3D

func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(800, 800)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.55, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.25, 0.2)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var crew := (load(CREW) as PackedScene).instantiate()
	add_child(crew)
	ap = crew.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	var dir := "res://assets/anim_src/blender"
	var prefix := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="): # e.g. --dir=tomazod --prefix=baked_ for the (git-ignored) Tomazod bakes
			dir = "res://assets/anim_src/" + a.get_slice("=", 1)
		elif a.begins_with("--prefix="):
			prefix = a.get_slice("=", 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			for c in a.get_slice("=", 1).split(","):
				lib.add_animation(c, load("%s/%s%s.res" % [dir, prefix, c]) as Animation)
	ap.add_animation_library("c", lib)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.4
	add_child(cam)
	cam.current = true
	_capture.call_deferred()

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	for _i in 6:
		await get_tree().process_frame
	for name in ap.get_animation_library("c").get_animation_list():
		ap.play("c/" + name)
		ap.pause()
		var len := ap.get_animation("c/" + name).length
		for view in ["tq", "side"]:
			if view == "tq":
				cam.position = Vector3(-2.4, 1.3, 3.0)
			else:
				cam.position = Vector3(-4.0, 1.1, 0.0)
			cam.look_at(Vector3(0, 0.95, 0.0))
			for k in 8:
				ap.seek(len * float(k) / 8.0, true)
				for _i in 3:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/clip_%s_%s_%d.png" % [name, view, k]))
	print("[clips] captures done")
	get_tree().quit()
