class_name NpcTwoBoneIkAdapter
extends NpcIkAdapter
## Default IK adapter: one TwoBoneIK3D per hand chain (independent ramps) and a LookAtModifier3D for the gaze.
## Proven patterns of the original crew rig: targets go through a proxy pulled inside 93 percent of the arm's reach from the shoulder (a straight
## arm has an undefined elbow plane and flips), influence ramps in over 1.2 s, and every chain has an elbow POLE marker (TwoBoneIK3D silently does
## nothing without one, see odd/evidence/npc-crew-jobs/A0/ik_spike.md).

const REACH_CLAMP := 0.93

class Chain:
	var name: StringName
	var ik: TwoBoneIK3D
	var proxy: Node3D
	var pole: Node3D
	var shoulder_bone := -1
	var length := 0.0
	var source: Node3D
	var weight := 0.0
	var from := 0.0
	var goal := 0.0
	var elapsed := 0.0
	var dur := 1.0

var _agent: Node3D
var _sk: Skeleton3D
var _chains: Dictionary = {} # name -> Chain
var _look: LookAtModifier3D
var _look_target: Node3D
var _look_weight := 0.0
var _look_from := 0.0
var _look_goal := 0.0
var _look_elapsed := 0.0
var _look_dur := 1.0

func bind(agent: Node3D, skeleton: Skeleton3D, profile: NpcRigProfile) -> bool:
	if agent == null or skeleton == null or profile == null:
		return false
	_agent = agent
	_sk = skeleton
	var scale := skeleton.global_transform.basis.get_scale().x
	for cname in profile.chains:
		var bones: PackedStringArray = profile.chains[cname]
		if bones.size() != 3:
			continue
		var ids := [skeleton.find_bone(bones[0]), skeleton.find_bone(bones[1]), skeleton.find_bone(bones[2])]
		if ids.has(-1):
			push_warning("[npc_life] IK chain '%s': bone missing in the rig (%s)" % [cname, ", ".join(bones)])
			continue
		var c := Chain.new()
		c.name = cname
		c.shoulder_bone = ids[0]
		var a := skeleton.get_bone_global_rest(ids[0]).origin
		var b := skeleton.get_bone_global_rest(ids[1]).origin
		var h := skeleton.get_bone_global_rest(ids[2]).origin
		c.length = (a.distance_to(b) + b.distance_to(h)) * scale
		c.proxy = Node3D.new()
		c.proxy.name = "%sReachTarget" % cname
		c.proxy.top_level = true
		skeleton.add_child(c.proxy)
		c.pole = Marker3D.new()
		c.pole.name = "%sPole" % cname
		c.pole.position = profile.pole_offsets.get(cname, Vector3(0, 1.0, 0.25))
		agent.add_child(c.pole)
		c.ik = TwoBoneIK3D.new()
		c.ik.name = "%sIK" % cname
		c.ik.setting_count = 1
		skeleton.add_child(c.ik)
		c.ik.set_root_bone_name(0, bones[0])
		c.ik.set_middle_bone_name(0, bones[1])
		c.ik.set_end_bone_name(0, bones[2])
		c.ik.set_target_node(0, c.ik.get_path_to(c.proxy))
		c.ik.set_pole_node(0, c.ik.get_path_to(c.pole))
		c.ik.influence = 0.0
		c.proxy.global_position = skeleton.global_transform * skeleton.get_bone_global_pose(ids[2]).origin
		_chains[cname] = c
	if _chains.is_empty():
		return false
	if profile.look_bone != &"" and skeleton.find_bone(profile.look_bone) >= 0:
		_look = LookAtModifier3D.new()
		_look.name = "LookAt"
		_look.bone_name = profile.look_bone
		_look.influence = 0.0
		skeleton.add_child(_look)
	return true

# ---- queries (tests and debug tools) ---------------------------------------------------------------------------------------------------

func modifier_of(chain: StringName) -> SkeletonModifier3D:
	return (_chains[chain] as Chain).ik if _chains.has(chain) else null

func proxy_of(chain: StringName) -> Node3D:
	return (_chains[chain] as Chain).proxy if _chains.has(chain) else null

func weight_of(chain: StringName) -> float:
	return (_chains[chain] as Chain).weight if _chains.has(chain) else 0.0

func has_target(chain: StringName) -> bool:
	return _chains.has(chain) and (_chains[chain] as Chain).source != null

func look_target() -> Node3D:
	return _look_target

func look_weight() -> float:
	return _look_weight

# ---- control ---------------------------------------------------------------------------------------------------------------------------

func set_target(chain: StringName, target: Node3D, weight := 1.0, ramp_s := 1.2) -> void:
	if not _chains.has(chain):
		return
	var c := _chains[chain] as Chain
	c.source = target
	c.from = c.weight
	c.goal = weight
	c.elapsed = 0.0
	c.dur = maxf(ramp_s, 0.001)

func clear(chain: StringName, ramp_s := 0.5) -> void:
	if not _chains.has(chain):
		return
	var c := _chains[chain] as Chain
	c.from = c.weight
	c.goal = 0.0
	c.elapsed = 0.0
	c.dur = maxf(ramp_s, 0.001)

func set_look_at(target: Node3D, weight := 1.0) -> void:
	if _look == null:
		return
	if target != null:
		_look_target = target
		_look.set_target_node(_look.get_path_to(target))
	_look_from = _look_weight
	_look_goal = weight if target != null else 0.0
	_look_elapsed = 0.0
	_look_dur = 1.2

func process(delta: float) -> void:
	if _sk == null:
		return
	for c: Chain in _chains.values():
		if c.source != null and is_instance_valid(c.source):
			var shoulder := _sk.global_transform * _sk.get_bone_global_pose(c.shoulder_bone).origin
			var d := c.source.global_position - shoulder
			c.proxy.global_position = shoulder + d.limit_length(c.length * REACH_CLAMP)
		c.elapsed = minf(c.elapsed + delta, c.dur)
		c.weight = lerpf(c.from, c.goal, smoothstep(0.0, 1.0, c.elapsed / c.dur))
		if c.goal == 0.0 and c.elapsed >= c.dur:
			c.weight = 0.0
			c.source = null
		c.ik.influence = c.weight
	if _look != null:
		_look_elapsed = minf(_look_elapsed + delta, _look_dur)
		_look_weight = lerpf(_look_from, _look_goal, smoothstep(0.0, 1.0, _look_elapsed / _look_dur))
		if _look_goal == 0.0 and _look_elapsed >= _look_dur:
			_look_target = null
		_look.influence = _look_weight
