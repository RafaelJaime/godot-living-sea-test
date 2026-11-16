extends SceneTree
## Read-only survey (pivot space): the walkable height along z for several x lanes, from downward rays against trimesh colliders of the deck/aft/interior/hull meshes.
## Prints every change of height > 0.12 m between consecutive samples, i.e. steps, stairs and ramps. usage: godot --headless --path godot --script res://tests/deck_profile.gd
const GLB := "res://assets/ship/pinnace/barco_pinnace.glb"
const ORIGIN := Vector3(0.023975, -1.14587, 0.918434)
const MESHES := ["geo_ship_pinnace_deck.001", "geo_ship_pinnace_details", "geo_ship_pinnace_aft", "geo_ship_pinnace_interior", "geo_ship_pinnace_hull"]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.transform = Transform3D(Basis(Vector3.UP, PI), ORIGIN)  # glb -> pivot: yaw 180 then origin (as ship_loader's normalisation)
	var inst := (load(GLB) as PackedScene).instantiate()
	holder.add_child(inst)
	await process_frame
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if not MESHES.has(mi.name):
			continue
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		b.add_child(cs)
		root.add_child(b)
		b.global_transform = (mi as Node3D).global_transform
	for _i in 3:
		await physics_frame
	var space := (root as Window).world_3d.direct_space_state
	for x in [-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0]:
		var prev := NAN
		var line := "x=%.1f:" % x
		var z := -13.0
		while z <= 18.5:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -1.0, z))
			var hit := space.intersect_ray(q)
			var y := NAN if hit.is_empty() else float(hit["position"].y)
			if not is_nan(y) and not is_nan(prev) and absf(y - prev) > 0.12:
				line += "  z%.1f:%.2f->%.2f" % [z, prev, y]
			if not is_nan(y):
				prev = y
			z += 0.1
		print("[deck] ", line)
	quit()
