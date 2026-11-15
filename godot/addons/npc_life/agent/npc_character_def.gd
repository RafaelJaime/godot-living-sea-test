class_name NpcCharacterDef
extends Resource
## Who an agent is: roles and tags (which jobs it may take), preferences, skills, needs, signature actions and personality. Editable in the
## inspector, game-agnostic. Policy for out-of-range values: `validate()` reports them without touching anything, `sanitize()` clamps them
## in place and returns the same report.

@export var agent_id: StringName
@export var display_name: String
## Role names; they also act as tags (a role `climber` makes jobs that require `climber` eligible).
@export var roles: PackedStringArray
@export var tags: PackedStringArray
## Job kind -> -1..1 (dislike .. like). Missing kinds are neutral (0).
@export var preferences: Dictionary[StringName, float] = {}
## Job kind or roster watch -> 0..1. Missing entries are 0.5.
@export var skills: Dictionary[StringName, float] = {}
## Need -> growth per minute.
@export var needs: Dictionary[StringName, float] = {}
@export var signature_actions: Array[NpcActionDef]
@export var anim_set: Resource ## NpcAnimSet (animation slice)
@export var rig_profile: Resource ## NpcRigProfile (animation slice)
## Personality: more (>1) or less (<1) erratic than the world's softmax temperature.
@export var temperature_scale := 1.0
@export var walk_speed := 1.2

func skill_for(key: StringName) -> float:
	return skills.get(key, 0.5)

func preference_for(kind: StringName) -> float:
	return preferences.get(kind, 0.0)

## Roles and tags together, without duplicates.
func all_tags() -> PackedStringArray:
	var out := PackedStringArray()
	for t in roles:
		if not out.has(t):
			out.append(t)
	for t in tags:
		if not out.has(t):
			out.append(t)
	return out

## Violations by field name. `known_kinds` (when not empty) flags preference / skill keys that are no job kind or role; `anim_tags` (when not
## empty) flags signature actions whose animation tag the animation set cannot play.
func validate(known_kinds := PackedStringArray(), anim_tags := PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	if agent_id == &"":
		out.append("agent_id: empty")
	for k in preferences:
		if preferences[k] < -1.0 or preferences[k] > 1.0:
			out.append("preferences[%s]: %s out of range -1..1" % [k, preferences[k]])
		if not known_kinds.is_empty() and not known_kinds.has(k):
			out.append("preferences[%s]: unknown job kind" % k)
	for k in skills:
		if skills[k] < 0.0 or skills[k] > 1.0:
			out.append("skills[%s]: %s out of range 0..1" % [k, skills[k]])
		if not known_kinds.is_empty() and not known_kinds.has(k) and not roles.has(k):
			out.append("skills[%s]: unknown job kind or role" % k)
	if walk_speed <= 0.0:
		out.append("walk_speed: %s must be positive" % walk_speed)
	if temperature_scale <= 0.0:
		out.append("temperature_scale: %s must be positive" % temperature_scale)
	for a in signature_actions:
		if a == null:
			out.append("signature_actions: null entry")
			continue
		out.append_array(a.validate())
		if not anim_tags.is_empty() and a.anim_tag != &"" and not anim_tags.has(a.anim_tag):
			out.append("signature_actions[%s].anim_tag: '%s' not in the animation set" % [a.action_id, a.anim_tag])
	return out

## Clamps preferences to -1..1 and skills to 0..1 in place; returns the violations that were fixed (same text as `validate`).
func sanitize() -> PackedStringArray:
	var fixed := PackedStringArray()
	for k in preferences.keys():
		var v: float = preferences[k]
		if v < -1.0 or v > 1.0:
			fixed.append("preferences[%s]: %s out of range -1..1" % [k, v])
			preferences[k] = clampf(v, -1.0, 1.0)
	for k in skills.keys():
		var v: float = skills[k]
		if v < 0.0 or v > 1.0:
			fixed.append("skills[%s]: %s out of range 0..1" % [k, v])
			skills[k] = clampf(v, 0.0, 1.0)
	return fixed
