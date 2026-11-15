extends GutTest
## Specs: npc-life-stations (declaration, claim/release, stale claims, moving parent, IK targets).

class FakeAgent extends Node:
	var agent_id: StringName = &"a"
	var tags: PackedStringArray = PackedStringArray()
	func _init(id: StringName = &"a", t: PackedStringArray = PackedStringArray()) -> void:
		agent_id = id
		tags = t
		name = String(id)

func _station() -> NpcStation:
	var st := NpcStation.new()
	add_child_autofree(st)
	return st

func _agent(id: StringName, tags := PackedStringArray()) -> FakeAgent:
	var a := FakeAgent.new(id, tags)
	add_child_autofree(a)
	return a

func test_declaration_defaults() -> void:
	var st := _station()
	assert_eq(st.capacity(), 1, "one slot by default")
	assert_eq(st.free_slots(), 1)
	assert_true(st.is_free())
	assert_eq(st.occupant(0), &"")
	assert_eq(st.facing_deg, 0.0)
	assert_eq(st.required_tags.size(), 0)

func test_multi_slot_capacity() -> void:
	var st := _station()
	st.slot_count = 3
	assert_eq(st.capacity(), 3)
	assert_eq(st.free_slots(), 3)

func test_claim_release_single_slot() -> void:
	var st := _station()
	var a := _agent(&"A")
	watch_signals(st)
	var slot := st.claim(a)
	assert_eq(slot, 0, "first claim gets slot 0")
	assert_false(st.is_free())
	assert_eq(st.occupant(0), &"A")
	assert_signal_emit_count(st, "claimed", 1)
	st.release(a)
	assert_true(st.is_free())
	assert_signal_emit_count(st, "released", 1)

func test_release_without_claim_is_noop() -> void:
	var st := _station()
	var a := _agent(&"A")
	watch_signals(st)
	st.release(a)
	assert_true(st.is_free())
	assert_signal_emit_count(st, "released", 0)

func test_multi_slot_claim_returns_distinct_slots() -> void:
	var st := _station()
	st.slot_count = 3
	var slots := []
	for id in [&"A", &"B", &"C"]:
		slots.append(st.claim(_agent(id)))
	slots.sort()
	assert_eq(slots, [0, 1, 2])
	assert_eq(st.claim(_agent(&"D")), -1, "no fourth slot")
	assert_eq(st.free_slots(), 0)

func test_competing_claims_one_winner() -> void:
	var st := _station()
	var a := _agent(&"A")
	var b := _agent(&"B")
	var ra := st.claim(a)
	var rb := st.claim(b)
	assert_true((ra >= 0) != (rb >= 0), "exactly one succeeds")
	assert_eq(st.occupant(0), &"A", "loser leaves no trace")

func test_same_agent_claims_once() -> void:
	var st := _station()
	st.slot_count = 2
	var a := _agent(&"A")
	assert_eq(st.claim(a), 0)
	assert_eq(st.claim(a), 0, "second claim by the holder returns its slot, no extra slot taken")
	assert_eq(st.free_slots(), 1)

func test_required_tags_reject_agent() -> void:
	var st := _station()
	st.required_tags = PackedStringArray(["climber"])
	var plain := _agent(&"P")
	var climber := _agent(&"C", PackedStringArray(["climber"]))
	assert_eq(st.claim(plain), -1)
	assert_true(st.is_free(), "occupancy unchanged after rejection")
	assert_eq(st.claim(climber), 0)

func test_stale_claim_released_on_agent_freed() -> void:
	var st := _station()
	var a := FakeAgent.new(&"A")
	add_child(a)
	st.claim(a)
	assert_false(st.is_free())
	a.free()
	assert_true(st.is_free(), "slot released in the same frame the agent leaves the tree")

func test_anchor_local_follows_moving_parent() -> void:
	var platform := Node3D.new()
	add_child_autofree(platform)
	var st := NpcStation.new()
	st.position = Vector3(2, 0, -1)
	platform.add_child(st)
	var local0 := st.anchor_local(0, platform)
	var world0 := st.anchor_world(0)
	platform.rotation.y = deg_to_rad(60.0)
	platform.position = Vector3(5, 0, 3)
	var local1 := st.anchor_local(0, platform)
	assert_true(local0.origin.is_equal_approx(local1.origin), "platform-local anchor unchanged by platform motion")
	assert_almost_eq(st.anchor_world(0).distance_to(st.global_transform * Vector3.ZERO), 0.0, 1e-4)
	assert_false(st.anchor_world(0).is_equal_approx(world0), "world anchor follows the platform")
	# approach point: local offset resolved against the platform too
	var ap := st.approach_local(0, platform)
	assert_true(ap.is_equal_approx(local1.origin + local1.basis * st.approach_offset))

func test_slot_override_anchor() -> void:
	var st := _station()
	st.slot_count = 2
	var s1 := NpcStationSlot.new()
	s1.position = Vector3(0.5, 0, 0)
	s1.slot_index = 1
	st.add_child(s1)
	var platform := Node3D.new()
	add_child_autofree(platform)
	assert_true(st.anchor_local(0, platform).origin.is_equal_approx(Vector3.ZERO))
	assert_true(st.anchor_local(1, platform).origin.is_equal_approx(Vector3(0.5, 0, 0)))

func test_ik_target_absent_returns_null() -> void:
	var st := _station()
	var m := Marker3D.new()
	m.name = "hand_r"
	st.add_child(m)
	st.ik_targets = {&"hand_r": NodePath("hand_r")}
	assert_eq(st.ik_target(&"hand_r"), m)
	assert_eq(st.get_ik_target(&"hand_r"), m)
	assert_null(st.ik_target(&"look_at"))
	assert_null(st.get_ik_target(&"look_at"))
