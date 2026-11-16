class_name NpcWorld
extends Node
## The coordinator: a node the game places in its scene (no autoload, no project settings). It owns the logical clock, the blackboard, the
## job board and the registries of agents and sources. Decisions run on fixed logical ticks so the same seed reproduces the same history.

signal ticked(tick: int)
signal agent_decided(agent_id: StringName, job: NpcJob, reason: StringName) ## reason: override:emergency|roster|commit|softmax|ambient|forced
signal job_effect(job: NpcJob, agent_id: StringName, effect: StringName)
signal job_finished(job: NpcJob, agent_id: StringName, result: StringName) ## done|aborted|expired|preempted

@export var world_seed := 0
## Local space for agents, stations and the graph (the ship pivot, a raft).
@export var platform_root: Node3D
@export var graph: NpcWaypointGraph
## Station providers; empty = scan the group `npc_station`.
@export var station_providers: Array[NodePath] = []
@export var decision_hz := 10.0
@export var max_decisions_per_frame := 2
@export var commit_time_s := 5.0
@export var idle_bound_s := 20.0
@export var softmax_temperature := 0.35

## Utility weights and per-kind defaults; a game tunes or fills them before agents decide.
var scorer := NpcUtilityScorer.new()
var kind_defs: Dictionary = {} # kind -> NpcJobKindDef
## Largest number of decisions made in one frame (a frame = one `advance()` / `step()` call); the stagger budget is `max_decisions_per_frame`.
var max_decisions_in_a_frame := 0
var inputs := NpcWorldInputs.new()
var board := NpcJobBoard.new()
var decision_log := NpcDecisionLog.new()
## Optional height correction for walking agents (see NpcGroundProbe).
var ground_probe: NpcGroundProbe
var tick_count := 0

var _rngs: Dictionary = {} # "agent|stream" -> NpcRng
static var _monitor_usec := 0.0
var _tick_usec_last := 0.0
var _perf_sum := 0.0
var _perf_n := 0
var _perf_max := 0.0
var _quit_after_s := -1.0
var _cli_applied := false
var _pending_debug := false
var _pending_freeze := false
var _pending_steps := 0
var _forced: Dictionary = {} # agent id -> kind
var _overlay: NpcDebugOverlay
var _requested: Array[StringName] = []
var _acc := 0.0
var _decisions_this_frame := 0
var _rr := 0
var _frozen := false
var _agents: Dictionary = {} # id -> Node
var _sources: Array[NpcJobSource] = []

func _enter_tree() -> void:
	add_to_group(&"npc_world")

func _ready() -> void:
	if not _cli_applied:
		apply_cli_options(NpcCli.parse(OS.get_cmdline_user_args()))
	if world_seed == 0:
		world_seed = int(Time.get_ticks_usec()) & 0x7fffffff # no seed given: generate one and announce it so the run can be replayed
		print("[npc] seed=%d (generated; replay with --npc-seed=%d)" % [world_seed, world_seed])
	else:
		print("[npc] seed=%d" % world_seed)
	decision_log.write_line("[npc] seed=%d" % world_seed)
	if graph != null:
		var problems := graph.validate()
		for p in problems:
			push_warning("[npc] graph: " + p)
		graph.build_distance_cache()
	if not Performance.has_custom_monitor(&"npc_life/tick_usec"):
		Performance.add_custom_monitor(&"npc_life/tick_usec", NpcWorld._monitor_value) # static: no instance reference to dangle at shutdown
	for c in get_children():
		_adopt(c)
	if _pending_debug:
		set_debug(true)
	for a in get_tree().get_nodes_in_group(&"npc_agent"): # agents that entered the tree before this world (they live under the platform)
		if a is NpcAgent and (a as NpcAgent).world == null:
			adopt_agent(a)
	child_entered_tree.connect(_adopt)
	child_exiting_tree.connect(_forget)
	board.job_released.connect(_on_board_released)
	_after_ready_options()

func _after_ready_options() -> void:
	if _pending_freeze:
		set_frozen(true)
	if _pending_steps > 0:
		step(_pending_steps)

## Binds an agent to this world and registers it (agents may live anywhere that shares the platform's local space).
func adopt_agent(a: NpcAgent) -> void:
	a.bind_world(self)
	register_agent(a.agent_id, a)

func _adopt(n: Node) -> void:
	if n is NpcAgent:
		adopt_agent(n)
		return
	if n is NpcJobSource and not _sources.has(n):
		var s := n as NpcJobSource
		s.board = board
		_sources.append(s)
		_sources.sort_custom(func(a: NpcJobSource, b: NpcJobSource) -> bool: return String(a.source_id) < String(b.source_id))

func _forget(n: Node) -> void:
	if n is NpcJobSource:
		_sources.erase(n)
	elif n is NpcAgent:
		_release_agent(n as NpcAgent)

func _release_agent(a: NpcAgent) -> void:
	if a.current_job() != null:
		a.end_job(&"aborted")
	unregister_agent(a.agent_id)

func _process(delta: float) -> void:
	advance(delta)

## The end-of-run summary block (folds in agents that never got to decide; sources may add a line through `summary_line()`).
func summary_text() -> String:
	for id in agent_ids():
		decision_log.merge_idle_max(id, (_agents[id] as NpcAgent).idle_max_s)
	var t := decision_log.summary_text()
	for s in _sources:
		if s.has_method("summary_line"):
			t += "\n" + s.summary_line()
	return t

static func _monitor_value() -> float:
	return NpcWorld._monitor_usec

## Logical seconds: whole ticks only, independent of the frame rate.
func now() -> float:
	return float(tick_count) / decision_hz

## Accumulates `delta` and runs every logical tick that became due (does nothing while frozen).
func advance(delta: float) -> void:
	if _frozen:
		return
	_decisions_this_frame = 0
	_acc += delta
	var dt := 1.0 / decision_hz
	while _acc + 1.0e-9 >= dt:
		_acc -= dt
		_tick()
	_frame_update(delta)
	max_decisions_in_a_frame = maxi(max_decisions_in_a_frame, _decisions_this_frame)

func set_frozen(frozen: bool) -> void:
	_frozen = frozen

## Runs `ticks` logical ticks regardless of the frame clock (meant for a frozen world).
func step(ticks := 1) -> void:
	_decisions_this_frame = 0
	for i in ticks:
		_tick()
		_frame_update(1.0 / decision_hz)
	max_decisions_in_a_frame = maxi(max_decisions_in_a_frame, _decisions_this_frame)

## Applies parsed `--npc-*` options (see NpcCli). Called by `_ready` with the real command line unless the game called it earlier with its own options.
func apply_cli_options(o: Dictionary) -> void:
	_cli_applied = true
	if int(o.get("seed", 0)) != 0:
		world_seed = int(o["seed"])
	if o.get("log_enabled", false):
		decision_log.enabled = true
		if String(o.get("log", "")) != "":
			decision_log.open_file(String(o["log"]))
	if float(o.get("minutes", -1.0)) >= 0.0:
		_quit_after_s = float(o["minutes"]) * 60.0
	for f in o.get("force", []):
		force_job(StringName(f[0]), StringName(f[1]))
	_pending_debug = bool(o.get("debug", false))
	_pending_freeze = bool(o.get("freeze", false))
	_pending_steps = int(o.get("step", 0))

## Pins an agent to a job kind (bypasses scoring; logged as `forced`) until `clear_force`.
func force_job(agent_id: StringName, kind: StringName) -> void:
	_forced[agent_id] = kind

func clear_force(agent_id: StringName) -> void:
	_forced.erase(agent_id)

func forced_kind(agent_id: StringName) -> StringName:
	return _forced.get(agent_id, &"")

## Debug overlay on or off. Off = no overlay node exists.
func set_debug(on: bool) -> void:
	if on and _overlay == null:
		_overlay = NpcDebugOverlay.new()
		_overlay.world = self
		_overlay.name = "NpcDebugOverlay"
		add_child(_overlay)
	elif not on and _overlay != null:
		_overlay.teardown()
		_overlay.queue_free()
		_overlay = null

func overlay() -> NpcDebugOverlay:
	return _overlay

func _tick() -> void:
	var t0 := Time.get_ticks_usec()
	tick_count += 1
	var t := now()
	for s in _sources:
		s.poll_if_due(self, t)
	board.expire(t)
	var dt := 1.0 / decision_hz
	var ids := agent_ids()
	for id in ids:
		(_agents[id] as NpcAgent).tick(dt)
	_run_decisions(ids)
	ticked.emit(tick_count)
	_tick_usec_last = float(Time.get_ticks_usec() - t0)
	NpcWorld._monitor_usec = _tick_usec_last
	_perf_sum += _tick_usec_last
	_perf_n += 1
	_perf_max = maxf(_perf_max, _tick_usec_last)
	if _quit_after_s >= 0.0 and t >= _quit_after_s:
		_finish_run()

func _finish_run() -> void:
	_quit_after_s = -1.0
	print(summary_text())
	print("[npc] max local position error=%.4f m (platform-local, all navigators)" % max_local_error())
	decision_log.write_line(summary_text())
	print("[npc] perf avg=%.0f usec max=%.0f usec over %d ticks (decisions/frame max=%d, budget %d, agents %d, monitor npc_life/tick_usec=%.0f)" % [_perf_sum / maxf(_perf_n, 1), _perf_max, _perf_n, max_decisions_in_a_frame, max_decisions_per_frame, _agents.size(), Performance.get_custom_monitor(&"npc_life/tick_usec")])
	print("[npc] overlay: %s, debug labels in the scene: %d" % ["on" if _overlay != null else "off", get_tree().root.find_children("NpcDebugLabel", "Label3D", true, false).size() if is_inside_tree() else 0])
	decision_log.close_file()
	if is_inside_tree():
		get_tree().call_deferred("quit")

func _frame_update(delta: float) -> void:
	for id in agent_ids():
		(_agents[id] as NpcAgent).frame_update(delta)

## Decisions of this tick, staggered: agents are visited round-robin in sorted id order and the frame budget caps how many decide.
func _run_decisions(ids: Array[StringName]) -> void:
	var n := ids.size()
	var last := -1
	# agents a roster asked to decide first (a keeper that must be on watch from the first tick)
	for rid in _requested:
		if _decisions_this_frame >= max_decisions_per_frame:
			break
		var ra := _agents.get(rid) as NpcAgent
		if ra != null and ra.needs_decision(self):
			ra.decide(self, now())
			_decisions_this_frame += 1
	_requested.clear()
	for k in n:
		if _decisions_this_frame >= max_decisions_per_frame:
			break
		var idx := (_rr + k) % n
		var a := _agents[ids[idx]] as NpcAgent
		if a.needs_decision(self):
			a.decide(self, now())
			_decisions_this_frame += 1
			last = idx
	if last >= 0:
		_rr = (last + 1) % n

## The persistent random stream of an agent (one per agent and stream name), seeded from (world_seed, agent_id, stream).
func rng_for(agent_id: StringName, stream := &"brain") -> NpcRng:
	var key := "%s|%s" % [agent_id, stream]
	var r: NpcRng = _rngs.get(key)
	if r == null:
		r = NpcRng.new(NpcRng.seed_for(world_seed, agent_id, stream))
		_rngs[key] = r
	return r

# ---- agent callbacks --------------------------------------------------------------------------------------------------------------------

func on_agent_decided(agent: NpcAgent, job: NpcJob, reason: StringName, top: Array, temp: float, draw: int, idle_before: float) -> void:
	var parts := PackedStringArray()
	for row in top:
		parts.append("%s %.2f" % [(row["job"] as NpcJob).kind, float(row["score"])])
	agent.last_decision = {"job": job.id, "reason": reason, "top": "top=[%s]" % ", ".join(parts)}
	decision_log.record_idle(agent.agent_id, idle_before, idle_bound_s)
	decision_log.log_decision(tick_count, agent.agent_id, job, reason, top, temp, draw)
	agent_decided.emit(agent.agent_id, job, reason)

## Asks for `agent_id` to decide before the round-robin of this tick (still inside the frame budget).
func request_decision(agent_id: StringName) -> void:
	if not _requested.has(agent_id):
		_requested.append(agent_id)

## Called by the executor when a job's WORK reached its effect moment: the world signal and the owning source's callback.
func on_job_effect(agent: NpcAgent, job: NpcJob, effect: StringName) -> void:
	for s in _sources:
		if s.source_id == job.source_id:
			s._on_job_effect(job, agent, effect)
	job_effect.emit(job, agent.agent_id, effect)

func on_edge_entered(agent: NpcAgent, edge_type: StringName) -> void:
	decision_log.log_edge(tick_count, agent.agent_id, edge_type)

func on_job_finished(agent: NpcAgent, job: NpcJob, result: StringName) -> void:
	if result == &"done" and not NpcAmbient.is_ambient(job):
		decision_log.record_done(agent.agent_id, job.kind)
	for s in _sources:
		if s.source_id == job.source_id:
			s._on_job_finished(job, agent, result)
	job_finished.emit(job, agent.agent_id, result)

func _on_board_released(job: NpcJob, agent_id: StringName) -> void:
	var a := get_agent(agent_id) as NpcAgent
	if a and a.current_job() == job and not a.is_ending():
		a.on_job_removed(job.end_reason)

func find_station(station_id: StringName) -> NpcStation:
	if station_id == &"" or not is_inside_tree():
		return null
	for st in get_stations():
		if st.station_id == station_id:
			return st
	return null

func nearest_station_tagged(agent: Node3D, tag: String) -> NpcStation:
	var best: NpcStation
	var bd := INF
	for st in get_stations():
		if st.tags.has(tag):
			var d := distance_to(agent, st)
			if d < bd:
				bd = d
				best = st
	return best

## Path distance from an agent to a station: graph distance (all-pairs cache) when a graph exists, straight line in platform space otherwise.
func distance_to(agent: Node3D, station: NpcStation) -> float:
	if station == null:
		return 0.0
	var from_local: Vector3 = NpcStation.relative_transform(platform_root, agent).origin if platform_root else agent.position
	var to_local := station.approach_local(0, platform_root)
	if graph != null and graph.node_count() > 0:
		var d := graph.distance(graph.nearest_node(from_local), graph.nearest_node(to_local))
		if d != INF:
			return d + from_local.distance_to(graph.positions[graph.nearest_node(from_local)]) + to_local.distance_to(graph.positions[graph.nearest_node(to_local)])
	return from_local.distance_to(to_local)

## False when the graph has no route from the agent to the station's approach point (the job is then not eligible).
func reachable_from(agent: Node3D, station: NpcStation) -> bool:
	if graph == null or graph.node_count() == 0 or station == null:
		return true
	return graph.path_info(agent.position, station.approach_local(0, platform_root))["reason"] == &""

## Other agents (for the navigator's courtesy), in sorted id order.
func neighbors_of(agent: Node3D) -> Array:
	var out := []
	for id in agent_ids():
		var o := _agents[id] as Node3D
		if o != agent:
			out.append(o)
	return out

## Largest local-position error any navigator logged (m).
func max_local_error() -> float:
	var m := 0.0
	for id in _agents:
		m = maxf(m, (_agents[id] as NpcAgent).executor.navigator.max_error)
	return m

# ---- registries -----------------------------------------------------------------------------------------------------------------------------

func register_agent(agent_id: StringName, agent: Node) -> void:
	_agents[agent_id] = agent

func unregister_agent(agent_id: StringName) -> void:
	_agents.erase(agent_id)

func get_agent(agent_id: StringName) -> Node:
	return _agents.get(agent_id)

## Agent ids in sorted order (the order decisions are processed in).
func agent_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in _agents.keys():
		ids.append(k)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids

## Stations of the providers (or of the `npc_station` group), optionally of one kind, sorted by id.
func get_stations(kind := &"") -> Array[NpcStation]:
	var out: Array[NpcStation] = []
	if station_providers.is_empty():
		if is_inside_tree():
			for n in get_tree().get_nodes_in_group(&"npc_station"):
				if n is NpcStation:
					out.append(n)
	else:
		for p in station_providers:
			var prov := get_node_or_null(p) as NpcStationProvider
			if prov:
				out.append_array(prov.provide_stations())
	if kind != &"":
		out = out.filter(func(s: NpcStation) -> bool: return s.kind == kind)
	out.sort_custom(func(a: NpcStation, b: NpcStation) -> bool: return String(a.station_id) < String(b.station_id))
	return out
