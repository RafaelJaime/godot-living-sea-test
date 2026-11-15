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
@export var graph: Resource ## NpcWaypointGraph (navigation slice)
## Station providers; empty = scan the group `npc_station`.
@export var station_providers: Array[NodePath] = []
@export var decision_hz := 10.0
@export var max_decisions_per_frame := 2
@export var commit_time_s := 5.0
@export var idle_bound_s := 20.0
@export var softmax_temperature := 0.35

var inputs := NpcWorldInputs.new()
var board := NpcJobBoard.new()
var decision_log: RefCounted ## NpcDecisionLog (decision slice)
var tick_count := 0

var _acc := 0.0
var _frozen := false
var _agents: Dictionary = {} # id -> Node
var _sources: Array[NpcJobSource] = []

func _ready() -> void:
	for c in get_children():
		_adopt(c)
	child_entered_tree.connect(_adopt)
	child_exiting_tree.connect(_forget)

func _adopt(n: Node) -> void:
	if n is NpcJobSource and not _sources.has(n):
		var s := n as NpcJobSource
		s.board = board
		_sources.append(s)
		_sources.sort_custom(func(a: NpcJobSource, b: NpcJobSource) -> bool: return String(a.source_id) < String(b.source_id))

func _forget(n: Node) -> void:
	if n is NpcJobSource:
		_sources.erase(n)

func _process(delta: float) -> void:
	advance(delta)

## Logical seconds: whole ticks only, independent of the frame rate.
func now() -> float:
	return float(tick_count) / decision_hz

## Accumulates `delta` and runs every logical tick that became due (does nothing while frozen).
func advance(delta: float) -> void:
	if _frozen:
		return
	_acc += delta
	var dt := 1.0 / decision_hz
	while _acc + 1.0e-9 >= dt:
		_acc -= dt
		_tick()

func set_frozen(frozen: bool) -> void:
	_frozen = frozen

## Runs `ticks` logical ticks regardless of the frame clock (meant for a frozen world).
func step(ticks := 1) -> void:
	for i in ticks:
		_tick()

func _tick() -> void:
	tick_count += 1
	var t := now()
	for s in _sources:
		s.poll_if_due(self, t)
	board.expire(t)
	ticked.emit(tick_count)

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
