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

func _effect_at() -> float:
	return _action.effect_at if _action else 0.5

## Drops the current job without finishing it (the agent releases the claims).
func reset() -> void:
	navigator.set_path(PackedVector3Array(), [] as Array[StringName])
	_job = null
	_action = null
	_station = null
	phase = &""

func _set_phase(p: StringName) -> void:
	phase = p
	phase_changed.emit(p)
