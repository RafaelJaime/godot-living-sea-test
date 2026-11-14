class_name CrewAnim
extends RefCounted
## Shared animation library for the crew (res://assets/anim/crew_shared.res: walk, climb_stairs, talk, ... extracted from
## assets/anim_src/*.glb, all on the same 24-bone Meshy rig). install() copies it into a character's AnimationPlayer as
## library "shared", scaling the Hips POSITION tracks by the hip-height ratio so differently proportioned characters do not
## sink or float. Clip names after install: "shared/walk", "shared/climb_stairs", "shared/talk".

const LIB_PATH := "res://assets/anim/crew_shared.res"

static func install(player: AnimationPlayer, skeleton: Skeleton3D) -> bool:
	if not ResourceLoader.exists(LIB_PATH) or player == null or skeleton == null:
		return false
	var src := load(LIB_PATH) as AnimationLibrary
	var src_hips: float = float(src.get_meta("source_hips_y", 96.0))
	var hips := skeleton.find_bone("Hips")
	var ratio := 1.0
	if hips >= 0 and src_hips > 0.0:
		ratio = skeleton.get_bone_global_rest(hips).origin.y / src_hips
	var lib := AnimationLibrary.new()
	for n in src.get_animation_list():
		var a := (src.get_animation(n).duplicate()) as Animation
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with(":Hips"):
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * ratio)
		lib.add_animation(n, a)
	if player.has_animation_library("shared"):
		player.remove_animation_library("shared")
	player.add_animation_library("shared", lib)
	return true
