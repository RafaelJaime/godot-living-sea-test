class_name NpcActionDef
extends Resource
## A generic or signature action: which job kinds it can perform, its animation tag, how long the WORK phase lasts, when its world effect
## fires, optional IK usage and look-at, optional required station kind, and a cooldown.

@export var action_id: StringName
@export var job_kinds: PackedStringArray
@export var anim_tag: StringName
@export var duration_range := Vector2(6.0, 14.0) ## seconds of the WORK phase
@export var effect_at := 0.5 ## fraction of WORK when job_effect fires
@export var effect: StringName ## e.g. &"light", &"haul"
@export var ik: Dictionary[StringName, StringName] = {} ## chain -> station IK target key
@export var look_at: StringName ## station IK key or &"partner" / &"performer"
@export var props: Array[PackedScene] ## optional props the animation adapter attaches (spyglass, hammer)
@export var station_kind: StringName ## optional: only usable at this station kind
@export var cooldown_s := 0.0

## True when the action may be performed again: never performed (`last_done_at < 0`) or the cooldown elapsed.
func is_ready(last_done_at: float, now: float) -> bool:
	return cooldown_s <= 0.0 or last_done_at < 0.0 or now - last_done_at >= cooldown_s

## Violations by field name (empty = valid).
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if action_id == &"":
		out.append("action.action_id: empty")
	if duration_range.x <= 0.0 or duration_range.y < duration_range.x:
		out.append("action[%s].duration_range: %s must be positive with y >= x" % [action_id, duration_range])
	if effect_at < 0.0 or effect_at > 1.0:
		out.append("action[%s].effect_at: %s out of range 0..1" % [action_id, effect_at])
	if cooldown_s < 0.0:
		out.append("action[%s].cooldown_s: %s is negative" % [action_id, cooldown_s])
	return out
