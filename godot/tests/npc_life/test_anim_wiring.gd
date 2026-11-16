extends GutTest
## Agent + executor wiring to the animation and IK adapters (spec npc-life-animation: adapter interface with stubs, procedural IK hooks, missing adapter).

class StubAnim extends NpcAnimationAdapter:
	var calls: Array = []
	func bind(_a: Node, _v: Node) -> bool: return true
	func play(tag: StringName, _loop := true, blend := 0.35) -> void: calls.append(["play", tag, blend])
	func set_locomotion(edge_type: StringName, speed: float) -> void: calls.append(["loco", edge_type, speed])
	func attach_prop(scene: PackedScene, socket: StringName) -> Node3D:
		calls.append(["prop", socket])
		return Node3D.new() if scene != null else null
	func process(_d: float) -> void: calls.append(["process"])

class ExitStubAnim extends StubAnim:
	var exited: Array = []
	var advanced: Array = []
	func exit_transition(from_edge_type: StringName) -> float:
		exited.append(from_edge_type)
		return 0.5 if from_edge_type == &"ladder" else 0.0
	func exit_advance(from_edge_type: StringName) -> float:
		advanced.append(from_edge_type)
		return 0.35 if from_edge_type == &"ladder" else 0.0

class StubIk extends NpcIkAdapter:
	var calls: Array = []
	func bind(_a: Node3D, _s: Skeleton3D, _p: NpcRigProfile) -> bool: return true
	func set_target(chain: StringName, target: Node3D, weight := 1.0, ramp_s := 1.2) -> void: calls.append(["target", chain, target, weight, ramp_s])
	func clear(chain: StringName, ramp_s := 0.5) -> void: calls.append(["clear", chain, ramp_s])
	func set_look_at(target: Node3D, weight := 1.0) -> void: calls.append(["look", target, weight])

var world: NpcWorld
var platform: Node3D
var station: NpcStation
var agent: NpcAgent
var anim: StubAnim
var ik: StubIk

func before_each() -> void:
	platform = Node3D.new()
	add_child_autofree(platform)
	world = NpcWorld.new()
	world.world_seed = 4
	world.platform_root = platform
	platform.add_child(world)
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3(0, 0, 0))
	g.add_node(Vector3(6, 0, 0))
	g.connect_nodes(0, 1, &"walk")
	world.graph = g
	station = NpcStation.new()
	station.station_id = &"helm"
	station.kind = &"helm"
	station.position = Vector3(6, 0, 0)
	station.approach_offset = Vector3.ZERO
	station.anim_tag = &"steer"
	platform.add_child(station)
	for n in ["hand_r", "look_at"]:
		var m := Marker3D.new()
		m.name = n
		station.add_child(m)
		station.ik_targets[StringName(n)] = NodePath(n)
	var d := NpcCharacterDef.new()
	d.agent_id = &"A"
	agent = NpcAgent.new()
	agent.def = d
	platform.add_child(agent)
	anim = StubAnim.new()
	ik = StubIk.new()
	world.job_finished.connect(func(job: NpcJob, _id: StringName, _r: StringName) -> void: world.board.clear(job.id)) # a finished job leaves the board

func _job(action_tag := &"", with_ik := true) -> NpcJob:
	var j := NpcJob.new()
	j.id = &"j"
	j.kind = &"steer"
	j.station_id = &"helm"
	j.ttl_s = 0.0
	var a := NpcActionDef.new()
	a.action_id = &"steer"
	a.anim_tag = action_tag
	a.duration_range = Vector2(3.0, 3.0)
	if with_ik:
		a.ik = {&"hand_r": &"hand_r"}
		a.look_at = &"look_at"
	j.action = a
	return j

func _run(seconds: float) -> void:
	for i in int(round(seconds / 0.05)):
		world.advance(0.05)

func _tags(calls: Array, kind: String) -> Array:
	return calls.filter(func(c: Array) -> bool: return c[0] == kind)

func test_stub_adapters_receive_the_calls() -> void:
	agent.anim = anim
	agent.ik = ik
	world.board.post(_job(&"steer_wheel"), world.now())
	_run(14.0)
	var loco := _tags(anim.calls, "loco")
	assert_gt(loco.size(), 0, "locomotion set while walking")
	assert_eq(loco[0][1], &"walk")
	assert_eq(_tags(anim.calls, "play").filter(func(c: Array) -> bool: return c[1] == &"steer_wheel").size(), 1, "WORK plays the action's tag once")
	var targets := _tags(ik.calls, "target")
	assert_eq(targets.size(), 1)
	assert_eq(targets[0][1], &"hand_r")
	assert_same(targets[0][2], station.ik_target(&"hand_r"), "the live station marker is passed, so a moving parent is re-read every frame")
	assert_eq(_tags(ik.calls, "look").filter(func(c: Array) -> bool: return c[1] != null).size(), 1)
	assert_gt(_tags(ik.calls, "clear").size(), 0, "released when the job ends")
	assert_gt(_tags(anim.calls, "process").size(), 10, "the adapter is updated every frame")

func test_station_ik_targets_used_by_default() -> void:
	agent.anim = anim
	agent.ik = ik
	world.board.post(_job(&"", false), world.now()) # an action without ik keys: the station's own targets drive the IK
	_run(14.0)
	assert_eq(_tags(ik.calls, "target").size(), 1)
	assert_eq(_tags(ik.calls, "target")[0][1], &"hand_r")
	assert_eq(_tags(anim.calls, "play").filter(func(c: Array) -> bool: return c[1] == &"steer").size(), 1, "no action tag: the station's anim tag")

func test_ik_released_on_abort() -> void:
	agent.anim = anim
	agent.ik = ik
	world.board.post(_job(&"steer_wheel"), world.now())
	_run(9.0)
	assert_gt(_tags(ik.calls, "target").size(), 0)
	agent.abort_job()
	assert_gt(_tags(ik.calls, "clear").size(), 0, "abort releases the IK too")

func test_props_attached_at_work() -> void:
	agent.anim = anim
	agent.ik = ik
	var j := _job(&"steer_wheel")
	(j.action as NpcActionDef).props = [PackedScene.new()]
	world.board.post(j, world.now())
	_run(14.0)
	assert_eq(_tags(anim.calls, "prop").size(), 1)

func test_missing_adapters_log_once_and_logic_runs() -> void:
	var finished := []
	world.job_finished.connect(func(job: NpcJob, _id: StringName, result: StringName) -> void:
		if not NpcAmbient.is_ambient(job):
			finished.append(result))
	world.board.post(_job(&"steer_wheel"), world.now())
	_run(14.0)
	assert_eq(finished, [&"done"], "the job ran to completion without any adapter")
	var j2 := _job(&"steer_wheel")
	j2.id = &"j2"
	world.board.post(j2, world.now())
	_run(14.0)
	assert_eq(finished, [&"done", &"done"])
	assert_eq(agent.adapter_warnings, 1, "one warning, however many jobs and frames")

func test_agent_waits_at_the_top_of_a_ladder_for_the_exit_clip() -> void:
	## graph: 0 -(ladder)- 1 -(walk)- 2; the exit transition is requested when the walk edge begins, and the navigator holds for its length.
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3(0, 0, 0))
	g.add_node(Vector3(0, 2, 0))
	g.add_node(Vector3(4, 2, 0))
	g.connect_nodes(0, 1, &"ladder")
	g.connect_nodes(1, 2, &"walk")
	world.graph = g
	station.position = Vector3(4, 2, 0)
	var ex := ExitStubAnim.new()
	agent.anim = ex
	agent.position = Vector3(0, 0, 0)
	world.board.post(_job(&"steer", false), world.now())
	for i in 400:
		world.advance(0.05)
		if ex.exited.size() > 1:
			break
	assert_true(ex.advanced.has(&"ladder"), "the root motion of the exit clip is asked for")
	assert_eq(ex.exited, [&"walk", &"ladder"], "asked at each change of edge type; the ladder exit when the walk edge after it started")
