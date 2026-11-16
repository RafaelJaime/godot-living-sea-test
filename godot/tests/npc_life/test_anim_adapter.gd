extends GutTest
## Specs: npc-life-animation (adapter interface, crossfade, library install with hip-ratio scaling, procedural adapter, no bundled clips).

func _player_with_clips() -> AnimationPlayer:
	var p := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for n in ["walk", "idle", "work"]:
		var a := Animation.new()
		a.length = 1.0
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(n, a)
	p.add_animation_library("shared", lib)
	return p

func _anim_set() -> NpcAnimSet:
	var s := NpcAnimSet.new()
	s.shared = {&"walk": &"shared/walk", &"idle": &"shared/idle", &"work": &"shared/work"}
	s.fallback_tag = &"idle"
	return s

func _visual_with_player() -> Node3D:
	var v := Node3D.new()
	add_child_autofree(v)
	v.add_child(_player_with_clips())
	return v

func test_adapter_interface_defaults_are_inert() -> void:
	var a := NpcAnimationAdapter.new()
	assert_false(a.bind(null, null))
	assert_false(a.has_tag(&"walk"))
	a.play(&"walk") # no-ops, no errors
	a.set_locomotion(&"walk", 1.0)
	assert_null(a.attach_prop(null, &"hand_r"))

func test_play_crossfades_035s() -> void:
	var vis := _visual_with_player()
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = _anim_set()
	assert_true(ad.bind(null, vis))
	var player: AnimationPlayer = vis.get_child(0)
	ad.play(&"walk")
	assert_eq(player.current_animation, "shared/walk")
	ad.play(&"idle")
	assert_eq(player.current_animation, "shared/idle")
	assert_almost_eq(player.get_blend_time("shared/walk", "shared/idle"), 0.35, 1e-6, "default crossfade 0.35 s")
	ad.play(&"work", true, 0.25)
	assert_almost_eq(player.get_blend_time("shared/idle", "shared/work"), 0.25, 1e-6, "explicit blend time")
	assert_eq(ad.current_tag(), &"work")

func test_has_tag() -> void:
	var vis := _visual_with_player()
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = _anim_set()
	ad.bind(null, vis)
	assert_true(ad.has_tag(&"walk"))
	assert_false(ad.has_tag(&"flying"))

func test_missing_clip_falls_back_and_logs_once() -> void:
	var vis := _visual_with_player()
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = _anim_set()
	ad.bind(null, vis)
	ad.play(&"flying")
	ad.play(&"flying")
	assert_eq((vis.get_child(0) as AnimationPlayer).current_animation, "shared/idle")
	assert_eq(ad.anim_set.missing_tags().size(), 1)

func test_set_locomotion_plays_the_edge_tag() -> void:
	var vis := _visual_with_player()
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = _anim_set()
	ad.anim_set.locomotion = {&"walk": &"walk"}
	ad.bind(null, vis)
	ad.set_locomotion(&"walk", 1.2)
	assert_eq((vis.get_child(0) as AnimationPlayer).current_animation, "shared/walk")
	ad.set_locomotion(&"walk", 1.2)
	assert_eq(ad.current_tag(), &"walk", "no restart while the tag is unchanged")

func test_install_hip_ratio_scaling() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Hips")
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 50, 0)))
	sk.reset_bone_poses()
	var vis := Node3D.new()
	add_child_autofree(vis)
	vis.add_child(sk)
	var player := AnimationPlayer.new()
	vis.add_child(player)
	var lib := AnimationLibrary.new()
	var a := Animation.new()
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, NodePath("Skeleton3D:Hips"))
	a.position_track_insert_key(t, 0.0, Vector3(0, 100, 0))
	lib.add_animation("walk", a)
	lib.set_meta("source_hips_y", 100.0)
	var s := NpcAnimSet.new()
	s.library = lib
	s.shared = {&"walk": &"shared/walk"}
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = s
	assert_true(ad.bind(null, vis))
	var inst := player.get_animation("shared/walk")
	assert_not_null(inst)
	assert_almost_eq((inst.track_get_key_value(0, 0) as Vector3).y, 50.0, 1e-4, "hips Y scaled by 50/100")
	assert_almost_eq((lib.get_animation("walk").track_get_key_value(0, 0) as Vector3).y, 100.0, 1e-4, "the source library is not modified")

func test_procedural_adapter_works_without_skeleton() -> void:
	var puppet := Node3D.new()
	add_child_autofree(puppet)
	var ad := NpcProceduralAdapter.new()
	assert_true(ad.bind(null, puppet))
	assert_true(ad.has_tag(&"walk"))
	ad.play(&"walk")
	var ys := []
	for i in 20:
		ad.process(0.05)
		ys.append(puppet.position.y)
	assert_gt(ys.max() - ys.min(), 0.005, "walking bobs the puppet")
	ad.play(&"idle")
	for i in 40:
		ad.process(0.05)
	var y_idle := puppet.position.y
	for i in 5:
		ad.process(0.05)
	assert_almost_eq(puppet.position.y, y_idle, 0.02, "idle settles")

func test_no_third_party_clip_in_addon() -> void:
	var bad: Array[String] = []
	_scan("res://addons/npc_life", bad)
	assert_eq(bad, [] as Array[String], "the addon ships no animation or model files: %s" % [bad])

func _scan(dir: String, bad: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		if ext in ["glb", "gltf", "fbx", "anim", "res", "blend"]:
			bad.append(dir + "/" + f)
	for sub in d.get_directories():
		_scan(dir + "/" + sub, bad)

func test_clip_speed_of_a_tag_sets_the_playback_rate() -> void:
	## A clip authored for 0.4 m/s of travel must play at speed/0.4 when the agent really moves at 0.54 m/s, or the feet slide.
	var vis := _visual_with_player()
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = _anim_set()
	ad.anim_set.shared[&"ladder"] = &"shared/work"
	ad.anim_set.locomotion = {&"walk": &"walk", &"ladder": &"ladder"}
	ad.anim_set.clip_speeds = {&"ladder": 0.4}
	ad.bind(null, vis)
	ad.set_locomotion(&"ladder", 0.54)
	assert_almost_eq((vis.get_child(0) as AnimationPlayer).speed_scale, 1.35, 0.001, "0.54 / 0.4")
	ad.set_locomotion(&"walk", 1.2)
	assert_almost_eq((vis.get_child(0) as AnimationPlayer).speed_scale, 1.0, 0.001, "tags without a clip speed use the reference speed")
