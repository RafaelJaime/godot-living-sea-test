class_name NpcAnimSet
extends Resource
## Tag -> clip resolution for one character: signature clips first, then the shared library, then the fallback tag (the miss is logged once
## per tag). Edge types map to locomotion tags. Clip names are whatever the animation player calls them (`shared/walk`); jobs and stations only
## ever talk about tags.

## Optional library the adapter installs into the player (the addon ships none; the game provides it). Meta `source_hips_y` enables hip-ratio scaling.
@export var library: AnimationLibrary
@export var library_name: StringName = &"shared"
## tag -> clip, shared by all characters.
@export var shared: Dictionary[StringName, StringName] = {}
## tag -> clip, only for this character (wins over `shared`).
@export var signature: Dictionary[StringName, StringName] = {}
## Edge type (walk, stairs, ladder, rope) -> locomotion tag.
@export var locomotion: Dictionary[StringName, StringName] = {}
@export var fallback_tag: StringName = &"idle"

var _missing: Array[StringName] = []

func has_tag(tag: StringName) -> bool:
	return signature.has(tag) or shared.has(tag)

func tags() -> PackedStringArray:
	var out := PackedStringArray()
	for k in shared:
		out.append(String(k))
	for k in signature:
		if not out.has(String(k)):
			out.append(String(k))
	return out

func _clip(tag: StringName) -> StringName:
	if signature.has(tag):
		return signature[tag]
	return shared.get(tag, &"")

## The clip for a tag (signature, shared, fallback). A tag without any clip is recorded once and answered by the fallback tag's clip.
func resolve(tag: StringName) -> StringName:
	var c := _clip(tag)
	if c != &"":
		return c
	if not _missing.has(tag):
		_missing.append(tag)
		push_warning("[npc_life] animation tag '%s' has no clip, using fallback '%s'" % [tag, fallback_tag])
	return _clip(fallback_tag)

func missing_tags() -> Array[StringName]:
	return _missing

func locomotion_tag(edge_type: StringName) -> StringName:
	return locomotion.get(edge_type, &"walk")

## Problems: required tags without a clip, a fallback tag without a clip.
func validate(required_tags := PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	for t in required_tags:
		if not has_tag(StringName(t)):
			out.append("anim_set: tag '%s' has no clip" % t)
	if _clip(fallback_tag) == &"":
		out.append("anim_set: fallback tag '%s' has no clip" % fallback_tag)
	return out
