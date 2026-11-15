class_name NpcProceduralAdapter
extends NpcAnimationAdapter
## Skeleton-less adapter for puppets (capsules, sprites, the example scene): bobs and tilts the visual root according to the tag.

const TAGS := [&"idle", &"walk", &"work", &"climb_ladder", &"climb", &"talk", &"stairs"]

var _root: Node3D
var _rest := Vector3.ZERO
var _tag: StringName = &"idle"
var _t := 0.0
var _amp := 0.0
var _tilt := 0.0

func bind(_agent: Node, visual_root: Node) -> bool:
	_root = visual_root as Node3D
	if _root:
		_rest = _root.position
	return _root != null

func has_tag(tag: StringName) -> bool:
	return TAGS.has(tag)

func current_tag() -> StringName:
	return _tag

func play(tag: StringName, _loop := true, _blend := 0.35) -> void:
	_tag = tag

func set_locomotion(edge_type: StringName, _speed: float) -> void:
	_tag = &"climb_ladder" if edge_type == &"ladder" else &"walk"

func process(delta: float) -> void:
	if _root == null:
		return
	_t += delta
	var want_amp := 0.0
	var want_tilt := 0.0
	var freq := 9.0
	match _tag:
		&"walk", &"stairs":
			want_amp = 0.05
			want_tilt = 0.05
		&"climb_ladder", &"climb":
			want_amp = 0.04
			freq = 5.0
		&"work", &"talk":
			want_amp = 0.015
			freq = 4.0
	_amp = lerpf(_amp, want_amp, 1.0 - exp(-8.0 * delta))
	_tilt = lerpf(_tilt, want_tilt, 1.0 - exp(-8.0 * delta))
	_root.position.y = _rest.y + sin(_t * freq) * _amp
	_root.rotation.z = sin(_t * freq * 0.5) * _tilt
