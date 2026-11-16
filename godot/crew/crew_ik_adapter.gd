class_name CrewIkAdapter
extends NpcTwoBoneIkAdapter
## Project IK adapter for the ship crew (C1.4). The addon's two-bone adapter already reproduces the helm rig (reach clamp, poles, 1.2 s ramps);
## this subclass adds what is specific to the ship:
##  - the imported idle may only be forced neutral on the upper body while IK holds the arms, so the walk keeps its arm swing: it toggles
##    `CrewPoseModifier.neutral_active` with the IK weight (the lean and brace layers of the modifier are untouched);
##  - Don Omar's violin and bow (scripts/violin.gd) appear while the animation tag is `violin_play` and fold away when it changes.
## `rig` is the CrewRig node: it owns the shared clamped-target proxies the violin arms use.

const VIOLIN_TAG := &"violin_play"
const HAUL_TAG := &"haul"
const NEUTRAL_EPSILON := 0.02

var rig: Node
var _violin: Violin
var _pose: CrewPoseModifier
var _rope: MeshInstance3D
var _hauling := false

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
	_hauling = to_tag == HAUL_TAG
	if _hauling and _rope == null and _agent != null:
		_rope = _make_rope()
	if _rope != null:
		_rope.visible = _hauling

## A taut rope from the right hand up and inboard (toward the yard the brace belongs to) while the haul clip plays; cheap and purely visual.
func _make_rope() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "HaulRope"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	cyl.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.3)
	mat.roughness = 0.9
	cyl.material = mat
	m.mesh = cyl
	m.top_level = true
	m.visible = false
	_agent.add_child(m)
	return m

func rope_node() -> MeshInstance3D:
	return _rope

func _update_rope() -> void:
	var hand := _sk.find_bone("RightHand")
	if hand < 0:
		return
	var from := _sk.global_transform * _sk.get_bone_global_pose(hand).origin
	var plat := _agent.get_parent() as Node3D
	var local := _agent.position
	var to := plat.global_transform * Vector3(local.x * 0.75, local.y + 2.8, local.z) if plat != null else from + Vector3.UP * 2.0
	var d := to - from
	var len := maxf(d.length(), 0.01)
	_rope.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d / len)).scaled(Vector3(1, len, 1)), from + d * 0.5)

func set_violin(on: bool) -> void:
	if _violin != null:
		_violin.set_playing(on)

func violin_active() -> bool:
	return _violin != null and _violin.is_playing()

func process(delta: float) -> void:
	super.process(delta)
	if _rope != null and _hauling:
		_update_rope()
	if _pose != null:
		var holding := violin_active()
		for c in [&"hand_l", &"hand_r"]:
			holding = holding or weight_of(c) > NEUTRAL_EPSILON
		_pose.neutral_active = holding
