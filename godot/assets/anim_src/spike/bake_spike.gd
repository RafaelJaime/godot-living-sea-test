extends SceneTree
## C4.1 spike: bakes clips of several CC0 sources onto the 24-bone Meshy rig of a crew model (read-only).
## Method (global-delta retarget with limb rest normalisation, the idea of Godot's Fix Silhouette applied to the target in memory):
##   limb bones (shoulders, arms, forearms, hands, legs, feet, toes): rest direction of the target bone rotated (shortest arc) onto the source rest direction
##   (T-pose), then target_global = (source_pose_global * source_rest_global^-1) * normalised target rest; local = parent_global^-1 * global.
##   v2 (lean fix): hips, spines, neck and head are NOT normalised bone by bone: the Meshy spine is straight (forward lean -0.7 deg) while the UAL rest spine is curved
##   (hips->spine 14.5, spine->chest 7.0, neck->head 10.9 deg forward); copying that curvature bone by bone made the crew lean about 10 deg in the walk. Instead
##   the whole chain gets ONE arc: the rotation taking the target rest hips->head direction onto the source rest hips->head direction (4.8 deg for UAL).
##   Bones without a source counterpart follow their parent rigidly (global = parent_delta * own rest global) so the skinning stays consistent.
##   Hips position = target rest + (source pose - source rest) * (target hip height / source hip height).
## Output: baked_<name>.res (Animation, tracks "Armature/Skeleton3D:<Meshy bone>") + [bake] log lines incl. the forward lean of hips->head (source vs target).

const TARGET := "res://assets/characters/papi_fuego.glb"
const FPS := 30.0
const PROFILE_MAP := {
	"Hips": "Hips", "Spine02": "Spine", "Spine01": "Chest", "Spine": "UpperChest", "neck": "Neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightArm": "RightUpperArm", "RightForeArm": "RightLowerArm", "RightHand": "RightHand",
	"LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToes",
	"RightUpLeg": "RightUpperLeg", "RightLeg": "RightLowerLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToes"}
# KayKit Rig_Medium has no neck, no shoulders and only two spine bones: those Meshy bones follow their parent.
const KAYKIT_MAP := {
	"Hips": "hips", "Spine02": "spine", "Spine01": "chest", "Head": "head",
	"LeftArm": "upperarm.l", "LeftForeArm": "lowerarm.l", "LeftHand": "hand.l", "RightArm": "upperarm.r", "RightForeArm": "lowerarm.r", "RightHand": "hand.r",
	"LeftUpLeg": "upperleg.l", "LeftLeg": "lowerleg.l", "LeftFoot": "foot.l", "LeftToeBase": "toes.l",
	"RightUpLeg": "upperleg.r", "RightLeg": "lowerleg.r", "RightFoot": "foot.r", "RightToeBase": "toes.r"}
const NO_ARC := ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head"] # keep the target's own spine/neck/head orientation (lean fix)

const JOBS := [
	{"id": "ual1", "scene": "res://assets/anim_src/spike/UAL1_Standard.glb", "map": PROFILE_MAP, "hips": "Hips", "head": "Head", "loops": [],
		"clips": {"Walk": "walk", "Fixing_Kneeling": "fixing_kneeling", "Idle_Talking": "idle_talking"}},
	{"id": "ual2", "scene": "res://assets/anim_src/spike/UAL2_Standard.glb", "map": PROFILE_MAP, "hips": "Hips", "head": "Head", "loops": [],
		"clips": {"Idle_Rail": "idle_rail", "Idle_Lantern": "idle_lantern", "Walk_Carry": "walk_carry", "ClimbUp_1m": "climb_up_1m"}},
	{"id": "kaykit", "scene": "res://assets/anim_src/spike/Rig_Medium_Tools.glb", "map": KAYKIT_MAP, "hips": "hips", "head": "head",
		"loops": ["Fishing_Idle", "Fishing_Reeling", "Hammering", "Sawing"],
		"clips": {"Fishing_Cast": "fishing_cast", "Fishing_Idle": "fishing_idle", "Fishing_Reeling": "fishing_reeling", "Hammering": "hammering", "Sawing": "sawing"}},
]

var tgt_root: Node
var tgt_sk: Skeleton3D

func _init() -> void:
	_run.call_deferred()

func _find_bone(sk: Skeleton3D, n: String) -> int:
	var i := sk.find_bone(n)
	return i if i >= 0 else sk.find_bone(n.replace(".", "_"))

func _child_dir(sk: Skeleton3D, bone: int) -> Variant:
	var rest := sk.get_bone_global_rest(bone)
	for c in sk.get_bone_children(bone):
		var d := sk.get_bone_global_rest(c).origin - rest.origin
		if d.length() > 1e-4:
			return d.normalized()
	return null

func _run() -> void:
	tgt_root = (load(TARGET) as PackedScene).instantiate()
	root.add_child(tgt_root)
	tgt_sk = tgt_root.find_children("*", "Skeleton3D", true, false)[0]
	for job in JOBS:
		await _bake_job(job)
	quit()

func _bake_job(job: Dictionary) -> void:
	var map: Dictionary = job["map"]
	var src_root := (load(job["scene"]) as PackedScene).instantiate()
	root.add_child(src_root)
	var src_sk: Skeleton3D = src_root.find_children("*", "Skeleton3D", true, false)[0]
	var src_ap: AnimationPlayer = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	await process_frame
	var arc := {}
	var tgt_ref := {}
	var report := []
	var chain_arc := Quaternion.IDENTITY
	var s_head_i := _find_bone(src_sk, job["head"])
	var s_hips_i := _find_bone(src_sk, job["hips"])
	var t_hd := (tgt_sk.get_bone_global_rest(tgt_sk.find_bone("Head")).origin - tgt_sk.get_bone_global_rest(tgt_sk.find_bone("Hips")).origin).normalized()
	var s_hd := (src_sk.get_bone_global_rest(s_head_i).origin - src_sk.get_bone_global_rest(s_hips_i).origin).normalized()
	chain_arc = Quaternion(t_hd, s_hd)
	report.append("chain %.1f" % rad_to_deg(chain_arc.get_angle()))
	for ti in tgt_sk.get_bone_count():
		var tn := tgt_sk.get_bone_name(ti)
		if not map.has(tn):
			continue
		var si := _find_bone(src_sk, map[tn])
		if si < 0:
			print("[bake] ", job["id"], " MISSING source bone ", map[tn])
			continue
		var t_rest := tgt_sk.get_bone_global_rest(ti).basis.get_rotation_quaternion()
		var a := chain_arc if NO_ARC.has(tn) else Quaternion.IDENTITY
		if not NO_ARC.has(tn):
			var td: Variant = _child_dir(tgt_sk, ti)
			var sd: Variant = _child_dir(src_sk, si)
			if td != null and sd != null:
				a = Quaternion(td, sd) if (td as Vector3).dot(sd) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
			else:
				var p := tgt_sk.get_bone_parent(ti)
				while p >= 0 and not arc.has(tgt_sk.get_bone_name(p)):
					p = tgt_sk.get_bone_parent(p)
				a = arc[tgt_sk.get_bone_name(p)] if p >= 0 else Quaternion.IDENTITY
		arc[tn] = a
		tgt_ref[tn] = a * t_rest
		report.append("%s %.1f" % [tn, rad_to_deg(a.get_angle())])
	print("[bake] ", job["id"], " rest normalisation arcs (deg): ", ", ".join(report))
	var s_hips := _find_bone(src_sk, job["hips"])
	var t_hips := tgt_sk.find_bone("Hips")
	var hip_scale := tgt_sk.get_bone_global_rest(t_hips).origin.y / src_sk.get_bone_global_rest(s_hips).origin.y
	var names := src_ap.get_animation_list()
	for clip in job["clips"]:
		if not names.has(clip):
			print("[bake] ", job["id"], " clip not found: ", clip, " (have ", names, ")")
			continue
		var anim_src := src_ap.get_animation(clip)
		var len := anim_src.length
		var out := Animation.new()
		out.length = len
		out.loop_mode = Animation.LOOP_LINEAR if (anim_src.loop_mode != Animation.LOOP_NONE or (job["loops"] as Array).has(clip)) else Animation.LOOP_NONE
		out.step = 1.0 / FPS
		var rot_tracks := {}
		var hips_track := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath("Armature/Skeleton3D:Hips"))
		for tn in map:
			var tr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr, NodePath("Armature/Skeleton3D:" + tn))
			rot_tracks[tn] = tr
		src_ap.play(clip)
		var frames := int(round(len * FPS)) + 1
		var lean_t := 0.0
		var lean_s := 0.0
		var lean_t_max := -90.0
		var lean_s_max := -90.0
		for f in frames:
			var t := minf(float(f) / FPS, len)
			src_ap.seek(t, true)
			src_ap.advance(0.0)
			src_sk.force_update_all_bone_transforms()
			var g := {}   # target bone name -> global rotation
			var o := {}   # target bone name -> global origin (cm)
			for ti in tgt_sk.get_bone_count():
				var tn := tgt_sk.get_bone_name(ti)
				var par := tgt_sk.get_bone_parent(ti)
				var par_g := Quaternion.IDENTITY if par < 0 else (g[tgt_sk.get_bone_name(par)] as Quaternion)
				var par_rest_g := Quaternion.IDENTITY if par < 0 else tgt_sk.get_bone_global_rest(par).basis.get_rotation_quaternion()
				var rest_g := tgt_sk.get_bone_global_rest(ti).basis.get_rotation_quaternion()
				var gq: Quaternion
				if map.has(tn) and tgt_ref.has(tn):
					var si := _find_bone(src_sk, map[tn])
					var delta := src_sk.get_bone_global_pose(si).basis.get_rotation_quaternion() * src_sk.get_bone_global_rest(si).basis.get_rotation_quaternion().inverse()
					gq = delta * (tgt_ref[tn] as Quaternion)
					out.rotation_track_insert_key(rot_tracks[tn], t, (par_g.inverse() * gq).normalized())
				else:
					gq = (par_g * par_rest_g.inverse()) * rest_g # rigid follow of the parent's change since rest
				g[tn] = gq
				var rest_local_o := tgt_sk.get_bone_rest(ti).origin
				if tn == "Hips":
					var sh_pose := src_sk.get_bone_global_pose(s_hips).origin
					var sh_rest := src_sk.get_bone_global_rest(s_hips).origin
					o[tn] = tgt_sk.get_bone_global_rest(t_hips).origin + (sh_pose - sh_rest) * hip_scale
				else:
					o[tn] = (o[tgt_sk.get_bone_name(par)] as Vector3) + (g[tgt_sk.get_bone_name(par)] as Quaternion) * rest_local_o if par >= 0 else rest_local_o
			var sh := src_sk.get_bone_global_pose(s_hips).origin
			out.position_track_insert_key(hips_track, t, o["Hips"])
			var hd := (o["Head"] as Vector3) - (o["Hips"] as Vector3)
			var sd2 := src_sk.get_bone_global_pose(_find_bone(src_sk, job["head"])).origin - sh
			var lt := rad_to_deg(atan2(hd.z, hd.y))
			var ls := rad_to_deg(atan2(sd2.z, sd2.y))
			lean_t += lt
			lean_s += ls
			lean_t_max = maxf(lean_t_max, lt)
			lean_s_max = maxf(lean_s_max, ls)
		var path := "res://assets/anim_src/spike/baked_%s.res" % job["clips"][clip]
		var err := ResourceSaver.save(out, path)
		print("[bake] ", job["id"], " ", clip, " -> ", path, " len=", snappedf(len, 0.01), " frames=", frames, " loop=", out.loop_mode, " save err=", err,
			" | hips->head forward lean mean/max: target ", snappedf(lean_t / frames, 0.1), "/", snappedf(lean_t_max, 0.1), " deg, source ", snappedf(lean_s / frames, 0.1), "/", snappedf(lean_s_max, 0.1), " deg")
	src_ap.stop()
	src_root.queue_free()
	await process_frame
