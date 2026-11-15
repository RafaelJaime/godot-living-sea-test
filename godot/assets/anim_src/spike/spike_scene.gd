extends Node3D
## C4.1 spike capture: the retargeted clip on a crew model (left) next to the UAL mannequin playing the source clip (right), four phases per clip.
const CLIPS := {"Walk": "walk", "Fixing_Kneeling": "fixing_kneeling", "Idle_Talking": "idle_talking"}
const CREW := "res://assets/characters/papi_fuego.glb"

var crew: Node3D
var crew_ap: AnimationPlayer
var ual: Node3D
var ual_ap: AnimationPlayer
var cam: Camera3D

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 6)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.3, 0.25)
	floor_mi.material_override = fm
	add_child(floor_mi)
	crew = (load(CREW) as PackedScene).instantiate()
	crew.scale = Vector3.ONE # the glb already carries its cm->m node scale
	crew.position = Vector3(-0.8, 0, 0)
	add_child(crew)
	crew_ap = crew.find_children("*", "AnimationPlayer", true, false)[0]
	ual = (load("res://assets/anim_src/spike/UAL1_Standard.glb") as PackedScene).instantiate()
	ual.position = Vector3(0.8, 0, 0)
	add_child(ual)
	ual_ap = ual.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		lib.add_animation(CLIPS[clip], load("res://assets/anim_src/spike/baked_%s.res" % CLIPS[clip]) as Animation)
	crew_ap.add_animation_library("spike", lib)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.15, 4.6)
	cam.fov = 38.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.9, 0.0))
	cam.current = true
	_capture.call_deferred()

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	for _i in 6:
		await get_tree().process_frame
	for clip in CLIPS:
		var a := ual_ap.get_animation(clip)
		crew_ap.play("spike/" + CLIPS[clip])
		ual_ap.play(clip)
		for k in 4:
			var t := a.length * float(k) / 4.0
			crew_ap.seek(t, true)
			ual_ap.seek(t, true)
			await get_tree().process_frame
			await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://_shots/spike_%s_%d.png" % [CLIPS[clip], k]))
	var mis := crew.find_children("*", "MeshInstance3D", true, false)
	for m in mis:
		var mi := m as MeshInstance3D
		print("[spike] crew mesh ", mi.name, " visible=", mi.is_visible_in_tree(), " global aabb=", mi.global_transform * mi.get_aabb())
	var sk := crew.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("[spike] crew hips pose origin ", sk.get_bone_pose_position(sk.find_bone("Hips")), " crew position ", crew.global_position, " ap=", crew_ap.current_animation, " playing=", crew_ap.is_playing())
	print("[spike] captures done")
	get_tree().quit()
