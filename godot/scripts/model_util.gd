class_name ModelUtil
extends RefCounted
## Helpers shared by the ship and crew loaders.

## Loads a GLB as a Node. Uses the imported resource when available, otherwise parses the
## file at runtime (so a freshly dropped GLB works even before the editor imported it).
static func load_glb(path: String) -> Node:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return (res as PackedScene).instantiate()
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			return doc.generate_scene(state)
	return null

static func file_present(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

## AABB of all meshes under `root`, expressed in `root`'s local space. `root` must be in the tree.
static func local_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var box: AABB
		var skel := _skeleton_of(mi)
		if skel != null and mi.skin != null:
			box = _skinned_aabb(mi, skel, inv)
		else:
			box = (inv * mi.global_transform) * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result

## All world-space... local-space mesh vertices (sampled) under root, for hull heuristics.
static func sample_vertices(root: Node3D, max_per_mesh := 4000) -> PackedVector3Array:
	var inv := root.global_transform.affine_inverse()
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var step: int = maxi(1, v.size() / max_per_mesh)
			for i in range(0, v.size(), step):
				out.append(t * v[i])
	return out

static func _skeleton_of(mi: MeshInstance3D) -> Skeleton3D:
	if mi.get_skeleton_path().is_empty():
		return null
	return mi.get_node_or_null(mi.get_skeleton_path()) as Skeleton3D

## AABB of a skinned mesh computed by CPU-skinning its vertices with the skeleton's current pose.
## (MeshInstance3D.get_aabb() ignores bone scales, e.g. the typical 0.01 armature / x100 bone pair.)
static func _skinned_aabb(mi: MeshInstance3D, skel: Skeleton3D, root_inv: Transform3D) -> AABB:
	var to_root := root_inv * skel.global_transform
	var skin := mi.skin
	var poses: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(i))
		var pose := skel.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
		poses.append(pose * skin.get_bind_pose(i))
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var stride := (bones.size() / verts.size()) if (verts.size() > 0 and bones.size() > 0) else 0
		var step: int = maxi(1, verts.size() / 6000)
		for vi in range(0, verts.size(), step):
			var p := Vector3.ZERO
			if stride == 0:
				p = verts[vi]
			else:
				var wsum := 0.0
				for k in stride:
					var w := weights[vi * stride + k]
					if w > 0.0:
						p += (poses[bones[vi * stride + k]] * verts[vi]) * w
						wsum += w
				if wsum > 0.0:
					p /= wsum
				else:
					p = verts[vi]
			p = to_root * p
			lo = lo.min(p)
			hi = hi.max(p)
	return AABB(lo, hi - lo)
