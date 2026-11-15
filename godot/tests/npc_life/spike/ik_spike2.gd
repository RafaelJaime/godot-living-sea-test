extends SceneTree
## A0.3 spike, part 2 (dev-only): TwoBoneIK3D on a trivial 3-bone skeleton, to separate API misuse from a crew-rig problem.
func _initialize() -> void:
	await process_frame # the root enters the tree only once the main loop runs: build everything after this
	var sk := Skeleton3D.new()
	sk.name = "Sk"
	sk.add_bone("root"); sk.add_bone("mid"); sk.add_bone("end")
	sk.set_bone_parent(1, 0); sk.set_bone_parent(2, 1)
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	sk.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	sk.reset_bone_poses()
	get_root().add_child(sk)
	var tgt := Node3D.new()
	tgt.name = "Tgt"
	get_root().add_child(tgt)
	tgt.global_position = Vector3(1.2, 0.8, 0.0)
	var ik: Node = ClassDB.instantiate("TwoBoneIK3D")
	ik.name = "IK"
	sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "root")
	ik.set_middle_bone_name(0, "mid")
	ik.set_end_bone_name(0, "end")
	ik.set_target_node(0, ik.get_path_to(tgt))
	var seen := {"p": Vector3.ZERO, "n": 0}
	sk.skeleton_updated.connect(func() -> void:
		seen["p"] = sk.get_bone_global_pose(2).origin
		seen["n"] += 1)
	print("[spike2] hand rest pos=", sk.get_bone_global_pose(2).origin, " target=", tgt.global_position)
	for i in 10:
		await process_frame
	sk.advance(0.016)
	print("[spike2] after advance(): updates=", seen["n"], " end pos=", sk.get_bone_global_pose(2).origin, " ik.active=", ik.active, " influence=", ik.influence, " mode=", sk.modifier_callback_mode_process, " is_processing_internal=", sk.is_processing_internal() if sk.has_method("is_processing_internal") else "n/a")
	print("[spike2] TwoBoneIK3D updates=", seen["n"], " hand pos in update=", seen["p"], " dist=", snappedf((seen["p"] as Vector3).distance_to(tgt.global_position), 0.001))
	# same with a LookAt present, and influence 0.5
	ik.influence = 0.5
	for i in 5:
		await process_frame
	print("[spike2] influence 0.5 hand pos=", seen["p"])
	# controls: which modifier classes make the skeleton emit skeleton_updated here
	for cn in ["LookAtModifier3D", "CCDIK3D", "FABRIK3D", "TwoBoneIK3D"]:
		var sk2 := Skeleton3D.new()
		sk2.add_bone("root"); sk2.add_bone("mid"); sk2.add_bone("end")
		sk2.set_bone_parent(1, 0); sk2.set_bone_parent(2, 1)
		sk2.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		sk2.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		if OS.get_cmdline_user_args().has("--bend"):
			sk2.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0.15))) # a slightly bent elbow (real arms are never collinear)
		sk2.reset_bone_poses()
		if OS.get_cmdline_user_args().has("--tpos"):
			tgt.global_position = Vector3(0.4, 1.7, 0.3)
		if OS.get_cmdline_user_args().has("--rot"):
			sk2.rotation = Vector3(0, 0.5, 0)
		get_root().add_child(sk2)
		var m: Node = ClassDB.instantiate(cn)
		sk2.add_child(m)
		var n := {"n": 0, "mp": 0, "end": Vector3.ZERO}
		sk2.skeleton_updated.connect(func() -> void: n["n"] += 1)
		m.modification_processed.connect(func() -> void:
			n["mp"] += 1
			n["end"] = sk2.get_bone_global_pose(2).origin)
		if cn == "LookAtModifier3D":
			m.bone_name = "mid"
			m.set_target_node(m.get_path_to(tgt))
		elif cn == "TwoBoneIK3D":
			m.setting_count = 1
			m.set_root_bone_name(0, "root"); m.set_middle_bone_name(0, "mid"); m.set_end_bone_name(0, "end")
			m.set_target_node(0, sk2.get_path_to(tgt) if OS.get_cmdline_user_args().has("--skpath") else m.get_path_to(tgt))
			if OS.get_cmdline_user_args().has("--virt"):
				m.set_use_virtual_end(0, true)
				m.set_end_bone_length(0, 0.3)
				m.set_end_bone_direction(0, 2)
			if OS.get_cmdline_user_args().has("--pole"):
				m.set_pole_direction(0, int(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--pole") + 1]))
				m.set_pole_direction_vector(0, Vector3(0, 0, 1))
		else:
			m.setting_count = 1
			m.set_root_bone_name(0, "root"); m.set_end_bone_name(0, "end")
			m.set_target_node(0, m.get_path_to(tgt))
		if cn == "TwoBoneIK3D":
			var props := []
			for pr in m.get_property_list():
				if str(pr["name"]).begins_with("settings") or pr["name"] in ["active", "influence", "setting_count"]:
					props.append(str(pr["name"]) + "=" + str(m.get(pr["name"])))
			print("[spike2] TwoBoneIK3D dynamic props: ", props)
		for i in 5:
			await process_frame
		print("[spike2] control ", cn, " skeleton_updated=", n["n"], " modification_processed=", n["mp"], " end pos inside signal=", n["end"])
		sk2.queue_free()
	quit(0)
