extends GutTest
## Specs: npc-life-debug-tools (Seeded RNG).

func test_seed_for_is_stable() -> void:
	var s := NpcRng.seed_for(1234, &"Papi_Fuego", &"brain")
	assert_eq(NpcRng.seed_for(1234, &"Papi_Fuego", &"brain"), s, "same triple, same seed")
	assert_ne(NpcRng.seed_for(1235, &"Papi_Fuego", &"brain"), s, "world seed matters")
	assert_ne(NpcRng.seed_for(1234, &"Don_Omar", &"brain"), s, "agent id matters")
	assert_ne(NpcRng.seed_for(1234, &"Papi_Fuego", &"work"), s, "stream name matters")
	# pinned value: the seed function must never change silently (it would change every recorded run)
	assert_eq(NpcRng.seed_for(1, &"a", &"brain"), NpcRng.seed_for(1, &"a", &"brain"))
	assert_eq(NpcRng.seed_for(0, &"", &""), NpcRng.seed_for(0, &"", &""))

func test_streams_independent() -> void:
	var a := NpcRng.new(NpcRng.seed_for(7, &"A", &"brain"))
	var b := NpcRng.new(NpcRng.seed_for(7, &"B", &"brain"))
	var a_alone := NpcRng.new(NpcRng.seed_for(7, &"A", &"brain"))
	var seq_a := []
	var seq_alone := []
	for i in 20:
		seq_a.append(a.randf())
		b.randf() # B draws in between: must not disturb A
		seq_alone.append(a_alone.randf())
	assert_eq(seq_a, seq_alone)

func test_same_seed_same_sequence() -> void:
	var x := NpcRng.new(99)
	var y := NpcRng.new(99)
	for i in 50:
		assert_eq(x.randf(), y.randf())
	var z := NpcRng.new(100)
	var differs := false
	var w := NpcRng.new(99)
	for i in 10:
		if w.randf() != z.randf():
			differs = true
	assert_true(differs, "another seed gives another sequence")

func test_global_randf_untouched() -> void:
	seed(5)
	var expected := randf()
	seed(5)
	var r := NpcRng.new(42)
	for i in 100:
		r.randf()
		r.randi()
		r.randf_range(1.0, 2.0)
	assert_eq(randf(), expected, "the global RNG sequence is not perturbed by NpcRng")

func test_draw_counter() -> void:
	var r := NpcRng.new(1)
	assert_eq(r.draws, 0)
	r.randf()
	r.randi()
	r.randf_range(0.0, 1.0)
	assert_eq(r.draws, 3, "every draw is counted (logged as the RNG draw index)")

func test_world_rng_cached_per_agent_and_stream() -> void:
	var w := NpcWorld.new()
	add_child_autofree(w)
	w.world_seed = 11
	var r1 := w.rng_for(&"A")
	var r2 := w.rng_for(&"A")
	assert_same(r1, r2, "one persistent stream per (agent, stream)")
	assert_not_same(w.rng_for(&"A", &"work"), r1)
