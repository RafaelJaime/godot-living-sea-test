extends Node3D
## Final capture: each chosen prop scene (BoneAttachment3D on RightHand) with its clip on a crew model, 4 phases.
const CREW := "res://assets/characters/papi_fuego.glb"
const SHOTS := [
	{"id": "fishing_rod", "clip": "res://assets/anim_src/spike/baked_fishing_cast.res", "cam": Vector3(-2.2, 1.3, 2.6), "look": Vector3(0, 1.0, 0.1), "at": [0.05, 0.35, 0.65, 0.9]},
	{"id": "hammer", "clip": "res://assets/anim_src/spike/baked_hammering.res", "cam": Vector3(-2.2, 1.3, 2.6), "look": Vector3(0, 1.0, 0.1), "at": [0.0, 0.25, 0.5, 0.75]},
	{"id": "saw", "clip": "res://assets/anim_src/spike/baked_sawing.res", "cam": Vector3(-2.2, 1.3, 2.6), "look": Vector3(0, 1.0, 0.1), "at": [0.0, 0.25, 0.5, 0.75]},
	{"id": "lantern", "clip": "res://assets/anim_src/spike/baked_idle_lantern.res", "cam": Vector3(-2.2, 1.3, 2.6), "look": Vector3(0, 1.0, 0.1), "at": [0.0, 0.3, 0.6, 0.9]},
	{"id": "spyglass", "clip": "res://assets/anim_src/blender/spyglass_look.res", "cam": Vector3(-2.6, 1.5, 1.0), "look": Vector3(0, 1.45, -0.1), "at": [0.0, 0.25, 0.5, 0.75]},
	{"id": "mop", "clip": "res://assets/anim_src/blender/deck_swab.res", "cam": Vector3(-3.0, 1.1, 1.4), "look": Vector3(0, 0.85, -0.2), "at": [0.0, 0.25, 0.5, 0.75]},
]
var sk: Skeleton3D
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
	var crew := (load(CREW) as PackedScene).instantiate()
	add_child(crew)
	sk = crew.find_children("*", "Skeleton3D", true, false)[0]
	ap = crew.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for s in SHOTS:
		lib.add_animation(s["id"], load(s["clip"]) as Animation)
	ap.add_animation_library("p", lib)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	add_child(cam)
	cam.current = true
	_capture.call_deferred()

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	for _i in 6:
		await get_tree().process_frame
	for s in SHOTS:
		var att := BoneAttachment3D.new()
		sk.add_child(att)
		att.bone_name = "RightHand"
		var prop := (load("res://assets/props/%s_prop.tscn" % s["id"]) as PackedScene).instantiate()
		att.add_child(prop)
		cam.position = s["cam"]
		cam.look_at(s["look"])
		ap.play("p/" + s["id"])
		ap.pause()
		var len := ap.get_animation("p/" + s["id"]).length
		for k in (s["at"] as Array).size():
			ap.seek(float(s["at"][k]) * len, true)
			for _i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/final_%s_%d.png" % [s["id"], k]))
		att.queue_free()
		await get_tree().process_frame
	print("[props] final captures done")
	get_tree().quit()
