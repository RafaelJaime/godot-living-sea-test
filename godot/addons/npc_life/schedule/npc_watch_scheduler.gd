class_name NpcWatchScheduler
extends NpcJobSource
## Keeps every watch of a roster staffed: posts one must-staff job per post of each watch (assigned to a keeper chosen by skill-weighted
## rotation), hands over before the shift ends with an OVERLAP (the relief is posted `handover_lead_s` early and the keeper is released only
## when the relief is working at the station), extends the shift when nobody can relieve, and keeps `keep_during_emergency` watches staffed
## during all-hands events (the best-skilled agent takes the post). A watch station gets one extra slot, used only while the relief overlaps.
## Logs `[roster]` lines into the world's decision log. Add it as a child of the NpcWorld.

@export var roster: NpcRoster

class Post:
	var keeper: StringName = &""
	var job_id: StringName = &""
	var shift_end := 0.0
	var consecutive := 0
	var relief: StringName = &""
	var relief_job: StringName = &""
	var serial := 0
	var emergency_swap := false

class WatchState:
	var def: NpcWatchDef
	var posts: Array[Post] = []
	var first_staffed := false
	var unstaffed_ticks := 0
	var overlap_ticks := 0
	var handovers := 0
	var extended := 0
	var min_staffing := 1000000
	var started := false

var _states: Dictionary = {} # watch_id -> WatchState
var _world: NpcWorld

func _init() -> void:
	poll_hz = 10.0 # every logical tick: staffing is checked at tick resolution

# ---- selection -----------------------------------------------------------------------------------------------------------------------------

## Next keeper: weighted random by skill (floor 0.05), excluding the current keeper after `max_consecutive` shifts when another candidate exists.
static func choose(def: NpcWatchDef, candidates: Array[StringName], current: StringName, consecutive: int, skill: Callable, rng: NpcRng) -> StringName:
	var pool := candidates.duplicate()
	if pool.has(current) and consecutive >= def.max_consecutive and pool.size() >= 2:
		pool.erase(current)
	if pool.is_empty():
		return &""
	var weights: Array[float] = []
	var sum := 0.0
	for id in pool:
		var w := maxf(float(skill.call(id)), 0.05)
		weights.append(w)
		sum += w
	var r := rng.randf() * sum
	var acc := 0.0
	for i in pool.size():
		acc += weights[i]
		if r < acc:
			return pool[i]
	return pool[pool.size() - 1]

# ---- queries (tests, logs) -----------------------------------------------------------------------------------------------------------------

func keeper_of(watch_id: StringName, post := 0) -> StringName:
	var st: WatchState = _states.get(watch_id)
	return st.posts[post].keeper if st and post < st.posts.size() else &""

func unstaffed_ticks(watch_id: StringName) -> int:
	var st: WatchState = _states.get(watch_id)
	return st.unstaffed_ticks if st else 0

func overlap_ticks(watch_id: StringName) -> int:
	var st: WatchState = _states.get(watch_id)
	return st.overlap_ticks if st else 0

func handovers_done(watch_id: StringName) -> int:
	var st: WatchState = _states.get(watch_id)
	return st.handovers if st else 0

func min_staffing_observed(watch_id: StringName) -> int:
	var st: WatchState = _states.get(watch_id)
	return st.min_staffing if st and st.min_staffing < 1000000 else 0

## Test and debug aid: makes `agent_id` the keeper of the post now (the job is re-assigned).
func force_keeper(watch_id: StringName, agent_id: StringName, post := 0) -> void:
	var st: WatchState = _states.get(watch_id)
	if st == null or post >= st.posts.size():
		return
	var p := st.posts[post]
	if p.job_id != &"":
		board.clear(p.job_id)
	p.keeper = agent_id
	p.relief = &""
	_post_job(st, post, agent_id)
	p.shift_end = _world.now() + st.def.shift_s
	_world.request_decision(agent_id)
	_log("watch=%s event=forced keeper=%s" % [watch_id, agent_id])

func summary_line() -> String:
	var parts := PackedStringArray()
	var ids := _states.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id in ids:
		var st: WatchState = _states[id]
		parts.append("%s min_staffing=%d handovers=%d overlap_ticks=%d unstaffed_ticks=%d extended=%d" % [id, min_staffing_observed(id), st.handovers, st.overlap_ticks, st.unstaffed_ticks, st.extended])
	return "[roster] SUMMARY " + "; ".join(parts)

# ---- polling -------------------------------------------------------------------------------------------------------------------------------

func _poll(world: Node, now: float) -> void:
	_world = world as NpcWorld
	if roster == null:
		return
	var emergency := _emergency_active()
	for w in roster.watches:
		var st: WatchState = _states.get(w.watch_id)
		if st == null:
			st = _init_watch(w)
		if not st.started:
			_start_watch(st, now)
		for k in st.posts.size():
			_step_post(st, k, now, emergency)
		_measure(st)

func _init_watch(w: NpcWatchDef) -> WatchState:
	var st := WatchState.new()
	st.def = w
	for k in w.min_staff:
		st.posts.append(Post.new())
	_states[w.watch_id] = st
	var station := _world.find_station(w.station_id)
	if station != null and station.slot_count < w.min_staff + 1:
		station.slot_count = w.min_staff + 1 # one spare slot for the relief while it overlaps the keeper
	return st

func _start_watch(st: WatchState, now: float) -> void:
	st.started = true
	var taken: Array[StringName] = []
	for k in st.posts.size():
		var cands := _free_candidates(st, taken)
		var keeper := choose(st.def, cands, &"", 0, _skill_fn(st.def), _world.rng_for(&"roster", st.def.watch_id))
		if keeper == &"":
			continue
		taken.append(keeper)
		var p := st.posts[k]
		p.keeper = keeper
		p.consecutive = 1
		p.shift_end = now + _shift_len(st.def)
		_post_job(st, k, keeper)
		_world.request_decision(keeper)
		_log("watch=%s event=assign keeper=%s post=%d" % [st.def.watch_id, keeper, k])

func _step_post(st: WatchState, k: int, now: float, emergency: bool) -> void:
	var p := st.posts[k]
	var def := st.def
	if p.keeper == &"" and not emergency:
		# nobody was available at the start (or the keeper left the world): try again
		var cands := _free_candidates(st, _keepers(st))
		var keeper := choose(def, cands, &"", 0, _skill_fn(def), _world.rng_for(&"roster", def.watch_id))
		if keeper != &"":
			p.keeper = keeper
			p.consecutive = 1
			p.shift_end = now + _shift_len(def)
			_post_job(st, k, keeper)
			_world.request_decision(keeper)
			_log("watch=%s event=assign keeper=%s post=%d" % [def.watch_id, keeper, k])
		return
	# a relief in progress: finished when it works at the station
	if p.relief != &"":
		var ra := _world.get_agent(p.relief) as NpcAgent
		if ra == null:
			board.clear(p.relief_job)
			p.relief = &""
			p.relief_job = &""
		elif ra.current_job_id() == p.relief_job and ra.phase() == &"work":
			var old := p.job_id
			board.clear(old) # the keeper is released only now
			_log("watch=%s event=handover from=%s to=%s post=%d" % [def.watch_id, p.keeper, p.relief, k])
			p.consecutive = p.consecutive + 1 if p.relief == p.keeper else 1
			p.keeper = p.relief
			p.job_id = p.relief_job
			p.relief = &""
			p.relief_job = &""
			p.shift_end = now + _shift_len(def)
			st.handovers += 1
		return
	# all-hands: keep-during-emergency watches get the best-skilled agent, the other watches are suspended
	if emergency:
		if def.keep_during_emergency and not p.emergency_swap:
			p.emergency_swap = true
			var best := _best_skilled(st, k)
			if best != &"" and best != p.keeper:
				_start_relief(st, k, best, "emergency")
		return
	p.emergency_swap = false
	if now >= p.shift_end - def.handover_lead_s:
		var cands := _free_candidates(st, _other_keepers(st, k)) # may include the current keeper
		var single := def.eligible.size() <= 1 # configured with one eligible agent: it simply continues (no extension to report)
		var others := cands.filter(func(id: StringName) -> bool: return id != p.keeper)
		var relief: StringName = &""
		if not others.is_empty():
			relief = choose(def, cands, p.keeper, p.consecutive, _skill_fn(def), _world.rng_for(&"roster", def.watch_id)) # the keeper may be chosen again
		if relief == &"":
			if single and _world.get_agent(p.keeper) != null:
				p.shift_end = now + _shift_len(def)
				p.consecutive += 1
				_log("watch=%s event=renewed keeper=%s post=%d (single eligible agent)" % [def.watch_id, p.keeper, k])
			else:
				p.shift_end += _shift_len(def)
				st.extended += 1
				_log("watch=%s event=extended_shift keeper=%s post=%d until=%.1f (no relief available)" % [def.watch_id, p.keeper, k, p.shift_end])
		elif relief == p.keeper:
			p.shift_end = now + _shift_len(def)
			p.consecutive += 1
			_log("watch=%s event=renewed keeper=%s post=%d (chosen again)" % [def.watch_id, p.keeper, k])
		else:
			_start_relief(st, k, relief, "shift_end")

func _start_relief(st: WatchState, k: int, relief: StringName, why: String) -> void:
	var p := st.posts[k]
	p.relief = relief
	_post_job(st, k, relief, true)
	_world.request_decision(relief)
	_log("watch=%s event=handover_start from=%s to=%s post=%d why=%s" % [st.def.watch_id, p.keeper, relief, k, why])

func _post_job(st: WatchState, k: int, agent_id: StringName, as_relief := false) -> void:
	var p := st.posts[k]
	p.serial += 1
	var j := NpcJob.new()
	j.id = StringName("%s:watch:%d:%d" % [st.def.watch_id, k, p.serial])
	j.kind = st.def.job_kind
	j.station_id = st.def.station_id
	j.override = &"must_staff"
	j.slots = 1
	j.ttl_s = 0.0
	j.payload = {"assigned": agent_id, "keep_in_emergency": st.def.keep_during_emergency, "watch": st.def.watch_id}
	var act := NpcActionDef.new()
	act.action_id = st.def.job_kind
	act.duration_range = Vector2(1.0e6, 1.0e6) # a watch lasts until the roster ends it
	j.action = act
	post_job(j, _world.now())
	if as_relief:
		p.relief_job = j.id
	else:
		p.job_id = j.id

# ---- helpers -------------------------------------------------------------------------------------------------------------------------------

func _measure(st: WatchState) -> void:
	var staffed := 0
	var overlap := false
	for p in st.posts:
		var a := _claimed(p.job_id)
		var b := _claimed(p.relief_job)
		if a or b:
			staffed += 1
		if a and b:
			overlap = true
	if overlap:
		st.overlap_ticks += 1
	if staffed >= st.def.min_staff:
		st.first_staffed = true
	if st.first_staffed:
		st.min_staffing = mini(st.min_staffing, staffed)
		if staffed < st.def.min_staff and not _emergency_active():
			st.unstaffed_ticks += 1
			_log("watch=%s event=unstaffed staffed=%d" % [st.def.watch_id, staffed])

func _claimed(job_id: StringName) -> bool:
	if job_id == &"":
		return false
	var j := board.get_job(job_id)
	return j != null and j.claimed_by.size() > 0

func _emergency_active() -> bool:
	for j in board.open_jobs():
		if j.override == &"emergency" or j.override == &"all_hands":
			return true
	return false

func _keepers(st: WatchState) -> Array[StringName]:
	var out: Array[StringName] = []
	for p in st.posts:
		if p.keeper != &"":
			out.append(p.keeper)
	return out

func _other_keepers(st: WatchState, k: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in st.posts.size():
		if i != k and st.posts[i].keeper != &"":
			out.append(st.posts[i].keeper)
		if i != k and st.posts[i].relief != &"":
			out.append(st.posts[i].relief)
	return out

## True when `id` is already the keeper (or the incoming relief) of a post of a different watch. Judged from the scheduler's own state, not from
## the agent's current job, because on the first tick the job is not yet claimed and two watches would otherwise pick the same agent and fight
## over it on every decision.
func _holds_post_of_other_watch(id: StringName, st: WatchState) -> bool:
	for wid in _states:
		if wid == st.def.watch_id:
			continue
		for p in (_states[wid] as WatchState).posts:
			if p.keeper == id or p.relief == id:
				return true
	return false

## Eligible agents that exist in the world and are not keeping another post (current keepers of this watch excluded through `taken`).
func _free_candidates(st: WatchState, taken: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in st.def.eligible:
		var sid := StringName(id)
		var a := _world.get_agent(sid) as NpcAgent
		if a == null or taken.has(sid) or _holds_post_of_other_watch(sid, st):
			continue
		var cj := a.current_job()
		if cj != null and cj.override == &"must_staff" and cj.payload.get("watch", &"") != st.def.watch_id:
			continue # keeping a different watch
		out.append(sid)
	return out

func _best_skilled(st: WatchState, k: int) -> StringName:
	var best: StringName = &""
	var bs := -1.0
	var taken := _other_keepers(st, k)
	for id in st.def.eligible:
		var sid := StringName(id)
		if _world.get_agent(sid) == null or taken.has(sid):
			continue
		var s := float(_skill_fn(st.def).call(sid))
		if s > bs:
			bs = s
			best = sid
	return best

func _skill_fn(def: NpcWatchDef) -> Callable:
	return func(id: StringName) -> float:
		var a := _world.get_agent(id) as NpcAgent
		return a.def.skill_for(def.job_kind) if a and a.def else 0.5

func _shift_len(def: NpcWatchDef) -> float:
	if def.shift_jitter_s <= 0.0:
		return def.shift_s
	return def.shift_s + _world.rng_for(&"roster", def.watch_id).randf_range(0.0, def.shift_jitter_s)

func _log(msg: String) -> void:
	_world.decision_log.write_line("[roster] T=%06d %s" % [_world.tick_count, msg])
