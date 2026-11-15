class_name NpcAgent
extends Node3D
## One autonomous character: a brain that decides what to do on the world's logical ticks, and (from the navigation slice on) a navigator and
## executor that perform the job. Decision precedence: (1) emergency / all-hands overrides, (2) roster must-staff jobs, (3) commitment,
## (4) softmax over utility scores, (5) ambient fallback. Spatial state lives in the local space of the world's platform root.
##
## A claimed job is performed by the NpcJobExecutor (MOVE, ALIGN, WORK, LEAVE) per frame; WORK lasts a duration drawn from the action's
## range with the agent's `work` stream.

signal phase_changed(phase: StringName)

@export var def: NpcCharacterDef
## Optional explicit world; otherwise the agent finds the NpcWorld among its ancestors, or the only world in the scene (group `npc_world`).
@export var world_path: NodePath

var agent_id: StringName
var tags := PackedStringArray()
var world: NpcWorld
var needs: NpcNeeds
var idle_s := 0.0
var idle_max_s := 0.0

var _job: NpcJob
var _station: NpcStation
var executor: NpcJobExecutor
var _committed_until := 0.0
var _last_done: Dictionary = {} # kind -> logical time
var _last_station_id: StringName = &""
var _ambient_serial := 0
var _ending := false

func _enter_tree() -> void:
	add_to_group(&"npc_agent")
	if world == null:
		var w := _find_world()
		if w != null:
			w.adopt_agent(self)

func _find_world() -> NpcWorld:
	if not world_path.is_empty():
		return get_node_or_null(world_path) as NpcWorld
	var n := get_parent()
	while n != null:
		if n is NpcWorld:
			return n
		n = n.get_parent()
	for w in get_tree().get_nodes_in_group(&"npc_world"):
		return w as NpcWorld
	return null

func bind_world(w: NpcWorld) -> void:
	if world == w:
		return
	world = w
	executor = NpcJobExecutor.new(self)
	executor.phase_changed.connect(func(p: StringName) -> void: phase_changed.emit(p))
	executor.navigator.edge_entered.connect(func(t: StringName, _i: int) -> void: world.on_edge_entered(self, t))
	if def:
		agent_id = def.agent_id
		tags = def.all_tags()
		needs = NpcNeeds.new(def)
		if name == &"" or String(name).begins_with("@"):
			name = String(agent_id)

func current_job() -> NpcJob:
	return _job

func current_job_id() -> StringName:
	return _job.id if _job else &""

func current_station() -> NpcStation:
	return _station

func is_ending() -> bool:
	return _ending

## Hook for scripts that read skills through a station constraint (NpcStation.min_skill).
func skill_for(key: StringName) -> float:
	return def.skill_for(key) if def else 0.5

# ---- per-tick ------------------------------------------------------------------------------------------------------------------------------

## Advances needs and idle accounting by one logical tick.
func tick(dt: float) -> void:
	if needs:
		needs.advance(dt)
	if _job == null:
		idle_s += dt
		idle_max_s = maxf(idle_max_s, idle_s)

## Per-frame update: moves and works through the executor.
func frame_update(delta: float) -> void:
	if _job != null and executor != null:
		executor.update(delta)

func phase() -> StringName:
	return executor.phase if executor else &""

## Drops the current job as `aborted` (claims released).
func abort_job() -> void:
	end_job(&"aborted")

## True when this agent should run a decision now (the world applies the per-frame budget).
func needs_decision(w: NpcWorld) -> bool:
	if _job == null:
		return true
	var now := w.now()
	var holds_override := _job.override != &""
	if not holds_override and not w.board.candidates(agent_id, tags).filter(func(j: NpcJob) -> bool: return j.override == &"emergency" or j.override == &"all_hands").is_empty():
		return true
	if NpcAmbient.is_ambient(_job) and now >= _committed_until:
		return not w.board.candidates(agent_id, tags).is_empty()
	return false

# ---- decision ------------------------------------------------------------------------------------------------------------------------------

func decide(w: NpcWorld, now: float) -> void:
	var cands := w.board.candidates(agent_id, tags)
	var overrides: Array[NpcJob] = []
	var staffing: Array[NpcJob] = []
	var normal: Array[NpcJob] = []
	for j in cands:
		match j.override:
			&"emergency", &"all_hands":
				overrides.append(j)
			&"must_staff":
				staffing.append(j)
			_:
				normal.append(j)
	# 1. overrides bypass scoring and the commitment window
	if _job == null or _job.override == &"":
		for j in _by_priority(overrides):
			if _job != null:
				end_job(&"preempted")
			if _take(j, StringName("override:%s" % j.override), now, []):
				return
	# 2. roster: must-staff jobs before any scored pick
	if _job == null or NpcAmbient.is_ambient(_job):
		for j in _by_priority(staffing):
			if _job != null:
				end_job(&"preempted")
			if _take(j, &"roster", now, []):
				return
	# 3. commitment: an ambient job inside its window is kept (real jobs run to completion, only the timer ends them)
	if _job != null and now < _committed_until:
		return
	# 4. softmax over the utility scores of the eligible normal jobs
	if not normal.is_empty():
		if _job != null:
			end_job(&"preempted") # an ambient job yields (its window elapsed)
		var rng := w.rng_for(agent_id, &"brain")
		var pool := normal.duplicate()
		while not pool.is_empty():
			var scores := PackedFloat32Array()
			for j in pool:
				scores.append(_score(w, j, now))
			var temp := w.scorer.effective_temperature(w.softmax_temperature, def)
			var idx := w.scorer.softmax_pick(scores, temp, rng)
			var top := w.scorer.top_k(pool, scores, 3)
			var pick: NpcJob = pool[idx]
			if _take(pick, &"softmax", now, top, temp, rng.draws):
				return
			pool.remove_at(idx) # its station was taken in the meantime: try the others
	# 5. ambient fallback: never aimless
	if _job == null:
		_take_ambient(w, now)

func _by_priority(jobs: Array[NpcJob]) -> Array[NpcJob]:
	var out := jobs.duplicate()
	out.sort_custom(func(a: NpcJob, b: NpcJob) -> bool:
		if a.priority != b.priority:
			return a.priority > b.priority
		return String(a.id) < String(b.id))
	return out

func _score(w: NpcWorld, j: NpcJob, now: float) -> float:
	var c := NpcUtilityScorer.Ctx.new()
	c.job = j
	c.kind_def = w.kind_defs.get(j.kind)
	c.def = def
	c.needs = needs
	c.agent_tags = tags
	var st := w.find_station(j.station_id)
	c.distance = w.distance_to(self, st) if st else 0.0
	c.urgency = w.board.urgency_of(j, now)
	c.since_done_s = (now - float(_last_done[j.kind])) if _last_done.has(j.kind) else -1.0
	return w.scorer.score(c)

func _take(j: NpcJob, reason: StringName, now: float, top: Array, temp := 0.0, draw := 0) -> bool:
	var st := _station_for(j)
	if st != null and not world.reachable_from(self, st):
		return false # unreachable on the waypoint graph: not eligible, the caller picks another
	if st != null and st.claim(self, -1, tags) < 0:
		return false
	if not world.board.claim(j.id, agent_id, tags):
		if st != null:
			st.release(self)
		return false
	_begin(j, st, reason, now, top, temp, draw)
	return true

func _station_for(j: NpcJob) -> NpcStation:
	return world.find_station(j.station_id) if j.station_id != &"" else null

func _take_ambient(w: NpcWorld, now: float) -> void:
	_ambient_serial += 1
	var amb_station: NpcStation = w.nearest_station_tagged(self, &"ambient_ok")
	var j := NpcAmbient.make(agent_id, _ambient_serial, _last_station_id, amb_station.station_id if amb_station else &"", w.rng_for(agent_id, &"ambient"))
	_begin(j, null, &"ambient", now, [], 0.0, 0)

func _begin(j: NpcJob, st: NpcStation, reason: StringName, now: float, top: Array, temp: float, draw: int) -> void:
	_job = j
	_station = st
	if st:
		_last_station_id = st.station_id
	elif j.station_id != &"":
		_last_station_id = j.station_id
	_committed_until = now if j.override != &"" else now + world.commit_time_s
	var act: NpcActionDef = j.action
	if act == null:
		var kd: NpcJobKindDef = world.kind_defs.get(j.kind)
		act = kd.default_action as NpcActionDef if kd else null
	var dr := act.duration_range if act else Vector2(6.0, 14.0)
	var work_s := world.rng_for(agent_id, &"work").randf_range(dr.x, maxf(dr.y, dr.x))
	idle_max_s = maxf(idle_max_s, idle_s)
	var idle_before := idle_s
	idle_s = 0.0
	executor.start(j, st, work_s, act)
	world.on_agent_decided(self, j, reason, top, temp, draw, idle_before)

# ---- ending --------------------------------------------------------------------------------------------------------------------------------

## Finishes the current job as `done` (or `aborted`): satisfies needs, records the recency, releases the claims.
func complete_job(result: StringName) -> void:
	if _job == null:
		return
	var j := _job
	if result == &"done":
		_last_done[j.kind] = world.now()
		var kd: NpcJobKindDef = world.kind_defs.get(j.kind)
		if kd and kd.satisfies != &"" and needs:
			needs.satisfy(kd.satisfies, kd.satisfy_amount)
	end_job(result)

## Releases the current job with `result` (done | aborted | expired | preempted) and tells the world and the job's source.
func end_job(result: StringName) -> void:
	if _job == null:
		return
	var j := _job
	_ending = true
	executor.reset()
	if _station:
		_station.release(self)
		_station = null
	world.board.release(j.id, agent_id)
	_job = null
	_ending = false
	world.on_job_finished(self, j, result)

## The board removed the job under this agent (expired or cleared): end it without double-releasing.
func on_job_removed(reason: StringName) -> void:
	if _job == null:
		return
	var j := _job
	executor.reset()
	if _station:
		_station.release(self)
		_station = null
	_job = null
	world.on_job_finished(self, j, &"expired" if reason == &"expired" else &"aborted")

func _exit_tree() -> void:
	if world:
		world._release_agent(self)
		world = null
