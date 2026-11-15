extends RefCounted
## Line-of-sight queries against the ship's own geometry (hull, masts, yards, sails, rigging), in the ship pivot's local
## frame. Used by camera_director.gd to place shots so that no sail, shroud or lantern sits between the lens and its subject.
## Built once from the visible meshes under the ship model (rest pose; crew are not part of it), cached triangle BVHs.

var items: Array = [] ## {slot: {tm: TriangleMesh, aabb: AABB (mesh space)}, inv: Transform3D, box: AABB (pivot space), name: String}; empty until built
var last_blocker := ""

# Incremental, mostly off-thread build (see begin_build / step_build). The expensive parts of the old synchronous build were RenderingServer
# read-backs (surface_get_arrays / get_faces / bake_mesh_from_current_skeleton_pose cost 5-9 ms EACH on the main thread, ~180 ms in total).
# Now the main thread only (1) snapshots the skeleton skin transforms in slices and (2) queues one worker task per mesh; the worker reads the
# mesh arrays, skins them with the snapshot (the same maths as MeshInstance3D.bake_mesh_from_current_skeleton_pose, checked with --cam-verify),
# builds the triangle BVH and publishes the result in its slot. The set is built once and cached.
var _meshes: Array[Node] = []
var _next := 0
var _stage := 0 ## 0 = skin snapshot, 1 = queue mesh tasks, 2 = wait for the tasks
var _pivot_inv := Transform3D.IDENTITY
var _pending: Array = [] ## {slot, task: int, inv, name, xf}
var _slot_cache := {}
var _skel: Skeleton3D
var _skin: Skin
var _skin_xf: Array[Transform3D] = []
var _skin_next := 0
var building := false
var verify_log := false
var _verify_n := 0
var _verify_list: Array = []

func begin_build(roots: Array, pivot: Node3D) -> void:
	items.clear()
	_pending.clear()
	_slot_cache.clear()
	_meshes.clear()
	for r in roots:
		_meshes.append_array((r as Node).find_children("*", "MeshInstance3D", true, false))
	_next = 0
	_stage = 0
	_skel = null
	_skin = null
	_skin_xf = []
	_skin_next = 0
	for n in _meshes: # the shared skeleton and skin of the ship (one skin with every bone)
		var mi := n as MeshInstance3D
		if _skel == null and mi.skin != null and not mi.skeleton.is_empty():
			_skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D
			_skin = mi.skin
	_pivot_inv = pivot.global_transform.affine_inverse()
	verify_log = OS.get_cmdline_user_args().has("--cam-verify")
	building = true

## Advances the build for about `budget_us` microseconds (at least one unit per call). True once `items` is complete.
func step_build(budget_us: int) -> bool:
	if not building:
		return not items.is_empty()
	var t_end := Time.get_ticks_usec() + budget_us
	if _stage == 0:
		if _skin != null and _skel != null:
			var n := _skin.get_bind_count()
			if _skin_xf.size() != n:
				_skin_xf.resize(n)
			while _skin_next < n:
				var j := _skin_next
				var bi := _skin.get_bind_bone(j)
				if bi < 0:
					bi = _skel.find_bone(_skin.get_bind_name(j))
				_skin_xf[j] = (_skel.get_bone_global_pose(bi) if bi >= 0 else Transform3D.IDENTITY) * _skin.get_bind_pose(j)
				_skin_next += 1
				if (j & 31) == 31 and Time.get_ticks_usec() >= t_end:
					return false
		_stage = 1
	if _stage == 1:
		while _next < _meshes.size():
			_queue_one(_meshes[_next] as MeshInstance3D)
			_next += 1
			if Time.get_ticks_usec() >= t_end:
				return false
		_stage = 2
	for p in _pending:
		if not WorkerThreadPool.is_task_completed(p["task"]):
			return false # still working off-thread: check again next frame, never block
	for p in _pending:
		WorkerThreadPool.wait_for_task_completion(p["task"]) # releases the task
	for p in _pending:
		var slot: Dictionary = p["slot"]
		if (slot["tm"] as TriangleMesh) == null:
			continue
		var xf: Transform3D = p["xf"]
		items.append({"slot": slot, "inv": xf.affine_inverse(), "box": xf * (slot["aabb"] as AABB), "name": p["name"], "solid": false})
	_pending.clear()
	_slot_cache.clear()
	_meshes.clear()
	for v in _verify_list:
		_verify(v[0], null, v[1])
	_verify_list.clear()
	building = false
	return not items.is_empty()

## Exit safety: worker tasks must not outlive the scene tree. A worker blocked in a RenderingServer read needs the main thread to flush its command
## queue, so a plain wait would deadlock; flush while polling (bounded), then release every task.
func finish_pending(timeout_ms := 3000) -> void:
	var t_end := Time.get_ticks_msec() + timeout_ms
	for p in _pending:
		while not WorkerThreadPool.is_task_completed(p["task"]) and Time.get_ticks_msec() < t_end:
			RenderingServer.force_sync()
			OS.delay_usec(500)
	for p in _pending:
		if WorkerThreadPool.is_task_completed(p["task"]):
			WorkerThreadPool.wait_for_task_completion(p["task"])
	_pending.clear()
	_meshes.clear()
	building = false

func _queue_one(mi: MeshInstance3D) -> void:
	if mi.mesh == null or not mi.is_visible_in_tree():
		return
	var xf := _pivot_inv * mi.global_transform
	if absf(xf.basis.determinant()) < 1e-6:
		return # collapsed (unlit lantern flames scale to zero): not invertible, nothing to see
	var mesh: Mesh = mi.mesh
	var skinned := mi.skin != null and not _skin_xf.is_empty() and mi.skin == _skin
	var key: Variant = mesh if not skinned else null
	var slot: Dictionary
	if key != null and _slot_cache.has(key):
		slot = _slot_cache[key]
	else:
		slot = {"tm": null, "aabb": AABB(), "task": -1}
		var xfs := _skin_xf if skinned else ([] as Array[Transform3D])
		slot["task"] = WorkerThreadPool.add_task(func() -> void: _worker(slot, mesh, xfs))
		if verify_log and skinned and _verify_n < 4:
			_verify_n += 1
			_verify_list.append([slot, mi])
		if key != null:
			_slot_cache[key] = slot
	_pending.append({"slot": slot, "task": slot["task"], "xf": xf, "name": String(mi.name)})

## Worker thread: skins (when `xfs` is given) every surface of `mesh`, builds the BVH, fills the slot. Pure data in, pure data out.
func _worker(slot: Dictionary, mesh: Mesh, xfs: Array[Transform3D]) -> void:
	var faces := PackedVector3Array()
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	if xfs.is_empty():
		faces = mesh.get_faces()
		for v in faces:
			lo = lo.min(v)
			hi = hi.max(v)
	else:
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var n := vs.size()
			if n == 0:
				continue
			var infl := bones.size() / n
			var out := PackedVector3Array()
			out.resize(n)
			for i in n:
				var v := vs[i]
				var p := Vector3.ZERO
				for k in infl:
					var w := weights[i * infl + k]
					if w > 0.0:
						p += (xfs[bones[i * infl + k]] * v) * w
				out[i] = p
				lo = lo.min(p)
				hi = hi.max(p)
			if idx.is_empty():
				faces.append_array(out)
			else:
				for t in idx:
					faces.append(out[t])
	if faces.is_empty():
		return
	var tm := TriangleMesh.new()
	tm.create_from_faces(faces)
	slot["aabb"] = AABB(lo, hi - lo)
	slot["tm"] = tm

## --cam-verify: compares the worker result with the engine bake for one mesh (main thread, debug only).
func _verify(slot: Dictionary, _mesh: Mesh, mi: MeshInstance3D) -> void: # (never waits on a task: workers need the main thread for RenderingServer reads)
	var baked := mi.bake_mesh_from_current_skeleton_pose()
	if baked == null or slot["tm"] == null:
		print("[camverify] ", mi.name, " no bake / no result")
		return
	var bf := baked.get_faces()
	var mf := (slot["tm"] as TriangleMesh).get_faces()
	var md := 0.0
	if bf.size() == mf.size():
		for i in bf.size():
			md = maxf(md, bf[i].distance_to(mf[i]))
	print("[camverify] ", mi.name, " faces ", bf.size() / 3, " vs ", mf.size() / 3, " max vertex diff ", snappedf(md, 0.0001), " m")

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
		var h: Dictionary = ((it["slot"] as Dictionary)["tm"] as TriangleMesh).intersect_segment(inv * a, inv * b)
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
