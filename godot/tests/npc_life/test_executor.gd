extends GutTest
## Job executor phases (MOVE, ALIGN, WORK, LEAVE) with effect timing, release and abort, on a real world, graph and station.

var world: NpcWorld
var platform: Node3D
var phases: Array = []
var effects: Array = []
var finished: Array = []

func before_each() -> void:
	phases = []
	effects = []
	finished = []
	platform = Node3D.new()
	add_child_autofree(platform)
	world = NpcWorld.new()
	world.world_seed = 3
	world.platform_root = platform
	platform.add_child(world) # the world sits under the platform so agents and stations share its local space
	var g := NpcWaypointGraph.new()
	for i in 6:
		g.add_node(Vector3(i * 2.0, 0, 0)) # 0..10 m along x
		if i > 0:
			g.connect_nodes(i - 1, i, &"walk")
	world.graph = g
	world.job_effect.connect(func(job: NpcJob, id: StringName, eff: StringName) -> void: effects.append([world.now(), job.id, id, eff]))
	world.job_finished.connect(func(job: NpcJob, id: StringName, result: StringName) -> void:
		finished.append([job.id, id, result])
		world.board.clear(job.id)) # like a real source: a finished job leaves the board (otherwise it would simply be picked again)

func _station(id: StringName, x: float, facing := 90.0) -> NpcStation:
	var s := NpcStation.new()
	s.station_id = id
	s.kind = &"bench"
	s.position = Vector3(x, 0, 0)
	s.facing_deg = facing
	s.approach_offset = Vector3(0, 0, 0)
	platform.add_child(s)
	return s

func _agent(id: StringName) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	var a := NpcAgent.new()
	a.def = d
	platform.add_child(a)
	a.phase_changed.connect(func(p: StringName) -> void: phases.append([world.now(), p]))
	return a

func _job(id: StringName, station: StringName, work_s := 4.0, effect_at := 0.5) -> NpcJob:
	var j := NpcJob.new()
	j.id = id
	j.kind = &"light"
	j.station_id = station
	j.ttl_s = 0.0
	var act := NpcActionDef.new()
	act.action_id = &"light"
	act.duration_range = Vector2(work_s, work_s)
	act.effect_at = effect_at
	act.effect = &"light"
	j.action = act
	return j

func _run(seconds: float, dt := 0.05) -> void:
	for i in int(round(seconds / dt)):
		world.advance(dt)

func _phase_names() -> Array:
	return phases.map(func(p: Array) -> StringName: return p[1])

func test_phase_order() -> void:
	_station(&"s1", 10.0)
	var a := _agent(&"A")
	world.board.post(_job(&"j1", &"s1"), world.now())
	_run(20.0)
	var names := _phase_names()
	assert_eq(names.slice(0, 4), [&"move", &"align", &"work", &"leave"], "phases in order: %s" % [names])
	assert_eq(finished[0][2], &"done")
	assert_true(a.position.distance_to(Vector3(10, 0, 0)) < 0.1, "arrived at the station")

func test_effect_fires_at_fraction() -> void:
	_station(&"s1", 4.0)
	_agent(&"A")
	world.board.post(_job(&"j1", &"s1", 10.0, 0.5), world.now())
	_run(25.0)
	assert_eq(effects.size(), 1, "exactly one effect per job")
	assert_eq(effects[0][3], &"light")
	var work_start: float = phases.filter(func(p: Array) -> bool: return p[1] == &"work")[0][0]
	assert_almost_eq(effects[0][0] - work_start, 5.0, 0.25, "effect at 50 percent of a 10 s WORK phase")

func test_effect_reaches_the_source() -> void:
	var seen := []
	var src := LightSource.new()
	src.source_id = &"lamps"
	src.log_to = seen
	world.add_child(src)
	_station(&"s1", 2.0)
	_agent(&"A")
	world.step(1)
	_run(15.0)
	assert_eq(seen, [&"effect:light", &"finished:done"], "the job source gets the effect and the finish callbacks")

class LightSource extends NpcJobSource:
	var log_to: Array
	func _poll(_world: Node, now: float) -> void:
		if board.get_job(&"lamp:1") == null and log_to.is_empty(): # post once
			var j := NpcJob.new()
			j.id = &"lamp:1"
			j.kind = &"light"
			j.station_id = &"s1"
			j.ttl_s = 0.0
			var act := NpcActionDef.new()
			act.duration_range = Vector2(2.0, 2.0)
			act.effect = &"light"
			j.action = act
			post_job(j, now)
	func _on_job_effect(_job: NpcJob, _agent: Node, effect: StringName) -> void:
		log_to.append(StringName("effect:%s" % effect))
	func _on_job_finished(job: NpcJob, _agent: Node, result: StringName) -> void:
		log_to.append(StringName("finished:%s" % result))
		clear_job(job.id) # the source retires its own job

func test_release_on_leave() -> void:
	var st := _station(&"s1", 4.0)
	var a := _agent(&"A")
	world.board.post(_job(&"j1", &"s1", 3.0), world.now())
	_run(2.0)
	assert_false(st.is_free(), "the station is held while the agent walks to it")
	_run(12.0)
	assert_eq(finished[0][2], &"done")
	assert_true(st.is_free(), "released on leave")
	assert_eq(world.board.claimed_job_of(&"A"), &"", "board claim released too")
	assert_true(String(a.current_job_id()).begins_with("ambient:") or a.current_job_id() == &"", "free for the next decision")

func test_abort_releases_claim() -> void:
	var st := _station(&"s1", 10.0)
	var a := _agent(&"A")
	world.board.post(_job(&"j1", &"s1", 5.0), world.now())
	_run(2.0)
	assert_eq(a.current_job_id(), &"j1")
	a.abort_job()
	assert_true(st.is_free())
	assert_eq(world.board.claimed_job_of(&"A"), &"")
	assert_eq(finished[0][2], &"aborted")
	assert_eq(a.phase(), &"")

func test_unreachable_station_job_not_eligible() -> void:
	_station(&"far", 10.0)
	world.graph.add_node(Vector3(30, 0, 30)) # a node with no edges...
	_station(&"island", 30.0).position = Vector3(30, 0, 30) # ...holding the station
	_agent(&"A")
	world.board.post(_job(&"unreachable", &"island"), world.now())
	world.board.post(_job(&"ok", &"far"), world.now())
	_run(3.0)
	assert_false(world.board.get_job(&"unreachable").claimed_by.has(&"A"), "never claimed")
	assert_eq(world.get_agent(&"A").current_job_id(), &"ok", "picked the reachable job instead")

func test_job_without_station_just_works() -> void:
	_agent(&"A")
	world.board.post(_job(&"j1", &"", 2.0), world.now())
	_run(4.0)
	assert_eq(_phase_names().slice(0, 2), [&"work", &"leave"], "no station: no MOVE or ALIGN")
	assert_eq(finished[0][2], &"done")
