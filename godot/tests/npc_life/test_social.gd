extends GutTest
## Specs: npc-life-social (gatherings, two-party conversation, audience around a performer, join and leave offers, social seeding).

class StubAnim extends NpcAnimationAdapter:
	var plays: Array = []
	func bind(_a: Node, _v: Node) -> bool: return true
	func play(tag: StringName, _loop := true, _blend := 0.35) -> void: plays.append(tag)

class StubIk extends NpcIkAdapter:
	var looks: Array = []
	func bind(_a: Node3D, _s: Skeleton3D, _p: NpcRigProfile) -> bool: return true
	func set_look_at(target: Node3D, _weight := 1.0) -> void: looks.append(target)

var world: NpcWorld
var social: NpcSocialDirector
var events: Array = []

func before_each() -> void:
	events = []
	world = NpcWorld.new()
	world.world_seed = 31
	add_child_autofree(world)
	world.job_finished.connect(func(job: NpcJob, _id: StringName, _r: StringName) -> void:
		if job.kind == &"craft":
			world.board.clear(job.id))

func _agent(id: StringName, pos := Vector3.ZERO, tags := PackedStringArray()) -> NpcAgent:
	var d := NpcCharacterDef.new()
	d.agent_id = id
	d.tags = tags
	var a := NpcAgent.new()
	a.def = d
	a.position = pos
	world.add_child(a)
	a.anim = StubAnim.new()
	a.ik = StubIk.new()
	return a

func _station(id: StringName, kind: StringName, pos: Vector3, slots := 1, tags := PackedStringArray()) -> NpcStation:
	var s := NpcStation.new()
	s.station_id = id
	s.kind = kind
	s.position = pos
	s.slot_count = slots
	s.tags = tags
	s.approach_offset = Vector3.ZERO
	world.add_child(s)
	return s

func _start() -> void:
	social = NpcSocialDirector.new()
	social.source_id = &"social"
	world.add_child(social)
	social.gathering_started.connect(func(spot: StringName, agents: Array) -> void: events.append(["gathering_started", spot, agents.size()]))
	social.gathering_ended.connect(func(spot: StringName, reason: StringName) -> void: events.append(["gathering_ended", spot, reason]))
	social.conversation_started.connect(func(a: StringName, b: StringName) -> void: events.append(["conversation_started", a, b, world.now()]))
	social.conversation_ended.connect(func(a: StringName, b: StringName) -> void: events.append(["conversation_ended", a, b]))

func _run(seconds: float) -> void:
	for i in int(round(seconds / 0.1)):
		world.advance(0.1)

func _count(kind: String) -> int:
	return events.filter(func(e: Array) -> bool: return e[0] == kind).size()

func _yaw_dir(a: Node3D) -> Vector3:
	return -a.global_transform.basis.z

# ---- gatherings -------------------------------------------------------------------------------------------------------------------------------

func test_gathering_multi_slot_station() -> void:
	_station(&"campfire", &"social_spot", Vector3(3, 0, 0), 3, PackedStringArray(["social"]))
	_agent(&"A")
	_agent(&"B")
	_agent(&"C")
	_start()
	social.gathering_duration = Vector2(20.0, 20.0)
	_run(1.0)
	assert_not_null(world.board.get_job(&"gather:campfire"), "a join offer is on the board while the spot has capacity")
	assert_eq(world.board.get_job(&"gather:campfire").slots, 3)
	_run(12.0)
	assert_eq(_count("gathering_started"), 1, "a gathering forms once two members arrived")
	assert_gte(events[0][2], 2)

func test_gathering_ends_on_timer() -> void:
	_station(&"campfire", &"social_spot", Vector3(3, 0, 0), 3, PackedStringArray(["social"]))
	_agent(&"A")
	_agent(&"B")
	_start()
	social.gathering_duration = Vector2(8.0, 8.0)
	_run(30.0)
	var ended := events.filter(func(e: Array) -> bool: return e[0] == "gathering_ended")
	assert_gt(ended.size(), 0)
	assert_eq(ended[0][2], &"timer")

func test_gathering_ends_when_override_pulls_members() -> void:
	_station(&"campfire", &"social_spot", Vector3(3, 0, 0), 3, PackedStringArray(["social"]))
	_agent(&"A")
	_agent(&"B")
	_start()
	social.gathering_duration = Vector2(60.0, 60.0)
	_run(10.0)
	assert_eq(_count("gathering_started"), 1)
	var em := NpcJob.new()
	em.id = &"alarm"
	em.kind = &"alarm"
	em.override = &"emergency"
	em.slots = 2
	em.ttl_s = 0.0
	world.board.post(em, world.now())
	_run(3.0)
	var ended := events.filter(func(e: Array) -> bool: return e[0] == "gathering_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0][2], &"members", "fewer than two members left")

func test_join_offer_gone_when_full() -> void:
	_station(&"campfire", &"social_spot", Vector3(1, 0, 0), 2, PackedStringArray(["social"]))
	_agent(&"A")
	_agent(&"B")
	_agent(&"C")
	_start()
	_run(5.0)
	var offer := world.board.get_job(&"gather:campfire")
	assert_not_null(offer)
	assert_eq(offer.claimed_by.size(), 2)
	assert_eq(world.board.candidates(&"C", PackedStringArray()).filter(func(j: NpcJob) -> bool: return j.id == &"gather:campfire").size(), 0, "full: no longer offered to anyone else")

# ---- conversations ----------------------------------------------------------------------------------------------------------------------------

func test_conversation_offer_claimed_by_one_partner() -> void:
	var a := _agent(&"A", Vector3(0, 0, 0))
	_agent(&"B", Vector3(6, 0, 0))
	_agent(&"C", Vector3(-6, 0, 0))
	_start()
	social.chat_cooldown_s = 1000.0
	_run(0.5)
	var id := social.offer_chat(&"A")
	assert_ne(id, &"", "the initiator holds an ambient job and can offer")
	assert_eq(world.board.get_job(id).slots, 1, "claimable by exactly one partner")
	_run(12.0)
	assert_eq(_count("conversation_started"), 1)
	var partner: StringName = events.filter(func(e: Array) -> bool: return e[0] == "conversation_started")[0][2]
	assert_true(partner in [&"B", &"C"])
	assert_not_null(a)

func test_conversation_lifecycle_faces_alternates_and_releases() -> void:
	var a := _agent(&"A", Vector3(0, 0, 0))
	var b := _agent(&"B", Vector3(5, 0, 0))
	_start()
	social.chat_cooldown_s = 1000.0
	social.conversation_duration = Vector2(12.0, 12.0)
	_run(0.5)
	social.offer_chat(&"A")
	var checked := false
	for i in 320:
		world.advance(0.1)
		if _count("conversation_started") == 1 and not checked and world.now() > events[0][3] + 1.0:
			var ab := (b.global_position - a.global_position).normalized()
			assert_lt(rad_to_deg(_yaw_dir(a).angle_to(ab)), 20.0, "A faces B")
			assert_lt(rad_to_deg(_yaw_dir(b).angle_to(-ab)), 20.0, "B faces A")
			assert_lt(a.global_position.distance_to(b.global_position), 1.6, "at speaking distance")
			assert_true((a.ik as StubIk).looks.has(b) and (b.ik as StubIk).looks.has(a), "both look at the partner")
			checked = true
	assert_true(checked)
	assert_eq(_count("conversation_ended"), 1)
	var tags_a := (a.anim as StubAnim).plays.filter(func(t: StringName) -> bool: return t == &"talk" or t == &"listen")
	assert_gte(tags_a.size(), 3, "speaker and listener tags alternate at least twice")
	assert_ne(tags_a[0], tags_a[1])
	assert_false(String(world.get_agent(&"B").current_job_id()).begins_with("chat:"), "B is free to pick jobs again")
	assert_false(String(world.get_agent(&"A").current_job_id()).begins_with("ambient:A:1") and world.get_agent(&"A").current_job().kind == &"ambient_chat_offer", "A left its chat offer")
	assert_true((a.ik as StubIk).looks.back() == null and (b.ik as StubIk).looks.back() == null, "the gaze is released")

func test_offer_declined_no_deadlock() -> void:
	_agent(&"A", Vector3(0, 0, 0))
	_agent(&"B", Vector3(5, 0, 0), PackedStringArray(["worker"]))
	_start()
	social.chat_cooldown_s = 1000.0
	social.chat_offer_ttl_s = 6.0
	_run(0.5)
	social.offer_chat(&"A")
	var big := NpcJob.new() # B has a much better job: it declines the offer by not picking it
	big.id = &"urgent_chore"
	big.kind = &"chore"
	big.priority = 50.0
	big.required_tags = PackedStringArray(["worker"]) # only B can take it
	big.ttl_s = 0.0
	var act := NpcActionDef.new()
	act.duration_range = Vector2(40.0, 40.0)
	big.action = act
	world.board.post(big, world.now())
	_run(20.0)
	assert_eq(_count("conversation_started"), 0)
	assert_eq(world.get_agent(&"B").current_job_id(), &"urgent_chore")
	assert_ne(world.get_agent(&"A").current_job_id(), &"", "A moved on: no deadlock")
	assert_null(world.board.get_job(&"chat:A:1"), "the unclaimed offer expired")

func test_social_seeding_same_seed_same_offers() -> void:
	var logs := []
	for run in 2:
		events = []
		var w := NpcWorld.new()
		w.world_seed = 77
		add_child_autofree(w)
		for id in [&"A", &"B", &"C"]:
			var d := NpcCharacterDef.new()
			d.agent_id = id
			var ag := NpcAgent.new()
			ag.def = d
			ag.position = Vector3(float(String(id).unicode_at(0) - 65) * 2.0, 0, 0)
			w.add_child(ag)
		var sd := NpcSocialDirector.new()
		sd.source_id = &"social"
		sd.chat_chance = 0.8
		w.add_child(sd)
		var lines := []
		sd.conversation_started.connect(func(a: StringName, b: StringName) -> void: lines.append("%s-%s@%.1f" % [a, b, w.now()]))
		for i in 3000:
			w.advance(0.1)
		logs.append(lines)
		w.queue_free()
	assert_gt(logs[0].size(), 0, "conversations happened")
	assert_eq(logs[0], logs[1], "a seed reproduces who talks to whom and when")

# ---- audience ---------------------------------------------------------------------------------------------------------------------------------

func _performer_setup() -> Dictionary:
	var seat := _station(&"violin_seat", &"performer_seat", Vector3(0, 0, 0), 1, PackedStringArray(["performer"]))
	var perf := _agent(&"Omar", Vector3(0, 0, 1.0), PackedStringArray(["performer"]))
	var j := NpcJob.new()
	j.id = &"play"
	j.kind = &"music"
	j.station_id = &"violin_seat"
	j.required_tags = PackedStringArray(["performer"])
	j.ttl_s = 0.0
	j.priority = 100.0
	var act := NpcActionDef.new()
	act.duration_range = Vector2(30.0, 30.0)
	j.action = act
	world.board.post(j, world.now())
	return {"seat": seat, "perf": perf, "job": j}

func test_audience_ring_slots_around_performer() -> void:
	var p := _performer_setup()
	_agent(&"L1", Vector3(8, 0, 0))
	_start()
	social.listen_spots = 3
	social.listen_radius = 1.6
	_run(6.0)
	var spots := social.audience_spots(&"violin_seat")
	assert_eq(spots.size(), 3, "a ring of listen spots")
	var perf_pos: Vector3 = (p["seat"] as NpcStation).global_position
	for s: NpcStation in spots:
		assert_almost_eq(s.global_position.distance_to(perf_pos), 1.6, 0.05, "on the ring")
		var face := -Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(s.facing_deg))
		var to_perf := (perf_pos - s.global_position).normalized()
		assert_lt(rad_to_deg(face.angle_to(to_perf)), 5.0, "facing the performer")

func test_listener_joins_and_is_preempted() -> void:
	_performer_setup()
	var l := _agent(&"L1", Vector3(8, 0, 0))
	_start()
	social.listen_spots = 2
	_run(20.0)
	assert_true(String(l.current_job_id()).begins_with("listen:"), "an idle agent chose to listen: %s" % l.current_job_id())
	var em := NpcJob.new()
	em.id = &"alarm"
	em.kind = &"alarm"
	em.override = &"emergency"
	em.slots = 2
	em.ttl_s = 0.0
	world.board.post(em, world.now())
	_run(1.0)
	assert_eq(l.current_job_id(), &"alarm", "the listener leaves immediately")
	for s: NpcStation in social.audience_spots(&"violin_seat"):
		assert_true(s.is_free(), "the spot is free again")

func test_performer_leaves_clears_listen_jobs() -> void:
	_performer_setup()
	_agent(&"L1", Vector3(8, 0, 0))
	_start()
	social.listen_spots = 2
	_run(8.0)
	assert_gt(world.board.open_jobs().filter(func(j: NpcJob) -> bool: return String(j.id).begins_with("listen:")).size(), 0)
	world.board.clear(&"play") # the performance ends
	_run(2.0)
	assert_eq(world.board.open_jobs().filter(func(j: NpcJob) -> bool: return String(j.id).begins_with("listen:")).size(), 0, "listen jobs cleared")
	assert_eq(social.audience_spots(&"violin_seat").size(), 0, "ring removed")

func test_no_listeners_performance_completes() -> void:
	_performer_setup()
	var done := []
	world.job_finished.connect(func(job: NpcJob, _id: StringName, result: StringName) -> void:
		if job.id == &"play":
			done.append(result))
	_start()
	social.listen_spots = 3
	_run(40.0)
	assert_eq(done, [&"done"], "the performance ran to completion with nobody listening")
