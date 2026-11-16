extends GutTest
## Specs: npc-life-navigation (platform-local pathing, per-edge locomotion, collision courtesy).

var nav: NpcNavigator

func before_each() -> void:
	nav = NpcNavigator.new()

func _agent(parent: Node3D, id: String, pos := Vector3.ZERO) -> Node3D:
	var a := Node3D.new()
	a.name = id
	a.position = pos
	parent.add_child(a)
	return a

func _types(n: int, t := &"walk") -> Array[StringName]:
	var out: Array[StringName] = []
	for i in n:
		out.append(t)
	return out

func _run_to_end(agent: Node3D, speed: float, dt: float, max_steps := 4000, on_step := Callable()) -> int:
	var steps := 0
	while not nav.finished and steps < max_steps:
		nav.step(agent, dt, speed)
		if on_step.is_valid():
			on_step.call()
		steps += 1
	return steps

func test_follows_polyline_in_local_space() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var a := _agent(root, "A")
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 3)])
	nav.set_path(pts, _types(2))
	var worst := 0.0
	var steps := _run_to_end(a, 1.0, 0.05, 4000, func() -> void:
		var p := a.position
		var d := minf(_dist_to_segment(p, pts[0], pts[1]), _dist_to_segment(p, pts[1], pts[2]))
		worst = maxf(worst, d))
	assert_true(nav.finished)
	assert_true(a.position.is_equal_approx(pts[2]), "ends on the last point")
	assert_lt(worst, 1e-4, "never leaves the polyline")
	assert_almost_eq(steps * 0.05, 7.0, 0.2, "7 m at 1 m/s")

func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func test_uses_position_not_global_position() -> void:
	var platform := Node3D.new()
	add_child_autofree(platform)
	var a := _agent(platform, "A")
	nav.set_path(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), _types(1))
	var g0 := a.global_position
	var t := 0.0
	while not nav.finished and t < 30.0:
		platform.rotation.y += deg_to_rad(30.0) * 0.05 # spinning ...
		platform.position += Vector3(0.3, 0.1, -0.2) * 0.05 # ... and drifting
		nav.step(a, 0.05, 2.0)
		t += 0.05
	assert_true(nav.finished)
	assert_true(a.position.is_equal_approx(Vector3(10, 0, 0)), "local position reached the path end regardless of platform motion")
	assert_false(a.global_position.is_equal_approx(g0 + Vector3(10, 0, 0)), "the world position is whatever the platform made of it")

func test_platform_rotation_no_drift() -> void:
	var platform := Node3D.new()
	add_child_autofree(platform)
	var a := _agent(platform, "A")
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)])
	nav.set_path(pts, _types(1))
	var t := 0.0
	while not nav.finished and t < 30.0:
		platform.rotation = Vector3(deg_to_rad(15.0) * sin(t), t * 0.5, deg_to_rad(15.0) * cos(t * 0.7)) # roll, yaw, pitch
		platform.position = Vector3(sin(t) * 5.0, cos(t) * 2.0, t)
		nav.step(a, 0.05, 1.5)
		t += 0.05
	assert_lt(nav.max_error, 0.01, "max local position error under 1 cm")
	assert_almost_eq(a.position.y, 0.0, 1e-5, "local height equals the path height: no sliding from platform motion")

func test_rebase_shift_does_not_affect_local_position() -> void:
	var platform := Node3D.new()
	add_child_autofree(platform)
	platform.position = Vector3(900.0, 0, 0)
	var a := _agent(platform, "A")
	nav.set_path(PackedVector3Array([Vector3.ZERO, Vector3(6, 0, 0)]), _types(1))
	for i in 40:
		nav.step(a, 0.05, 1.0)
	var local_before := a.position
	platform.global_position -= Vector3(1024.0, 0, 0) # floating-origin rebase of the world
	assert_true(a.position.is_equal_approx(local_before), "local position untouched by the shift")
	for i in 40:
		nav.step(a, 0.05, 1.0)
	assert_almost_eq(a.position.x, 4.0, 0.01, "keeps walking along the same local path")

func test_edge_type_sets_locomotion_tag_and_speed() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var a := _agent(root, "A")
	nav.set_path(PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0), Vector3(2, 3, 0)]), [&"walk", &"ladder"] as Array[StringName])
	var seen: Array[StringName] = []
	nav.edge_entered.connect(func(t: StringName, _i: int) -> void: seen.append(t))
	var tags := {}
	var speeds := {}
	while not nav.finished:
		nav.step(a, 0.05, 1.0)
		tags[nav.locomotion_tag()] = true
		speeds[nav.locomotion_tag()] = nav.current_speed(1.0)
	assert_eq(seen, [&"walk", &"ladder"] as Array[StringName], "edge types entered in order")
	assert_true(tags.has(&"walk") and tags.has(&"ladder"))
	assert_almost_eq(speeds[&"walk"], 1.0, 1e-6)
	assert_lt(speeds[&"ladder"], speeds[&"walk"], "ladders are slower")

func test_empty_or_zero_length_path_finishes() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var a := _agent(root, "A")
	nav.set_path(PackedVector3Array([Vector3(1, 0, 1)]), _types(0))
	assert_true(nav.finished)
	nav.step(a, 0.05, 1.0)
	assert_true(nav.finished)

func test_courtesy_yields_to_other_agent() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var a := _agent(root, "A", Vector3(0, 0, 0))
	var b := _agent(root, "B", Vector3(10, 0, 0))
	var na := NpcNavigator.new()
	var nb := NpcNavigator.new()
	na.set_path(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)]), _types(1))
	nb.set_path(PackedVector3Array([Vector3(10, 0, 0), Vector3(0, 0, 0)]), _types(1))
	var t := 0.0
	var min_sep := 99.0
	var stall := 0.0
	var worst_stall := 0.0
	var last_a := a.position
	while (not na.finished or not nb.finished) and t < 20.0:
		na.step(a, 0.05, 1.2, [b])
		nb.step(b, 0.05, 1.2, [a])
		t += 0.05
		min_sep = minf(min_sep, a.position.distance_to(b.position))
		if a.position.distance_to(last_a) < 1e-4 and not na.finished:
			stall += 0.05
			worst_stall = maxf(worst_stall, stall)
		else:
			stall = 0.0
		last_a = a.position
	assert_true(na.finished and nb.finished, "both arrive: no deadlock")
	assert_lt(t, 12.0, "10 m at 1.2 m/s is 8.3 s: passing costs little")
	assert_gt(min_sep, 0.5, "they pass each other without overlapping")
	assert_lt(worst_stall, 2.0, "nobody waits long")
	assert_true(a.position.distance_to(Vector3(10, 0, 0)) < 0.05 and b.position.distance_to(Vector3.ZERO) < 0.05, "both end exactly on their path end (the sidestep is eased back)")

func test_hold_pauses_the_walk_and_then_resumes() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var a := _agent(parent, "a")
	nav.set_path(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), _types(1))
	nav.step(a, 0.1, 1.0)
	var x0 := a.position.x
	nav.hold(0.5)
	for i in 4:
		nav.step(a, 0.1, 1.0)
	assert_eq(a.position.x, x0, "no movement while held")
	assert_false(nav.finished, "the path is still pending")
	for i in 3:
		nav.step(a, 0.1, 1.0)
	assert_gt(a.position.x, x0, "it walks again after the hold")

func test_hold_can_carry_the_agent_forward_along_the_path() -> void:
	## Stepping off a ladder: the animation stays in place and the node covers the clip's root motion during the hold, eased in and out.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var a := _agent(parent, "a")
	nav.set_path(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), _types(1))
	nav.step(a, 0.0, 1.0) # enters the first segment
	var x0 := a.position.x
	nav.hold(1.0, 0.35)
	var last := x0
	for i in 10:
		nav.step(a, 0.1, 1.0)
		assert_gte(a.position.x, last - 1e-6, "never backwards")
		last = a.position.x
	assert_almost_eq(a.position.x - x0, 0.35, 0.002, "exactly the root motion over the hold")
	nav.step(a, 0.1, 1.0)
	assert_gt(a.position.x - x0, 0.35 + 0.05, "then the normal walk resumes")
