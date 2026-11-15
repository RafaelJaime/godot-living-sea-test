extends GutTest
## Specs: npc-life-characters (CharacterDef resource, role and action defs, validation, variety by definition).

func _action(id: StringName, kind: StringName, tag: StringName) -> NpcActionDef:
	var a := NpcActionDef.new()
	a.action_id = id
	a.job_kinds = PackedStringArray([kind])
	a.anim_tag = tag
	return a

func test_defaults() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"solo"
	assert_eq(d.validate().size(), 0, "a def with only an id is valid")
	assert_eq(d.skill_for(&"anything"), 0.5, "skill 0.5 everywhere by default")
	assert_eq(d.preference_for(&"anything"), 0.0, "neutral preferences")
	assert_eq(d.signature_actions.size(), 0)
	assert_eq(d.all_tags().size(), 0)
	assert_eq(d.temperature_scale, 1.0)
	assert_true(d.walk_speed > 0.0)

func test_role_grants_tags() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"c"
	d.roles = PackedStringArray(["helmsman"])
	d.tags = PackedStringArray(["climber"])
	var t := d.all_tags()
	assert_true(t.has("helmsman"), "roles act as tags")
	assert_true(t.has("climber"))
	assert_eq(t.size(), 2, "no duplicates")

func test_resource_round_trip() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"rt"
	d.display_name = "Round Trip"
	d.roles = PackedStringArray(["a", "b"])
	d.preferences = {&"music": 0.8, &"fishing": -0.3}
	d.skills = {&"helm": 0.9}
	d.needs = {&"boredom": 0.5}
	d.signature_actions = [_action(&"s1", &"music", &"play"), _action(&"s2", &"fish", &"cast"), _action(&"s3", &"mop", &"scrub")]
	d.temperature_scale = 1.4
	var path := "user://npc_def_round_trip.tres"
	assert_eq(ResourceSaver.save(d, path), OK)
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NpcCharacterDef
	assert_not_null(back)
	assert_eq(back.agent_id, d.agent_id)
	assert_eq(back.display_name, d.display_name)
	assert_eq(back.roles, d.roles)
	assert_eq(back.preferences, d.preferences)
	assert_eq(back.skills, d.skills)
	assert_eq(back.needs, d.needs)
	assert_eq(back.signature_actions.size(), 3)
	assert_eq(back.signature_actions[2].anim_tag, &"scrub")
	assert_eq(back.temperature_scale, 1.4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_validation_reports_empty_id() -> void:
	var d := NpcCharacterDef.new()
	var v := d.validate()
	assert_eq(v.size(), 1)
	assert_true(v[0].contains("agent_id"))

func test_validation_reports_unknown_kind() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"c"
	d.preferences = {&"music": 0.5, &"warp_drive": 0.5}
	var v := d.validate(PackedStringArray(["music", "fishing"]))
	assert_eq(v.size(), 1)
	assert_true(v[0].contains("preferences") and v[0].contains("warp_drive"), "names the field and the key")

func test_validation_reports_missing_anim_tag() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"c"
	d.signature_actions = [_action(&"play", &"music", &"play_violin")]
	var v := d.validate(PackedStringArray(), PackedStringArray(["walk", "idle"]))
	assert_eq(v.size(), 1)
	assert_true(v[0].contains("signature_actions") and v[0].contains("play_violin"))
	assert_eq(d.validate(PackedStringArray(), PackedStringArray(["walk", "play_violin"])).size(), 0)

func test_out_of_range_skill_reported_and_clamped() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"c"
	d.skills = {&"helm": 1.7, &"mop": -0.2}
	var v := d.validate()
	assert_eq(v.size(), 2, "each violation reported by field name")
	assert_true(v[0].contains("skills"))
	var fixed := d.sanitize()
	assert_eq(fixed.size(), 2)
	assert_eq(d.skills[&"helm"], 1.0, "policy: sanitize() clamps to range")
	assert_eq(d.skills[&"mop"], 0.0)
	assert_eq(d.validate().size(), 0)

func test_preferences_range_clamped() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"c"
	d.preferences = {&"music": 2.5, &"fishing": -3.0}
	assert_eq(d.validate().size(), 2)
	d.sanitize()
	assert_eq(d.preferences[&"music"], 1.0)
	assert_eq(d.preferences[&"fishing"], -1.0)
	assert_eq(d.preference_for(&"music"), 1.0)

func test_non_positive_duration_reported() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"c"
	var a := _action(&"bad", &"k", &"t")
	a.duration_range = Vector2(0.0, -1.0)
	d.signature_actions = [a]
	var v := d.validate()
	assert_gt(v.size(), 0)
	assert_true(v[0].contains("duration_range"))

func test_action_cooldown() -> void:
	var a := _action(&"fancy", &"k", &"t")
	a.cooldown_s = 60.0
	assert_true(a.is_ready(-1.0, 0.0), "never performed: ready")
	assert_false(a.is_ready(0.0, 30.0), "performed 30 s ago with cooldown 60: excluded")
	assert_true(a.is_ready(0.0, 60.0))
	var free := _action(&"free", &"k", &"t")
	assert_true(free.is_ready(0.0, 0.0), "no cooldown: always ready")

func test_two_defs_differ_in_variety_fields() -> void:
	var x := NpcCharacterDef.new()
	x.agent_id = &"X"
	x.preferences = {&"music": 0.9}
	var y := NpcCharacterDef.new()
	y.agent_id = &"Y"
	y.preferences = {&"fishing": 0.9}
	assert_gt(x.preference_for(&"music"), y.preference_for(&"music"))
	assert_gt(y.preference_for(&"fishing"), x.preference_for(&"fishing"))
