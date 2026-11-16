@tool
extends SceneTree
## Dev tool (run once, commit the output): builds the four crew NpcCharacterDefs, the roster, the rig profile and the anim set under res://crew/defs/.
## Usage: godot --headless --path godot -s crew/defs/build_crew_defs.gd
## Signature animation tags map to existing shared clips until the C4 clip pipeline bakes the real ones (see odd/evidence/npc-crew-jobs/C4).

const OUT := "res://crew/defs/"
const LIB_SRC := "res://assets/anim/crew_clips.res" ## built by tools/crew_anim_bake.gd
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
	_map_tags(anim)
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

func _act(id: StringName, kinds: Array, tag: StringName, dur := Vector2(8, 16), effect := &"", station_kind := &"", ik := {}, look := &"", cooldown := 0.0, prop := "") -> NpcActionDef:
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
	if prop != "":
		a.props = [load("res://assets/props/%s" % prop) as PackedScene] # grip-ready scenes (assets/props/README.md), attached to the right hand
	return a

func _def(id: StringName, name: String, roles: Array, tags: Array, walk: float, temp: float, prefs: Dictionary, skills: Dictionary, needs: Dictionary, acts: Array) -> NpcCharacterDef:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	d.display_name = name
	d.roles = PackedStringArray(roles)
	d.tags = PackedStringArray(tags)
	d.tags.append(String(id)) # the agent's own id is a tag, so a source can address one agent (free-time fairness)
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
		_act(&"spyglass_scan", ["spyglass_post"], &"spyglass_scan", Vector2(10, 20), &"", &"spyglass_post", {}, &"horizon", 0.0, "spyglass_prop.tscn"),
		_act(&"point_ahead", ["spyglass_post", "social_spot"], &"point_ahead", Vector2(2.4, 2.6), &"", &"", {}, &"horizon", 90.0)])

func _diagnostica() -> NpcCharacterDef:
	return _def(&"papi_diagnostica", "Papi Diagnóstica", ["carpenter", "climber"], [], 1.35, 1.0,
		{&"repair_spot": 0.8, &"ratline_path": 0.5, &"reef_pin": 0.3, &"mop_zone": -0.4},
		{&"repair_spot": 0.9, &"ratline_path": 0.8, &"helm": 0.3},
		{&"boredom": 0.4},
		[_act(&"hammer_repair", ["repair_spot"], &"hammer_repair", Vector2(10, 20), &"repair", &"repair_spot", {}, &"", 0.0, "hammer_prop.tscn"),
		_act(&"ratline_climb", ["ratline_path"], &"ratline_climb", Vector2(8, 14), &"", &"ratline_path"),
		_act(&"carry_crate", ["haul"], &"carry_crate", Vector2(6, 12), &"haul")])

func _salchipapa() -> NpcCharacterDef:
	return _def(&"el_salchipapa", "El Salchipapa", ["lookout", "climber", "fisher"], ["joker"], 1.1, 1.4,
		{&"crows_nest": 0.8, &"fishing_rail": 0.7, &"reef_pin": 0.2, &"mop_zone": -0.6},
		{&"crows_nest": 0.85, &"fishing_rail": 0.8, &"helm": 0.15},
		{&"boredom": 0.6},
		[_act(&"crows_nest_watch", ["crows_nest"], &"crows_nest_watch", Vector2(14, 30), &"", &"crows_nest", {}, &"horizon"),
		_act(&"rope_work", ["reef_pin"], &"rope_work", Vector2(8, 16), &"", &"reef_pin"),
		_act(&"fishing_cast", ["fishing_rail"], &"fishing_cast", Vector2(16, 40), &"", &"fishing_rail", {}, &"", 0.0, "fishing_rod_prop.tscn"),
		_act(&"comic_fall", ["chat", "social_spot"], &"comic_fall", Vector2(3.0, 3.1), &"", &"", {}, &"", 240.0)])

func _omar() -> NpcCharacterDef:
	return _def(&"don_omar", "Don Omar", ["musician", "navigator"], ["elder"], 0.95, 0.6,
		{&"violin_seat": 0.9, &"chart_table": 0.6, &"listen_spot": 0.3, &"mop_zone": -0.5},
		{&"violin_seat": 0.9, &"chart_table": 0.8, &"helm": 0.35},
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
	s.library = load(LIB_SRC) as AnimationLibrary
	s.library_name = &"shared"
	s.fallback_tag = &"idle"
	s.shared = {}
	return s

## Tag -> clip. `want` are clip names in order of preference (a later authored clip, e.g. furl_aloft from godot-ship, wins automatically once the bake
## tool has put it in the library); the last one must exist. Stand-ins are noted so the gaps stay visible: haul and furl_aloft reuse arm-work clips,
## play_violin and comic_fall use the talking gestures until their clips are authored.
func _map_tags(anim: NpcAnimSet) -> void:
	var table := {
		# locomotion and base
		&"idle": ["idle"], &"walk": ["walk"], &"talk": ["talk"], &"stairs": ["climb_stairs"], &"rope": ["ratline_climb"], &"ladder": ["climb_ladder", "ratline_climb"], &"ladder_off": ["climb_ladder_off", "idle"],
		# station tags of ShipStations
		&"steer": ["idle"], &"chart": ["idle_rail"], &"fish": ["fishing_idle"], &"inspect": ["idle_rail"], &"listen": ["idle_rail"],
		&"lookout": ["idle_rail"], &"mop": ["deck_swab"], &"repair": ["hammering"], &"spyglass": ["spyglass_look"], &"violin": ["play_violin", "idle_talking"],
		&"light": ["idle_lantern"], &"haul": ["haul", "sawing"], &"climb": ["ratline_climb"], &"furl_aloft": ["furl_aloft", "hammering"],
		# signature actions
		&"helm_steer": ["idle"], &"spyglass_scan": ["spyglass_look"], &"point_ahead": ["point_ahead", "idle_talking"],
		&"hammer_repair": ["hammering"], &"ratline_climb": ["ratline_climb"], &"carry_crate": ["walk_carry"],
		&"crows_nest_watch": ["idle_rail"], &"rope_work": ["fixing_kneeling"], &"fishing_cast": ["fishing_idle"], &"comic_fall": ["comic_fall", "idle_talking"],
		&"violin_play": ["play_violin", "idle_talking"], &"chart_study": ["idle_rail"], &"star_gaze": ["idle_lantern"],
	}
	for tag in table:
		var clip := &""
		for c in table[tag]:
			if anim.library.has_animation(c):
				clip = StringName("shared/%s" % c)
				break
		if clip == &"":
			push_error("[build_crew_defs] no clip for tag %s (wanted %s)" % [tag, table[tag]])
			continue
		anim.shared[tag] = clip
	# travel speed (m/s) each climbing clip was authored for: ratline_climb 0.476 vertical, climb_ladder 0.40 vertical
	anim.clip_speeds = {&"ladder": 0.40, &"rope": 0.476}
	anim.exit_tags = {&"ladder": &"ladder_off"}
	anim.exit_advance = {&"ladder": 0.35} # the clip is baked in place (tools/crew_anim_bake.gd); the node covers its 0.35 m of hip travel # step off the ladder onto the deck before walking on
	anim.locomotion = {&"walk": &"walk", &"stairs": &"stairs", &"ladder": &"ladder", &"rope": &"rope"}

## Only the helm is a standing watch: with four people, three permanent posts would leave nobody free for chores and free time. Lookout duty at the
## spyglass and the crow's nest is ordinary free-time work (CrewLeisureSource). Skill weights make Fuego the most frequent helmsman.
func _roster() -> NpcRoster:
	var r := NpcRoster.new()
	r.watches = [
		_watch(&"helm_watch", &"helm", &"helm", ["papi_fuego", "don_omar", "papi_diagnostica", "el_salchipapa"], 240.0, 40.0, true),
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
	w.max_consecutive = 3 # nobody holds the post for more than three shifts in a row when someone else can take it
	return w
