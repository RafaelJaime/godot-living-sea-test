extends Node
## Test aid (`--yard-survey`): prints, in ship-pivot space, the posed bounding box of every sail / mast / yard-related mesh and the position of every `def_*` bone, then quits.
## Used to place the aloft crew stations (yards, tops) on the real rig. Output lines start with `[yards]`.
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t < 4.0:
		return
	set_process(false)
	var main := get_parent()
	var pivot := main.get_node("Ship/Pivot") as Node3D
	var model := pivot.get_node("Model")
	var sail_i := 0
	var sk: Skeleton3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var low := String(mi.name).to_lower()
		if mi.mesh == null:
			continue
		if sk == null and mi.get_skeleton_path() != NodePath():
			sk = mi.get_node_or_null(mi.get_skeleton_path()) as Skeleton3D
		var tag := ""
		if "sails_" in low and low.ends_with("_down"):
			tag = "SAIL"
		elif "mast" in low:
			tag = "MAST"
		elif "rigging_" in low:
			tag = "RIG"
		if tag == "":
			continue
		var pts := ModelUtil.posed_points(mi, pivot, 100000000)
		if pts.is_empty():
			continue
		var mn := pts[0]; var mx := pts[0]
		for p in pts:
			mn = mn.min(p); mx = mx.max(p)
		print("[yards] %s %s visible=%s min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)" % [tag, mi.name, str(mi.visible), mn.x, mn.y, mn.z, mx.x, mx.y, mx.z])
	if sk != null:
		for b in sk.get_bone_count():
			var bn := sk.get_bone_name(b)
			if bn.begins_with("def_") and not bn.contains("rope") and not bn.contains("chain"):
				var g := pivot.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(b)).origin
				print("[yards] BONE %s (%.2f,%.2f,%.2f)" % [bn, g.x, g.y, g.z])
	var ship := main.get_node("Ship")
	if "sail_defs" in ship:
		for i in (ship.sail_defs as Array).size():
			var d: Dictionary = ship.sail_defs[i]
			print("[yards] SAILDEF %d %s pos=(%.2f,%.2f,%.2f) area=%.1f" % [i, d["name"], d["pos"].x, d["pos"].y, d["pos"].z, d["area"]])
	get_tree().quit()
