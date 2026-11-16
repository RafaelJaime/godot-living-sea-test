class_name NpcAnimationAdapter
extends RefCounted
## Abstract animation interface. Agents talk to animation only through it, so a game can supply its own implementation (an AnimationTree,
## sprite sheets, anything). The base class is inert: every method is a safe no-op.

## Binds to a character's visual root. False when nothing animatable was found.
func bind(_agent: Node, _visual_root: Node) -> bool:
	return false

## Plays the clip behind `tag` with a crossfade of `blend` seconds.
func play(_tag: StringName, _loop := true, _blend := 0.35) -> void:
	pass

func has_tag(_tag: StringName) -> bool:
	return false

func current_tag() -> StringName:
	return &""

## Locomotion for the edge type being walked (walk, stairs, ladder, rope) at `speed` m/s: picks the matching tag.
func set_locomotion(_edge_type: StringName, _speed: float) -> void:
	pass

## Attaches a prop scene at a socket (hand, belt, ...). Null when the adapter cannot.
## Called when the agent leaves a locomotion edge of type `_from_edge_type` for another one. Returns how many seconds a transition clip takes (the agent
## stands still for that long), 0.0 when there is none.
func exit_transition(_from_edge_type: StringName) -> float:
	return 0.0

func attach_prop(_scene: PackedScene, _socket: StringName) -> Node3D:
	return null

## Per-frame hook for adapters that animate procedurally.
func process(_delta: float) -> void:
	pass
