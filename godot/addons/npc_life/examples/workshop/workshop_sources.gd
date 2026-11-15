extends NpcJobSource
## Example job source: lamp jobs when the (example) daylight drops, craft and mend chores at random with jitter from its own seeded stream.
## Reads only the blackboard (`world.inputs`), never game state.

var _n := 0
var _next_chore := 0.0

func _poll(world: Node, now: float) -> void:
	var w := world as NpcWorld
	var daylight: float = w.inputs.get_value(&"daylight", 1.0)
	if daylight < 0.3:
		_post(&"lamp:1", &"lamp", &"lamp_post", 0.4, now) # lit at dusk: a job per lamp
	else:
		clear_job(&"lamp:1")
	if now >= _next_chore:
		var rng := w.rng_for(&"workshop_source", &"post")
		_n += 1
		var kind: StringName = [&"craft", &"mend"][rng.randi() % 2]
		_post(StringName("%s:%d" % [kind, _n]), kind, &"workbench" if kind == &"craft" else &"net_rack", rng.randf_range(0.0, 0.5), now)
		_next_chore = now + rng.randf_range(4.0, 12.0)

func _post(id: StringName, kind: StringName, station: StringName, priority: float, now: float) -> void:
	var j := NpcJob.new()
	j.id = id
	j.kind = kind
	j.station_id = station
	j.priority = priority
	j.ttl_s = 90.0
	post_job(j, now)

func _on_job_effect(job: NpcJob, agent: Node, effect: StringName) -> void:
	print("[workshop] ", (agent as NpcAgent).agent_id, " effect ", effect, " (", job.id, ")")

func _on_job_finished(job: NpcJob, _agent: Node, result: StringName) -> void:
	if result == &"done" and job.kind != &"lamp":
		clear_job(job.id) # a finished chore leaves the board; lamps stay while it is dark
