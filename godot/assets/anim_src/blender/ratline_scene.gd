extends Node3D
## Capture of ratline_climb.res on a crew model: static shrouds, rungs sliding down at the body's rise speed (the clip is in place).
const CREW := "res://assets/characters/papi_fuego.glb"
const CLIP := "res://assets/anim_src/blender/ratline_climb.res"
const RISE := 0.4 / 0.6
const SPACING := RISE / 2.0
const FOOT_Y := -0.20
const HAND_Y := -0.43
const HAND_X := 0.22
var crew: Node3D
var ap: AnimationPlayer
var rungs: Array[MeshInstance3D] = []
var cam: Camera3D

func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi

func _ready() -> void:
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
	crew = (load(CREW) as PackedScene).instantiate()
	add_child(crew)
	ap = crew.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := AnimationLibrary.new()
	lib.add_animation("ratline_climb", load(CLIP) as Animation)
	ap.add_animation_library("rl", lib)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.015, 3.2, 0.015), Vector3(sx * HAND_X, 1.0, -HAND_Y), Color(0.9, 0.8, 0.2))
	for k in 12:
		rungs.append(_box(Vector3(0.46, 0.016, 0.016), Vector3(0, 0, -(FOOT_Y - 0.115)), Color(0.15, 0.85, 0.25)))
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	_capture.call_deferred()

func _set_rungs(u: float) -> void:
	for i in rungs.size():
		var z := fposmod(i * SPACING - RISE * u, SPACING * 12.0) - SPACING * 3.0 + 0.03
		rungs[i].position.y = z

func _view(name: String) -> void:
	match name:
		"side":
			cam.position = Vector3(4.0, 1.0, 0.2)
			cam.look_at(Vector3(0, 1.0, 0.2))
		"front":
			cam.position = Vector3(0.0, 1.0, 4.0)
			cam.look_at(Vector3(0, 1.0, 0))
		"threeq":
			cam.position = Vector3(2.6, 1.3, 2.8)
			cam.look_at(Vector3(0, 1.0, 0.1))
	cam.size = 2.4
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	for _i in 6:
		await get_tree().process_frame
	ap.play("rl/ratline_climb")
	ap.pause()
	for f in [0, 5, 11, 16, 21, 26, 32, 37]:
		var u := float(f) / 42.0
		ap.seek(u * 1.4, true)
		_set_rungs(u)
		for v in ["side", "front", "threeq"]:
			_view(v)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/ratline_%s_%02d.png" % [v, f]))
	print("[ratline] captures done")
	get_tree().quit()
