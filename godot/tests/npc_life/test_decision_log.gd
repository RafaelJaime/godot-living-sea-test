extends GutTest
## Specs: npc-life-debug-tools (decision log, metrics report, seeded reproducibility of the log).

func _job(id: StringName, kind: StringName) -> NpcJob:
	var j := NpcJob.new()
	j.id = id
	j.kind = kind
	return j

func _top(pairs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pairs:
		out.append({"job": _job(StringName(p[0]), StringName(p[0])), "score": p[1]})
	return out

func test_line_format_stable() -> void:
	var log := NpcDecisionLog.new()
	log.log_decision(123, &"Papi_Fuego", _job(&"helm:watch", &"helm"), &"roster", _top([["helm", 2.1], ["mop", 0.8], ["fish", 0.55]]), 0.35, 17)
	var line := log.lines()[0]
	var re := RegEx.create_from_string("^\\[npc\\] T=000123 agent=Papi_Fuego pick=helm:watch reason=roster top=\\[helm 2\\.10, mop 0\\.80, fish 0\\.55\\] temp=0\\.35 draw=17$")
	assert_not_null(re.search(line), line)

func test_line_for_override_has_empty_top() -> void:
	var log := NpcDecisionLog.new()
	log.log_decision(5, &"A", _job(&"storm", &"reef"), &"override:emergency", [], 0.0, 0)
	assert_true(log.lines()[0].contains("reason=override:emergency top=[]"))

func test_ring_buffer_bounded() -> void:
	var log := NpcDecisionLog.new()
	log.max_lines = 10
	for i in 100:
		log.log_decision(i, &"A", _job(&"j", &"k"), &"softmax", [], 0.3, i)
	assert_eq(log.lines().size(), 10)
	assert_true(log.lines()[9].contains("T=000099"), "the newest lines are kept")

func test_log_off_writes_nothing() -> void:
	var log := NpcDecisionLog.new()
	log.enabled = false
	log.log_decision(1, &"A", _job(&"j", &"k"), &"softmax", [], 0.3, 1)
	assert_eq(log.lines().size(), 0)
	log.record_idle(&"A", 30.0, 20.0)
	assert_gt(log.summary()["idle_max"][&"A"], 0.0, "metrics keep running with the log off")

func test_summary_metrics_idle_max() -> void:
	var log := NpcDecisionLog.new()
	log.record_idle(&"A", 4.0, 20.0)
	log.record_idle(&"A", 9.0, 20.0)
	log.record_idle(&"B", 2.0, 20.0)
	log.record_done(&"A", &"mop")
	log.record_done(&"A", &"mop")
	log.record_done(&"B", &"fish")
	var s := log.summary()
	assert_eq(s["idle_max"][&"A"], 9.0)
	assert_eq(s["idle_max"][&"B"], 2.0)
	assert_eq(s["jobs_per_kind"][&"mop"], 2)
	assert_eq(s["jobs_per_kind"][&"fish"], 1)
	assert_eq(s["idle_failures"], 0)

func test_idle_over_bound_is_a_failure_line() -> void:
	var log := NpcDecisionLog.new()
	log.record_idle(&"A", 21.5, 20.0)
	assert_eq(log.summary()["idle_failures"], 1)
	assert_true(log.lines()[0].begins_with("[npc] FAIL idle_bound agent=A"))

func test_summary_text_is_one_block() -> void:
	var log := NpcDecisionLog.new()
	log.record_idle(&"A", 3.0, 20.0)
	log.record_done(&"A", &"mop")
	var t := log.summary_text()
	assert_true(t.begins_with("[npc] SUMMARY"))
	assert_true(t.contains("idle_max A=3.0"))
	assert_true(t.contains("mop=1"))

func _run_world(world_seed: int) -> PackedStringArray:
	var w := NpcWorld.new()
	w.world_seed = world_seed
	add_child_autofree(w)
	for id in [&"A", &"B", &"C"]:
		var d := NpcCharacterDef.new()
		d.agent_id = id
		var a := NpcAgent.new()
		a.def = d
		w.add_child(a)
	for k in 8:
		var j := _job(StringName("job%d" % k), StringName("kind%d" % (k % 4)))
		j.ttl_s = 0.0
		var act := NpcActionDef.new()
		act.duration_range = Vector2(4.0, 9.0)
		j.action = act
		w.board.post(j, 0.0)
	for i in 1200:
		w.advance(0.1)
		if i % 40 == 0:
			var jn := _job(StringName("late%d" % i), StringName("kind%d" % (i % 4)))
			jn.ttl_s = 0.0
			w.board.post(jn, w.now())
	return w.decision_log.lines()

func test_same_seed_byte_equal_lines() -> void:
	var a := _run_world(7)
	var b := _run_world(7)
	assert_gt(a.size(), 20)
	assert_eq(a, b, "same seed, same inputs: identical log lines")

func test_different_seed_differs() -> void:
	assert_ne(_run_world(7), _run_world(8))
