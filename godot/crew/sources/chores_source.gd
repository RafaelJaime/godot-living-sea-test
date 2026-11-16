class_name CrewChoresSource
extends NpcJobSource
## Periodic chores (C2.2): mopping, repairs and the boat check, at a relaxed pace. The gap between chores is drawn with jitter from this
## source's own seeded stream (`rng_for(&"crew_chores")`), so the same seed repeats exactly and other seeds differ. At most `max_open` chore
## jobs exist at once. Nothing is posted during a storm (the storm source takes over). A soaked deck (`deck_wetness` on the blackboard,
## optional) makes mopping more likely.

@export var min_gap_s := 50.0
@export var max_gap_s := 130.0
@export var max_open := 2
@export var pause_storm := 0.5

const CHORES: Array[Dictionary] = [
	{"kind": &"mop_zone", "stations": [&"mop_zone_0", &"mop_zone_1"], "weight": 1.0},
	{"kind": &"repair_spot", "stations": [&"repair_spot_0", &"repair_spot_1"], "weight": 1.0},
	{"kind": &"boat_check", "stations": [&"boat_check"], "weight": 0.5},
]

var _next := -1.0
var _n := 0

func _init() -> void:
	source_id = &"chores"
	poll_hz = 1.0

func _open_count() -> int:
	var n := 0
	for j in board.open_jobs():
		if j.source_id == source_id:
			n += 1
	return n

func _poll(world: Node, now: float) -> void:
	var w := world as NpcWorld
	if float(w.inputs.get_value(&"storm", 0.0)) >= pause_storm:
		return
	var rng := w.rng_for(&"crew_chores", &"post")
	if _next < 0.0:
		_next = now + rng.randf_range(min_gap_s * 0.5, max_gap_s)
	if now < _next:
		return
	if _open_count() >= max_open:
		_next = now + 10.0
		return
	var wet := clampf(float(w.inputs.get_value(&"deck_wetness", 0.0)), 0.0, 1.0)
	var total := 0.0
	var weights: Array[float] = []
	for c in CHORES:
		var wt: float = c["weight"]
		if c["kind"] == &"mop_zone":
			wt += 6.0 * wet
		weights.append(wt)
		total += wt
	var r := rng.randf() * total
	var pick := 0
	for i in CHORES.size():
		r -= weights[i]
		if r <= 0.0:
			pick = i
			break
	var chore := CHORES[pick]
	var stations: Array = chore["stations"]
	_n += 1
	var j := NpcJob.new()
	j.id = StringName("chore:%s:%d" % [chore["kind"], _n])
	j.kind = chore["kind"]
	j.station_id = stations[rng.randi() % stations.size()]
	j.priority = 0.0
	j.ttl_s = 150.0
	post_job(j, now)
	_next = now + rng.randf_range(min_gap_s, max_gap_s)

func _on_job_finished(job: NpcJob, _agent: Node, result: StringName) -> void:
	if result == &"done":
		clear_job(job.id)
