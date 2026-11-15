extends Node
## H1.1 deck survey (read-only debug aid, flag --deck-survey): prints Pivot-local coordinates of the deck levels and steps (downward rays against
## temporary trimesh colliders of the deck/aft meshes), the mast tops (platform candidates), the helm wheel, the crew markers and the lights.
## Output goes to the log with the prefix [survey]; the findings are written up in odd/evidence/npc-crew-jobs/H1/deck_survey.md.

func _ready() -> void:
	get_node("/root/Main/Ship/Pivot/Model").ship_ready.connect(_run.unbind(3), CONNECT_DEFERRED)

func _run() -> void:
	var pivot := get_node("/root/Main/Ship/Pivot") as Node3D
	var model := get_node("/root/Main/Ship/Pivot/Model")
	# --- temporary colliders on a private layer ---
	var bodies: Array[StaticBody3D] = []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var low := String(mi.name).to_lower()
		if mi.mesh == null or not ("deck" in low or "aft" in low or "interior" in low):
			continue
		var b := StaticBody3D.new()
		b.collision_layer = 1 << 18
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		b.add_child(cs)
		add_child(b)
		b.global_transform = mi.global_transform
		bodies.append(b)
	for i in 3:
		await get_tree().physics_frame
	var space := pivot.get_world_3d().direct_space_state
	var xs := [-3.0, -1.5, 0.0, 1.5, 3.0]
	print("[survey] deck height by z (Pivot-local, m) for x = ", xs, " (top-down ray from y 14; '-' = nothing)")
	var z := 21.0
	while z >= -21.0:
		var row := "[survey] z=%6.1f" % z
		for x in xs:
			var q := PhysicsRayQueryParameters3D.create(pivot.to_global(Vector3(x, 14.0, z)), pivot.to_global(Vector3(x, -2.0, z)))
			q.collision_mask = 1 << 18
			var h := space.intersect_ray(q)
			row += "  " + ("%5.2f" % pivot.to_local(h["position"]).y if not h.is_empty() else "  -  ")
		print(row)
		z -= 1.0
	for b in bodies:
		b.queue_free()
	# --- mast tops: widest horizontal extent per 1 m slice above 8 m ---
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name).to_lower()
		if not (nm.ends_with("_mast") or nm.ends_with("foremast")):
			continue
		var pts := ModelUtil.posed_points(mi, pivot, 100000000)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		print("[survey] mast ", mi.name, " bbox lo=", lo.snapped(Vector3.ONE * 0.01), " hi=", hi.snapped(Vector3.ONE * 0.01))
		var y0 := int(floor(lo.y))
		for y in range(maxi(y0, 8), int(ceil(hi.y)) + 1):
			var sl_lo := Vector2(INF, INF)
			var sl_hi := Vector2(-INF, -INF)
			var cnt := 0
			for p in pts:
				if p.y >= y and p.y < y + 1:
					sl_lo = sl_lo.min(Vector2(p.x, p.z))
					sl_hi = sl_hi.max(Vector2(p.x, p.z))
					cnt += 1
			if cnt > 0:
				print("[survey]   y=%d..%d extent x=%.2f z=%.2f centre=(%.2f, %.2f) verts=%d" % [y, y + 1, sl_hi.x - sl_lo.x, sl_hi.y - sl_lo.y, (sl_hi.x + sl_lo.x) * 0.5, (sl_hi.y + sl_lo.y) * 0.5, cnt])
	# --- helm, crew markers, lights ---
	var helm := get_node_or_null("/root/Main/Ship/Pivot/Helm")
	if helm == null:
		for h in get_tree().root.find_children("*", "Node", true, false):
			if h.get_script() != null and "wheel_pos" in h:
				helm = h
				break
	if helm:
		print("[survey] helm wheel_pos (Pivot-local) = ", helm.wheel_pos, " radius ", helm.wheel_radius)
	var cm := get_node_or_null("/root/Main/Ship/Pivot/CrewMarkers")
	if cm:
		for c in cm.get_children():
			if c is Node3D:
				print("[survey] crew marker ", c.name, " Pivot-local = ", (c as Node3D).position.snapped(Vector3.ONE * 0.01))
	for l in ShipLights.get_lanterns():
		print("[survey] light ", l["id"], " local_position=", (l["local_position"] as Vector3).snapped(Vector3.ONE * 0.01), " stand_local=", (l["stand_local"] as Vector3).snapped(Vector3.ONE * 0.01))
	print("[survey] done")
