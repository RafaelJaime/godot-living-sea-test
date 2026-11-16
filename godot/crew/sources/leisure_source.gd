class_name CrewLeisureSource
extends NpcJobSource
## Free time (C2.3): fishing, music, chart study, star gazing and a spot to talk. Few jobs, long ones, at a calm pace; nothing in a storm,
## fewer as the weather worsens. At night music and star gazing weigh more. Violin jobs need the `musician` tag and the chart table the
## `navigator` tag. Own seeded stream, so a seed reproduces the sequence exactly.

@export var min_gap_s := 40.0
@export var max_gap_s := 100.0
@export var max_open := 2
@export var pause_storm := 0.5

# kind, stations, day weight, night weight, required tag
const LEISURE: Array[Dictionary] = [
	{"kind": &"fishing_rail", "stations": [&"fishing_rail_0", &"fishing_rail_1"], "day": 1.0, "night": 0.2, "tag": ""},
	{"kind": &"violin_seat", "stations": [&"violin_seat"], "day": 0.5, "night": 1.6, "tag": "musician"},
	{"kind": &"chart_table", "stations": [&"chart_table"], "day": 0.6, "night": 0.4, "tag": "navigator"},
	{"kind": &"listen_spot", "stations": [&"listen_spot_0", &"listen_spot_1", &"listen_spot_2"], "day": 0.2, "night": 1.4, "tag": ""},
	{"kind": &"spyglass_post", "stations": [&"spyglass_post"], "day": 0.9, "night": 0.2, "tag": ""},
	{"kind": &"crows_nest", "stations": [&"crows_nest"], "day": 0.8, "night": 0.2, "tag": ""},
	{"kind": &"social_spot", "stations": [&"social_spot_0", &"social_spot_1"], "day": 0.6, "night": 0.6, "tag": ""},
]

var _next := -1.0
var _n := 0
var _done: Dictionary = {} # agent id -> finished free-time jobs, for fairness

func _init() -> void:
	source_id = &"leisure"
	poll_hz = 1.0

func _open_count() -> int:
	var n := 0
	for j in board.open_jobs():
		if j.source_id == source_id:
			n += 1
	return n

func _poll(world: Node, now: float) -> void:
	var w := world as NpcWorld
	var storm := float(w.inputs.get_value(&"storm", 0.0))
	if storm >= pause_storm:
		return
	var rng := w.rng_for(&"crew_leisure", &"post")
	if _next < 0.0:
		_next = now + rng.randf_range(min_gap_s * 0.5, max_gap_s)
	if now < _next:
		return
	if _open_count() >= max_open:
		_next = now + 10.0
		return
	var night := 1.0 - clampf(float(w.inputs.get_value(&"daylight", 1.0)) / 0.5, 0.0, 1.0)
	var total := 0.0
	var weights: Array[float] = []
	for e in LEISURE:
		var wt := lerpf(float(e["day"]), float(e["night"]), night)
		weights.append(wt)
		total += wt
	var r := rng.randf() * total
	var pick := 0
	for i in LEISURE.size():
		r -= weights[i]
		if r <= 0.0:
			pick = i
			break
	var e := LEISURE[pick]
	var stations: Array = e["stations"]
	_n += 1
	var j := NpcJob.new()
	j.id = StringName("leisure:%s:%d" % [e["kind"], _n])
	j.kind = e["kind"]
	j.station_id = stations[rng.randi() % stations.size()]
	j.priority = 0.3
	j.ttl_s = 180.0
	if String(e["tag"]) != "":
		j.required_tags = PackedStringArray([e["tag"]])
	var target := _least_served(w, String(e["tag"]), rng)
	if target != &"":
		j.required_tags.append(String(target)) # agents carry their own id as a tag (see build_crew_defs.gd): the job goes to the one with least free time so far
		j.payload = {"for": target}
	post_job(j, now)
	_next = now + (rng.randf_range(min_gap_s, max_gap_s)) * (1.0 + 3.0 * storm)

## The free agent (not holding a must-staff post) with the fewest finished free-time jobs that can take this kind; ties drawn with `rng`.
## &"" when nobody carries their own id as a tag (plain worlds, tests): then the job is open to anyone eligible.
func _least_served(w: NpcWorld, kind_tag: String, rng: NpcRng) -> StringName:
	var best: Array[StringName] = []
	var best_n := 1 << 30
	for id in w.agent_ids():
		var a := w.get_agent(id) as NpcAgent
		if a == null or not a.tags.has(String(id)):
			continue
		if kind_tag != "" and not a.tags.has(kind_tag):
			continue
		var cj := a.current_job()
		if cj != null and cj.override == &"must_staff":
			continue
		var n: int = _done.get(id, 0)
		if n < best_n:
			best_n = n
			best = [id]
		elif n == best_n:
			best.append(id)
	return best[rng.randi() % best.size()] if not best.is_empty() else &""

func _on_job_finished(job: NpcJob, agent: Node, result: StringName) -> void:
	if result == &"done":
		if agent is NpcAgent:
			_done[(agent as NpcAgent).agent_id] = int(_done.get((agent as NpcAgent).agent_id, 0)) + 1
		clear_job(job.id)
