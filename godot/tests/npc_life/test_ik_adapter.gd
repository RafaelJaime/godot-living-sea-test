extends GutTest
## Specs: npc-life-animation (procedural IK hooks). Runs the default TwoBoneIK3D / LookAtModifier3D adapter on a small programmatic humanoid.
## Regression for the A0 finding: TwoBoneIK3D silently does nothing without a pole, so a bound chain must have one and the hand must reach.

var agent: Node3D
var sk: Skeleton3D
var ad: NpcTwoBoneIkAdapter

func _humanoid(with_arms := true) -> Skeleton3D:
	var s := Skeleton3D.new()
	s.name = "Skeleton3D"
	var names := ["Hips", "Spine", "Head"]
	var parents := [-1, 0, 1]
	var rests := [Vector3(0, 1.0, 0), Vector3(0, 0.3, 0), Vector3(0, 0.5, 0)]
	if with_arms:
		for side in ["Left", "Right"]:
			var sx := -1.0 if side == "Left" else 1.0
			var base := names.size()
			names += [side + "UpperArm", side + "LowerArm", side + "Hand"]
			parents += [1, base, base + 1]
			rests += [Vector3(sx * 0.2, 0.3, 0), Vector3(0, -0.3, 0.04), Vector3(0, -0.3, 0)] # a slightly bent elbow: arms are never collinear
	for i in names.size():
		s.add_bone(names[i])
	for i in names.size():
		s.set_bone_parent(i, parents[i])
		s.set_bone_rest(i, Transform3D(Basis.IDENTITY, rests[i]))
	s.reset_bone_poses()
	return s

func before_each() -> void:
	agent = Node3D.new()
	add_child_autofree(agent)
	sk = _humanoid()
	agent.add_child(sk)
	ad = NpcTwoBoneIkAdapter.new()
	await wait_frames(1)

func _target(pos: Vector3) -> Node3D:
	var t := Node3D.new()
	t.name = "Tgt"
	add_child_autofree(t)
	t.global_position = pos
	return t

func test_bind_creates_chains_with_poles() -> void:
	assert_true(ad.bind(agent, sk, NpcRigProfile.new()))
	for chain in [&"hand_l", &"hand_r"]:
		var ik := ad.modifier_of(chain) as TwoBoneIK3D
		assert_not_null(ik)
		assert_false(ik.get_pole_node(0).is_empty(), "a TwoBoneIK3D without a pole does nothing (A0 finding): every chain has one")
		assert_false(ik.get_target_node(0).is_empty())

func test_adapter_binds_false_when_chain_missing() -> void:
	var bare := _humanoid(false)
	agent.add_child(bare)
	var a2 := NpcTwoBoneIkAdapter.new()
	assert_false(a2.bind(agent, bare, NpcRigProfile.new()))
	assert_false(a2.bind(agent, null, NpcRigProfile.new()))

func test_set_target_ramps_influence_12s() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	ad.set_target(&"hand_r", _target(Vector3(0.3, 1.0, 0.4)))
	assert_eq(ad.weight_of(&"hand_r"), 0.0, "starts released")
	ad.process(0.6)
	assert_almost_eq(ad.weight_of(&"hand_r"), 0.5, 0.05, "half way after 0.6 s of a 1.2 s ramp")
	assert_almost_eq((ad.modifier_of(&"hand_r") as SkeletonModifier3D).influence, ad.weight_of(&"hand_r"), 1e-6, "the modifier follows")
	ad.process(0.6)
	assert_almost_eq(ad.weight_of(&"hand_r"), 1.0, 0.01)
	assert_eq(ad.weight_of(&"hand_l"), 0.0, "other chains untouched")

func test_reach_clamped_at_93_percent() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	ad.set_target(&"hand_r", _target(Vector3(8, 1, 8)))
	ad.process(0.016)
	var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var upper := sk.get_bone_global_rest(sk.find_bone("RightUpperArm")).origin
	var lower := sk.get_bone_global_rest(sk.find_bone("RightLowerArm")).origin
	var hand := sk.get_bone_global_rest(sk.find_bone("RightHand")).origin
	var length := upper.distance_to(lower) + lower.distance_to(hand)
	assert_almost_eq(ad.proxy_of(&"hand_r").global_position.distance_to(shoulder), length * 0.93, 0.005, "the proxy is pulled inside 93 percent of the reach")

func test_reachable_target_is_not_pulled() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var near := shoulder + Vector3(0.05, -0.2, 0.2)
	ad.set_target(&"hand_r", _target(near))
	ad.process(0.016)
	assert_true(ad.proxy_of(&"hand_r").global_position.is_equal_approx(near))

func test_clear_ramps_out() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	ad.set_target(&"hand_r", _target(Vector3(0.3, 1.0, 0.4)))
	ad.process(1.3)
	assert_almost_eq(ad.weight_of(&"hand_r"), 1.0, 0.01)
	ad.clear(&"hand_r", 0.5)
	ad.process(0.25)
	assert_almost_eq(ad.weight_of(&"hand_r"), 0.5, 0.05)
	ad.process(0.3)
	assert_almost_eq(ad.weight_of(&"hand_r"), 0.0, 1e-6, "weight back to 0 when the job ends")
	assert_false(ad.has_target(&"hand_r"))

func test_look_at_target_set() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	var t := _target(Vector3(2, 1.8, 1))
	ad.set_look_at(t, 1.0)
	assert_eq(ad.look_target(), t)
	ad.process(1.3)
	assert_almost_eq(ad.look_weight(), 1.0, 0.01)
	ad.set_look_at(null)
	ad.process(2.0)
	assert_almost_eq(ad.look_weight(), 0.0, 0.01, "no target: the gaze is released")

func test_moving_target_is_re_read_each_frame() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var t := _target(shoulder + Vector3(0.0, -0.2, 0.3))
	ad.set_target(&"hand_r", t)
	ad.process(0.016)
	var p0 := ad.proxy_of(&"hand_r").global_position
	t.global_position = shoulder + Vector3(0.1, -0.1, 0.35)
	ad.process(0.016)
	assert_false(ad.proxy_of(&"hand_r").global_position.is_equal_approx(p0), "the proxy follows the moving target")

func test_hand_reaches_target_through_the_modifier() -> void:
	ad.bind(agent, sk, NpcRigProfile.new())
	var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var want := shoulder + Vector3(0.0, -0.15, 0.4)
	ad.set_target(&"hand_r", _target(want))
	var hand := sk.find_bone("RightHand")
	var seen := {"p": Vector3.INF}
	sk.skeleton_updated.connect(func() -> void: seen["p"] = sk.global_transform * sk.get_bone_global_pose(hand).origin)
	for i in 6:
		ad.process(0.3) # ramp to full weight
		await wait_frames(2)
	assert_lt((seen["p"] as Vector3).distance_to(want), 0.03, "the hand ends on the target: hand at %s, target %s" % [seen["p"], want])

func test_interface_has_no_engine_ik_types_in_signature() -> void:
	var banned := ["TwoBoneIK3D", "LookAtModifier3D", "SkeletonModifier3D", "IKModifier3D", "CCDIK3D", "FABRIK3D"]
	var base := NpcIkAdapter.new()
	for m in (base.get_script() as Script).get_script_method_list():
		for a in m["args"]:
			assert_false(banned.has(String(a["class_name"])), "%s argument %s" % [m["name"], a["name"]])
		assert_false(banned.has(String(m["return"]["class_name"])), "%s return" % m["name"])

func test_base_adapter_is_inert() -> void:
	var base := NpcIkAdapter.new()
	assert_false(base.bind(agent, sk, NpcRigProfile.new()))
	base.set_target(&"hand_r", null)
	base.clear(&"hand_r")
	base.set_look_at(null)
	base.process(0.1)
	assert_true(true, "no errors")

func test_proxy_rides_with_the_skeleton_between_process_and_solve() -> void:
	## A moving platform: the agent (and so the skeleton) is carried after the adapter's per-frame update and before the skeleton solves. The proxy
	## must travel with the skeleton, otherwise the hand lags one frame of platform motion behind the grip (seen on the moving ship).
	ad.bind(agent, sk, NpcRigProfile.new())
	var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	ad.set_target(&"hand_r", _target(shoulder + Vector3(0.05, -0.2, 0.2)))
	ad.process(0.016)
	var before := ad.proxy_of(&"hand_r").global_position
	agent.position += Vector3(5.0, 0.0, 0.0)
	assert_true(ad.proxy_of(&"hand_r").global_position.is_equal_approx(before + Vector3(5.0, 0.0, 0.0)), "the proxy moved with the carried skeleton")
