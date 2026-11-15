extends GutTest
## Specs: npc-life-schedules (roster and shifts, minimum staffing, skill-weighted rotation, emergency suspension).

var world: NpcWorld
var sched: NpcWatchScheduler

func before_each() -> void:
	world = NpcWorld.new()
	world.world_seed = 21
	add_child_autofree(world)

func _station(id: StringName, x: float) -> NpcStation:
	var s := NpcStation.new()
	s.station_id = id
	s.kind = id
	s.position = Vector3(x, 0, 0)
	s.approach_offset = Vector3.ZERO
	world.add_child(s)
	return s

func _agent(id: StringName, skills := {}) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	for k in skills:
		d.skills[k] = skills[k]
	var a := NpcAgent.new()
	a.def = d
	a.position = Vector3(-3, 0, 0)
	world.add_child(a)
	return a

func _watch(id: StringName, station: StringName, eligible: Array, shift := 20.0, lead := 8.0, max_consecutive := 3, keep := false) -> NpcWatchDef:
	var w := NpcWatchDef.new()
	w.watch_id = id
	w.station_id = station
	w.job_kind = id
	w.eligible = PackedStringArray(eligible)
	w.shift_s = shift
	w.handover_lead_s = lead
	w.max_consecutive = max_consecutive
	w.keep_during_emergency = keep
	return w

func _roster(watches: Array) -> NpcRoster:
	var r := NpcRoster.new()
	for w in watches:
		r.watches.append(w)
	return r

func _start(roster: NpcRoster) -> void:
	sched = NpcWatchScheduler.new()
	sched.source_id = &"roster"
	sched.roster = roster
	world.add_child(sched)

func _run(seconds: float) -> void:
	for i in int(round(seconds / 0.1)):
		world.advance(0.1)

func test_roster_validation_unknown_station() -> void:
	var r := _roster([_watch(&"helm", &"nowhere", [&"A", &"ghost"])])
	var v := r.validate(PackedStringArray(["helm_post"]), PackedStringArray(["A", "B"]))
	assert_eq(v.size(), 2)
	assert_true(v[0].contains("nowhere"), "names the unknown station")
	assert_true(v[1].contains("ghost"), "and the unknown agent")
	var w := _watch(&"helm", &"helm_post", [&"A"])
	w.min_staff = 0
	assert_gt(_roster([w]).validate(PackedStringArray(["helm_post"]), PackedStringArray(["A"])).size(), 0, "min staffing must be at least 1")

func test_must_staff_job_posted_per_watch() -> void:
	_station(&"helm_post", 4.0)
	_station(&"lookout_post", -4.0)
	_agent(&"A")
	_agent(&"B")
	_start(_roster([_watch(&"helm", &"helm_post", [&"A", &"B"]), _watch(&"lookout", &"lookout_post", [&"A", &"B"])]))
	world.step(1)
	for id in [&"helm", &"lookout"]:
		var jobs := world.board.open_jobs().filter(func(j: NpcJob) -> bool: return String(j.id).begins_with("%s:watch" % id))
		assert_eq(jobs.size(), 1, "one watch job per watch")
		assert_eq(jobs[0].override, &"must_staff")
		assert_eq(jobs[0].station_id, StringName("%s_post" % id))
		assert_eq(jobs[0].slots, 1)

func test_staffed_from_start() -> void:
	_station(&"helm_post", 4.0)
	_agent(&"A")
	_agent(&"B")
	_agent(&"C")
	_start(_roster([_watch(&"helm", &"helm_post", [&"A", &"B"], 60.0)]))
	world.step(1)
	var held := world.board.open_jobs().filter(func(j: NpcJob) -> bool: return String(j.id).begins_with("helm:watch") and j.claimed_by.size() == 1)
	assert_eq(held.size(), 1, "the first tick already has a keeper holding the watch")
	assert_true(held[0].claimed_by[0] in [&"A", &"B"], "an eligible agent")

func test_min_staffing_never_violated_during_handover() -> void:
	_station(&"helm_post", 4.0)
	_agent(&"A")
	_agent(&"B")
	_start(_roster([_watch(&"helm", &"helm_post", [&"A", &"B"], 20.0, 8.0, 1)]))
	_run(120.0)
	assert_gte(sched.handovers_done(&"helm"), 3, "several handovers in two minutes")
	assert_eq(sched.unstaffed_ticks(&"helm"), 0, "zero ticks below minimum staffing")
	assert_gte(sched.min_staffing_observed(&"helm"), 1)

func test_relief_overlaps_before_keeper_leaves() -> void:
	_station(&"helm_post", 4.0)
	_agent(&"A")
	_agent(&"B")
	_start(_roster([_watch(&"helm", &"helm_post", [&"A", &"B"], 20.0, 8.0, 1)]))
	_run(60.0)
	assert_gt(sched.overlap_ticks(&"helm"), 0, "the relief held the watch while the keeper still did")
	var log := Array(world.decision_log.lines())
	var handovers := log.filter(func(l: String) -> bool: return l.contains("[roster]") and l.contains("handover"))
	assert_gt(handovers.size(), 0)

func test_no_relief_extends_shift_logged() -> void:
	_station(&"helm_post", 4.0)
	_agent(&"A")
	# B is eligible by name but not part of the world: nobody can relieve A
	_start(_roster([_watch(&"helm", &"helm_post", [&"A", &"B"], 20.0, 8.0, 3)]))
	_run(45.0)
	var ext := Array(world.decision_log.lines()).filter(func(l: String) -> bool: return l.contains("extended_shift"))
	assert_gt(ext.size(), 0, "extended_shift is logged")
	assert_eq(sched.unstaffed_ticks(&"helm"), 0, "A stays on the station")

func test_single_eligible_agent_continues_without_gap() -> void:
	_station(&"helm_post", 4.0)
	_agent(&"A")
	_start(_roster([_watch(&"helm", &"helm_post", [&"A"], 15.0, 5.0, 1)]))
	_run(60.0)
	assert_eq(sched.unstaffed_ticks(&"helm"), 0)
	assert_eq(sched.keeper_of(&"helm"), &"A")

func test_rotation_share_skill_weighted() -> void:
	var w := _watch(&"helm", &"helm_post", [&"Fuego", &"Omar"], 60.0, 5.0, 3)
	var rng := NpcRng.new(NpcRng.seed_for(7, &"roster", &"helm"))
	var skills := {&"Fuego": 0.9, &"Omar": 0.5}
	var counts := {&"Fuego": 0, &"Omar": 0}
	var current: StringName = &""
	var consecutive := 0
	var worst_run := 0
	for i in 200:
		var next := NpcWatchScheduler.choose(w, [&"Fuego", &"Omar"] as Array[StringName], current, consecutive, func(id: StringName) -> float: return skills[id], rng)
		consecutive = consecutive + 1 if next == current else 1
		worst_run = maxi(worst_run, consecutive)
		current = next
		counts[next] += 1
	assert_gt(counts[&"Fuego"], counts[&"Omar"], "the higher skill holds more shifts")
	assert_gte(counts[&"Omar"], 1, "but not all of them")
	assert_lte(worst_run, 3, "no agent exceeds the maximum consecutive shifts")

func test_emergency_keeps_keep_during_emergency_watch() -> void:
	_station(&"helm_post", 4.0)
	_station(&"lookout_post", -4.0)
	_agent(&"Fuego", {&"helm": 0.9})
	_agent(&"Diag", {&"helm": 0.3})
	_agent(&"Omar", {&"helm": 0.3})
	_start(_roster([_watch(&"helm", &"helm_post", [&"Fuego", &"Diag", &"Omar"], 600.0, 8.0, 3, true), _watch(&"lookout", &"lookout_post", [&"Diag", &"Omar"], 600.0, 8.0, 3, false)]))
	_run(15.0)
	var ah := NpcJob.new()
	ah.id = &"reef:all"
	ah.kind = &"reef"
	ah.override = &"all_hands"
	ah.slots = 3
	ah.ttl_s = 0.0
	var act := NpcActionDef.new()
	act.duration_range = Vector2(40.0, 40.0)
	ah.action = act
	world.board.post(ah, world.now())
	_run(20.0)
	var helm_keeper := sched.keeper_of(&"helm")
	assert_ne(helm_keeper, &"")
	assert_eq(world.get_agent(helm_keeper).current_job().kind, &"helm", "the helm stays staffed during all-hands")
	var on_reef := 0
	for id in world.agent_ids():
		if world.get_agent(id).current_job_id() == &"reef:all":
			on_reef += 1
	assert_eq(on_reef, 2, "the other two agents took the all-hands job, the keeper kept the helm")
	assert_eq(sched.unstaffed_ticks(&"helm"), 0)

func test_captain_takes_helm_in_all_hands() -> void:
	_station(&"helm_post", 4.0)
	_agent(&"Fuego", {&"helm": 0.95})
	_agent(&"Omar", {&"helm": 0.2})
	var w := _watch(&"helm", &"helm_post", [&"Fuego", &"Omar"], 600.0, 8.0, 3, true)
	_start(_roster([w]))
	sched.force_keeper(&"helm", &"Omar") # the weak helmsman happens to be on watch when the alarm goes
	_run(10.0)
	assert_eq(sched.keeper_of(&"helm"), &"Omar")
	var ah := NpcJob.new()
	ah.id = &"storm"
	ah.kind = &"reef"
	ah.override = &"all_hands"
	ah.slots = 2
	ah.ttl_s = 0.0
	var act := NpcActionDef.new()
	act.duration_range = Vector2(60.0, 60.0)
	ah.action = act
	world.board.post(ah, world.now())
	_run(25.0)
	assert_eq(sched.keeper_of(&"helm"), &"Fuego", "the highest-skill agent takes the helm for the emergency")
	assert_eq(sched.unstaffed_ticks(&"helm"), 0, "without a staffing gap")
