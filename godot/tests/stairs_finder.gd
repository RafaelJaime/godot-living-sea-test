extends SceneTree
## Read-only survey (pivot space): finds LADDERS (>=4 horizontal rungs stacked at the same x/z, evenly spaced in y) and STAIRS (treads stepping up along z) in the ship GLB.
## Pivot = hull normalisation transform of ship_loader (yaw 180, origin below). usage: godot --headless --path godot --script res://tests/stairs_finder.gd
const GLB := "res://assets/ship/pinnace/barco_pinnace.glb"
const ORIGIN := Vector3(0.023975, -1.14587, 0.918434)
const MESHES := ["geo_ship_pinnace_deck.001", "geo_ship_pinnace_details", "geo_ship_pinnace_aft", "geo_ship_pinnace_interior"]

func _init() -> void:
	_run.call_deferred()

func _to_pivot(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, -v.z) + ORIGIN

func _run() -> void:
	var root_node := (load(GLB) as PackedScene).instantiate()
	root.add_child(root_node)
	var rungs := []   # {x, z, y, w, d}
	for mi in root_node.find_children("*", "MeshInstance3D", true, false):
		if not MESHES.has(mi.name):
			continue
		var xf: Transform3D = (mi as Node3D).global_transform
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tris := idx.size() / 3 if idx.size() > 0 else vs.size() / 3
			# group horizontal triangles into small patches by connected bounding boxes: use per-triangle centre buckets
			var buckets := {}
			for t in tris:
				var i0 := idx[t * 3] if idx.size() > 0 else t * 3
				var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
				var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
				var a := _to_pivot(xf * vs[i0]); var b := _to_pivot(xf * vs[i1]); var c := _to_pivot(xf * vs[i2])
				var n := (b - a).cross(c - a)
				if n.length() < 1e-9:
					continue
				n = n.normalized()
				if absf(n.y) < 0.96:
					continue
				var cen := (a + b + c) / 3.0
				if cen.y < 1.2 or cen.y > 9.0 or absf(cen.x) > 4.0 or cen.z < -13.0 or cen.z > 16.0:
					continue
				var key := Vector3i(int(roundf(cen.x / 0.12)), int(roundf(cen.y / 0.04)), int(roundf(cen.z / 0.12)))
				if not buckets.has(key):
					buckets[key] = [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
				var bb: Array = buckets[key]
				for p in [a, b, c]:
					bb[0] = (bb[0] as Vector3).min(p); bb[1] = (bb[1] as Vector3).max(p)
			# merge buckets into rung records (thin in z or x)
			for k in buckets:
				var bb: Array = buckets[k]
				var mn: Vector3 = bb[0]; var mx: Vector3 = bb[1]
				var sz := mx - mn
				if sz.x > 1.4 or sz.z > 1.4 or sz.x < 0.05 and sz.z < 0.05:
					continue
				rungs.append({"c": (mn + mx) * 0.5, "sz": sz})
	print("[ladder] small tread records: ", rungs.size())
	var win := OS.get_cmdline_user_args()
	if win.size() >= 4:
		var z0 := float(win[0]); var z1 := float(win[1]); var y0 := float(win[2]); var y1 := float(win[3])
		var sel := []
		for r in rungs:
			var c: Vector3 = r["c"]
			if c.z >= z0 and c.z <= z1 and c.y >= y0 and c.y <= y1:
				sel.append(r)
		sel.sort_custom(func(p, q): return p["c"].y < q["c"].y)
		for r in sel:
			print("[rec] y %.2f z %.2f x %.2f size(%.2f,%.2f,%.2f)" % [r["c"].y, r["c"].z, r["c"].x, r["sz"].x, r["sz"].y, r["sz"].z])
	# ladders: stacks of records with similar (x,z) within 0.25, y spacing 0.15..0.45, >= 4 levels
	var used := {}
	var cols := {}
	for r in rungs:
		var c: Vector3 = r["c"]
		var key := Vector2i(int(roundf(c.x / 0.3)), int(roundf(c.z / 0.3)))
		if not cols.has(key):
			cols[key] = []
		cols[key].append(c)
	for key in cols:
		var arr: Array = cols[key]
		arr.sort_custom(func(p, q): return p.y < q.y)
		var ys := []
		for c in arr:
			if ys.is_empty() or c.y - ys[ys.size() - 1] > 0.1:
				ys.append(c.y)
		if ys.size() >= 4:
			var gaps := []
			for i in range(1, ys.size()):
				gaps.append(ys[i] - ys[i - 1])
			var mean := 0.0
			for g in gaps:
				mean += g
			mean /= gaps.size()
			if mean > 0.14 and mean < 0.5:
				var cx := 0.0; var cz := 0.0
				for c in arr:
					cx += c.x; cz += c.z
				print("[ladder] ", ys.size(), " rungs  x %.2f z %.2f  y %.2f -> %.2f  spacing %.2f" % [cx / arr.size(), cz / arr.size(), ys[0], ys[ys.size() - 1], mean])
	quit()
