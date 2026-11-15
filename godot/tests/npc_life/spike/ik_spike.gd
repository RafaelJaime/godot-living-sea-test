extends SceneTree
## A0.3 spike (dev-only): which IK / look-at modifier classes exist in this Godot build, their properties and whether they work on the crew rig.
## godot --headless --path godot -s tests/npc_life/spike/ik_spike.gd

func _initialize() -> void:
	await process_frame # the root enters the tree only once the main loop runs: build everything after this
	print("[spike] Godot ", Engine.get_version_info()["string"])
	for cn in ["TwoBoneIK3D", "LookAtModifier3D", "SkeletonModifier3D", "IKModifier3D", "ChainIK3D", "FABRIK3D", "CCDIK3D", "SplineIK3D", "SkeletonIK3D", "BoneConstraint3D", "ModifierBoneTarget3D"]:
		print("[spike] class ", cn, " exists=", ClassDB.class_exists(cn))
	for cn in ["TwoBoneIK3D", "LookAtModifier3D"]:
		if not ClassDB.class_exists(cn):
			continue
		print("[spike] ", cn, " parent=", ClassDB.get_parent_class(cn), " instantiable=", ClassDB.can_instantiate(cn))
		var props := []
		for p in ClassDB.class_get_property_list(cn, true):
			props.append(p["name"])
		print("[spike] ", cn, " props=", props)
		var ms := []
		for m in ClassDB.class_get_method_list(cn, true):
			ms.append(m["name"])
		print("[spike] ", cn, " methods=", ms)
	# Crew rig: find a skeleton and the arm chain
	var scn := load("res://assets/characters/papi_fuego.glb") as PackedScene
	if scn == null:
		print("[spike] FAIL cannot load crew glb")
		quit(1)
		return
	var root := scn.instantiate()
	get_root().add_child(root)
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	print("[spike] skeleton=", sk, " bones=", sk.get_bone_count() if sk else -1)
	if sk == null:
		quit(1)
		return
	var names := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("[spike] bone names=", names)
	# TwoBoneIK3D on the right arm
	if ClassDB.class_exists("TwoBoneIK3D"):
		var ik: Node = ClassDB.instantiate("TwoBoneIK3D")
		sk.add_child(ik)
		ik.name = "SpikeIK"
		print("[spike] TwoBoneIK3D added, active=", ik.get("active"), " influence=", ik.get("influence"))
		var tgt := Node3D.new()
		get_root().add_child(tgt)
		var chain := ["root_bone", "middle_bone", "end_bone", "target_node", "pole_node", "setting_count"]
		for c in chain:
			print("[spike]  prop ", c, " = ", ik.get(c))
		# Try the 4.6+ per-setting API if present
		for m in ["set_root_bone_name", "set_middle_bone_name", "set_end_bone_name", "set_target_node", "set_pole_node", "set_setting_count", "set_root_bone", "set_end_bone"]:
			print("[spike]  has ", m, "=", ik.has_method(m))
		ik.queue_free()
	if ClassDB.class_exists("LookAtModifier3D"):
		var la: Node = ClassDB.instantiate("LookAtModifier3D")
		sk.add_child(la)
		print("[spike] LookAtModifier3D added, influence=", la.get("influence"), " bone_name=", la.get("bone_name"), " target_node=", la.get("target_node"))
		la.queue_free()
	# Functional check on the real arm chain: does the hand reach a target within the arm's reach, and does influence ramp?
	await process_frame
	var hand := sk.find_bone("RightHand")
	var arm := sk.find_bone("RightArm")
	var fore := sk.find_bone("RightForeArm")
	var hand_before: Vector3 = sk.global_transform * sk.get_bone_global_pose(hand).origin
	var arm_pos: Vector3 = sk.global_transform * sk.get_bone_global_pose(arm).origin
	var reach: float = (sk.get_bone_global_pose(arm).origin - sk.get_bone_global_pose(fore).origin).length() + (sk.get_bone_global_pose(fore).origin - sk.get_bone_global_pose(hand).origin).length()
	reach *= sk.global_transform.basis.get_scale().x # bone poses are skeleton-local (the GLB root carries the unit scale)
	var tgt2 := Node3D.new()
	tgt2.name = "SpikeTarget"
	get_root().add_child(tgt2)
	var want := arm_pos + Vector3(0.0, -0.1, 0.9) * reach * 0.9 # in front of the shoulder, 90 % of reach (world axes: the model is unrotated)
	tgt2.global_position = want
	var ik2: Node = ClassDB.instantiate("TwoBoneIK3D")
	sk.add_child(ik2)
	ik2.setting_count = 1
	ik2.set_root_bone_name(0, "RightArm")
	ik2.set_middle_bone_name(0, "RightForeArm")
	ik2.set_end_bone_name(0, "RightHand")
	ik2.set_target_node(0, ik2.get_path_to(tgt2))
	print("[spike] arm reach=", snappedf(reach, 0.001), " m; hand before: dist to target=", snappedf(hand_before.distance_to(want), 0.001))
	print("[spike] ik2 bone ids root/mid/end=", ik2.get_root_bone(0), "/", ik2.get_middle_bone(0), "/", ik2.get_end_bone(0), " (arm/fore/hand=", arm, "/", fore, "/", hand, ") skeleton of ik2=", ik2.get_skeleton() if ik2.has_method("get_skeleton") else "n/a", " ik2 class chain=", ik2.get_class())
	print("[spike] ik2 settings=", ik2.setting_count, " root=", ik2.get_root_bone_name(0), " mid=", ik2.get_middle_bone_name(0), " end=", ik2.get_end_bone_name(0), " target=", ik2.get_target_node(0), " active=", ik2.active, " skeleton_mode=", sk.modifier_callback_mode_process, " modifier_child_count=", sk.get_child_count(), " tgt in tree=", tgt2.is_inside_tree())
	var seen := {"hand": Vector3.ZERO, "n": 0}
	if OS.get_cmdline_user_args().has("--with-lookat"):
		var la0: Node = ClassDB.instantiate("LookAtModifier3D")
		sk.add_child(la0)
		la0.bone_name = "Head"
		la0.set_target_node(la0.get_path_to(tgt2))
	sk.skeleton_updated.connect(func() -> void:
		seen["hand"] = sk.global_transform * sk.get_bone_global_pose(hand).origin # read INSIDE the update: the pose after all modifiers
		seen["n"] += 1)
	for infl in [1.0, 0.5, 0.0]:
		ik2.influence = infl
		for i in 20:
			await process_frame
		var hp: Vector3 = seen["hand"]
		print("[spike] TwoBoneIK3D influence=", infl, " -> hand dist to target (skeleton_updated, ", seen["n"], " updates)=", snappedf(hp.distance_to(want), 0.001), " ; outside-update read=", snappedf((sk.global_transform * sk.get_bone_global_pose(hand).origin).distance_to(want), 0.001))
	# LookAtModifier3D on the head toward a target on the left
	var head := sk.find_bone("Head")
	var la2: Node = ClassDB.instantiate("LookAtModifier3D")
	sk.add_child(la2)
	la2.bone_name = "Head"
	var lt := Node3D.new()
	lt.name = "SpikeLookTarget"
	get_root().add_child(lt)
	lt.global_position = (sk.global_transform * sk.get_bone_global_pose(head).origin) + Vector3(2, 0, 1)
	la2.set_target_node(la2.get_path_to(lt))
	var rest_fwd: Vector3 = (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z
	la2.influence = 0.0
	for i in 3:
		await process_frame
	var f0: Vector3 = (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z
	la2.influence = 1.0
	for i in 5:
		await process_frame
	var f1: Vector3 = (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z
	var hseen := {"f": f1}
	sk.skeleton_updated.connect(func() -> void: hseen["f"] = (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z)
	for i in 3:
		await process_frame
	f1 = hseen["f"]
	print("[spike] LookAtModifier3D head axis rotation at influence 1 vs 0: ", snappedf(rad_to_deg(f0.angle_to(f1)), 0.1), " deg (rest-vs-0: ", snappedf(rad_to_deg(rest_fwd.angle_to(f0)), 0.1), ")")
	# modifier order: IK before look-at in child order
	print("[spike] skeleton modifier children order=", sk.get_children().filter(func(n: Node) -> bool: return n is SkeletonModifier3D).map(func(n: Node) -> String: return n.get_class()))
	print("[spike] DONE")
	quit(0)
