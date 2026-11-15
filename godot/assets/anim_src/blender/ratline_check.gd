extends SceneTree
## Debug: applies frame F of ratline_climb.res to the skeleton and compares each global bone rotation with D*Rb from the json.
func _init() -> void:
	_run.call_deferred()
func _q(a: Array) -> Quaternion:
	return Quaternion(a[1], a[3], -a[2], a[0]).normalized()
func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/anim_src/blender/ratline_climb.json"))
	var inst := (load("res://assets/characters/papi_fuego.glb") as PackedScene).instantiate()
	root.add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	print("[chk] skeleton xform ", sk.transform, " armature ", inst.get_child(0).transform if inst.get_child_count() > 0 else "-")
	var anim: Animation = load("res://assets/anim_src/blender/ratline_climb.res")
	var f := 11
	var d: Dictionary = data["delta"][f]
	for t in anim.get_track_count():
		var p := String(anim.track_get_path(t)).get_slice(":", 1)
		var bi := sk.find_bone(p)
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			sk.set_bone_pose_rotation(bi, anim.rotation_track_interpolate(t, f / 30.0))
		else:
			sk.set_bone_pose_position(bi, anim.position_track_interpolate(t, f / 30.0))
	for bn in ["Hips", "Spine02", "Spine", "Head", "LeftArm", "LeftHand", "LeftUpLeg", "LeftFoot"]:
		var bi := sk.find_bone(bn)
		var want := _q(d[bn]) * sk.get_bone_global_rest(bi).basis.get_rotation_quaternion()
		var got := sk.get_bone_global_pose(bi).basis.get_rotation_quaternion()
		print("[chk] ", bn, " err deg ", snappedf(rad_to_deg(want.angle_to(got)), 0.01), " pos ", sk.get_bone_global_pose(bi).origin)
	quit()
