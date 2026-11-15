extends GutTest
## Spec ship-crew-characters (C1.1): the four crew members as data, validated, distinct and bound to the Meshy rig.

const DEFS := {
	&"papi_fuego": "res://crew/defs/papi_fuego.tres",
	&"papi_diagnostica": "res://crew/defs/papi_diagnostica.tres",
	&"el_salchipapa": "res://crew/defs/el_salchipapa.tres",
	&"don_omar": "res://crew/defs/don_omar.tres",
}
const MODELS := {
	&"papi_fuego": "res://assets/characters/papi_fuego.glb",
	&"papi_diagnostica": "res://assets/characters/papi_diagnostica.glb",
	&"el_salchipapa": "res://assets/characters/el_salchipapa.glb",
	&"don_omar": "res://assets/characters/don_omar.glb",
}
const ROSTER := "res://crew/defs/crew_roster.tres"
const PROFILE := "res://crew/defs/crew_rig_profile.tres"
const ANIM_SET := "res://crew/defs/crew_anim_set.tres"
const STATION_KINDS := ["helm", "spyglass_post", "crows_nest", "ratline_path", "chart_table", "violin_seat", "listen_spot", "social_spot", "fishing_rail", "repair_spot", "mop_zone", "boat_check", "reef_pin", "lantern", "lamp", "chat", "haul"]

func _def(id: StringName) -> NpcCharacterDef:
	return load(DEFS[id]) as NpcCharacterDef

func _all() -> Array[NpcCharacterDef]:
	var out: Array[NpcCharacterDef] = []
	for id in DEFS:
		out.append(_def(id))
	return out

func test_four_defs_load_and_validate_clean() -> void:
	for id in DEFS:
		var d := _def(id)
		assert_not_null(d, "%s loads as an NpcCharacterDef" % id)
		if d == null:
			continue
		var anim := load(ANIM_SET) as NpcAnimSet
		assert_not_null(anim, "the shared crew anim set loads")
		var problems := d.validate(PackedStringArray(STATION_KINDS), anim.tags() if anim else PackedStringArray())
		assert_eq(problems.size(), 0, "%s validates: %s" % [id, problems])

func test_agent_ids_match_files_and_are_unique() -> void:
	var seen := {}
	for id in DEFS:
		var d := _def(id)
		assert_eq(d.agent_id, id, "agent_id equals the file id")
		assert_false(seen.has(d.agent_id), "agent id %s is unique" % d.agent_id)
		seen[d.agent_id] = true
	assert_eq(seen.size(), 4)

func test_every_def_has_at_least_two_signature_actions() -> void:
	for d in _all():
		assert_gte(d.signature_actions.size(), 2, "%s has two or more signature actions" % d.agent_id)
		var ids := {}
		for a in d.signature_actions:
			assert_false(ids.has(a.action_id), "%s: action id %s is unique" % [d.agent_id, a.action_id])
			ids[a.action_id] = true

func test_each_character_declares_its_spec_actions() -> void:
	var want := {
		&"papi_fuego": [&"helm_steer", &"spyglass_scan", &"point_ahead"],
		&"papi_diagnostica": [&"hammer_repair", &"ratline_climb", &"carry_crate"],
		&"el_salchipapa": [&"crows_nest_watch", &"rope_work", &"fishing_cast", &"comic_fall"],
		&"don_omar": [&"violin_play", &"chart_study", &"star_gaze"],
	}
	for id in want:
		var have := PackedStringArray()
		for a in _def(id).signature_actions:
			have.append(String(a.action_id))
		var hit := 0
		for w in want[id]:
			if have.has(String(w)):
				hit += 1
		assert_gte(hit, 2, "%s has at least two of its spec actions, has %s" % [id, have])

func test_variety_fields_differ() -> void:
	var walk := {}
	var temp := {}
	var top_pref := {}
	for d in _all():
		walk[snappedf(d.walk_speed, 0.01)] = true
		temp[snappedf(d.temperature_scale, 0.01)] = true
		var best := &""
		var bv := -2.0
		for k in d.preferences:
			if d.preferences[k] > bv:
				bv = d.preferences[k]
				best = k
		top_pref[best] = true
	assert_gte(walk.size(), 3, "walk speeds differ across the crew")
	assert_gte(temp.size(), 3, "decision temperatures differ across the crew")
	assert_gte(top_pref.size(), 3, "favourite job kinds differ across the crew")

func test_fuego_has_the_best_helm_skill() -> void:
	var best := &""
	var bv := -1.0
	for d in _all():
		var s := d.skill_for(&"helm")
		if s > bv:
			bv = s
			best = d.agent_id
	assert_eq(best, &"papi_fuego", "Fuego steers best")
	for d in _all():
		if d.agent_id != &"papi_fuego":
			assert_lt(d.skill_for(&"helm"), _def(&"papi_fuego").skill_for(&"helm"), "%s steers worse than Fuego" % d.agent_id)

func test_rig_profile_bones_exist_in_every_meshy_model() -> void:
	var prof := load(PROFILE) as NpcRigProfile
	assert_not_null(prof, "the crew rig profile loads")
	if prof == null:
		return
	var names := PackedStringArray()
	for c in prof.chains:
		names.append_array(prof.chains[c])
	names.append(String(prof.look_bone))
	names.append(String(prof.hips_bone))
	for s in prof.sockets:
		names.append(String(prof.sockets[s]))
	assert_gt(names.size(), 6)
	for id in MODELS:
		var inst := (load(MODELS[id]) as PackedScene).instantiate()
		add_child_autofree(inst)
		var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for n in names:
			assert_gte(sk.find_bone(n), 0, "%s: bone '%s' exists" % [id, n])

func test_defs_point_at_the_shared_profile_and_anim_set() -> void:
	for d in _all():
		assert_true(d.rig_profile is NpcRigProfile, "%s has a rig profile" % d.agent_id)
		assert_true(d.anim_set is NpcAnimSet, "%s has an anim set" % d.agent_id)

func test_roster_validates_against_ship_stations_and_the_crew() -> void:
	var r := load(ROSTER) as NpcRoster
	assert_not_null(r, "roster loads")
	if r == null:
		return
	var stations := PackedStringArray(["helm", "spyglass_post", "crows_nest"])
	var agents := PackedStringArray()
	for id in DEFS:
		agents.append(String(id))
	assert_eq(r.validate(stations, agents).size(), 0, "roster validates: %s" % [r.validate(stations, agents)])
	var helm: NpcWatchDef = null
	for w in r.watches:
		if w.station_id == &"helm":
			helm = w
	assert_not_null(helm, "the helm has a watch")
	if helm:
		assert_true(helm.eligible.has("papi_fuego"), "Fuego is eligible at the helm")
		assert_gte(helm.eligible.size(), 2, "someone can relieve the helm")
