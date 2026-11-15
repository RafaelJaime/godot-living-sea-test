class_name NpcAmbient
extends RefCounted
## Ambient fallback: the always-available job an agent takes when nothing else is open, so that no agent is ever aimless. Built from the
## agent's last station or the nearest station tagged `ambient_ok`; variants idle_at_station and look_around (chat offers join with the
## social layer). Ambient jobs live on the agent only (never on the board) and are given a low score by construction: any real job wins.

const DURATION_MIN := 8.0
const DURATION_MAX := 20.0

## `rng` is the agent's `ambient` stream: variant and duration are drawn from it.
static func make(agent_id: StringName, serial: int, last_station_id: StringName, ambient_station_id: StringName, rng: NpcRng) -> NpcJob:
	var j := NpcJob.new()
	j.id = StringName("ambient:%s:%d" % [agent_id, serial])
	j.ttl_s = 0.0
	var station := last_station_id if last_station_id != &"" else ambient_station_id
	var variant_pick := rng.randf()
	if station != &"" and variant_pick < 0.6:
		j.kind = &"ambient_idle_at_station"
		j.station_id = station
	else:
		j.kind = &"ambient_look_around"
	var act := NpcActionDef.new()
	act.action_id = j.kind
	var d := rng.randf_range(DURATION_MIN, DURATION_MAX)
	act.duration_range = Vector2(d, d)
	act.anim_tag = &"idle"
	j.action = act
	return j

static func is_ambient(job: NpcJob) -> bool:
	return job != null and String(job.id).begins_with("ambient:")
