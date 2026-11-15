class_name NpcStation
extends Node3D
## A smart object: where and how an agent works, and who occupies it. Everything spatial is expressed in the station's own local space, so a
## station parented to a rolling ship or a rotating raft stays correct; world / platform-local values are resolved on demand.
## Slots: `slot_count` of them, optionally positioned by NpcStationSlot children (matched by `slot_index`).

signal claimed(agent_id: StringName, slot: int)
signal released(agent_id: StringName, slot: int)

@export var station_id: StringName
@export var kind: StringName
@export var tags: PackedStringArray
@export var slot_count := 1:
	set(v):
		slot_count = maxi(v, 1)
		_resize_occupants()
## Approach point, local to the station (or to the slot marker that overrides it).
@export var approach_offset := Vector3(0, 0, 0.6)
## Yaw about the platform's +Y: 0 = -Z (bow), +90 = -X (port). Same convention as the ship lanterns.
@export var facing_deg := 0.0
@export var anim_tag: StringName
## IK target markers by chain name (`hand_l`, `hand_r`, `look_at`, ...): paths relative to this station; the target may move every frame.
@export var ik_targets: Dictionary[StringName, NodePath] = {}
## The agent must carry every one of these tags to claim a slot.
@export var required_tags: PackedStringArray
## Minimum value of the agent's skill `skill_key` (checked only when the claimant exposes `skill_for(key)`).
@export var min_skill := 0.0
@export var skill_key: StringName
## A roster may keep this station staffed (helm, watch posts).
@export var must_staff := false

var _occupants: Array[StringName] = [&""]
var _watched: Dictionary = {} # agent_id -> Node whose tree_exiting is connected

func _init() -> void:
	_resize_occupants()

func _enter_tree() -> void:
	add_to_group(&"npc_station")

func _resize_occupants() -> void:
	var old := _occupants.size()
	_occupants.resize(slot_count)
	for i in range(old, slot_count):
		_occupants[i] = &""

# ---- occupancy ---------------------------------------------------------------------------------------------------------------------------

func capacity() -> int:
	return slot_count

func free_slots() -> int:
	var n := 0
	for o in _occupants:
		if o == &"":
			n += 1
	return n

## True when at least one slot is free.
func is_free() -> bool:
	return free_slots() > 0

func occupant(slot: int) -> StringName:
	return _occupants[slot] if slot >= 0 and slot < _occupants.size() else &""

func slot_of(who: Variant) -> int:
	return _occupants.find(_id_of(who))

## Claims a slot for `who` (an agent Node or an agent id). Returns the slot index, or -1 on failure (no free slot, requested slot taken,
## constraints not met). The holder claiming again gets its own slot back. `agent_tags` adds tags for plain-id claimants.
func claim(who: Variant, slot := -1, agent_tags := PackedStringArray()) -> int:
	var id := _id_of(who)
	if id == &"":
		return -1
	var held := _occupants.find(id)
	if held >= 0:
		return held
	if not _eligible(who, agent_tags):
		return -1
	var s := slot
	if s < 0:
		s = _occupants.find(&"")
	elif s >= _occupants.size() or _occupants[s] != &"":
		s = -1
	if s < 0:
		return -1
	_occupants[s] = id
	if who is Node and not _watched.has(id):
		_watched[id] = who
		(who as Node).tree_exiting.connect(_on_claimant_exiting.bind(id), CONNECT_ONE_SHOT)
	claimed.emit(id, s)
	return s

## Releases the slot held by `who`; a no-op when it holds none.
func release(who: Variant) -> void:
	var id := _id_of(who)
	var s := _occupants.find(id)
	if id == &"" or s < 0:
		return
	_occupants[s] = &""
	if _watched.has(id):
		var n: Node = _watched[id]
		if is_instance_valid(n) and n.tree_exiting.is_connected(_on_claimant_exiting.bind(id)):
			n.tree_exiting.disconnect(_on_claimant_exiting.bind(id))
		_watched.erase(id)
	released.emit(id, s)

func _on_claimant_exiting(id: StringName) -> void:
	_watched.erase(id)
	var s := _occupants.find(id)
	if s >= 0:
		_occupants[s] = &""
		released.emit(id, s)

func _eligible(who: Variant, agent_tags: PackedStringArray) -> bool:
	var have := agent_tags
	if who is Object and "tags" in who:
		have = have + PackedStringArray(who.tags)
	for t in required_tags:
		if not have.has(t):
			return false
	if min_skill > 0.0 and skill_key != &"" and who is Object and who.has_method("skill_for"):
		if float(who.skill_for(skill_key)) < min_skill:
			return false
	return true

static func _id_of(who: Variant) -> StringName:
	if who is StringName or who is String:
		return StringName(who)
	if who is Object:
		if "agent_id" in who and StringName(who.agent_id) != &"":
			return StringName(who.agent_id)
		if who is Node:
			return StringName((who as Node).name)
	return &""

# ---- spatial -----------------------------------------------------------------------------------------------------------------------------

func _slot_node(slot: int) -> NpcStationSlot:
	for c in get_children():
		if c is NpcStationSlot and (c as NpcStationSlot).slot_index == slot:
			return c
	return null

## Work anchor of a slot in the local space of `platform` (the station's own transform when no platform is given).
func anchor_local(slot: int, platform: Node3D) -> Transform3D:
	var sn := _slot_node(slot)
	var g := sn.global_transform if sn else global_transform
	return platform.global_transform.affine_inverse() * g if platform else g

func anchor_world(slot: int) -> Vector3:
	var sn := _slot_node(slot)
	return (sn.global_transform if sn else global_transform).origin

## Approach point of a slot in `platform` space (walk here, then align to the anchor).
func approach_local(slot: int, platform: Node3D) -> Vector3:
	var sn := _slot_node(slot)
	var off := sn.approach_offset if (sn and sn.use_approach) else approach_offset
	var a := anchor_local(slot, platform)
	return a.origin + a.basis * off

## Yaw (radians) the agent should face while working, about the platform's +Y (0 = -Z).
func facing_local(slot: int, platform: Node3D) -> float:
	var sn := _slot_node(slot)
	var deg := sn.facing_deg if (sn and sn.use_facing) else facing_deg
	var a := anchor_local(slot, platform)
	return a.basis.get_euler().y + deg_to_rad(deg)

## IK target marker for a chain, or null when absent (never an error).
func ik_target(chain: StringName) -> Node3D:
	if not ik_targets.has(chain):
		return null
	return get_node_or_null(ik_targets[chain]) as Node3D

func get_ik_target(chain: StringName) -> Node3D:
	return ik_target(chain)
