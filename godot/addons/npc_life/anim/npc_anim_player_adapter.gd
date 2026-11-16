class_name NpcAnimPlayerAdapter
extends NpcAnimationAdapter
## Default adapter: an AnimationPlayer under the character's visual root plus an NpcAnimSet. Crossfades with the player's blend times, installs the
## set's library with Hips position tracks scaled by the hip-height ratio (so differently proportioned characters neither sink nor float), attaches
## props through BoneAttachment3D.

var anim_set: NpcAnimSet
var rig_profile: NpcRigProfile
## Walk speed the shared walk clip was authored for; locomotion speed scales playback relative to it.
var reference_speed := 1.2

## Emitted whenever a different tag starts (a crossfade of `blend` seconds from the previous clip).
signal tag_changed(from_tag: StringName, to_tag: StringName, blend: float)

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _tag: StringName = &""
var _clip: StringName = &""

func bind(_agent: Node, visual_root: Node) -> bool:
	if visual_root == null or anim_set == null:
		return false
	var players := visual_root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return false
	_player = players[0]
	var sks := visual_root.find_children("*", "Skeleton3D", true, false)
	_skeleton = sks[0] if not sks.is_empty() else null
	if anim_set.library != null:
		_install(anim_set.library)
	return true

func _install(src: AnimationLibrary) -> void:
	var hips_name := String(rig_profile.hips_bone) if rig_profile else "Hips"
	var ratio := 1.0
	var src_hips := float(src.get_meta("source_hips_y", 0.0))
	if _skeleton != null and src_hips > 0.0:
		var hi := _skeleton.find_bone(hips_name)
		if hi >= 0:
			ratio = _skeleton.get_bone_global_rest(hi).origin.y / src_hips
	var lib := AnimationLibrary.new()
	for n in src.get_animation_list():
		var a := src.get_animation(n).duplicate() as Animation
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t)).ends_with(":" + hips_name):
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * ratio)
		lib.add_animation(n, a)
	var lname := String(anim_set.library_name)
	if _player.has_animation_library(lname):
		_player.remove_animation_library(lname)
	_player.add_animation_library(lname, lib)

func has_tag(tag: StringName) -> bool:
	return _player != null and anim_set.has_tag(tag) and _player.has_animation(String(anim_set.resolve(tag)))

func current_tag() -> StringName:
	return _tag

func play(tag: StringName, loop := true, blend := 0.35) -> void:
	if _player == null:
		return
	var clip := anim_set.resolve(tag)
	if clip == &"" or not _player.has_animation(String(clip)):
		return
	if _clip != &"" and _clip != clip:
		_player.set_blend_time(String(_clip), String(clip), blend)
	var anim := _player.get_animation(String(clip))
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_player.play(String(clip))
	if tag != _tag:
		tag_changed.emit(_tag, tag, blend)
	_tag = tag
	_clip = clip

var _exit_clip: StringName = &""
var _pending_tag: StringName = &""
var _pending_speed := 1.0

func exit_transition(from_edge_type: StringName) -> float:
	var tag: StringName = anim_set.exit_tags.get(from_edge_type, &"")
	if _player == null or tag == &"":
		return 0.0
	var clip := anim_set.resolve(tag)
	if clip == &"" or not _player.has_animation(String(clip)):
		return 0.0
	if not _player.animation_finished.is_connected(_on_clip_finished):
		_player.animation_finished.connect(_on_clip_finished)
	play(tag, false)
	_player.speed_scale = 1.0
	_exit_clip = clip
	_pending_tag = &""
	return _player.get_animation(String(clip)).length

func _on_clip_finished(clip_name: StringName) -> void:
	if _exit_clip == &"" or clip_name != _exit_clip:
		return
	_exit_clip = &""
	if _pending_tag != &"":
		var t := _pending_tag
		_pending_tag = &""
		play(t)
		_player.speed_scale = clampf(_pending_speed / maxf(float(anim_set.clip_speeds.get(t, reference_speed)), 0.01), 0.25, 2.5)

func set_locomotion(edge_type: StringName, speed: float) -> void:
	if _player == null:
		return
	if _exit_clip != &"": # a transition clip is playing: the next locomotion waits for it
		_pending_tag = anim_set.locomotion_tag(edge_type)
		_pending_speed = speed
		return
	var tag := anim_set.locomotion_tag(edge_type)
	if tag != _tag:
		play(tag)
	_player.speed_scale = clampf(speed / maxf(float(anim_set.clip_speeds.get(tag, reference_speed)), 0.01), 0.25, 2.5)

func attach_prop(scene: PackedScene, socket: StringName) -> Node3D:
	if _skeleton == null or scene == null:
		return null
	var bone := String(rig_profile.sockets.get(socket, socket)) if rig_profile else String(socket)
	if _skeleton.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skeleton.add_child(att)
	var prop := scene.instantiate() as Node3D
	att.add_child(prop)
	return prop
