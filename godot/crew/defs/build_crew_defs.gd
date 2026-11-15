@tool
extends SceneTree
## Dev tool (run once, commit the output): builds the four crew NpcCharacterDefs, the roster, the rig profile and the anim set under res://crew/defs/.
## Usage: godot --headless --path godot -s crew/defs/build_crew_defs.gd
## Signature animation tags map to existing shared clips until the C4 clip pipeline bakes the real ones (see odd/evidence/npc-crew-jobs/C4).

const OUT := "res://crew/defs/"
const LIB_SRC := "res://assets/anim/crew_shared.res"
const IDLE_SRC := "res://assets/characters/papi_fuego.glb"

func _initialize() -> void:
	var prof := _profile()
	var anim := _anim_set()
	var defs: Array[NpcCharacterDef] = [_fuego(), _diagnostica(), _salchipapa(), _omar()]
	for d in defs:
		d.rig_profile = prof
		d.anim_set = anim
		_save(d, "%s.tres" % d.agent_id)
	_save(prof, "crew_rig_profile.tres")
	_save(_roster(), "crew_roster.tres")
	# the anim set must reference its tags: every signature tag gets a shared clip for now
	var tags := {}
	for d in defs:
		for a in d.signature_actions:
			tags[a.anim_tag] = true
	for t in tags:
		anim.shared[t] = &"idle" if t != &"carry_crate" else &"walk"
	_save(anim, "crew_anim_set.tres")
	# re-save defs so they point at the final resource files
	var anim_res := load(OUT + "crew_anim_set.tres")
	var prof_res := load(OUT + "crew_rig_profile.tres")
	for d in defs:
		d.anim_set = anim_res
		d.rig_profile = prof_res
		_save(d, "%s.tres" % d.agent_id)
	quit(0)

func _save(r: Resource, file: String) -> void:
	var err := ResourceSaver.save(r, OUT + file)
	print("[build_crew_defs] ", file, " -> ", error_string(err))
	if err != OK:
		quit(1)

func _act(id: StringName, kinds: Array, tag: StringName, dur := Vector2(8, 16), effect := &"", station_kind := &"", ik := {}, look := &"", cooldown := 0.0) -> NpcActionDef:
	var a := NpcActionDef.new()
	a.action_id = id
	a.job_kinds = PackedStringArray(kinds)
	a.anim_tag = tag
	a.duration_range = dur
	a.effect = effect
	a.station_kind = station_kind
	for k in ik:
		a.ik[k] = ik[k]
	a.look_at = look
	a.cooldown_s = cooldown
	return a

func _def(id: StringName, name: String, roles: Array, tags: Array, walk: float, temp: float, prefs: Dictionary, skills: Dictionary, needs: Dictionary, acts: Array) -> NpcCharacterDef:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	d.display_name = name
	d.roles = PackedStringArray(roles)
	d.tags = PackedStringArray(tags)
	d.walk_speed = walk
	d.temperature_scale = temp
	for k in prefs:
		d.preferences[k] = prefs[k]
	for k in skills:
		d.skills[k] = skills[k]
	for k in needs:
		d.needs[k] = needs[k]
	var typed: Array[NpcActionDef] = []
	for a in acts:
		typed.append(a)
	d.signature_actions = typed
	return d

func _fuego() -> NpcCharacterDef:
	return _def(&"papi_fuego", "Papi Fuego", ["helmsman", "lookout"], ["captain"], 1.25, 0.8,
		{&"helm": 0.8, &"spyglass_post": 0.5, &"social_spot": 0.2, &"fishing_rail": -0.2},
		{&"helm": 0.95, &"spyglass_post": 0.8, &"repair_spot": 0.4},
		{&"boredom": 0.3},
		[_act(&"helm_steer", ["helm"], &"helm_steer", Vector2(20, 45), &"", &"helm", {&"hand_l": &"hand_l", &"hand_r": &"hand_r"}, &"ahead"),
		_act(&"spyglass_scan", ["spyglass_post"], &"spyglass_scan", Vector2(10, 20), &"", &"spyglass_post", {}, &"horizon"),
		_act(&"point_ahead", ["spyglass_post", "social_spot"], &"point_ahead", Vector2(4, 8), &"", &"", {}, &"horizon", 90.0)])

func _diagnostica() -> NpcCharacterDef:
	return _def(&"papi_diagnostica", "Papi Diagnóstica", ["carpenter", "climber"], [], 1.35, 1.0,
		{&"repair_spot": 0.8, &"ratline_path": 0.5, &"reef_pin": 0.3, &"mop_zone": -0.4},
		{&"repair_spot": 0.9, &"ratline_path": 0.8, &"helm": 0.5},
		{&"boredom": 0.4},
		[_act(&"hammer_repair", ["repair_spot"], &"hammer_repair", Vector2(10, 20), &"repair", &"repair_spot"),
		_act(&"ratline_climb", ["ratline_path"], &"ratline_climb", Vector2(8, 14), &"", &"ratline_path"),
		_act(&"carry_crate", ["haul"], &"carry_crate", Vector2(6, 12), &"haul")])

func _salchipapa() -> NpcCharacterDef:
	return _def(&"el_salchipapa", "El Salchipapa", ["lookout", "climber", "fisher"], ["joker"], 1.1, 1.4,
		{&"crows_nest": 0.8, &"fishing_rail": 0.7, &"reef_pin": 0.2, &"mop_zone": -0.6},
		{&"crows_nest": 0.85, &"fishing_rail": 0.8, &"helm": 0.3},
		{&"boredom": 0.6},
		[_act(&"crows_nest_watch", ["crows_nest"], &"crows_nest_watch", Vector2(14, 30), &"", &"crows_nest", {}, &"horizon"),
		_act(&"rope_work", ["reef_pin"], &"rope_work", Vector2(8, 16), &"", &"reef_pin"),
		_act(&"fishing_cast", ["fishing_rail"], &"fishing_cast", Vector2(16, 40), &"", &"fishing_rail"),
		_act(&"comic_fall", ["chat", "social_spot"], &"comic_fall", Vector2(3, 5), &"", &"", {}, &"", 240.0)])

func _omar() -> NpcCharacterDef:
	return _def(&"don_omar", "Don Omar", ["musician", "navigator"], ["elder"], 0.95, 0.6,
		{&"violin_seat": 0.9, &"chart_table": 0.6, &"listen_spot": 0.3, &"mop_zone": -0.5},
		{&"violin_seat": 0.9, &"chart_table": 0.8, &"helm": 0.6},
		{&"boredom": 0.2},
		[_act(&"violin_play", ["violin_seat"], &"violin_play", Vector2(25, 60), &"", &"violin_seat"),
		_act(&"chart_study", ["chart_table"], &"chart_study", Vector2(12, 25), &"", &"chart_table"),
		_act(&"star_gaze", ["listen_spot", "social_spot"], &"star_gaze", Vector2(10, 20), &"", &"", {}, &"sky", 120.0)])

func _profile() -> NpcRigProfile:
	var p := NpcRigProfile.new()
	p.chains = {
		&"hand_l": PackedStringArray(["LeftArm", "LeftForeArm", "LeftHand"]),
		&"hand_r": PackedStringArray(["RightArm", "RightForeArm", "RightHand"]),
	}
	p.look_bone = &"Head"
	p.hips_bone = &"Hips"
	p.sockets = {&"hand_r": &"RightHand", &"hand_l": &"LeftHand"}
	return p

func _anim_set() -> NpcAnimSet:
	var s := NpcAnimSet.new()
	var src := load(LIB_SRC) as AnimationLibrary
	var lib := AnimationLibrary.new()
	for n in src.get_animation_list():
		lib.add_animation(n, src.get_animation(n))
	lib.set_meta("source_hips_y", src.get_meta("source_hips_y", 95.36))
	var idle := _bake_idle(float(lib.get_meta("source_hips_y")))
	if idle != null:
		lib.add_animation(&"idle", idle)
	s.library = lib
	s.library_name = &"shared"
	s.shared = {&"idle": &"idle", &"walk": &"walk", &"talk": &"talk", &"stairs": &"climb_stairs"}
	s.locomotion = {&"walk": &"walk", &"stairs": &"stairs", &"ladder": &"stairs", &"rope": &"stairs"}
	s.fallback_tag = &"idle"
	return s

## Fuego's own idle, re-expressed at the library's source hip height so the adapter's hip-ratio scaling is neutral for the others.
func _bake_idle(source_hips_y: float) -> Animation:
	var root := (load(IDLE_SRC) as PackedScene).instantiate()
	var ap := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var clip := ap.get_animation(ap.get_animation_list()[0]).duplicate() as Animation
	var hips := sk.find_bone("Hips")
	var ratio := source_hips_y / sk.get_bone_global_rest(hips).origin.y
	for t in clip.get_track_count():
		if clip.track_get_type(t) == Animation.TYPE_POSITION_3D and String(clip.track_get_path(t)).ends_with(":Hips"):
			for k in clip.track_get_key_count(t):
				clip.track_set_key_value(t, k, (clip.track_get_key_value(t, k) as Vector3) * ratio)
	clip.loop_mode = Animation.LOOP_LINEAR
	root.free()
	return clip

func _roster() -> NpcRoster:
	var r := NpcRoster.new()
	r.watches = [
		_watch(&"helm_watch", &"helm", &"helm", ["papi_fuego", "don_omar", "papi_diagnostica"], 240.0, 40.0, true),
		_watch(&"spyglass_watch", &"spyglass_post", &"spyglass_post", ["papi_fuego", "el_salchipapa"], 150.0, 30.0, false),
		_watch(&"nest_watch", &"crows_nest", &"crows_nest", ["el_salchipapa", "papi_fuego"], 200.0, 30.0, false),
	]
	return r

func _watch(id: StringName, station: StringName, kind: StringName, eligible: Array, shift: float, jitter: float, emergency: bool) -> NpcWatchDef:
	var w := NpcWatchDef.new()
	w.watch_id = id
	w.station_id = station
	w.job_kind = kind
	w.eligible = PackedStringArray(eligible)
	w.shift_s = shift
	w.shift_jitter_s = jitter
	w.keep_during_emergency = emergency
	return w
