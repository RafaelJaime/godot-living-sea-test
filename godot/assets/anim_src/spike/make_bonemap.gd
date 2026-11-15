extends SceneTree
## Prints the BoneMap (UAL bone names -> SkeletonProfileHumanoid) as an inline resource string for the glb .import file.
func _init() -> void:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	var m := {&"Root": "root", &"Hips": "pelvis", &"Spine": "spine_01", &"Chest": "spine_02", &"UpperChest": "spine_03", &"Neck": "neck_01", &"Head": "Head"}
	for side in ["Left", "Right"]:
		var s := "l" if side == "Left" else "r"
		m[StringName(side + "Shoulder")] = "clavicle_" + s
		m[StringName(side + "UpperArm")] = "upperarm_" + s
		m[StringName(side + "LowerArm")] = "lowerarm_" + s
		m[StringName(side + "Hand")] = "hand_" + s
		m[StringName(side + "UpperLeg")] = "thigh_" + s
		m[StringName(side + "LowerLeg")] = "calf_" + s
		m[StringName(side + "Foot")] = "foot_" + s
		m[StringName(side + "Toes")] = "ball_" + s
		for f in [["Thumb", "thumb", ["Metacarpal", "Proximal", "Distal"]], ["Index", "index", ["Proximal", "Intermediate", "Distal"]], ["Middle", "middle", ["Proximal", "Intermediate", "Distal"]],
				["Ring", "ring", ["Proximal", "Intermediate", "Distal"]], ["Little", "pinky", ["Proximal", "Intermediate", "Distal"]]]:
			for i in 3:
				m[StringName("%s%s%s" % [side, f[0], f[2][i]])] = "%s_%02d_%s" % [f[1], i + 1, s]
	for k in m:
		bm.set_skeleton_bone_name(k, StringName(m[k]))
	var f := FileAccess.open("res://assets/anim_src/spike/bonemap.txt", FileAccess.WRITE)
	f.store_string(var_to_str(bm))
	f.close()
	print("[bonemap] mapped ", m.size(), " bones")
	quit()
