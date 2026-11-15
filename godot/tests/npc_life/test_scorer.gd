extends GutTest
## Specs: npc-life-utility-ai (utility scoring, softmax selection, recency penalty).

var scorer: NpcUtilityScorer

func before_each() -> void:
	scorer = NpcUtilityScorer.new()

func _ctx() -> NpcUtilityScorer.Ctx:
	var c := NpcUtilityScorer.Ctx.new()
	c.def = NpcCharacterDef.new()
	c.def.agent_id = &"A"
	c.needs = NpcNeeds.new(c.def)
	c.job = NpcJob.new()
	c.job.id = &"j"
	c.job.kind = &"fishing"
	c.distance = 0.0
	c.urgency = 0.0
	c.since_done_s = -1.0
	return c

func test_score_factors_each_contribute() -> void:
	var base := scorer.score(_ctx())
	var c := _ctx()
	c.job.priority = 2.0
	assert_almost_eq(scorer.score(c) - base, 2.0, 1e-5, "priority adds")
	c = _ctx()
	c.def.preferences = {&"fishing": 1.0}
	assert_gt(scorer.score(c), base, "preference raises the score")
	c = _ctx()
	c.def.skills = {&"fishing": 1.0}
	assert_gt(scorer.score(c), base, "skill above the 0.5 default raises the score")
	c = _ctx()
	c.kind_def = NpcJobKindDef.new()
	c.kind_def.base_score = 1.5
	assert_almost_eq(scorer.score(c) - base, 1.5 * scorer.w_base, 1e-5)
	c = _ctx()
	c.kind_def = NpcJobKindDef.new()
	c.kind_def.satisfies = &"boredom"
	c.def.needs = {&"boredom": 60.0}
	c.needs = NpcNeeds.new(c.def)
	c.needs.advance(30.0)
	assert_gt(scorer.score(c), base, "a satisfied need level raises the score")

func test_preference_raises_score_between_identical_jobs() -> void:
	var fish := _ctx()
	fish.def.preferences = {&"fishing": 0.9}
	var mop := _ctx()
	mop.def = fish.def
	mop.job.kind = &"mop"
	assert_gt(scorer.score(fish), scorer.score(mop))

func test_distance_term_reduces_score() -> void:
	var near := _ctx()
	near.distance = 2.0
	var far := _ctx()
	far.distance = 20.0
	assert_gt(scorer.score(near), scorer.score(far))

func test_urgency_term_grows() -> void:
	var calm := _ctx()
	calm.urgency = 0.0
	var late := _ctx()
	late.urgency = 1.0
	assert_gt(scorer.score(late), scorer.score(calm))

func test_ineligible_job_is_not_scored() -> void:
	var c := _ctx()
	c.job.required_tags = PackedStringArray(["climber"])
	assert_false(scorer.eligible(c), "tags unmet: the scorer reports ineligible")
	c.agent_tags = PackedStringArray(["climber"])
	assert_true(scorer.eligible(c))

func test_softmax_low_temperature_top_pick_99pct() -> void:
	var rng := NpcRng.new(2024)
	var scores := PackedFloat32Array([1.0, 0.5, 0.1])
	var top := 0
	for i in 1000:
		if scorer.softmax_pick(scores, 0.01, rng) == 0:
			top += 1
	assert_gte(top, 990, "T=0.01: top candidate at least 99 percent")

func test_softmax_high_temperature_all_picked() -> void:
	var rng := NpcRng.new(2024)
	var scores := PackedFloat32Array([1.0, 0.5, 0.1])
	var seen := {}
	for i in 1000:
		seen[scorer.softmax_pick(scores, 1.0, rng)] = true
	assert_eq(seen.size(), 3, "T=1: every candidate picked at least once")

func test_softmax_is_deterministic_for_a_seed() -> void:
	var scores := PackedFloat32Array([0.4, 0.5, 0.45, 0.2])
	var a := NpcRng.new(5)
	var b := NpcRng.new(5)
	for i in 100:
		assert_eq(scorer.softmax_pick(scores, 0.5, a), scorer.softmax_pick(scores, 0.5, b))

func test_recency_penalty_decays() -> void:
	var fresh := scorer.recency_penalty(0.0)
	var later := scorer.recency_penalty(60.0)
	assert_gt(fresh, later)
	assert_eq(scorer.recency_penalty(-1.0), 0.0, "never done: no penalty")
	assert_lt(scorer.recency_penalty(600.0), 0.01 * fresh, "decays toward zero")

func test_repeat_avoidance() -> void:
	var just_mopped := _ctx()
	just_mopped.job.kind = &"mop"
	just_mopped.since_done_s = 0.0
	var repair := _ctx()
	repair.job.kind = &"repair"
	assert_gt(scorer.score(repair), scorer.score(just_mopped), "an equivalent kind that was not just done wins")

func test_temperature_scale_per_character() -> void:
	var d := NpcCharacterDef.new()
	d.temperature_scale = 2.0
	assert_almost_eq(scorer.effective_temperature(0.35, d), 0.7, 1e-6)
	d.temperature_scale = 0.5
	assert_almost_eq(scorer.effective_temperature(0.35, d), 0.175, 1e-6)

func test_topk_scores_returned() -> void:
	var jobs: Array[NpcJob] = []
	for k in [&"a", &"b", &"c", &"d"]:
		var j := NpcJob.new()
		j.id = k
		j.kind = k
		jobs.append(j)
	var scores := PackedFloat32Array([0.1, 0.9, 0.5, 0.7])
	var top := scorer.top_k(jobs, scores, 3)
	assert_eq(top.size(), 3)
	assert_eq(top[0]["job"].id, &"b")
	assert_eq(top[1]["job"].id, &"d")
	assert_eq(top[2]["job"].id, &"c")
	assert_almost_eq(top[0]["score"], 0.9, 1e-6)
