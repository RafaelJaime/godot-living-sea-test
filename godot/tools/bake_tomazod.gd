extends SceneTree
## Tomazod Ultimate Animation Library (free demo, 20 clips) baked onto the 24-bone Meshy rig. Source GLB and output stay OUT of git (see godot/README.md, `assets/anim_src/tomazod/`). Same method as the C4.1 spike: bakes clips of several CC0 sources onto the 24-bone Meshy rig of a crew model (read-only).
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
const OUT_DIR := "res://assets/anim_src/tomazod/"
# Meshy bone -> Tomazod mannequin bone (Mixamo-style names without prefix)
const MAP := {
	"Hips": "Hips", "Spine02": "Spine", "Spine01": "Spine1", "Spine": "Spine2", "neck": "Neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
	"RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToeBase"}
const NO_ARC := ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head"] # keep the target's own spine/neck/head orientation (lean fix)
const LOOPS := ["068_Military_Shooter_Realistic_rifle_ads_fire", "075_Military_Shooter_Stylized_tactical_sprint_low_ready"]
const CLIPS := {
	"001_Sword_and_Magic_Anime_sword_slash_heavy": "sword_slash_heavy", "002_Sword_and_Magic_Anime_spell_cast_fireball": "spell_cast_fireball",
	"003_Sword_and_Magic_Anime_dash_teleport": "dash_teleport", "004_Sword_and_Magic_Anime_shield_block_parry": "shield_block_parry",
	"005_Military_Shooter_Realistic_rifle_reload_tactical": "rifle_reload", "006_Military_Shooter_Realistic_cover_crouch_to_stand_fire": "cover_crouch_to_stand_fire",
	"007_Military_Shooter_Realistic_prone_low_crawl": "prone_low_crawl", "008_Military_Shooter_Realistic_grenade_throw_overhand": "grenade_throw_overhand",
	"009_Sports_Stylized_basketball_dunk_windmill": "basketball_dunk_windmill", "010_Sports_Stylized_soccer_bicycle_kick": "soccer_bicycle_kick",
	"011_Sports_Stylized_tennis_serve_power": "tennis_serve_power", "054_Holding_Sword_and_Magic_Anime_sword_swing_01": "sword_swing_01",
	"067_Sports_Cartoon_soccer_kick_power": "soccer_kick_power", "068_Military_Shooter_Realistic_rifle_ads_fire": "rifle_ads_fire_loop",
	"075_Military_Shooter_Stylized_tactical_sprint_low_ready": "tactical_sprint_low_ready", "083_Sports_Cartoon_low_lunge": "low_lunge",
	"086_Sports_Cartoon_driving_front_kick": "driving_front_kick", "087_Sports_Cartoon_leg_catch_throw": "leg_catch_throw",
	"093_Sports_Cartoon_leaping_kick": "leaping_kick", "100_Anime_Military_Shooter_saber_slash": "saber_slash"}
const SOURCE := "res://assets/anim_src/tomazod/White_Mannequin_20_Animations_Without_Root_Motion.glb"

var tgt_root: Node
var tgt_sk: Skeleton3D

func _init() -> void:
	_run.call_deferred()

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
	var src_root := (load(SOURCE) as PackedScene).instantiate()
	root.add_child(src_root)
	var src_sk: Skeleton3D = src_root.find_children("*", "Skeleton3D", true, false)[0]
	var src_ap: AnimationPlayer = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	await process_frame
	var arc := {}
	var tgt_ref := {}
	var t_hd := (tgt_sk.get_bone_global_rest(tgt_sk.find_bone("Head")).origin - tgt_sk.get_bone_global_rest(tgt_sk.find_bone("Hips")).origin).normalized()
	var s_hd := (src_sk.get_bone_global_rest(src_sk.find_bone("Head")).origin - src_sk.get_bone_global_rest(src_sk.find_bone("Hips")).origin).normalized()
	var chain_arc := Quaternion(t_hd, s_hd)
	for ti in tgt_sk.get_bone_count():
		var tn := tgt_sk.get_bone_name(ti)
		if not MAP.has(tn):
			continue
		var si := src_sk.find_bone(MAP[tn])
		if si < 0:
			print("[tz] MISSING source bone ", MAP[tn])
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
	var s_hips := src_sk.find_bone("Hips")
	var t_hips := tgt_sk.find_bone("Hips")
	var hip_scale := tgt_sk.get_bone_global_rest(t_hips).origin.y / src_sk.get_bone_global_rest(s_hips).origin.y
	print("[tz] chain arc ", snappedf(rad_to_deg(chain_arc.get_angle()), 0.1), " deg, hip scale ", snappedf(hip_scale, 0.0001))
	var names := src_ap.get_animation_list()
	for clip in CLIPS:
		if not names.has(clip):
			print("[tz] clip not found: ", clip, " have ", names)
			continue
		var anim_src := src_ap.get_animation(clip)
		var len := anim_src.length
		var out := Animation.new()
		out.length = len
		out.loop_mode = Animation.LOOP_LINEAR if LOOPS.has(clip) else Animation.LOOP_NONE
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
		for f in frames:
			var t := minf(float(f) / FPS, len)
			src_ap.seek(t, true)
			src_ap.advance(0.0)
			src_sk.force_update_all_bone_transforms()
			var g := {}
			var o := {}
			for ti in tgt_sk.get_bone_count():
				var tn := tgt_sk.get_bone_name(ti)
				var par := tgt_sk.get_bone_parent(ti)
				var par_g := Quaternion.IDENTITY if par < 0 else (g[tgt_sk.get_bone_name(par)] as Quaternion)
				var par_rest_g := Quaternion.IDENTITY if par < 0 else tgt_sk.get_bone_global_rest(par).basis.get_rotation_quaternion()
				var rest_g := tgt_sk.get_bone_global_rest(ti).basis.get_rotation_quaternion()
				var gq: Quaternion
				if MAP.has(tn) and tgt_ref.has(tn):
					var si := src_sk.find_bone(MAP[tn])
					var delta := src_sk.get_bone_global_pose(si).basis.get_rotation_quaternion() * src_sk.get_bone_global_rest(si).basis.get_rotation_quaternion().inverse()
					gq = delta * (tgt_ref[tn] as Quaternion)
					out.rotation_track_insert_key(rot_tracks[tn], t, (par_g.inverse() * gq).normalized())
				else:
					gq = (par_g * par_rest_g.inverse()) * rest_g
				g[tn] = gq
				var rest_local_o := tgt_sk.get_bone_rest(ti).origin
				if tn == "Hips":
					o[tn] = tgt_sk.get_bone_global_rest(t_hips).origin + (src_sk.get_bone_global_pose(s_hips).origin - src_sk.get_bone_global_rest(s_hips).origin) * hip_scale
				else:
					o[tn] = (o[tgt_sk.get_bone_name(par)] as Vector3) + (g[tgt_sk.get_bone_name(par)] as Quaternion) * rest_local_o if par >= 0 else rest_local_o
			out.position_track_insert_key(hips_track, t, o["Hips"])
		var path := OUT_DIR + "baked_%s.res" % CLIPS[clip]
		print("[tz] ", clip, " -> ", path, " len=", snappedf(len, 0.01), " frames=", frames, " save err=", ResourceSaver.save(out, path))
	src_ap.stop()
	quit()
