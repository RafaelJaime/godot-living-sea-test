extends GutTest
## Spec ship-crew-characters (C1.4): the project IK adapter on the real Meshy rig: helm reach, violin on demand, neutral bones only while IK holds the arms.

class FakeAgent extends Node3D:
	var agent_id: StringName = &"papi_fuego"
	var anim: Object

class FakeRig extends Node:
	var ramped := 0
	func _ramp_in(_m: SkeletonModifier3D) -> void:
		ramped += 1
	func make_clamped_target(sk: Skeleton3D, side: String, source: Node3D) -> Node3D:
		var proxy := Node3D.new()
		proxy.name = side + "ReachTarget"
		proxy.top_level = true
		sk.add_child(proxy)
		proxy.global_position = source.global_position
		return proxy

const PROFILE := "res://crew/defs/crew_rig_profile.tres"

var agent: FakeAgent
var sk: Skeleton3D
var rig: FakeRig
var pose: CrewPoseModifier

func _model(path: String, id: StringName) -> void:
	agent = FakeAgent.new()
	agent.agent_id = id
	add_child_autofree(agent)
	var inst := (load(path) as PackedScene).instantiate()
	agent.add_child(inst)
	sk = inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	pose = CrewPoseModifier.new()
	pose.name = "CrewPose"
	pose.neutral_active = false
	sk.add_child(pose)
	rig = FakeRig.new()
	add_child_autofree(rig)

func _adapter() -> CrewIkAdapter:
	var ad := CrewIkAdapter.new()
	ad.rig = rig
	assert_true(ad.bind(agent, sk, load(PROFILE) as NpcRigProfile), "binds on the Meshy rig")
	return ad

func _target() -> Node3D:
	var t := Node3D.new()
	agent.add_child(t)
	t.position = Vector3(0.0, 1.2, -0.5)
	return t

func test_binds_both_hand_chains_on_meshy_rig() -> void:
	_model("res://assets/characters/papi_fuego.glb", &"papi_fuego")
	var ad := _adapter()
	assert_not_null(ad.modifier_of(&"hand_l"))
	assert_not_null(ad.modifier_of(&"hand_r"))

func test_only_omar_gets_a_violin() -> void:
	_model("res://assets/characters/papi_fuego.glb", &"papi_fuego")
	_adapter().set_violin(true)
	assert_eq(sk.find_children("Violin", "", true, false).size(), 0, "Fuego has no violin")
	autofree(agent)
	_model("res://assets/characters/don_omar.glb", &"don_omar")
	_adapter()
	assert_eq(sk.find_children("Violin", "Node", true, false).size() >= 1, true, "Omar has one")

func test_violin_follows_the_animation_tag_and_is_off_by_default() -> void:
	_model("res://assets/characters/don_omar.glb", &"don_omar")
	var ad := _adapter()
	assert_false(ad.violin_active(), "folded away at the start")
	assert_eq(rig.ramped, 0, "no automatic ramp-in: it is on demand")
	ad._on_tag_changed(&"idle", &"violin_play", 0.3)
	await wait_seconds(0.4)
	assert_true(ad.violin_active(), "violin_play raises it")
	ad._on_tag_changed(&"violin_play", &"walk", 0.3)
	await wait_seconds(1.5)
	assert_false(ad.violin_active(), "any other tag folds it away")

func test_neutral_bones_only_while_ik_holds_the_arms() -> void:
	_model("res://assets/characters/papi_fuego.glb", &"papi_fuego")
	var ad := _adapter()
	ad.process(0.016)
	assert_false(pose.neutral_active, "walking keeps the imported arm swing")
	ad.set_target(&"hand_l", _target(), 1.0, 0.2)
	ad.set_target(&"hand_r", _target(), 1.0, 0.2)
	for i in 30:
		ad.process(0.02)
	assert_true(pose.neutral_active, "arms held by IK: neutral upper body")
	ad.clear(&"hand_l", 0.2)
	ad.clear(&"hand_r", 0.2)
	for i in 30:
		ad.process(0.02)
	assert_false(pose.neutral_active, "released: the animation drives the arms again")

func test_hand_reaches_the_target_on_the_real_rig() -> void:
	_model("res://assets/characters/papi_fuego.glb", &"papi_fuego")
	var ad := _adapter()
	var hand := sk.find_bone("RightHand")
	var start := sk.global_transform * sk.get_bone_global_pose(hand).origin
	var t := Node3D.new()
	agent.add_child(t)
	t.global_position = start + Vector3(0.0, 0.2, 0.0) # a comfortable reach: 20 cm above where the hand rests
	var seen: Array[Vector3] = [start]
	sk.skeleton_updated.connect(func() -> void: seen[0] = sk.global_transform * sk.get_bone_global_pose(hand).origin) # the pose after the modifiers ran
	ad.set_target(&"hand_r", t, 1.0, 0.1)
	for i in 20:
		ad.process(0.02)
		await wait_frames(1)
	assert_gt(ad.weight_of(&"hand_r"), 0.95, "fully blended in")
	var hp := seen[0]
	assert_lt(hp.distance_to(t.global_position), 0.08, "the right hand ends up on the target")
	assert_gt(hp.distance_to(start), 0.12, "and it actually moved there")
