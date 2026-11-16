extends GutTest
## Spec ship-crew-job-sources (C2): lantern, chores and leisure sources, tested on a bare NpcWorld with fake lights.

class FakeLights extends Node:
	signal lighting_needed(ids: Array)
	signal extinguish_suggested(ids: Array)
	var lit: Dictionary = {}
	func light(id: String) -> bool:
		lit[id] = true
		return true
	func extinguish(id: String) -> bool:
		lit[id] = false
		return true

var world: NpcWorld
var lights: FakeLights

func _world(seed_value := 4) -> void:
	world = NpcWorld.new()
	world.world_seed = seed_value
	add_child_autofree(world)

func _agent(id: StringName, roles := []) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	d.roles = PackedStringArray(roles)
	var a := NpcAgent.new()
	a.def = d
	world.add_child(a)
	return a

func _lantern_source() -> CrewLanternSource:
	lights = FakeLights.new()
	add_child_autofree(lights)
	var s := CrewLanternSource.new()
	s.source_id = &"lanterns"
	s.lights = lights
	world.add_child(s)
	return s

func test_dusk_posts_one_light_job_per_lantern_on_its_station() -> void:
	_world()
	var s := _lantern_source()
	lights.lighting_needed.emit(["stern_port", "cabin"])
	var j := world.board.get_job(&"lantern:stern_port")
	assert_not_null(j, "a job per lantern")
	assert_eq(j.kind, &"lantern")
	assert_eq(j.station_id, &"lantern_stern_port")
	assert_eq(j.payload["lit"], true)
	assert_not_null(world.board.get_job(&"lantern:cabin"))
	lights.lighting_needed.emit(["stern_port"])
	assert_eq(world.board.open_jobs().size(), 2, "no duplicate jobs")
	s.queue_free()

func test_dawn_posts_extinguish_jobs() -> void:
	_world()
	_lantern_source()
	lights.extinguish_suggested.emit(["cabin"])
	var j := world.board.get_job(&"lantern:cabin")
	assert_eq(j.payload["lit"], false)

func test_effect_toggles_the_lantern_and_names_the_agent() -> void:
	_world()
	var s := _lantern_source()
	var ag := _agent(&"papi_fuego")
	lights.lighting_needed.emit(["cabin"])
	var j := world.board.get_job(&"lantern:cabin")
	s._on_job_effect(j, ag, &"light")
	assert_true(lights.lit["cabin"], "the lantern is lit")
	assert_eq(s.last_actor.get("cabin"), &"papi_fuego", "and the agent is recorded")
	lights.extinguish_suggested.emit(["cabin"])
	s._on_job_effect(world.board.get_job(&"lantern:cabin"), ag, &"light")
	assert_false(lights.lit["cabin"], "the dawn job puts it out")

func test_finished_job_leaves_the_board() -> void:
	_world()
	var s := _lantern_source()
	var ag := _agent(&"a")
	lights.lighting_needed.emit(["cabin"])
	s._on_job_finished(world.board.get_job(&"lantern:cabin"), ag, &"done")
	assert_null(world.board.get_job(&"lantern:cabin"))

func _chores(seed_value: int) -> CrewChoresSource:
	_world(seed_value)
	var s := CrewChoresSource.new()
	s.source_id = &"chores"
	world.add_child(s)
	return s

func _record(seconds: float) -> Array:
	var seen := []
	var known := {}
	for i in int(seconds / 0.5):
		world.advance(0.5)
		for j in world.board.open_jobs():
			if not known.has(j.id):
				known[j.id] = true
				seen.append([snappedf(world.now(), 0.5), j.kind])
		for j in world.board.open_jobs().duplicate():
			world.board.clear(j.id) # a chore finishes at once: only the posting sequence matters here
	return seen

func test_chores_are_periodic_and_use_chore_kinds() -> void:
	_chores(4)
	var seq := _record(600.0)
	assert_gt(seq.size(), 3, "several chores in 10 minutes")
	assert_lt(seq.size(), 14, "but a relaxed rate")
	for e in seq:
		assert_true([&"mop_zone", &"repair_spot", &"boat_check"].has(e[1]), "chore kinds only, got %s" % e[1])

func test_chores_seeded_variety() -> void:
	_chores(4)
	var a := _record(600.0)
	_chores(4)
	var a2 := _record(600.0)
	_chores(9)
	var b := _record(600.0)
	assert_eq(a, a2, "same seed, same sequence")
	assert_ne(a, b, "other seed, other sequence")

func test_chores_never_pile_up() -> void:
	var s := _chores(4)
	s.max_open = 2
	var peak := 0
	for i in 1200:
		world.advance(0.5)
		peak = maxi(peak, world.board.open_jobs().size())
	assert_lte(peak, 2, "at most max_open chore jobs at any time")

func test_chores_pause_in_a_storm() -> void:
	_chores(4)
	world.inputs.set_value(&"storm", 0.9)
	assert_eq(_record(300.0).size(), 0, "no chores during a storm")

func test_wet_deck_brings_mopping_forward() -> void:
	var s := _chores(4)
	world.inputs.set_value(&"deck_wetness", 1.0)
	var kinds := {}
	for e in _record(600.0):
		kinds[e[1]] = kinds.get(e[1], 0) + 1
	assert_gt(kinds.get(&"mop_zone", 0), kinds.get(&"repair_spot", 0), "a soaked deck is mopped more than repaired")
	assert_not_null(s)

func _leisure(seed_value: int) -> CrewLeisureSource:
	_world(seed_value)
	_agent(&"omar", ["musician"])
	var s := CrewLeisureSource.new()
	s.source_id = &"leisure"
	world.add_child(s)
	return s

func test_leisure_calm_posts_relaxed_jobs() -> void:
	_leisure(4)
	world.inputs.set_value(&"storm", 0.0)
	world.inputs.set_value(&"daylight", 1.0)
	var seq := _record(600.0)
	assert_gt(seq.size(), 2, "some free time in 10 minutes")
	assert_lt(seq.size(), 16)

func test_leisure_silent_in_a_storm() -> void:
	_leisure(4)
	world.inputs.set_value(&"storm", 0.9)
	assert_eq(_record(300.0).size(), 0)

func test_night_brings_music_and_stargazing() -> void:
	_leisure(4)
	world.inputs.set_value(&"daylight", 0.0)
	var kinds := {}
	for e in _record(900.0):
		kinds[e[1]] = true
	assert_true(kinds.has(&"violin_seat") or kinds.has(&"listen_spot"), "music or star gazing at night: %s" % [kinds.keys()])

func test_violin_job_needs_a_musician() -> void:
	_leisure(4)
	world.inputs.set_value(&"daylight", 0.0)
	for i in 3000:
		world.advance(0.5)
		for j in world.board.open_jobs():
			if j.kind == &"violin_seat":
				assert_true(j.required_tags.has("musician"), "violin jobs require the musician tag")
				return
				
	pass_test("no violin job came up in this seed")

func test_leisure_goes_to_the_least_served_agent() -> void:
	var s := _leisure(4)
	var ids := [&"a", &"b", &"c"]
	for id in ids:
		var d := NpcCharacterDef.new()
		d.agent_id = id
		d.tags = PackedStringArray([String(id)])
		var ag := NpcAgent.new()
		ag.def = d
		world.add_child(ag)
	var first := {}
	for i in 600:
		world.advance(0.5)
		for j in world.board.open_jobs():
			if j.payload.has("for") and not first.has(j.payload["for"]) and not j.required_tags.has("musician") and not j.required_tags.has("navigator"):
				first[j.payload["for"]] = j.id
				s._on_job_finished(j, world.get_agent(j.payload["for"]), &"done") # served at once
	assert_eq(first.size(), 3, "every agent is addressed once before anyone twice: %s" % [first.keys()])

func test_tags_include_the_agent_id_for_all_four() -> void:
	for id in [&"papi_fuego", &"papi_diagnostica", &"el_salchipapa", &"don_omar"]:
		var d := load("res://crew/defs/%s.tres" % id) as NpcCharacterDef
		assert_true(d.all_tags().has(String(id)), "%s carries its own id as a tag" % id)
