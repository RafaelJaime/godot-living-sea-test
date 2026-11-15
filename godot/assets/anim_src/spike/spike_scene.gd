extends Node3D
## C4.1 spike capture: the baked clip on a crew model (left) next to the source mannequin playing the source clip (right), four phases per clip.
## Groups: ual1 (UAL1 mannequin), ual2 (UAL2 mannequin), kaykit (KayKit Mannequin_Medium with the Rig_Medium_Tools clips copied onto it).
const GROUPS := [
	{"id": "ual1", "scene": "res://assets/anim_src/spike/UAL1_Standard.glb", "clips": {"Walk": "walk", "Fixing_Kneeling": "fixing_kneeling", "Idle_Talking": "idle_talking"}},
	{"id": "ual2", "scene": "res://assets/anim_src/spike/UAL2_Standard.glb", "clips": {"Idle_Rail": "idle_rail", "Idle_Lantern": "idle_lantern", "Walk_Carry": "walk_carry", "ClimbUp_1m": "climb_up_1m"}},
	{"id": "kaykit", "scene": "res://assets/anim_src/spike/Mannequin_Medium.glb", "anims": "res://assets/anim_src/spike/Rig_Medium_Tools.glb",
		"clips": {"Fishing_Cast": "fishing_cast", "Fishing_Idle": "fishing_idle", "Fishing_Reeling": "fishing_reeling", "Hammering": "hammering", "Sawing": "sawing"}},
]
const CREW := "res://assets/characters/papi_fuego.glb"

var crew: Node3D
var crew_ap: AnimationPlayer
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
	crew.position = Vector3(-0.8, 0, 0)
	add_child(crew)
	crew_ap = crew.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	for g in GROUPS:
		for clip in g["clips"]:
			lib.add_animation(g["clips"][clip], load("res://assets/anim_src/spike/baked_%s.res" % g["clips"][clip]) as Animation)
	crew_ap.add_animation_library("spike", lib)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.15, 4.6)
	cam.fov = 38.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.9, 0.0))
	cam.current = true
	_capture.call_deferred()

func _source_player(g: Dictionary) -> Array:
	var src := (load(g["scene"]) as PackedScene).instantiate() as Node3D
	src.position = Vector3(0.8, 0, 0)
	add_child(src)
	var ap: AnimationPlayer
	var aps := src.find_children("*", "AnimationPlayer", true, false)
	if g.has("anims"):
		# KayKit: the mannequin has no clips; copy the ones of the animation glb onto it, re-pointing the tracks to the mannequin's skeleton
		var asrc := (load(g["anims"]) as PackedScene).instantiate()
		var from_ap := asrc.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var sk := src.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var sp := String(src.get_path_to(sk))
		ap = aps[0] if not aps.is_empty() else AnimationPlayer.new()
		if aps.is_empty():
			src.add_child(ap)
			ap.root_node = ap.get_path_to(src)
		var lib := AnimationLibrary.new()
		for n in from_ap.get_animation_list():
			var a := from_ap.get_animation(n).duplicate() as Animation
			for t in a.get_track_count():
				a.track_set_path(t, NodePath(sp + ":" + String(a.track_get_path(t)).get_slice(":", 1)))
			lib.add_animation(n, a)
		if ap.has_animation_library(""):
			ap.remove_animation_library("")
		ap.add_animation_library("", lib)
		asrc.free()
	else:
		ap = aps[0]
	return [src, ap]

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	for _i in 6:
		await get_tree().process_frame
	for g in GROUPS:
		var pair := _source_player(g)
		var src: Node3D = pair[0]
		var ap: AnimationPlayer = pair[1]
		for clip in g["clips"]:
			var a := ap.get_animation(clip)
			var out_name: String = g["clips"][clip]
			crew_ap.play("spike/" + out_name)
			ap.play(clip)
			for k in 4:
				var t := a.length * float(k) / 4.0
				crew_ap.seek(t, true)
				ap.seek(t, true)
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/spike_%s_%d.png" % [out_name, k]))
		src.queue_free()
		await get_tree().process_frame
	print("[spike] captures done")
	get_tree().quit()
