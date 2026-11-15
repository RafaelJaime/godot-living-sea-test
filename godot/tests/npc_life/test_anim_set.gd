extends GutTest
## Specs: npc-life-animation (shared library and signature clips, fallback, locomotion by edge type).

func _anim_set() -> NpcAnimSet:
	var s := NpcAnimSet.new()
	s.shared = {&"walk": &"shared/walk", &"idle": &"shared/idle", &"work": &"shared/work_generic"}
	s.signature = {&"work": &"sig/work_fancy", &"fish": &"sig/fish"}
	s.locomotion = {&"walk": &"walk", &"ladder": &"climb_ladder", &"stairs": &"walk"}
	s.fallback_tag = &"idle"
	return s

func test_tag_resolves_shared_clip() -> void:
	var s := _anim_set()
	assert_eq(s.resolve(&"walk"), &"shared/walk")
	assert_true(s.has_tag(&"walk"))

func test_signature_override_wins() -> void:
	var s := _anim_set()
	assert_eq(s.resolve(&"work"), &"sig/work_fancy", "the character's signature clip beats the shared one")
	assert_eq(s.resolve(&"fish"), &"sig/fish", "a signature-only tag resolves too")

func test_fallback_and_logged_once() -> void:
	var s := _anim_set()
	assert_eq(s.resolve(&"dance"), &"shared/idle", "unknown tag: the fallback tag's clip")
	s.resolve(&"dance")
	s.resolve(&"dance")
	assert_eq(s.missing_tags(), [&"dance"] as Array[StringName], "reported exactly once per tag")
	assert_false(s.has_tag(&"dance"))

func test_missing_tag_reports_validation() -> void:
	var s := _anim_set()
	var v := s.validate(PackedStringArray(["walk", "dance", "work"]))
	assert_eq(v.size(), 1)
	assert_true(v[0].contains("dance"))
	s.fallback_tag = &"nope"
	assert_gt(s.validate(PackedStringArray()).size(), 0, "a fallback tag without a clip is reported")

func test_locomotion_by_edge_type() -> void:
	var s := _anim_set()
	assert_eq(s.locomotion_tag(&"ladder"), &"climb_ladder")
	assert_eq(s.locomotion_tag(&"stairs"), &"walk")
	assert_eq(s.locomotion_tag(&"rope"), &"walk", "unmapped edge type: walk")

func test_character_def_validates_against_the_set() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"x"
	d.anim_set = _anim_set()
	var a := NpcActionDef.new()
	a.action_id = &"x"
	a.anim_tag = &"dance"
	d.signature_actions = [a]
	var v := d.validate(PackedStringArray(), (d.anim_set as NpcAnimSet).tags())
	assert_eq(v.size(), 1, "the def's tags are checked against the set's tags")
