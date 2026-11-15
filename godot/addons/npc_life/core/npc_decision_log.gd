class_name NpcDecisionLog
extends RefCounted
## Decision log and run metrics. One stable, diffable line per decision:
##   [npc] T=000123 agent=Papi_Fuego pick=helm:watch reason=roster top=[helm 2.10, mop 0.80, fish 0.55] temp=0.35 draw=17
## (T = logical tick, reason = override:emergency | override:all_hands | roster | softmax | ambient | forced, top = best candidates by kind,
## draw = the agent's RNG draw index). Two runs with the same seed and inputs produce byte-equal lines. Metrics are collected even when the
## text log is off.

## Off by default outside debug builds.
var enabled := OS.is_debug_build()
var max_lines := 4096
var decisions := 0

var _lines: PackedStringArray = PackedStringArray()
var _file: FileAccess
var _idle_max: Dictionary = {} # agent -> seconds
var _jobs_per_kind: Dictionary = {} # kind -> n
var _idle_failures := 0

func lines() -> PackedStringArray:
	return _lines

## Appends every new line to a file as well (flushed per line, so a crash keeps the log).
func open_file(path: String) -> bool:
	_file = FileAccess.open(path, FileAccess.WRITE)
	return _file != null

func close_file() -> void:
	_file = null

func log_decision(tick: int, agent_id: StringName, job: NpcJob, reason: StringName, top: Array, temperature: float, draw: int) -> void:
	decisions += 1
	if not enabled:
		return
	var parts := PackedStringArray()
	for row in top:
		parts.append("%s %.2f" % [(row["job"] as NpcJob).kind, float(row["score"])])
	_write("[npc] T=%06d agent=%s pick=%s reason=%s top=[%s] temp=%.2f draw=%d" % [tick, agent_id, job.id, reason, ", ".join(parts), temperature, draw])

## Edge type entered while walking (logged per traversal, in order).
func log_edge(tick: int, agent_id: StringName, edge_type: StringName) -> void:
	if enabled:
		_write("[npc] T=%06d agent=%s edge=%s" % [tick, agent_id, edge_type])

func write_line(line: String) -> void:
	if enabled:
		_write(line)

func _write(line: String) -> void:
	_lines.append(line)
	if _lines.size() > max_lines:
		_lines = _lines.slice(_lines.size() - max_lines)
	if _file:
		_file.store_line(line)
		_file.flush()

## One finished no-job gap of an agent (the time between losing a job and claiming the next). Over the bound it is a failure.
func record_idle(agent_id: StringName, idle_s: float, bound_s: float) -> void:
	_idle_max[agent_id] = maxf(_idle_max.get(agent_id, 0.0), idle_s)
	if idle_s > bound_s:
		_idle_failures += 1
		if enabled:
			_write("[npc] FAIL idle_bound agent=%s idle=%.1f bound=%.1f" % [agent_id, idle_s, bound_s])

## Folds in a running maximum (an agent that never got to decide) without counting a new failure episode.
func merge_idle_max(agent_id: StringName, idle_s: float) -> void:
	_idle_max[agent_id] = maxf(_idle_max.get(agent_id, 0.0), idle_s)

func record_done(_agent_id: StringName, kind: StringName) -> void:
	_jobs_per_kind[kind] = _jobs_per_kind.get(kind, 0) + 1

func summary() -> Dictionary:
	return {"idle_max": _idle_max, "jobs_per_kind": _jobs_per_kind, "idle_failures": _idle_failures, "decisions": decisions}

## A single block for the end of a headless run.
func summary_text() -> String:
	var ids := _idle_max.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var idle := PackedStringArray()
	for id in ids:
		idle.append("%s=%.1f" % [id, _idle_max[id]])
	var kinds := _jobs_per_kind.keys()
	kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var jobs := PackedStringArray()
	for k in kinds:
		jobs.append("%s=%d" % [k, _jobs_per_kind[k]])
	return "[npc] SUMMARY idle_max %s; jobs %s; idle_failures=%d decisions=%d" % [", ".join(idle), ", ".join(jobs), _idle_failures, decisions]
