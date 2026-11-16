class_name CrewManeuverSource
extends NpcJobSource
## Maneuver jobs (C3.2, C3.6). While the blackboard `maneuver` (written by the bridge from `Autopilot.maneuver_started/ended`) is a tack or a jibe,
## one `brace` job per mast is posted at the deck brace stations `brace_<mast>`; their effect asks the rig to swing the yards through
## `rig.request_brace(mast, angle)` (angle sign = the new tack side). Without brace stations the first two deck reef lines stand in. The jobs clear when
## the maneuver ends; the ship's slow automatic fallback remains when nobody comes.

@export var jobs_per_maneuver := 3

var rig: Object
var _active := false
var _n := 0

func _init() -> void:
	source_id = &"maneuver"
	poll_hz = 4.0

## Brace pins are `brace_<mast>_<p|s>`; the pin on the side of the new tack (side +1 = starboard) of each mast, in the order fore, main, mizzen. Plain
## `brace_<n>` and the deck reef lines stand in on ships without them.
func _stations(w: NpcWorld, side: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var suffix := "_s" if side >= 0 else "_p"
	for mast in ["fore", "main", "mizzen"]:
		var id := StringName("brace_%s%s" % [mast, suffix])
		if w.find_station(id) != null and out.size() < jobs_per_maneuver:
			out.append(id)
	if not out.is_empty():
		return out
	for prefix in ["brace_%d", "reef_line_%d"]:
		var i := 0
		while w.find_station(StringName(prefix % i)) != null and out.size() < jobs_per_maneuver:
			out.append(StringName(prefix % i))
			i += 1
		if not out.is_empty():
			return out
	return out

func _poll(world: Node, now: float) -> void:
	var w := world as NpcWorld
	var kind: StringName = w.inputs.get_value(&"maneuver", &"")
	if kind != &"" and not _active:
		_active = true
		_n += 1
		var side := int(w.inputs.get_value(&"maneuver_side", 1))
		var mast := 0
		for sid in _stations(w, side):
			var j := NpcJob.new()
			j.id = StringName("maneuver:%s:%d:%d" % [kind, _n, mast])
			j.kind = &"brace"
			j.station_id = sid
			j.priority = 0.9
			j.ttl_s = 90.0
			j.payload = {"mast": mast, "angle": 0.35 * float(signi(side) if side != 0 else 1), "maneuver": kind}
			var act := NpcActionDef.new()
			act.action_id = &"brace_yards"
			act.job_kinds = PackedStringArray(["brace"])
			act.anim_tag = &"haul"
			act.duration_range = Vector2(8.0, 14.0)
			act.effect_at = 0.4
			act.effect = &"brace"
			j.action = act
			post_job(j, now)
			mast += 1
		print("[crew] maneuver %s: %d brace jobs" % [kind, mast])
	elif kind == &"" and _active:
		_active = false
		for j in board.open_jobs():
			if j.source_id == source_id:
				clear_job(j.id)

func _on_job_effect(job: NpcJob, agent: Node, _effect: StringName) -> void:
	if not job.payload.has("mast"):
		return
	if rig != null and rig.has_method("request_brace"):
		rig.call("request_brace", int(job.payload["mast"]), float(job.payload["angle"]))
	print("[crew] brace mast %d by %s" % [job.payload["mast"], (agent as NpcAgent).agent_id if agent is NpcAgent else &"?"])

func _on_job_finished(job: NpcJob, _agent: Node, result: StringName) -> void:
	if result == &"done":
		clear_job(job.id)
