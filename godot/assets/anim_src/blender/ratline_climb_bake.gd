extends SceneTree
## Turns ratline_climb.json (GLOBAL bone rotations authored in Blender, Z-up) into an Animation for the Meshy skeleton (glTF axes).
## Godot poses are absolute: local = (Dp*Rp)^-1 * (Db*Rb), Rb/Rp the Godot global rests of the bone and its parent, so no bone orientation convention is assumed.
## Blender (x, y, z) -> glTF (x, z, -y). Output: ratline_climb.res (tracks "Armature/Skeleton3D:<bone>", LOOP_LINEAR, in place).
const TARGET := "res://assets/characters/papi_fuego.glb"
const JSON_PATH := "res://assets/anim_src/blender/ratline_climb.json"
const OUT := "res://assets/anim_src/blender/ratline_climb.res"

func _init() -> void:
	_run.call_deferred()

func _q(a: Array) -> Quaternion:
	# Blender (w, x, y, z) -> Godot Quaternion in glTF axes
	return Quaternion(a[1], a[3], -a[2], a[0]).normalized()

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var inst := (load(TARGET) as PackedScene).instantiate()
	root.add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var fps: float = data["fps"]
	var n: int = data["frames"]
	var anim := Animation.new()
	anim.length = float(n) / fps
	anim.loop_mode = Animation.LOOP_LINEAR
	anim.step = 1.0 / fps
	var tracks := {}
	var hips_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_track, NodePath("Armature/Skeleton3D:Hips"))
	var hips_i := sk.find_bone("Hips")
	var hips_rest := sk.get_bone_rest(hips_i).origin
	var missing := []
	for bn in data["bones"]:
		if sk.find_bone(bn) < 0:
			missing.append(bn)
			continue
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Armature/Skeleton3D:" + bn))
		tracks[bn] = tr
	for f in n:
		var t := float(f) / fps
		var d: Dictionary = data["delta"][f]
		for bn in tracks:
			var bi := sk.find_bone(bn)
			var par := sk.get_bone_parent(bi)
			var rb := sk.get_bone_global_rest(bi).basis.get_rotation_quaternion()
			var par_g := Quaternion.IDENTITY
			if par >= 0:
				par_g = _q(d[sk.get_bone_name(par)]) * sk.get_bone_global_rest(par).basis.get_rotation_quaternion()
			var loc := par_g.inverse() * _q(d[bn]) * rb
			anim.rotation_track_insert_key(tracks[bn], t, loc.normalized())
		var ho: Array = data["hips_offset_m"][f]
		var off_cm := Vector3(ho[0], ho[2], -ho[1]) * 100.0   # metres -> skeleton units (cm), Blender -> glTF axes
		anim.position_track_insert_key(hips_track, t, hips_rest + off_cm)
	var err := ResourceSaver.save(anim, OUT)
	print("[ratline] saved ", OUT, " err=", err, " len=", anim.length, " tracks=", anim.get_track_count(), " missing=", missing, " hips_rest=", hips_rest, " hips_rest_m_blender=", data["hips_rest_m"])
	quit()
