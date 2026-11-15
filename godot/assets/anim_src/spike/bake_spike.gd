extends SceneTree
## C4.1 spike: bakes UAL clips (imported with BoneMap + SkeletonProfileHumanoid, see UAL1_Standard.glb.import) onto the 24-bone Meshy rig of a crew model.
## Method (global-delta retarget with rest normalisation, the same idea as Godot's Fix Silhouette): for every mapped bone
##   delta  = source_pose_global * source_rest_global^-1                (rotation of the bone since the source rest/T-pose)
##   target = delta * target_rest_global rotated so its bone direction matches the source rest direction (T-pose)
## then local = parent_global^-1 * global. Hips position = target rest + (source pose - source rest) * (target hip height / source hip height).
## Output: baked_<clip>.res (Animation with Meshy track names "Armature/Skeleton3D:<bone>") + spike_baked.log lines.

const SRC := "res://assets/anim_src/spike/UAL1_Standard.glb"
const TARGET := "res://assets/characters/papi_fuego.glb"
const CLIPS := {"Walk": "walk", "Fixing_Kneeling": "fixing_kneeling", "Idle_Talking": "idle_talking"}
const FPS := 30.0
# Meshy bone <- UAL (profile) bone
const MAP := {
	"Hips": "Hips", "Spine02": "Spine", "Spine01": "Chest", "Spine": "UpperChest", "neck": "Neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightArm": "RightUpperArm", "RightForeArm": "RightLowerArm", "RightHand": "RightHand",
	"LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToes",
	"RightUpLeg": "RightUpperLeg", "RightLeg": "RightLowerLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToes"}

var src_root: Node
var src_sk: Skeleton3D
var src_ap: AnimationPlayer
var tgt_root: Node
var tgt_sk: Skeleton3D
var arc := {}      # target bone name -> rotation taking its rest direction to the source rest direction
var tgt_ref := {}  # target bone name -> global rotation in the normalised (T-pose) reference

func _init() -> void:
	_run.call_deferred()

func _child_dir(sk: Skeleton3D, bone: int) -> Variant:
	# direction of the bone in skeleton space at rest: towards its first child bone (any), else null
	var rest := sk.get_bone_global_rest(bone)
	for c in sk.get_bone_children(bone):
		var d := sk.get_bone_global_rest(c).origin - rest.origin
		if d.length() > 1e-4:
			return d.normalized()
	return null

func _run() -> void:
	src_root = (load(SRC) as PackedScene).instantiate()
	root.add_child(src_root)
	src_sk = src_root.find_children("*", "Skeleton3D", true, false)[0]
	src_ap = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	tgt_root = (load(TARGET) as PackedScene).instantiate()
	root.add_child(tgt_root)
	tgt_sk = tgt_root.find_children("*", "Skeleton3D", true, false)[0]
	await process_frame
	# --- rest normalisation of the target ---
	var report := []
	for tn in MAP:
		var ti := tgt_sk.find_bone(tn)
		var si := src_sk.find_bone(MAP[tn])
		if ti < 0 or si < 0:
			print("[bake] MISSING bone ", tn, " / ", MAP[tn])
			continue
		var t_rest := tgt_sk.get_bone_global_rest(ti).basis.get_rotation_quaternion()
		var td: Variant = _child_dir(tgt_sk, ti)
		var sd: Variant = _child_dir(src_sk, si)
		var a := Quaternion.IDENTITY
		if td != null and sd != null:
			a = Quaternion(td, sd) if (td as Vector3).dot(sd) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
		else:
			var p := tgt_sk.get_bone_parent(ti)
			while p >= 0 and not arc.has(tgt_sk.get_bone_name(p)):
				p = tgt_sk.get_bone_parent(p)
			a = arc[tgt_sk.get_bone_name(p)] if p >= 0 else Quaternion.IDENTITY
		arc[tn] = a
		tgt_ref[tn] = a * t_rest
		report.append("%s arc=%.1f deg" % [tn, rad_to_deg(a.get_angle())])
	print("[bake] rest normalisation (target bone rotated to the source rest direction): ", ", ".join(report))
	var hip_scale := tgt_sk.get_bone_global_rest(tgt_sk.find_bone("Hips")).origin.y / src_sk.get_bone_global_rest(src_sk.find_bone("Hips")).origin.y
	print("[bake] hips scale ", hip_scale)
	# --- bake clips ---
	var names := src_ap.get_animation_list()
	for clip in CLIPS:
		if not names.has(clip):
			print("[bake] clip not found: ", clip, " (have ", names.slice(0, 50), ")")
			continue
		var anim_src := src_ap.get_animation(clip)
		var len := anim_src.length
		var out := Animation.new()
		out.length = len
		out.loop_mode = anim_src.loop_mode
		out.step = 1.0 / FPS
		var rot_tracks := {}
		var hips_track := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath("Armature/Skeleton3D:Hips"))
		for tn in MAP:
			var tr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr, NodePath("Armature/Skeleton3D:" + tn))
			rot_tracks[tn] = tr
		src_ap.play(clip)
		var frames := int(round(len * FPS)) + 1
		var max_arm := 0.0
		for f in frames:
			var t := minf(float(f) / FPS, len)
			src_ap.seek(t, true)
			src_ap.advance(0.0)
			src_sk.force_update_all_bone_transforms()
			var tgt_global := {}
			for ti in tgt_sk.get_bone_count():
				var tn := tgt_sk.get_bone_name(ti)
				var par := tgt_sk.get_bone_parent(ti)
				var par_g := Quaternion.IDENTITY if par < 0 else (tgt_global[tgt_sk.get_bone_name(par)] as Quaternion)
				var g: Quaternion
				if MAP.has(tn):
					var si := src_sk.find_bone(MAP[tn])
					var s_pose := src_sk.get_bone_global_pose(si).basis.get_rotation_quaternion()
					var s_rest := src_sk.get_bone_global_rest(si).basis.get_rotation_quaternion()
					var delta := s_pose * s_rest.inverse()
					g = delta * (tgt_ref[tn] as Quaternion)
					var local := (par_g.inverse() * g).normalized()
					out.rotation_track_insert_key(rot_tracks[tn], t, local)
					if tn == "LeftForeArm" or tn == "RightForeArm":
						max_arm = maxf(max_arm, rad_to_deg(delta.get_angle()))
				else:
					g = par_g * tgt_sk.get_bone_rest(ti).basis.get_rotation_quaternion()
				tgt_global[tn] = g
			var sh := src_sk.find_bone("Hips")
			var hp := src_sk.get_bone_global_pose(sh).origin - src_sk.get_bone_global_rest(sh).origin
			var th := tgt_sk.get_bone_global_rest(tgt_sk.find_bone("Hips")).origin
			out.position_track_insert_key(hips_track, t, th + hp * hip_scale)
		var path := "res://assets/anim_src/spike/baked_%s.res" % CLIPS[clip]
		var err := ResourceSaver.save(out, path)
		print("[bake] ", clip, " -> ", path, " len=", snappedf(len, 0.01), " frames=", frames, " loop=", anim_src.loop_mode, " save err=", err, " max forearm delta deg=", snappedf(max_arm, 0.1))
	src_ap.stop()
	quit()
