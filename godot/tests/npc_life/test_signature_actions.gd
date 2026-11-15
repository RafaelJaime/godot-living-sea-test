extends GutTest
## Spec npc-life-characters (Action cooldown): the agent picks one of its signature actions that matches the job, skips the ones cooling down,
## and falls back to the job kind default. Found missing while wiring the ship crew: the executor never consulted `signature_actions`.

var world: NpcWorld
var platform: Node3D
var started: Array[StringName] = []

func before_each() -> void:
	started = []
	platform = Node3D.new()
	add_child_autofree(platform)
	world = NpcWorld.new()
	world.world_seed = 9
	world.platform_root = platform
	platform.add_child(world)
	var g := NpcWaypointGraph.new()
	for i in 3:
		g.add_node(Vector3(i * 2.0, 0, 0))
		if i > 0:
			g.connect_nodes(i - 1, i, &"walk")
	world.graph = g
	world.job_finished.connect(func(job: NpcJob, _id: StringName, _r: StringName) -> void: world.board.clear(job.id))

func _station(kind: StringName) -> NpcStation:
	var s := NpcStation.new()
	s.station_id = &"post"
	s.kind = kind
	s.position = Vector3(4.0, 0, 0)
	s.approach_offset = Vector3.ZERO
	platform.add_child(s)
	return s

func _action(id: StringName, kinds: Array, cooldown := 0.0, station_kind := &"") -> NpcActionDef:
	var a := NpcActionDef.new()
	a.action_id = id
	a.job_kinds = PackedStringArray(kinds)
	a.duration_range = Vector2(1.0, 1.0)
	a.cooldown_s = cooldown
	a.station_kind = station_kind
	return a

func _agent(actions: Array) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = &"A"
	var typed: Array[NpcActionDef] = []
	for a in actions:
		typed.append(a)
	d.signature_actions = typed
	var ag := NpcAgent.new()
	ag.def = d
	ag.position = Vector3.ZERO
	platform.add_child(ag)
	return ag

func _job(id: StringName, kind: StringName) -> NpcJob:
	var j := NpcJob.new()
	j.id = id
	j.kind = kind
	j.station_id = &"post"
	j.ttl_s = 0.0
	return j

func _run(seconds: float) -> void:
	for i in int(round(seconds / 0.05)):
		world.advance(0.05)

func _action_of(a: NpcAgent) -> StringName:
	var act: NpcActionDef = a.executor.current_action()
	return act.action_id if act else &""

func test_matching_signature_action_is_used() -> void:
	_station(&"bench")
	var a := _agent([_action(&"hammer", ["mend"]), _action(&"sing", ["play"])])
	world.board.post(_job(&"j1", &"mend"), world.now())
	_run(0.5)
	assert_eq(_action_of(a), &"hammer", "the action whose job_kinds contain the job kind")

func test_station_kind_restricts_the_action() -> void:
	_station(&"bench")
	var a := _agent([_action(&"at_rail", ["mend"], 0.0, &"rail"), _action(&"at_bench", ["mend"], 0.0, &"bench")])
	world.board.post(_job(&"j1", &"mend"), world.now())
	_run(0.5)
	assert_eq(_action_of(a), &"at_bench", "only an action usable at this station kind")

func test_action_in_cooldown_is_excluded() -> void:
	_station(&"bench")
	var a := _agent([_action(&"hammer", ["mend"], 60.0), _action(&"patch", ["mend"])])
	world.board.post(_job(&"j1", &"mend"), world.now())
	_run(8.0)
	assert_eq(world.board.get_job(&"j1"), null, "first job done")
	var first := a.last_action_id()
	assert_ne(first, &"", "an action was used")
	var picks := {}
	for n in 6:
		world.board.post(_job(StringName("k%d" % n), &"mend"), world.now())
		_run(0.5)
		picks[_action_of(a)] = true
		_run(8.0)
	if first == &"hammer":
		assert_false(picks.has(&"hammer"), "hammer is cooling down for 60 s: never offered again in the next minute")
	assert_true(picks.has(&"patch") or first == &"patch", "the other action keeps being used")

func test_no_signature_match_falls_back_to_kind_default() -> void:
	_station(&"bench")
	var kd := NpcJobKindDef.new()
	kd.kind = &"mend"
	kd.default_action = _action(&"default_mend", ["mend"])
	world.kind_defs[&"mend"] = kd
	var a := _agent([_action(&"sing", ["play"])])
	world.board.post(_job(&"j1", &"mend"), world.now())
	_run(0.5)
	assert_eq(_action_of(a), &"default_mend")

func test_job_action_wins_over_signature() -> void:
	_station(&"bench")
	var a := _agent([_action(&"hammer", ["mend"])])
	var j := _job(&"j1", &"mend")
	j.action = _action(&"job_specific", ["mend"])
	world.board.post(j, world.now())
	_run(0.5)
	assert_eq(_action_of(a), &"job_specific")

func test_single_action_cooling_down_is_not_offered_again() -> void:
	var st := _station(&"bench")
	var a := _agent([_action(&"hammer", ["mend"], 60.0)])
	world.board.post(_job(&"j1", &"mend"), world.now())
	_run(0.5)
	assert_eq(_action_of(a), &"hammer", "first time it is ready")
	_run(10.0)
	assert_ne(a.current_job_id(), &"j1", "the first job is over")
	var next := _job(&"j2", &"mend")
	assert_null(a.call("_resolve_action", next, st, world.now()), "shortly after, it is still cooling down: no action")
	_run(70.0)
	var again: NpcActionDef = a.call("_resolve_action", next, st, world.now())
	assert_not_null(again, "after the cooldown it is back")
	if again:
		assert_eq(again.action_id, &"hammer")
