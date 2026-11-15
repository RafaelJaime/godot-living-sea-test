extends NpcJobSource
## Example job source: lamp jobs when the (example) daylight drops, craft and mend chores at random with jitter from its own seeded stream.
## Reads only the blackboard (`world.inputs`), never game state.

var _n := 0
var _next_chore := 0.0
## Demo mode (workshop.gd `--workshop-shots`): no chores, the fiddler plays at once, so captures catch the social scenes quickly.
var quiet := false
var no_play := false
var _next_play := 25.0
var _play_n := 0

func _poll(world: Node, now: float) -> void:
	var w := world as NpcWorld
	var daylight: float = w.inputs.get_value(&"daylight", 1.0)
	if daylight < 0.3:
		_post(&"lamp:1", &"lamp", &"lamp_post", 0.4, now) # lit at dusk: a job per lamp
	else:
		clear_job(&"lamp:1")
	if now >= _next_chore and not quiet:
		var rng := w.rng_for(&"workshop_source", &"post")
		_n += 1
		var kind: StringName = [&"craft", &"mend"][rng.randi() % 2]
		_post(StringName("%s:%d" % [kind, _n]), kind, &"workbench" if kind == &"craft" else &"net_rack", rng.randf_range(0.0, 0.5), now)
		_next_chore = now + rng.randf_range(14.0, 34.0)

	if quiet and not no_play and _next_play > 3.0:
		_next_play = 3.0
	if no_play:
		_next_play = INF
	if now >= _next_play and w.board.get_job(&"play:live") == null:
		var rng2 := w.rng_for(&"workshop_source", &"play")
		_play_n += 1
		var j := NpcJob.new()
		j.id = &"play:live"
		j.kind = &"play"
		j.station_id = &"fiddle_seat"
		j.priority = 0.8
		j.ttl_s = 60.0
		j.required_tags = PackedStringArray(["performer"])
		var act := NpcActionDef.new()
		act.action_id = &"play"
		act.anim_tag = &"work"
		act.duration_range = Vector2(25.0, 40.0)
		act.effect = &"played"
		j.action = act
		post_job(j, now)
		_next_play = now + rng2.randf_range(60.0, 100.0)

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
		clear_job(job.id)
	elif job.id == &"play:live":
		clear_job(job.id) # a finished chore leaves the board; lamps stay while it is dark
