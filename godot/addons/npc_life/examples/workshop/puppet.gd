class_name NpcExamplePuppet
extends RefCounted
## Example-only: a stick-figure puppet built in code (a Skeleton3D with the default NpcRigProfile bone names, one thin box per bone, an
## AnimationPlayer: the example's NpcAnimSet installs the own idle / walk / work clips into it), so the example shows real IK and crossfades without shipping any third-party asset.

const BONES := [
	# name, parent, rest position (m, parent space), bone length along its local -Y (m), thickness
	["Hips", "", Vector3(0, 0.95, 0), 0.0, 0.0],
	["Spine", "Hips", Vector3(0, 0.0, 0), -0.55, 0.14],
	["Head", "Spine", Vector3(0, 0.55, 0), -0.22, 0.12],
	["LeftUpperArm", "Spine", Vector3(-0.2, 0.5, 0), 0.3, 0.06],
	["LeftLowerArm", "LeftUpperArm", Vector3(0, -0.3, 0.035), 0.28, 0.05],
	["LeftHand", "LeftLowerArm", Vector3(0, -0.28, 0), 0.1, 0.05],
	["RightUpperArm", "Spine", Vector3(0.2, 0.5, 0), 0.3, 0.06],
	["RightLowerArm", "RightUpperArm", Vector3(0, -0.3, 0.035), 0.28, 0.05],
	["RightHand", "RightLowerArm", Vector3(0, -0.28, 0), 0.1, 0.05],
	["LeftUpperLeg", "Hips", Vector3(-0.1, 0.0, 0), 0.45, 0.08],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0, -0.45, 0), 0.45, 0.07],
	["RightUpperLeg", "Hips", Vector3(0.1, 0.0, 0), 0.45, 0.08],
	["RightLowerLeg", "RightUpperLeg", Vector3(0, -0.45, 0), 0.45, 0.07],
]

## Builds the puppet: returns the root Node3D (children: Skeleton3D, AnimationPlayer). `tint` colours the boxes.
static func build(tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Puppet"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	var idx := {}
	for b in BONES:
		idx[b[0]] = sk.get_bone_count()
		sk.add_bone(b[0])
	for b in BONES:
		var i: int = idx[b[0]]
		if b[1] != "":
			sk.set_bone_parent(i, idx[b[1]])
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, b[2]))
	sk.reset_bone_poses()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	for b in BONES:
		var length: float = b[3]
		if absf(length) < 0.001:
			continue
		var att := BoneAttachment3D.new()
		att.name = "%sVis" % b[0]
		att.bone_name = b[0]
		sk.add_child(att)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(b[4], absf(length), b[4])
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(0, -length * 0.5 if length > 0.0 else absf(length) * 0.5, 0)
		att.add_child(mi)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.root_node = player.get_path_to(root)
	return root

## Own, minimal clips: `idle` (slow sway) and `walk` (bob and leg swing). 1 s loops.
static func clips() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.set_meta("source_hips_y", 0.95)
	var idle := Animation.new()
	idle.length = 2.0
	idle.loop_mode = Animation.LOOP_LINEAR
	_pos(idle, "Hips", [[0.0, Vector3(0, 0.95, 0)], [1.0, Vector3(0, 0.945, 0)], [2.0, Vector3(0, 0.95, 0)]])
	_rot(idle, "Spine", [[0.0, Vector3(0, 0, 0.01)], [1.0, Vector3(0, 0, -0.01)], [2.0, Vector3(0, 0, 0.01)]])
	lib.add_animation("idle", idle)
	var walk := Animation.new()
	walk.length = 1.0
	walk.loop_mode = Animation.LOOP_LINEAR
	_pos(walk, "Hips", [[0.0, Vector3(0, 0.95, 0)], [0.25, Vector3(0, 0.98, 0)], [0.5, Vector3(0, 0.95, 0)], [0.75, Vector3(0, 0.98, 0)], [1.0, Vector3(0, 0.95, 0)]])
	_rot(walk, "LeftUpperLeg", [[0.0, Vector3(0.5, 0, 0)], [0.5, Vector3(-0.5, 0, 0)], [1.0, Vector3(0.5, 0, 0)]])
	_rot(walk, "RightUpperLeg", [[0.0, Vector3(-0.5, 0, 0)], [0.5, Vector3(0.5, 0, 0)], [1.0, Vector3(-0.5, 0, 0)]])
	_rot(walk, "LeftUpperArm", [[0.0, Vector3(-0.4, 0, 0)], [0.5, Vector3(0.4, 0, 0)], [1.0, Vector3(-0.4, 0, 0)]])
	_rot(walk, "RightUpperArm", [[0.0, Vector3(0.4, 0, 0)], [0.5, Vector3(-0.4, 0, 0)], [1.0, Vector3(0.4, 0, 0)]])
	lib.add_animation("walk", walk)
	var work := Animation.new()
	work.length = 1.0
	work.loop_mode = Animation.LOOP_LINEAR
	_rot(work, "Spine", [[0.0, Vector3(0.12, 0, 0)], [0.5, Vector3(0.2, 0, 0)], [1.0, Vector3(0.12, 0, 0)]])
	lib.add_animation("work", work)
	return lib

static func _pos(a: Animation, bone: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, NodePath("Skeleton3D:" + bone))
	for k in keys:
		a.position_track_insert_key(t, k[0], k[1])

static func _rot(a: Animation, bone: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("Skeleton3D:" + bone))
	for k in keys:
		a.rotation_track_insert_key(t, k[0], Quaternion.from_euler(k[1]))

static func skeleton_of(root: Node) -> Skeleton3D:
	return root.get_node("Skeleton3D") as Skeleton3D
