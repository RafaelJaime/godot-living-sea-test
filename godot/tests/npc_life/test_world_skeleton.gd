extends GutTest
## NpcWorld skeleton: logical clock, registries, source polling and expiry (no decision logic yet).

class PollSource extends NpcJobSource:
	var polls := 0
	func _poll(_world: Node, now: float) -> void:
		polls += 1
		var j := NpcJob.new()
		j.id = &"p"
		j.ttl_s = 5.0
		post_job(j, now)

var world: NpcWorld

func before_each() -> void:
	world = NpcWorld.new()
	add_child_autofree(world)

func test_defaults_follow_the_design() -> void:
	assert_eq(world.decision_hz, 10.0)
	assert_eq(world.max_decisions_per_frame, 2)
	assert_eq(world.commit_time_s, 5.0)
	assert_eq(world.idle_bound_s, 20.0)
	assert_eq(world.softmax_temperature, 0.35)
	assert_not_null(world.inputs)
	assert_not_null(world.board)

func test_logical_clock_ticks_at_decision_hz() -> void:
	var ticks := [0] # lambdas capture locals by value: count through a container
	world.ticked.connect(func(_t: int) -> void: ticks[0] += 1)
	world.advance(0.35)
	assert_eq(world.tick_count, 3, "0.35 s at 10 Hz = 3 ticks")
	assert_eq(ticks[0], 3)
	assert_almost_eq(world.now(), 0.3, 1e-6, "now() is the logical clock: whole ticks only")

func test_clock_is_frame_rate_independent() -> void:
	var w2 := NpcWorld.new()
	add_child_autofree(w2)
	for i in 100:
		world.advance(0.01)
	for i in 10:
		w2.advance(0.1)
	assert_eq(world.tick_count, w2.tick_count)

func test_freeze_and_step() -> void:
	world.set_frozen(true)
	world.advance(1.0)
	assert_eq(world.tick_count, 0, "frozen: the clock does not run")
	world.step(4)
	assert_eq(world.tick_count, 4)
	world.set_frozen(false)
	world.advance(0.1)
	assert_eq(world.tick_count, 5)

func test_source_registration_and_polling() -> void:
	var src := PollSource.new()
	src.source_id = &"ps"
	src.poll_hz = 1.0
	world.add_child(src)
	world.advance(0.1)
	assert_eq(src.polls, 1, "child sources are registered and polled")
	assert_eq(world.board.open_jobs().size(), 1)
	world.advance(0.5)
	assert_eq(src.polls, 1, "poll_hz 1: not polled again within a second")
	world.advance(0.6)
	assert_eq(src.polls, 2)

func test_expiry_runs_each_tick() -> void:
	var j := NpcJob.new()
	j.id = &"short"
	j.ttl_s = 0.5
	world.board.post(j, world.now())
	world.advance(0.3)
	assert_eq(world.board.open_jobs().size(), 1)
	world.advance(0.3)
	assert_eq(world.board.open_jobs().size(), 0, "expired by the logical clock")

func test_agent_registry_sorted() -> void:
	var a := Node.new()
	var b := Node.new()
	world.register_agent(&"b", b)
	world.register_agent(&"a", a)
	assert_eq(world.agent_ids(), [&"a", &"b"] as Array[StringName])
	world.unregister_agent(&"a")
	assert_eq(world.agent_ids(), [&"b"] as Array[StringName])
	a.free()
	b.free()

func test_stations_from_group_scan() -> void:
	var st := NpcStation.new()
	st.station_id = &"s1"
	st.kind = &"helm"
	add_child_autofree(st)
	var found := world.get_stations()
	assert_eq(found.size(), 1)
	assert_eq(world.get_stations(&"helm").size(), 1)
	assert_eq(world.get_stations(&"mop").size(), 0)
