class_name NpcWatchDef
extends Resource
## One watch of a roster: a must-staff station, who may keep it, how long a shift lasts and how the handover works.

@export var watch_id: StringName
@export var station_id: StringName
## Job kind of the watch job (also the skill key the rotation weighs).
@export var job_kind: StringName
@export var eligible: PackedStringArray
@export var shift_s := 180.0
## Random extra shift length, drawn from the roster's seeded stream (0 = fixed shifts).
@export var shift_jitter_s := 0.0
@export var min_staff := 1
@export var max_consecutive := 3
## The relief is posted this long before the shift ends and must reach the station before the keeper is released.
@export var handover_lead_s := 12.0
## All-hands events do not pull this watch's keeper away (the helm).
@export var keep_during_emergency := false

func validate(known_stations: PackedStringArray, known_agents: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if watch_id == &"":
		out.append("watch: empty watch_id")
	if not known_stations.has(String(station_id)):
		out.append("watch[%s].station_id: unknown station '%s'" % [watch_id, station_id])
	for a in eligible:
		if not known_agents.has(a):
			out.append("watch[%s].eligible: unknown agent '%s'" % [watch_id, a])
	if min_staff < 1:
		out.append("watch[%s].min_staff: %d must be at least 1" % [watch_id, min_staff])
	if shift_s <= 0.0:
		out.append("watch[%s].shift_s: %s must be positive" % [watch_id, shift_s])
	return out
