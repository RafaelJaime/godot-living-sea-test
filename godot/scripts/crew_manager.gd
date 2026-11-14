extends Node3D
## Places the crew once the ship is normalized. Builds temporary trimesh colliders on the ship
## meshes so slots can snap to the deck with a downward raycast, then discards them.

@export var ship_loader_path := NodePath("../Model")
@export var enabled_raycast_snap := true
## Only meshes whose name contains one of these take part in deck snapping (empty = all except sails/flags).
@export var snap_mesh_filter := PackedStringArray(["deck", "aft"])

signal crew_ready

func _ready() -> void:
	var loader := get_node(ship_loader_path)
	if loader.has_signal("ship_ready"):
		loader.ship_ready.connect(_on_ship_ready)

func loader_node() -> Node:
	return get_node(ship_loader_path)

func _on_ship_ready(length: float, beam: float, _ref: float) -> void:
	var bodies: Array[Node] = []
	if enabled_raycast_snap:
		var loader := get_node(ship_loader_path)
		for n in loader.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var low := mi.name.to_lower()
			if "sail" in low or "flag" in low:
				continue
			if not snap_mesh_filter.is_empty():
				var ok := false
				for f in snap_mesh_filter:
					if f in low:
						ok = true
				if not ok:
					continue
			mi.create_trimesh_collision()
		await get_tree().physics_frame
		await get_tree().physics_frame
		bodies = loader.find_children("*", "StaticBody3D", true, false)
	var space := get_world_3d().direct_space_state
	var snap := func(x: float, z: float, ref_y: float) -> Variant:
		var from := to_global(Vector3(x, ref_y + 14.0, z))
		var to := to_global(Vector3(x, ref_y - 14.0, z))
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		return to_local(hit["position"]).y
	if OS.get_cmdline_user_args().has("--debug-deck"):
		for u in range(0, 21):
			var z := lerpf(length * 0.5, -length * 0.5, float(u) / 20.0)
			var row := "[deck] u=%.2f z=%6.1f" % [float(u) / 20.0, z]
			for v in [-0.8, -0.5, -0.25, 0.0, 0.25, 0.5, 0.8]:
				var hy: Variant = snap.call(v * beam * 0.5, z, 12.0)
				row += "  v%.2f:%s" % [v, ("  -  " if hy == null else "%5.1f" % float(hy))]
			print(row)
	if OS.get_cmdline_user_args().has("--debug-wheel"):
		var holder := loader_node().get_node("Normalized") as Node3D
		var verts := ModelUtil.sample_vertices(holder, 200000)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var n := 0
		for v in verts:
			var p := holder.transform * v
			if p.z > 6.2 and p.z < 8.6 and absf(p.x) < 1.6 and p.y > 4.3 and p.y < 7.0:
				lo = lo.min(p); hi = hi.max(p); n += 1
		print("[wheel] verts=", n, " lo=", lo, " hi=", hi)
	for c in get_children():
		if c.has_method("setup"):
			c.setup(length, beam, snap)
	for b in bodies:
		b.queue_free()
	crew_ready.emit()
