extends GutTest
## Specs: npc-life-job-board (posting, claiming, expiry, ordering and urgency, source decoupling).

var board: NpcJobBoard

func before_each() -> void:
	board = NpcJobBoard.new()

func _job(id: StringName, kind := &"chore", priority := 0.0) -> NpcJob:
	var j := NpcJob.new()
	j.id = id
	j.kind = kind
	j.priority = priority
	return j

func test_post_and_clear() -> void:
	watch_signals(board)
	var a := board.post(_job(&"a", &"mop", 2.0), 0.0)
	board.post(_job(&"b"), 0.0)
	board.post(_job(&"c"), 0.0)
	assert_eq(board.open_jobs().size(), 3)
	assert_signal_emit_count(board, "job_posted", 3)
	assert_true(board.clear(&"b"))
	assert_eq(board.open_jobs().size(), 2)
	assert_signal_emit_count(board, "job_cleared", 1)
	assert_false(board.clear(&"nope"), "clearing an unknown id is a no-op")
	assert_eq(board.get_job(&"a"), a)

func test_clear_by_source_removes_only_its_jobs() -> void:
	var j1 := _job(&"s1:a")
	j1.source_id = &"s1"
	var j2 := _job(&"s2:a")
	j2.source_id = &"s2"
	board.post(j1, 0.0)
	board.post(j2, 0.0)
	assert_eq(board.clear_source(&"s1"), 1)
	assert_eq(board.open_jobs().size(), 1)
	assert_eq(board.open_jobs()[0].id, &"s2:a")

func test_duplicate_id_updates_in_place() -> void:
	var first := board.post(_job(&"x", &"mop", 1.0), 0.0)
	var again := _job(&"x", &"mop", 5.0)
	again.station_id = &"mop_zone"
	var kept := board.post(again, 1.0)
	assert_eq(board.open_jobs().size(), 1, "no duplicate")
	assert_same(kept, first, "the existing job object is updated, identity and claims kept")
	assert_eq(first.priority, 5.0)
	assert_eq(first.station_id, &"mop_zone")

func test_claim_marks_claimed_by() -> void:
	board.post(_job(&"j"), 0.0)
	watch_signals(board)
	assert_true(board.claim(&"j", &"A"))
	assert_eq(board.get_job(&"j").claimed_by, [&"A"] as Array[StringName])
	assert_signal_emit_count(board, "job_claimed", 1)
	assert_eq(board.candidates(&"B", PackedStringArray()).size(), 0, "claimed single-slot job is hidden from others")
	assert_true(board.release(&"j", &"A"))
	assert_eq(board.candidates(&"B", PackedStringArray()).size(), 1, "released job returns to the open list")

func test_agent_holds_one_job_at_a_time() -> void:
	board.post(_job(&"j1"), 0.0)
	board.post(_job(&"j2"), 0.0)
	assert_true(board.claim(&"j1", &"A"))
	assert_false(board.claim(&"j2", &"A"), "second claim by the same agent fails")
	assert_eq(board.claimed_job_of(&"A"), &"j1")

func test_multi_slot_job_claimed_by_n_agents() -> void:
	var j := _job(&"reef")
	j.slots = 3
	board.post(j, 0.0)
	assert_true(board.claim(&"reef", &"A"))
	assert_true(board.claim(&"reef", &"B"))
	assert_eq(board.candidates(&"C", PackedStringArray()).size(), 1, "still visible while slots are free")
	assert_true(board.claim(&"reef", &"C"))
	assert_false(board.claim(&"reef", &"D"), "a fourth claim fails")
	assert_eq(board.candidates(&"D", PackedStringArray()).size(), 0)

func test_required_tags_filter() -> void:
	var j := _job(&"climb")
	j.required_tags = PackedStringArray(["climber"])
	board.post(j, 0.0)
	assert_eq(board.candidates(&"A", PackedStringArray()).size(), 0)
	assert_eq(board.candidates(&"A", PackedStringArray(["climber"])).size(), 1)
	assert_false(board.claim(&"climb", &"A", PackedStringArray()), "claim enforces the tags too")
	assert_true(board.claim(&"climb", &"A", PackedStringArray(["climber"])))

func test_expiry_unclaimed() -> void:
	var j := _job(&"old")
	j.ttl_s = 10.0
	board.post(j, 0.0)
	watch_signals(board)
	assert_eq(board.expire(9.9).size(), 0)
	var gone := board.expire(10.0)
	assert_eq(gone.size(), 1)
	assert_eq(board.open_jobs().size(), 0)
	assert_signal_emit_count(board, "job_expired", 1)
	assert_eq(board.expire(11.0).size(), 0, "expires once")

func test_claimed_job_expires_when_ttl_elapsed() -> void:
	var j := _job(&"old")
	j.ttl_s = 10.0
	board.post(j, 0.0)
	board.claim(&"old", &"A")
	board.expire(10.0)
	assert_eq(board.claimed_job_of(&"A"), &"", "A's claim is released")
	board.post(_job(&"next"), 10.0)
	assert_true(board.claim(&"next", &"A"), "A can pick a new job")

func test_zero_ttl_never_expires() -> void:
	var j := _job(&"forever")
	j.ttl_s = 0.0
	board.post(j, 0.0)
	assert_eq(board.expire(1.0e6).size(), 0)

func test_urgency_grows_until_deadline() -> void:
	var j := _job(&"u")
	j.ttl_s = 20.0
	j.urgency = 0.2
	j.urgency_rate = 0.05
	board.post(j, 0.0)
	assert_gt(board.urgency_of(j, 18.0), board.urgency_of(j, 0.0))
	assert_almost_eq(board.urgency_of(j, 100.0), board.urgency_of(j, 20.0), 1e-6, "growth stops at the deadline")

func test_iteration_sorted_by_id() -> void:
	for id in [&"zeta", &"alpha", &"mid"]:
		board.post(_job(id), 0.0)
	var ids := board.open_jobs().map(func(j: NpcJob) -> StringName: return j.id)
	assert_eq(ids, [&"alpha", &"mid", &"zeta"])
	var cids := board.candidates(&"A", PackedStringArray()).map(func(j: NpcJob) -> StringName: return j.id)
	assert_eq(cids, [&"alpha", &"mid", &"zeta"])

class ExternalSource extends NpcJobSource:
	var effects := 0
	func _poll(_world: Node, now: float) -> void:
		var j := NpcJob.new()
		j.id = &"ext:1"
		j.kind = &"external"
		post_job(j, now)
	func _on_job_effect(_job: NpcJob, _agent: Node, _effect: StringName) -> void:
		effects += 1

func test_source_decoupling_no_agent_reference() -> void:
	var src := ExternalSource.new()
	src.source_id = &"ext"
	add_child_autofree(src)
	src.board = board
	assert_true(src.poll_if_due(null, 0.0), "first poll is due immediately")
	assert_eq(board.open_jobs().size(), 1)
	assert_eq(board.get_job(&"ext:1").source_id, &"ext", "the source stamps its id")
	assert_false(src.poll_if_due(null, 0.1), "not due again before 1 / poll_hz")
	assert_true(src.poll_if_due(null, 0.6))
	assert_eq(board.open_jobs().size(), 1, "re-posting the same id updates in place")
