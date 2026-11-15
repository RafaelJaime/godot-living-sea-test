extends RefCounted
## Line-of-sight queries against the ship's own geometry (hull, masts, yards, sails, rigging), in the ship pivot's local
## frame. Used by camera_director.gd to place shots so that no sail, shroud or lantern sits between the lens and its subject.
## Built once from the visible meshes under the ship model (rest pose; crew are not part of it), cached triangle BVHs.

var items: Array = [] ## {tm: TriangleMesh, inv: Transform3D, box: AABB (pivot space), name: String}
var last_blocker := ""

func build(roots: Array, pivot: Node3D) -> bool:
	items.clear()
	var pinv := pivot.global_transform.affine_inverse()
	var cache := {}
	var meshes: Array[Node] = []
	for r in roots:
		meshes.append_array((r as Node).find_children("*", "MeshInstance3D", true, false))
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var mesh: Mesh = mi.mesh
		var tm: TriangleMesh = null
		if mi.skin != null or not mi.skeleton.is_empty():
			# Skinned (almost the whole ship): bake the CURRENT skeleton pose, the bind pose differs from what is on screen.
			var baked := mi.bake_mesh_from_current_skeleton_pose()
			if baked != null:
				mesh = baked
				tm = baked.generate_triangle_mesh()
		else:
			tm = cache.get(mesh)
			if tm == null:
				tm = mesh.generate_triangle_mesh()
				cache[mesh] = tm
		if tm == null:
			continue
		var xf := pinv * mi.global_transform
		if absf(xf.basis.determinant()) < 1e-6:
			continue # collapsed (unlit lantern flames scale to zero): not invertible, nothing to see
		var solid := false # (sails stay triangle meshes: their boxes are huge, solid boxes would exclude every spot under them)
		var box: AABB = xf * mesh.get_aabb()
		items.append({"tm": tm, "inv": xf.affine_inverse(), "box": box.grow(1.2) if solid else box, "name": String(mi.name), "solid": solid})
	return not items.is_empty()

## True when the segment a -> b (pivot space) crosses any ship triangle.
func blocked(a: Vector3, b: Vector3) -> bool:
	for it in items:
		var hit: Variant = (it["box"] as AABB).intersects_segment(a, b)
		if hit == null or (hit is bool and not hit):
			continue
		if it["solid"]:
			last_blocker = it["name"]
			return true
		var inv: Transform3D = it["inv"]
		var h: Dictionary = (it["tm"] as TriangleMesh).intersect_segment(inv * a, inv * b)
		if not h.is_empty():
			last_blocker = it["name"]
			return true
	return false

## Fraction (0..1) of a dense ray grid from `cam` to the subject (`samples` are offsets: x across the view, y up) that is free.
## Thin shrouds and ratlines slip through a handful of rays, so the grid is fine (see camera_director._crew_samples); stops early
## once clearly blocked.
func clear_fraction(cam: Vector3, target: Vector3, samples: Array) -> float:
	var dir := target - cam
	var across := dir.cross(Vector3.UP)
	across = across.normalized() if across.length() > 0.001 else Vector3.RIGHT
	var blocked_n := 0
	var limit := maxi(samples.size() / 4, 1)
	for s in samples:
		var sp := s as Vector3
		if blocked(cam, target + across * sp.x + Vector3(0, sp.y, 0)):
			blocked_n += 1
			if blocked_n > limit:
				break
	return 1.0 - float(blocked_n) / float(maxi(samples.size(), 1))

## True when something sits within `reach` metres of the lens inside a cone (+-24 deg across, +-14 deg up/down) around the line to
## `target`: a lantern or rail filling a third of the frame is not an occlusion of the subject, but it ruins the shot.
func near_blocked(cam: Vector3, target: Vector3, reach := 2.5) -> bool:
	var dir := (target - cam).normalized()
	var across := dir.cross(Vector3.UP)
	across = across.normalized() if across.length() > 0.001 else Vector3.RIGHT
	var up := across.cross(dir).normalized()
	for ax in [-0.45, 0.0, 0.45]:
		for ay in [-0.25, 0.0, 0.25]:
			if blocked(cam, cam + (dir + across * ax + up * ay).normalized() * reach):
				return true
	return false
