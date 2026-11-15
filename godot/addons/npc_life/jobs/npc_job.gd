class_name NpcJob
extends RefCounted
## Runtime job record. Posted by an NpcJobSource on the NpcJobBoard; claimed by agents. `id` is unique on the board (posting an existing id
## updates that job in place).

var id: StringName
var kind: StringName
var source_id: StringName
var priority := 0.0
var urgency := 0.0 ## base urgency; grows by `urgency_rate` per second until the deadline
var urgency_rate := 0.0
var required_tags := PackedStringArray()
var station_id: StringName ## optional
var slots := 1 ## several agents may claim a multi-slot job (an all-hands reef)
var ttl_s := 120.0 ## expires this long after posting even if claimed; <= 0 means never
var override := &"" ## "" | must_staff | emergency | all_hands
var action: Resource ## NpcActionDef, null = the kind's default
var payload := {} ## source-private data (lantern id, sail index, ...)
var claimed_by: Array[StringName] = []
var posted_at := 0.0 ## logical seconds, stamped by the board on first post

func deadline() -> float:
	return posted_at + ttl_s if ttl_s > 0.0 else INF

func free_slots() -> int:
	return maxi(slots - claimed_by.size(), 0)

func has_tags(agent_tags: PackedStringArray) -> bool:
	for t in required_tags:
		if not agent_tags.has(t):
			return false
	return true

## Copies the descriptive fields of `other` into this job (the board keeps claims and the posting time).
func update_from(other: NpcJob) -> void:
	kind = other.kind
	source_id = other.source_id
	priority = other.priority
	urgency = other.urgency
	urgency_rate = other.urgency_rate
	required_tags = other.required_tags
	station_id = other.station_id
	slots = other.slots
	ttl_s = other.ttl_s
	override = other.override
	action = other.action
	payload = other.payload
