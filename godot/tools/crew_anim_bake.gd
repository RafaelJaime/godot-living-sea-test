@tool
extends SceneTree
## Dev tool (C4.2): builds the crew clip library `res://assets/anim/crew_clips.res` from
##  - the existing shared clips (`crew_shared.res`: walk, talk, climb_stairs),
##  - Fuego's own idle (re-expressed at the library hip height),
##  - the clips baked on the Meshy rig under `assets/anim_src/spike/` (Quaternius UAL 1 and 2, KayKit Character Animations, all CC0) and
##    `assets/anim_src/blender/` (hand authored in this repo).
## All hips position tracks are brought to the library's `source_hips_y` so the animation adapter's hip-ratio scaling is neutral for every clip.
## Source clips live only in `assets/anim_src/`; nothing is copied under `addons/`.
## Usage: godot --headless --path godot -s tools/crew_anim_bake.gd

const OUT := "res://assets/anim/crew_clips.res"
const SHARED := "res://assets/anim/crew_shared.res"
const IDLE_SRC := "res://assets/characters/papi_fuego.glb"
const FUEGO_HIPS := 109.502159 ## rest hips height of the crew model the spike and Blender clips were baked on (skeleton units)
## library name -> source file, relative to res://assets/anim_src/
const CLIPS := {
	&"walk_carry": "spike/baked_walk_carry.res",
	&"idle_lantern": "spike/baked_idle_lantern.res",
	&"idle_rail": "spike/baked_idle_rail.res",
	&"idle_talking": "spike/baked_idle_talking.res",
	&"hammering": "spike/baked_hammering.res",
	&"sawing": "spike/baked_sawing.res",
	&"fishing_idle": "spike/baked_fishing_idle.res",
	&"fishing_cast": "spike/baked_fishing_cast.res",
	&"fishing_reeling": "spike/baked_fishing_reeling.res",
	&"fixing_kneeling": "spike/baked_fixing_kneeling.res",
	&"climb_up_1m": "spike/baked_climb_up_1m.res",
	&"ratline_climb": "blender/ratline_climb.res",
	&"deck_swab": "blender/deck_swab.res",
	&"spyglass_look": "blender/spyglass_look.res",
}
## Optional clips authored later (godot-ship); picked up when the file exists.
const OPTIONAL := {
	&"furl_aloft": "blender/furl_aloft.res",
	&"haul": "blender/haul.res",
	&"play_violin": "blender/play_violin.res",
	&"point_ahead": "blender/point_ahead.res",
	&"comic_fall": "blender/comic_fall.res",
}

func _initialize() -> void:
	var shared := load(SHARED) as AnimationLibrary
	var ref_y := float(shared.get_meta("source_hips_y", 95.3615))
	var lib := AnimationLibrary.new()
	lib.set_meta("source_hips_y", ref_y)
	for n in shared.get_animation_list():
		lib.add_animation(n, shared.get_animation(n))
	lib.add_animation(&"idle", _fuego_idle(ref_y))
	var report: Array[String] = []
	var all := CLIPS.duplicate()
	for k in OPTIONAL:
		if ResourceLoader.exists("res://assets/anim_src/" + OPTIONAL[k]):
			all[k] = OPTIONAL[k]
	for name in all:
		var a := load("res://assets/anim_src/" + all[name]) as Animation
		if a == null:
			push_error("[bake] missing %s" % all[name])
			quit(1)
			return
		var c := a.duplicate() as Animation
		var k := _normalise_hips(c, ref_y)
		lib.add_animation(name, c)
		report.append("%s from %s: %d tracks, %.2f s, hips x%.3f" % [name, all[name], c.get_track_count(), c.length, k])
	var err := ResourceSaver.save(lib, OUT)
	for r in report:
		print("[bake] ", r)
	print("[bake] saved ", OUT, " (", lib.get_animation_list().size(), " clips) -> ", error_string(err))
	quit(0 if err == OK else 1)

## Every source clip was baked on (or authored for) Fuego's rig, whose rest hips are FUEGO_HIPS; the library works at `ref_y`.
## (A "standing height" heuristic misjudged bent clips such as fishing_reeling, so the factor is the same for all of them.)
func _normalise_hips(a: Animation, ref_y: float) -> float:
	var factor := ref_y / FUEGO_HIPS
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with(":Hips"):
			for k in a.track_get_key_count(t):
				a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * factor)
	return factor

func _fuego_idle(ref_y: float) -> Animation:
	var root := (load(IDLE_SRC) as PackedScene).instantiate()
	var ap := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clip := ap.get_animation(ap.get_animation_list()[0]).duplicate() as Animation
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ratio := ref_y / sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
	for t in clip.get_track_count():
		if clip.track_get_type(t) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(t)).ends_with(":Hips"):
			for k in clip.track_get_key_count(t):
				clip.track_set_key_value(t, k, (clip.track_get_key_value(t, k) as Vector3) * ratio)
	clip.loop_mode = Animation.LOOP_LINEAR
	root.free()
	return clip
