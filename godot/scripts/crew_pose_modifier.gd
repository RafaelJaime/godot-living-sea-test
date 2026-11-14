class_name CrewPoseModifier
extends SkeletonModifier3D
## Procedural layer over the imported animation: counter-leans the body against the ship's roll/pitch, leans into
## turns, turns the head toward the heading change and braces (small crouch + forward lean) on hard motion.
## Rotations are specified about WORLD axes and converted to the skeleton's frame, so the rig's bone axes do not matter.

var ship: Node           ## buoyancy.gd (rudder, yaw_rate, current_speed)
var pivot: Node3D        ## ship pivot (roll = rotation.z, pitch = rotation.x)
var counter_roll := 0.75 ## fraction of the ship's roll cancelled
var counter_pitch := 0.45
var turn_lean := 1.2     ## rad of lean per rad/s of yaw rate (into the turn)
var head_look := 0.0     ## rad of head yaw per unit rudder (toward the turn); 0 = disabled
var brace_gain := 1.0
var head_max := 0.44      ## max head yaw (rad) relative to the body (about 25 deg)
## Bones forced back to the rest pose every frame BEFORE the layers below (so the imported idle cannot drive them,
## e.g. the head looking back, and nothing accumulates). IK arms then start from a stable pose.
var neutral_bones: PackedStringArray = PackedStringArray()
var _neutral_idx: Array[int] = []
var _hips := -1
var _head := -1
var _spine := -1
var _brace := 0.0
var _last_t := 0.0

func _ready() -> void:
	var sk := get_skeleton()
	if sk:
		_hips = sk.find_bone("Hips")
		_head = sk.find_bone("Head")
		_spine = sk.find_bone("Spine")
		for n in neutral_bones:
			var i := sk.find_bone(n)
			if i >= 0:
				_neutral_idx.append(i)

func _rot_world(sk: Skeleton3D, bone: int, axis_world: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 1e-5:
		return
	var parent := sk.get_bone_parent(bone)
	var rp := Quaternion.IDENTITY
	if parent >= 0:
		rp = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var axis_skel := (sk.global_transform.basis.inverse() * axis_world).normalized()
	var q := Quaternion(axis_skel, angle)
	var local := sk.get_bone_pose_rotation(bone)
	sk.set_bone_pose_rotation(bone, (rp.inverse() * q * rp * local).normalized())

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or ship == null or pivot == null or _hips < 0:
		return
	for i in _neutral_idx:
		sk.set_bone_pose(i, sk.get_bone_rest(i))
	var roll: float = pivot.rotation.z
	var pitch: float = pivot.rotation.x
	var roll_rate: float = ship.get("roll_rate") if ship.get("roll_rate") != null else 0.0
	var yaw_rate: float = ship.get("yaw_rate") if ship.get("yaw_rate") != null else 0.0
	var rudder: float = ship.get("rudder") if ship.get("rudder") != null else 0.0
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - _last_t, 0.001, 0.1)
	_last_t = now
	# Brace on hard ship motion (smoothed so it eases in and out).
	var hard := clampf((absf(roll) + absf(pitch) * 1.5 + absf(roll_rate) * 0.25 - 0.09) / 0.16, 0.0, 1.0)
	_brace = lerpf(_brace, hard * brace_gain, 1.0 - exp(-4.0 * dt))
	# World axes: forward-roll axis is the ship's +Z (aft), pitch axis is +X.
	var basis_p := pivot.global_transform.basis
	var z_axis := basis_p.z.normalized()
	var x_axis := basis_p.x.normalized()
	var lean := -roll * counter_roll + yaw_rate * turn_lean - roll_rate * 0.10 # inertia: the body lags the deck
	_rot_world(sk, _hips, z_axis, lean * 0.6)
	_rot_world(sk, _spine, z_axis, lean * 0.4)
	var fwd_lean := -pitch * counter_pitch + _brace * 0.12 # bracing leans slightly forward (-Z tilt = negative about +X)
	_rot_world(sk, _hips, x_axis, fwd_lean * 0.6)
	_rot_world(sk, _spine, x_axis, fwd_lean * 0.4)
	if _brace > 0.01:
		var p := sk.get_bone_pose_position(_hips)
		sk.set_bone_pose_position(_hips, p + Vector3(0, -7.0 * _brace, 0)) # skeleton units are ~cm
	if head_look != 0.0:
		_rot_world(sk, _head, Vector3.UP, clampf(-rudder * head_look, -head_max, head_max))
