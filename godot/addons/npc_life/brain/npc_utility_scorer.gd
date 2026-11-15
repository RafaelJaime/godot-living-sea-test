class_name NpcUtilityScorer
extends RefCounted
## Linear utility score of a candidate job, softmax selection and the recency penalty (design "Scheduling, Social and Ambient Details").
##   s = w_base*kind.base + w_need*need(kind.satisfies) + w_pref*pref[kind] + w_skill*skill[kind] - w_dist*dist/ref_dist
##       + w_urg*urgency + job.priority - R*exp(-since_done/tau)
## Weights are plain fields: a world sets them once, a game may tune them.

var w_base := 1.0
var w_need := 1.0
var w_pref := 1.0
var w_skill := 0.5
var w_dist := 0.5
var w_urg := 1.0
var ref_dist := 10.0
var recency_r := 1.0
var recency_tau := 90.0

## Everything one score depends on.
class Ctx:
	var job: NpcJob
	var kind_def: NpcJobKindDef ## optional
	var def: NpcCharacterDef
	var needs: NpcNeeds
	var agent_tags := PackedStringArray()
	var distance := 0.0 ## path distance in metres
	var urgency := 0.0 ## the job's urgency at decision time
	var since_done_s := -1.0 ## seconds since this kind was last finished by the agent; < 0 = never

## False when the agent lacks a tag the job requires: ineligible jobs are never scored.
func eligible(c: Ctx) -> bool:
	return c.job.has_tags(c.agent_tags + (c.def.all_tags() if c.def else PackedStringArray()))

func score(c: Ctx) -> float:
	var s := c.job.priority + w_urg * c.urgency - w_dist * c.distance / maxf(ref_dist, 0.001)
	if c.kind_def:
		s += w_base * c.kind_def.base_score
		if c.kind_def.satisfies != &"" and c.needs:
			s += w_need * c.needs.level(c.kind_def.satisfies)
	if c.def:
		s += w_pref * c.def.preference_for(c.job.kind) + w_skill * c.def.skill_for(c.job.kind)
	return s - recency_penalty(c.since_done_s)

## Penalty for a kind finished `since_done_s` ago; decays exponentially, none when never done.
func recency_penalty(since_done_s: float) -> float:
	if since_done_s < 0.0:
		return 0.0
	return recency_r * exp(-since_done_s / maxf(recency_tau, 0.001))

func effective_temperature(world_temperature: float, def: NpcCharacterDef) -> float:
	return world_temperature * (def.temperature_scale if def else 1.0)

## Samples an index with probability proportional to exp((s - s_max) / temperature) using one draw of `rng`. Low temperature approaches
## argmax, high approaches uniform. -1 for an empty list.
func softmax_pick(scores: PackedFloat32Array, temperature: float, rng: NpcRng) -> int:
	var n := scores.size()
	if n == 0:
		return -1
	var smax := scores[0]
	for s in scores:
		smax = maxf(smax, s)
	var t := maxf(temperature, 1.0e-6)
	var weights := PackedFloat64Array()
	weights.resize(n)
	var sum := 0.0
	for i in n:
		weights[i] = exp(float(scores[i] - smax) / t)
		sum += weights[i]
	var r := rng.randf() * sum
	var acc := 0.0
	for i in n:
		acc += weights[i]
		if r < acc:
			return i
	return n - 1

## The k best candidates as [{job, score}], best first (ties by job id), for the decision log.
func top_k(jobs: Array[NpcJob], scores: PackedFloat32Array, k: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in jobs.size():
		rows.append({"job": jobs[i], "score": scores[i]})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return String((a["job"] as NpcJob).id) < String((b["job"] as NpcJob).id))
	return rows.slice(0, k)
