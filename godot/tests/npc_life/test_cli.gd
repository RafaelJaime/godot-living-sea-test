extends GutTest
## Specs: npc-life-debug-tools (CLI flags, force-job pinned, freeze and step).

var world: NpcWorld

func before_each() -> void:
	world = NpcWorld.new()
	world.world_seed = 41
	add_child_autofree(world)

func _agent(id: StringName) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	var a := NpcAgent.new()
	a.def = d
	world.add_child(a)
	return a

func _job(id: StringName, kind: StringName, duration := 5.0, priority := 0.0) -> NpcJob:
	var j := NpcJob.new()
	j.id = id
	j.kind = kind
	j.priority = priority
	j.ttl_s = 0.0
	var act := NpcActionDef.new()
	act.duration_range = Vector2(duration, duration)
	j.action = act
	return j

func _run(seconds: float) -> void:
	for i in int(round(seconds / 0.1)):
		world.advance(0.1)

func test_parses_seed_log_minutes() -> void:
	var o := NpcCli.parse(PackedStringArray(["--npc-seed=5", "--npc-log=/tmp/x.log", "--npc-minutes=2.5", "--npc-debug", "--npc-force=Fuego:helm", "--npc-freeze", "--npc-step=3", "--npc-agents=40"]))
	assert_eq(o["seed"], 5)
	assert_eq(o["log"], "/tmp/x.log")
	assert_eq(o["minutes"], 2.5)
	assert_true(o["debug"])
	assert_eq(o["force"], [["Fuego", "helm"]])
	assert_true(o["freeze"])
	assert_eq(o["step"], 3)
	assert_eq(o["agents"], 40)
	var bare := NpcCli.parse(PackedStringArray(["--npc-log"]))
	assert_eq(bare["log"], "", "--npc-log alone enables the log without a file")
	assert_true(bare["log_enabled"])

func test_unknown_flag_ignored() -> void:
	var o := NpcCli.parse(PackedStringArray(["--quality=final", "--npc-bogus=1", "--npc-seed=9", "positional"]))
	assert_eq(o["seed"], 9)
	assert_false(o["debug"])
	assert_false(o["freeze"])
	assert_eq(o["force"], [])

func test_force_job_pins_next_pick_logged_forced() -> void:
	var a := _agent(&"A")
	world.board.post(_job(&"mop1", &"mop"), world.now())
	world.board.post(_job(&"fish1", &"fish", 5.0, 9.0), world.now()) # far better scored
	world.force_job(&"A", &"mop")
	_run(0.5)
	assert_eq(a.current_job_id(), &"mop1", "pinned: the better job is ignored")
	var lines := Array(world.decision_log.lines()).filter(func(l: String) -> bool: return l.contains("reason=forced"))
	assert_eq(lines.size(), 1, "logged as forced")

func test_force_keeps_the_kind_and_clearing_returns_to_normal() -> void:
	var a := _agent(&"A")
	var finished := []
	world.job_finished.connect(func(job: NpcJob, _id: StringName, r: StringName) -> void:
		finished.append(job.kind)
		world.board.clear(job.id))
	world.force_job(&"A", &"mop")
	world.board.post(_job(&"mop0", &"mop", 3.0), world.now())
	world.board.post(_job(&"fish1", &"fish", 5.0, 9.0), world.now())
	_run(1.0)
	assert_eq(a.current_job().kind, &"mop")
	for n in 6:
		world.board.post(_job(StringName("moprep%d" % n), &"mop", 3.0), world.now())
	_run(40.0)
	assert_true(finished.all(func(k: StringName) -> bool: return k == &"mop" or String(k).begins_with("ambient")), "only mop (or ambient fillers) while pinned: %s" % [finished])
	world.clear_force(&"A")
	_run(30.0)
	assert_true(finished.has(&"fish"), "back to normal decisions: the other job gets done")

func test_freeze_stops_clock() -> void:
	var a := _agent(&"A")
	world.board.post(_job(&"j", &"mop"), world.now())
	world.set_frozen(true)
	_run(5.0)
	assert_eq(world.tick_count, 0)
	assert_eq(a.current_job_id(), &"", "no decisions while frozen")

func test_step_advances_n_ticks_while_frozen() -> void:
	var a := _agent(&"A")
	world.board.post(_job(&"j", &"mop"), world.now())
	world.set_frozen(true)
	world.step(3)
	assert_eq(world.tick_count, 3, "exactly 3 ticks")
	assert_ne(a.current_job_id(), &"", "decisions happen during a step")
	_run(2.0)
	assert_eq(world.tick_count, 3, "frozen again after the step")

func test_world_applies_cli_options() -> void:
	var w := NpcWorld.new()
	w.apply_cli_options({"seed": 77, "freeze": true, "step": 2, "log_enabled": true, "force": [["A", "mop"]], "debug": false, "minutes": -1.0, "log": "", "agents": 0})
	add_child_autofree(w)
	assert_eq(w.world_seed, 77)
	assert_eq(w.tick_count, 2, "--npc-step=2 ran two ticks and the world stays frozen")

func test_force_does_not_pull_an_agent_off_a_watch() -> void:
	var a := _agent(&"A")
	var watch := _job(&"w", &"lookout", 1000.0)
	watch.override = &"must_staff"
	world.board.post(watch, world.now())
	_run(0.5)
	assert_eq(a.current_job_id(), &"w")
	world.board.post(_job(&"mop1", &"mop"), world.now())
	world.force_job(&"A", &"mop")
	_run(3.0)
	assert_eq(a.current_job_id(), &"w", "the pin waits: a watch (must-staff) is not abandoned for a debug pin")
