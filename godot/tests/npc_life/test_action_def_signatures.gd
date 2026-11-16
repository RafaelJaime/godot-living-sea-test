extends GutTest
## Spec ship-crew-characters (C4.4): signature actions point at real clips, IK chains that exist, and the comic fall has time to recover.

const IDS := [&"papi_fuego", &"papi_diagnostica", &"el_salchipapa", &"don_omar"]
## Actions that deliberately stand still in the idle clip.
const IDLE_OK := [&"helm_steer"]
## Actions whose dedicated clip is still to be authored (requested from godot-ship); they keep a stand-in, listed so the gap is visible.
const STAND_IN := [&"play_violin", &"point_ahead", &"comic_fall"]

func _def(id: StringName) -> NpcCharacterDef:
	return load("res://crew/defs/%s.tres" % id) as NpcCharacterDef

func _anim_set() -> NpcAnimSet:
	return load("res://crew/defs/crew_anim_set.tres") as NpcAnimSet

func test_each_signature_clip_tag_exists_in_anim_anim_set() -> void:
	var set := _anim_set()
	for id in IDS:
		for a in _def(id).signature_actions:
			assert_true(set.has_tag(a.anim_tag), "%s/%s: tag %s has a clip" % [id, a.action_id, a.anim_tag])
			var clip := String(set.resolve(a.anim_tag))
			assert_true(set.library.has_animation(clip.get_slice("/", 1)), "%s: clip %s is in the library" % [a.action_id, clip])

func test_signature_actions_do_not_all_fall_back_to_idle() -> void:
	var set := _anim_set()
	var idle := set.resolve(&"idle")
	for id in IDS:
		var distinct := 0
		for a in _def(id).signature_actions:
			if set.resolve(a.anim_tag) != idle:
				distinct += 1
		assert_gte(distinct, 2, "%s has at least two signature actions with a clip of their own" % id)

func test_actions_have_their_own_clip_unless_listed() -> void:
	var set := _anim_set()
	var idle := set.resolve(&"idle")
	for id in IDS:
		for a in _def(id).signature_actions:
			if IDLE_OK.has(a.action_id) or STAND_IN.has(a.anim_tag):
				continue
			assert_ne(set.resolve(a.anim_tag), idle, "%s/%s plays a clip of its own" % [id, a.action_id])

func test_each_signature_ik_chain_in_rig_profile() -> void:
	for id in IDS:
		var d := _def(id)
		var prof := d.rig_profile as NpcRigProfile
		for a in d.signature_actions:
			for chain in a.ik:
				assert_true(prof.chains.has(chain), "%s/%s: IK chain %s is in the rig profile" % [id, a.action_id, chain])

func test_comic_fall_action_has_recovery_time() -> void:
	var fall: NpcActionDef = null
	for a in _def(&"el_salchipapa").signature_actions:
		if a.action_id == &"comic_fall":
			fall = a
	assert_not_null(fall, "Salchipapa has the comic fall")
	var set := _anim_set()
	var clip := String(set.resolve(fall.anim_tag)).get_slice("/", 1)
	var clip_len := set.library.get_animation(clip).length
	assert_gte(fall.duration_range.x, clip_len, "the work phase lasts at least as long as the clip: the fall and the recovery both play")
	assert_gt(fall.cooldown_s, 60.0, "and it stays rare")

func test_every_baked_clip_has_an_attribution_row() -> void:
	var text := FileAccess.get_file_as_string("res://../ATTRIBUTION.md")
	for needle in ["Universal Animation Library", "KayKit", "ratline climb"]:
		assert_true(text.contains(needle), "ATTRIBUTION.md mentions %s" % needle)

func test_no_third_party_clip_in_addon() -> void:
	var dirs := ["res://addons/npc_life"]
	var found: Array[String] = []
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.get_extension() in ["glb", "gltf", "fbx", "anim", "res"] or f.ends_with(".anim.tres"):
				found.append(d + "/" + f)
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d + "/" + sub)
	assert_eq(found, [], "no model or clip files under the addon")
