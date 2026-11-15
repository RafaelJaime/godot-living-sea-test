class_name NpcJobExecutor
extends RefCounted
## Performs a claimed job as a small phase machine: MOVE (walk the platform-local graph to the station's approach point) -> ALIGN (turn to the
## station's facing) -> WORK (the action's duration; the world effect fires at `effect_at` of it) -> LEAVE (release the claims, tell the world).
## Jobs without a station start directly with WORK. All motion goes through `NpcNavigator` in platform-local space.

signal phase_changed(phase: StringName)

const ALIGN_TURN_RATE := 4.0 # rad/s
const ALIGN_MAX_S := 1.5

var agent: NpcAgent
var navigator := NpcNavigator.new()
var phase: StringName = &""

var _job: NpcJob
var _action: NpcActionDef
var _station: NpcStation
var _slot := 0
var _work_total := 0.0
var _work_done := 0.0
var _effect_fired := false
var _yaw_target := 0.0
var _align_t := 0.0
var _active_chains: Array[StringName] = []
var _look_set := false
var _props: Array[Node3D] = []

func _init(owner_agent: NpcAgent = null) -> void:
	agent = owner_agent

## Starts the job. `work_s` is the WORK duration drawn by the agent. Returns false when the station cannot be reached (nothing is started).
func start(job: NpcJob, station: NpcStation, work_s: float, action: NpcActionDef = null) -> bool:
	_job = job
	_action = action if action else (job.action as NpcActionDef)
	_station = station
	_work_total = maxf(work_s, 0.0)
	_work_done = 0.0
	_effect_fired = false
	_align_t = 0.0
	if station == null:
		_set_phase(&"work")
		return true
	var world := agent.world
	_slot = maxi(station.slot_of(agent), 0)
	var approach := station.approach_local(_slot, world.platform_root)
	_yaw_target = station.facing_local(_slot, world.platform_root)
	var pts := PackedVector3Array([agent.position])
	var types: Array[StringName] = []
	if world.graph != null and world.graph.node_count() > 0:
		var info := world.graph.path_info(agent.position, approach)
		if info["reason"] != &"":
			_job = null
			return false
		var nodes: PackedInt32Array = info["nodes"]
		for i in nodes.size():
			pts.append(world.graph.positions[nodes[i]])
			types.append(&"walk" if i == 0 else (info["edge_types"] as Array[StringName])[i - 1])
	pts.append(approach)
	types.append(&"walk")
	navigator.ground_probe = world.ground_probe
	navigator.set_path(pts, types)
	if agent.anim:
		agent.anim.set_locomotion(&"walk", agent.def.walk_speed if agent.def else 1.2)
	_set_phase(&"move")
	return true

## Per-frame update.
func update(delta: float) -> void:
	match phase:
		&"move":
			navigator.step(agent, delta, agent.def.walk_speed if agent.def else 1.2, agent.world.neighbors_of(agent))
			if navigator.finished:
				_set_phase(&"align")
		&"align":
			_align_t += delta
			agent.rotation.y = rotate_toward(agent.rotation.y, _yaw_target, ALIGN_TURN_RATE * delta)
			if absf(angle_difference(agent.rotation.y, _yaw_target)) < 0.02 or _align_t >= ALIGN_MAX_S:
				agent.rotation.y = _yaw_target
				_set_phase(&"work")
		&"work":
			_work_done += delta
			if not _effect_fired and _work_done >= _work_total * _effect_at():
				_effect_fired = true
				if _action and _action.effect != &"":
					agent.world.on_job_effect(agent, _job, _action.effect)
			if _work_done >= _work_total:
				_set_phase(&"leave")
				agent.complete_job(&"done")

## The action being performed (null when the job has none).
func current_action() -> NpcActionDef:
	return _action

func _effect_at() -> float:
	return _action.effect_at if _action else 0.5

## Makes sure at least `seconds` of WORK remain (a social offer keeps its initiator waiting).
func ensure_remaining(seconds: float) -> void:
	_work_total = maxf(_work_total, _work_done + seconds)

## Drops the current job without finishing it (the agent releases the claims).
func reset() -> void:
	_release_adapters()
	navigator.set_path(PackedVector3Array(), [] as Array[StringName])
	_job = null
	_action = null
	_station = null
	phase = &""

func _set_phase(p: StringName) -> void:
	phase = p
	match p:
		&"align":
			_engage_ik()
		&"work":
			_start_work_animation()
		&"leave":
			_release_adapters()
	phase_changed.emit(p)

## Reach and gaze from the station's IK targets (or the action's mapping chain -> station key). The live marker nodes are passed, never copies,
## so a station on a moving parent is re-read every frame by the adapter.
func _engage_ik() -> void:
	if agent.ik == null or _station == null:
		return
	var chains := {}
	if _action and not _action.ik.is_empty():
		for ch in _action.ik:
			chains[ch] = _action.ik[ch]
	else:
		for key in _station.ik_targets:
			if key != &"look_at":
				chains[key] = key
	for ch in chains:
		var t := _station.ik_target(chains[ch])
		if t != null:
			agent.ik.set_target(ch, t)
			_active_chains.append(ch)
	var look_key: StringName = _action.look_at if (_action and _action.look_at != &"") else (&"look_at" if _station.ik_targets.has(&"look_at") else &"")
	if look_key != &"" and look_key != &"partner" and look_key != &"performer":
		var lt := _station.ik_target(look_key)
		if lt != null:
			agent.ik.set_look_at(lt)
			_look_set = true

func _start_work_animation() -> void:
	if agent.ik != null and _active_chains.is_empty() and not _look_set:
		_engage_ik() # a job whose station has IK but no ALIGN phase
	if agent.anim == null:
		return
	var tag: StringName = _action.anim_tag if (_action and _action.anim_tag != &"") else (_station.anim_tag if _station else &"")
	if tag != &"":
		agent.anim.play(tag)
	if _action:
		for scene in _action.props:
			var p := agent.anim.attach_prop(scene, &"hand_r")
			if p != null:
				_props.append(p)

func _release_adapters() -> void:
	if agent == null:
		return
	if agent.ik != null:
		for ch in _active_chains:
			agent.ik.clear(ch)
		if _look_set:
			agent.ik.set_look_at(null)
	_active_chains.clear()
	_look_set = false
	for p in _props:
		if is_instance_valid(p):
			if p.is_inside_tree():
				p.queue_free()
			else:
				p.free()
	_props.clear()
	if agent.anim != null and phase != &"":
		agent.anim.play(&"idle")
