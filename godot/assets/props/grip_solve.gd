extends SceneTree
## Grid search of the grip orientation (u_to, v_to, tilt, roll) of a prop for a baked clip: minimises the mean angle between the prop axes
## (u = butt->working end, v = second model axis) in world space and the wanted directions, over the clip. Character faces +Z, up is +Y.
## usage: --script grip_solve.gd -- <clip res path> <hand> <want_u x,y,z> <want_v x,y,z|none>
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var clips: Array[Animation] = []
	for cp in args[0].split(","):
		clips.append(load(cp))
	var hand: String = args[1]
	var wu := _vec(args[2]).normalized()
	var wv := Vector3.ZERO if args[3] == "none" else _vec(args[3]).normalized()
	var inst := (load("res://assets/characters/papi_fuego.glb") as PackedScene).instantiate()
	root.add_child(inst)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var hi := sk.find_bone(hand + "Hand")
	var fa := sk.find_bone(hand + "ForeArm")
	var rb := sk.get_bone_global_rest(hi).basis
	var F := (rb.inverse() * (sk.get_bone_global_rest(hi).origin - sk.get_bone_global_rest(fa).origin)).normalized()
	var ng := Vector3.RIGHT if hand == "Right" else Vector3.LEFT
	var N := rb.inverse() * ng
	N = (N - F * N.dot(F)).normalized()
	var A := F.cross(N)
	if (rb * A).z < 0.0:
		A = -A
	var axes := {"F": F, "-F": -F, "N": N, "-N": -N, "A": A, "-A": -A}
	var bases: Array[Basis] = []
	var nfr := 24 * clips.size()
	for clip in clips:
		for f in 24:
			sk.reset_bone_poses()
			var t := clip.length * float(f) / 24.0
			for tr in clip.get_track_count():
				var bi := sk.find_bone(String(clip.track_get_path(tr)).get_slice(":", 1))
				if clip.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(bi, clip.rotation_track_interpolate(tr, t))
				elif clip.track_get_type(tr) == Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(bi, clip.position_track_interpolate(tr, t))
			bases.append(sk.get_bone_global_pose(hi).basis.orthonormalized())
	var best := []
	for un in axes:
		for vn in axes:
			if un.trim_prefix("-") == vn.trim_prefix("-"):
				continue
			for tilt in range(-90, 91, 15):
				for roll in range(0, 360, 30):
					var ut: Vector3 = axes[un]
					var vt: Vector3 = axes[vn]
					vt = (vt - ut * vt.dot(ut)).normalized()
					vt = Basis(ut, deg_to_rad(roll)) * vt
					var tb := Basis(N, deg_to_rad(tilt))
					ut = tb * ut
					vt = tb * vt
					var score := 0.0
					for b in bases:
						score += (b * ut).angle_to(wu)
						if wv != Vector3.ZERO:
							score += (b * vt).angle_to(wv)
					score = rad_to_deg(score / nfr)
					best.append([score, un, vn, tilt, roll])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in 5:
		print("[solve] ", args[0].get_file(), " score %.1f deg  u_to=%s v_to=%s tilt=%d roll=%d" % best[i])
	quit()
func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
