class_name CrewIkAdapter
extends NpcTwoBoneIkAdapter
## Project IK adapter for the ship crew (C1.4). The addon's two-bone adapter already reproduces the helm rig (reach clamp, poles, 1.2 s ramps);
## this subclass adds what is specific to the ship:
##  - the imported idle may only be forced neutral on the upper body while IK holds the arms, so the walk keeps its arm swing: it toggles
##    `CrewPoseModifier.neutral_active` with the IK weight (the lean and brace layers of the modifier are untouched);
##  - Don Omar's violin and bow (scripts/violin.gd) appear while the animation tag is `violin_play` and fold away when it changes.
## `rig` is the CrewRig node: it owns the shared clamped-target proxies the violin arms use.

const VIOLIN_TAG := &"violin_play"
const NEUTRAL_EPSILON := 0.02

var rig: Node
var _violin: Violin
var _pose: CrewPoseModifier

func bind(agent: Node3D, skeleton: Skeleton3D, profile: NpcRigProfile) -> bool:
	var ok := super.bind(agent, skeleton, profile)
	_pose = skeleton.get_node_or_null("CrewPose") as CrewPoseModifier
	var anim: Variant = agent.get("anim")
	if rig != null and agent.get("agent_id") == &"don_omar":
		_violin = Violin.new()
		_violin.name = "Violin"
		skeleton.add_child(_violin)
		_violin.setup(skeleton, rig, true)
		if anim != null and (anim as Object).has_signal("tag_changed"):
			(anim as Object).connect("tag_changed", _on_tag_changed)
	return ok

func _on_tag_changed(_from: StringName, to_tag: StringName, _blend: float) -> void:
	set_violin(to_tag == VIOLIN_TAG)

func set_violin(on: bool) -> void:
	if _violin != null:
		_violin.set_playing(on)

func violin_active() -> bool:
	return _violin != null and _violin.is_playing()

func process(delta: float) -> void:
	super.process(delta)
	if _pose != null:
		var holding := violin_active()
		for c in [&"hand_l", &"hand_r"]:
			holding = holding or weight_of(c) > NEUTRAL_EPSILON
		_pose.neutral_active = holding
