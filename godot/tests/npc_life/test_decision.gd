extends GutTest
## Specs: npc-life-utility-ai (hard overrides, never aimless, tick budget, commitment) with the logical clock stepped by hand.

var world: NpcWorld
var picks: Array = [] # [agent_id, job_id, reason]

func before_each() -> void:
	picks = []
	world = _make_world(1)

func _make_world(world_seed: int) -> NpcWorld:
	var w := NpcWorld.new()
	w.world_seed = world_seed
	add_child_autofree(w)
	w.agent_decided.connect(func(id: StringName, job: NpcJob, reason: StringName) -> void: picks.append([id, job.id, reason]))
	return w

func _agent(w: NpcWorld, id: StringName, tags := PackedStringArray()) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	d.tags = tags
	var a := NpcAgent.new()
	a.def = d
	w.add_child(a)
	return a

func _job(id: StringName, kind := &"chore", duration := 30.0, priority := 0.0) -> NpcJob:
	var j := NpcJob.new()
	j.id = id
	j.kind = kind
	j.priority = priority
	j.ttl_s = 0.0
	var act := NpcActionDef.new()
	act.action_id = kind
	act.duration_range = Vector2(duration, duration)
	j.action = act
	return j

func _run(w: NpcWorld, seconds: float) -> void:
	for i in int(round(seconds * 10.0)):
		w.advance(0.1)

func test_emergency_override_preempts_commitment() -> void:
	var a := _agent(world, &"A")
	world.board.post(_job(&"relax", &"fishing", 60.0), world.now())
	_run(world, 1.0)
	assert_eq(a.current_job_id(), &"relax")
	var em := _job(&"storm", &"reef", 20.0, 5.0)
	em.override = &"emergency"
	world.board.post(em, world.now())
	_run(world, 0.3)
	assert_eq(a.current_job_id(), &"storm", "claimed within a few decision ticks, committed or not")
	assert_eq(picks[picks.size() - 1][2], &"override:emergency")
	assert_eq(world.board.get_job(&"relax").claimed_by.size(), 0, "the relaxed job was released")

func test_must_staff_before_softmax() -> void:
	var a := _agent(world, &"A")
	world.board.post(_job(&"nice", &"fishing", 30.0, 9.0), world.now())
	var helm := _job(&"helm:watch", &"helm", 30.0)
	helm.override = &"must_staff"
	world.board.post(helm, world.now())
	_run(world, 0.3)
	assert_eq(a.current_job_id(), &"helm:watch", "must-staff beats a far better scored job")
	assert_eq(picks[0][2], &"roster")

func test_all_hands_all_agents_take_override() -> void:
	var ids := [&"A", &"B", &"C"]
	for id in ids:
		_agent(world, id)
	var j := _job(&"reef:all", &"reef", 20.0)
	j.override = &"all_hands"
	j.slots = 3
	world.board.post(j, world.now())
	_run(world, 1.0)
	for id in ids:
		assert_eq(world.get_agent(id).current_job_id(), &"reef:all")
	assert_eq(world.board.get_job(&"reef:all").claimed_by.size(), 3)

func test_commitment_window_keeps_job() -> void:
	var a := _agent(world, &"A")
	_run(world, 0.5)
	var amb: StringName = a.current_job_id()
	assert_true(String(amb).begins_with("ambient:"), "empty board: an ambient job")
	_run(world, 1.5)
	world.board.post(_job(&"real", &"mop", 30.0, 3.0), world.now())
	_run(world, 1.0)
	assert_eq(a.current_job_id(), amb, "a better job appeared at ~2 s: the agent keeps its job inside the 5 s commitment window")
	_run(world, 4.0)
	assert_eq(a.current_job_id(), &"real", "after the window the ambient job yields to the real one")

func test_committed_real_job_runs_to_completion() -> void:
	var a := _agent(world, &"A")
	world.board.post(_job(&"first", &"mop", 30.0), world.now())
	_run(world, 1.0)
	world.board.post(_job(&"better", &"fishing", 30.0, 50.0), world.now())
	_run(world, 12.0)
	assert_eq(a.current_job_id(), &"first", "a working agent is not pulled away by a better job")

func test_commit_ends_on_job_done() -> void:
	var a := _agent(world, &"A")
	world.board.post(_job(&"short", &"mop", 2.0), world.now())
	_run(world, 1.0)
	assert_eq(a.current_job_id(), &"short")
	world.board.post(_job(&"next", &"repair", 30.0), world.now())
	_run(world, 2.5)
	assert_eq(a.current_job_id(), &"next", "done at ~2 s: the agent re-decided before the 5 s window ended")

func test_ambient_when_board_empty() -> void:
	var a := _agent(world, &"A")
	_run(world, 0.5)
	assert_true(String(a.current_job_id()).begins_with("ambient:"))
	assert_eq(picks[0][2], &"ambient")

func test_idle_max_reported_when_decisions_starved() -> void:
	world.max_decisions_per_frame = 0
	var a := _agent(world, &"A")
	_run(world, 25.0)
	assert_gt(a.idle_max_s, world.idle_bound_s, "no decision for 25 s: idle_max exceeds the 20 s bound")
	world.max_decisions_per_frame = 2
	_run(world, 0.5)
	assert_ne(a.current_job_id(), &"")

func test_decisions_per_frame_capped_stagger() -> void:
	world.max_decisions_per_frame = 4
	for i in 40:
		_agent(world, StringName("n%02d" % i))
	var per_frame := []
	for f in 10:
		var before := picks.size()
		world.advance(0.1)
		per_frame.append(picks.size() - before)
	for n in per_frame:
		assert_lte(n, 4, "no frame processes more than the budget")
	assert_eq(picks.size(), 40, "every agent decided at least once within 10 frames")
	assert_eq(world.max_decisions_in_a_frame, 4)

func test_sorted_agent_order_deterministic() -> void:
	var first: Array
	var second: Array
	for order in [[&"A", &"B", &"C"], [&"C", &"A", &"B"]]:
		picks = []
		var w := _make_world(5)
		for id in order:
			_agent(w, id)
		for k in 6:
			w.board.post(_job(StringName("j%d" % k), &"chore", 8.0), w.now())
		_run(w, 30.0)
		if first.is_empty():
			first = picks.duplicate()
		else:
			second = picks.duplicate()
	assert_gt(first.size(), 5, "the run produced decisions to compare")
	assert_eq(first, second, "the same agents give the same decisions whatever order they were added in")
