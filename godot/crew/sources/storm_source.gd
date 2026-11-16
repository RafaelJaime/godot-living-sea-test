class_name CrewStormSource
extends NpcJobSource
## Storm all-hands (C3.1, C3.5, C3.7). When the blackboard `storm` crosses `trigger` it posts one all-hands `reef` job per sail; the job's effect
## asks the ship to furl it through `rig.request_furl(sail, 1.0)` (furl_source=crew). Sails with a `yard_aloft_<i>` station are furled by climbing
## to the yard; at most `max_aloft` climbers are up at once (storms make climbing dangerous), the rest wait their turn. Without aloft stations the
## sail is furled from the deck reef line `reef_line_<i>`. Below `release` the jobs clear and calm `unfurl` jobs set the sails the crew furled again.
## Hysteresis: between `release` and `trigger` nothing changes. The helm stays staffed by the roster's keep-during-emergency watch.

@export var trigger := 0.6
@export var release := 0.4
@export var max_aloft := 2

var rig: Object ## PinnaceRig (request_furl, sail_count); null = jobs only, no ship effect
var _active := false
var _pending: Array[int] = [] # sails waiting for an aloft slot
var _done: Dictionary = {} # sail -> true once its storm job finished
var _furled: Dictionary = {} # sail -> true once the crew furled it

func _init() -> void:
	source_id = &"storm"
	poll_hz = 2.0

func _sails(w: NpcWorld) -> int:
	if rig != null and rig.has_method("sail_count"):
		return int(rig.call("sail_count"))
	var n := 0
	while w.find_station(StringName("reef_line_%d" % n)) != null:
		n += 1
	return n

## The aloft station of sail `i`: the ship has a port and a starboard footrope spot per yard (`yard_aloft_<i>_p|_s`); sails alternate sides so the
## crew spreads out. Plain `yard_aloft_<i>` is accepted too. &"" when the sail has none (the spritsail).
func _aloft_station(w: NpcWorld, i: int) -> StringName:
	var order: Array = ["_p", "_s", ""] if i % 2 == 0 else ["_s", "_p", ""]
	for suffix in order:
		var id := StringName("yard_aloft_%d%s" % [i, suffix])
		if w.find_station(id) != null:
			return id
	return &""

func _aloft(w: NpcWorld, i: int) -> bool:
	return _aloft_station(w, i) != &""

func _poll(world: Node, now: float) -> void:
	var w := world as NpcWorld
	var storm := float(w.inputs.get_value(&"storm", 0.0))
	if not _active and storm >= trigger:
		_active = true
		_done.clear()
		_pending.clear()
		for i in _sails(w):
			_pending.append(i)
		print("[crew] storm all-hands: %d sails" % _pending.size())
	elif _active and storm < release:
		_active = false
		_pending.clear()
		for j in board.open_jobs():
			if j.source_id == source_id and String(j.id).begins_with("storm:"):
				clear_job(j.id)
		for i in _furled:
			_post_unfurl(w, int(i), now)
		print("[crew] storm over: unfurling %d sails" % _furled.size())
		return
	if not _active:
		return
	var aloft_open := 0
	for j in board.open_jobs():
		if j.source_id == source_id and String(j.id).begins_with("storm:") and bool(j.payload.get("aloft", false)):
			aloft_open += 1
	var keep: Array[int] = []
	for i in _pending:
		if _aloft(w, i):
			if aloft_open >= max_aloft:
				keep.append(i)
				continue
			aloft_open += 1
		_post_furl(w, i, now)
	_pending = keep

func _action(aloft: bool, effect: StringName) -> NpcActionDef:
	var act := NpcActionDef.new()
	act.action_id = &"furl_aloft" if aloft else &"furl_deck"
	act.job_kinds = PackedStringArray(["reef"])
	act.anim_tag = &"furl_aloft" if aloft else &"haul"
	act.duration_range = Vector2(10.0, 16.0)
	act.effect_at = 0.5
	act.effect = effect
	return act

func _post_furl(w: NpcWorld, i: int, now: float) -> void:
	var aloft := _aloft(w, i)
	var j := NpcJob.new()
	j.id = StringName("storm:%d" % i)
	j.kind = &"reef"
	j.station_id = _aloft_station(w, i) if aloft else StringName("reef_line_%d" % i)
	j.priority = 1.0
	j.ttl_s = 0.0
	j.override = &"all_hands"
	j.payload = {"sail": i, "aloft": aloft, "target": 1.0}
	j.action = _action(aloft, &"furl")
	post_job(j, now)

func _post_unfurl(w: NpcWorld, i: int, now: float) -> void:
	var aloft := _aloft(w, i)
	var j := NpcJob.new()
	j.id = StringName("unfurl:%d" % i)
	j.kind = &"reef"
	j.station_id = _aloft_station(w, i) if aloft else StringName("reef_line_%d" % i)
	j.priority = 0.4
	j.ttl_s = 240.0
	j.payload = {"sail": i, "aloft": aloft, "target": 0.0}
	j.action = _action(aloft, &"furl")
	post_job(j, now)

func _on_job_effect(job: NpcJob, agent: Node, _effect: StringName) -> void:
	if not job.payload.has("sail"):
		return
	var sail: int = job.payload["sail"]
	var target: float = job.payload["target"]
	if rig != null and rig.has_method("request_furl"):
		rig.call("request_furl", sail, target)
	var who: StringName = (agent as NpcAgent).agent_id if agent is NpcAgent else &"?"
	print("[crew] sail %d %s by %s%s" % [sail, "furled" if target > 0.5 else "set", who, " (aloft)" if job.payload.get("aloft", false) else ""])
	if target > 0.5:
		_furled[sail] = true
	else:
		_furled.erase(sail)

func _on_job_finished(job: NpcJob, _agent: Node, result: StringName) -> void:
	if result != &"done":
		return
	if String(job.id).begins_with("storm:"):
		_done[int(job.payload.get("sail", -1))] = true
	clear_job(job.id)
