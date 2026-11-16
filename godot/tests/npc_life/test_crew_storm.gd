extends GutTest
## Spec ship-crew-job-sources (C3): storm all-hands (furl aloft, capped climbers), maneuver jobs, release.

class FakeRig extends Node:
	var furls: Array = []
	var braces: Array = []
	func sail_count() -> int:
		return 4
	func request_furl(idx: int, t: float) -> void:
		furls.append([idx, t])
	func request_brace(mast: int, angle: float) -> void:
		braces.append([mast, angle])

var world: NpcWorld
var rig: FakeRig

func _world(aloft := false, brace := false) -> void:
	world = NpcWorld.new()
	world.world_seed = 3
	add_child_autofree(world)
	for i in 4:
		_station(StringName("reef_line_%d" % i), &"reef_line")
		if aloft:
			_station(StringName("yard_aloft_%d" % i), &"yard_aloft")
	if brace:
		for m in 3:
			_station(StringName("brace_%d" % m), &"brace")
	rig = FakeRig.new()
	add_child_autofree(rig)

func _station(id: StringName, kind: StringName) -> NpcStation:
	var s := NpcStation.new()
	s.station_id = id
	s.kind = kind
	s.approach_offset = Vector3.ZERO
	world.add_child(s)
	return s

func _storm() -> CrewStormSource:
	var s := CrewStormSource.new()
	s.rig = rig
	world.add_child(s)
	return s

func _tick(n := 12) -> void:
	for i in n:
		world.advance(0.5)

func _jobs(prefix: String) -> Array:
	return world.board.open_jobs().filter(func(j: NpcJob) -> bool: return String(j.id).begins_with(prefix))

func test_calm_posts_nothing() -> void:
	_world()
	_storm()
	world.inputs.set_value(&"storm", 0.2)
	_tick()
	assert_eq(world.board.open_jobs().size(), 0)

func test_storm_posts_an_all_hands_job_per_sail_on_deck_without_aloft_stations() -> void:
	_world()
	_storm()
	world.inputs.set_value(&"storm", 0.9)
	_tick()
	var jobs := _jobs("storm:")
	assert_eq(jobs.size(), 4, "one per sail")
	for j in jobs:
		assert_eq(j.override, &"all_hands")
		assert_true(String(j.station_id).begins_with("reef_line_"), "falls back to the deck reef line")

func test_aloft_stations_are_used_and_capped() -> void:
	_world(true)
	var s := _storm()
	s.max_aloft = 2
	world.inputs.set_value(&"storm", 0.9)
	_tick()
	var aloft := _jobs("storm:").filter(func(j: NpcJob) -> bool: return String(j.station_id).begins_with("yard_aloft_"))
	assert_eq(aloft.size(), 2, "at most two climbers at once")
	s._on_job_finished(aloft[0], null, &"done")
	_tick()
	var again := _jobs("storm:").filter(func(j: NpcJob) -> bool: return String(j.station_id).begins_with("yard_aloft_"))
	assert_eq(again.size(), 2, "the next sail goes up when one comes down")

func test_effect_furls_the_sail_through_the_rig() -> void:
	_world()
	var s := _storm()
	world.inputs.set_value(&"storm", 0.9)
	_tick()
	var j := _jobs("storm:")[0] as NpcJob
	s._on_job_effect(j, null, &"furl")
	assert_eq(rig.furls.size(), 1)
	assert_eq(rig.furls[0][0], int(j.payload["sail"]))
	assert_eq(rig.furls[0][1], 1.0)

func test_storm_end_clears_jobs_and_unfurls() -> void:
	_world()
	var s := _storm()
	world.inputs.set_value(&"storm", 0.9)
	_tick()
	for j in _jobs("storm:"):
		s._on_job_effect(j, null, &"furl")
	world.inputs.set_value(&"storm", 0.1)
	_tick()
	assert_eq(_jobs("storm:").size(), 0, "storm jobs gone")
	var up := _jobs("unfurl:")
	assert_eq(up.size(), 4, "sails the crew furled are set again")
	assert_eq(up[0].override, &"", "calm work, not all-hands")

func test_hysteresis_keeps_the_all_hands_between_thresholds() -> void:
	_world()
	_storm()
	world.inputs.set_value(&"storm", 0.9)
	_tick()
	world.inputs.set_value(&"storm", 0.55)
	_tick()
	assert_eq(_jobs("storm:").size(), 4, "between the release and the trigger value it stays on")

func test_maneuver_posts_brace_jobs_and_clears_them() -> void:
	_world(false, true)
	var m := CrewManeuverSource.new()
	m.rig = rig
	world.add_child(m)
	world.inputs.set_value(&"maneuver", &"tack")
	world.inputs.set_value(&"maneuver_side", 1)
	_tick(4)
	var jobs := _jobs("maneuver:")
	assert_gte(jobs.size(), 1, "at least one job within 2 s")
	assert_eq(jobs[0].kind, &"brace")
	m._on_job_effect(jobs[0], null, &"brace")
	assert_eq(rig.braces.size(), 1, "the brace goes through the rig")
	world.inputs.set_value(&"maneuver", &"")
	_tick(4)
	assert_eq(_jobs("maneuver:").size(), 0, "cleared at maneuver_ended")

func test_maneuver_without_brace_stations_falls_back_to_reef_lines() -> void:
	_world()
	var m := CrewManeuverSource.new()
	m.rig = rig
	world.add_child(m)
	world.inputs.set_value(&"maneuver", &"jibe")
	_tick(4)
	assert_gte(_jobs("maneuver:").size(), 1)
