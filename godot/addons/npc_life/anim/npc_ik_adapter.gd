class_name NpcIkAdapter
extends RefCounted
## Abstract procedural-IK interface: reach (hand targets), look-at and release, with blend-in / blend-out weights. No engine IK type appears in
## any signature, so a game can implement it with anything. The base class is inert.

## Binds to a skeleton and rig profile. False when the rig lacks the chains.
func bind(_agent: Node3D, _skeleton: Skeleton3D, _profile: NpcRigProfile) -> bool:
	return false

## Reach `chain` (`hand_l`, `hand_r`, ...) toward `target`; the weight ramps to `weight` over `ramp_s`. The target is re-read every frame.
func set_target(_chain: StringName, _target: Node3D, _weight := 1.0, _ramp_s := 1.2) -> void:
	pass

## Releases a chain: the weight ramps to 0 over `ramp_s`.
func clear(_chain: StringName, _ramp_s := 0.5) -> void:
	pass

## Look at `target` (null releases the gaze).
func set_look_at(_target: Node3D, _weight := 1.0) -> void:
	pass

## Per-frame update (clamping proxies, ramps); the agent calls it.
func process(_delta: float) -> void:
	pass
