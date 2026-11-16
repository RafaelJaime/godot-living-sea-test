extends GutTest
## Spec ship-crew-job-sources (C1.2/C1.3): the --crew flag and the bridge that writes ship facts into the blackboard.

var world: NpcWorld
var ship: Node
var autopilot: Node
var bridge: CrewWorldBridge

func before_each() -> void:
	world = NpcWorld.new()
	world.world_seed = 5
	add_child_autofree(world)
	ship = Node.new()
	autopilot = Node.new()
	autopilot.name = "Autopilot"
	autopilot.add_user_signal("maneuver_started", [{"name": "kind", "type": TYPE_STRING_NAME}, {"name": "side", "type": TYPE_INT}])
	autopilot.add_user_signal("maneuver_ended", [{"name": "kind", "type": TYPE_STRING_NAME}])
	ship.add_child(autopilot)
	add_child_autofree(ship)
	bridge = CrewWorldBridge.new()
	add_child_autofree(bridge)
	bridge.bind(world, ship)

func test_flag_defaults_to_npc() -> void:
	assert_eq(CrewNpc.mode(PackedStringArray()), &"npc")
	assert_eq(CrewNpc.mode(PackedStringArray(["--other"])), &"npc")

func test_flag_values() -> void:
	assert_eq(CrewNpc.mode(PackedStringArray(["--crew=npc"])), &"npc")
	assert_eq(CrewNpc.mode(PackedStringArray(["--crew=legacy"])), &"legacy")

func test_unknown_flag_value_falls_back_to_npc() -> void:
	assert_eq(CrewNpc.mode(PackedStringArray(["--crew=banana"])), &"npc")
	assert_push_warning("unknown --crew value")

func test_bridge_writes_the_ship_facts() -> void:
	for key in [&"daylight", &"storm", &"wind", &"roll_deg", &"maneuver", &"maneuver_side"]:
		assert_true(world.inputs.has_value(key), "%s is on the blackboard" % key)
	assert_eq(world.inputs.get_value(&"maneuver"), &"")

func test_roll_is_quantized_and_absolute() -> void:
	ship.set_meta("x", 1) # the fake ship has no roll property: reads as flat
	assert_eq(world.inputs.get_value(&"roll_deg"), 0.0)

func test_maneuver_signals_reach_the_blackboard() -> void:
	autopilot.emit_signal("maneuver_started", &"tack", 1)
	assert_eq(world.inputs.get_value(&"maneuver"), &"tack")
	assert_eq(world.inputs.get_value(&"maneuver_side"), 1)
	autopilot.emit_signal("maneuver_ended", &"tack")
	assert_eq(world.inputs.get_value(&"maneuver"), &"")
	assert_eq(world.inputs.get_value(&"maneuver_side"), 0)

func test_legacy_creates_no_world() -> void:
	var c := CrewNpc.new()
	c.mode_override = &"legacy"
	add_child_autofree(c)
	assert_null(c.world, "no NpcWorld with --crew=legacy")
	assert_eq(c.agents.size(), 0)

func test_without_a_crew_node_it_stays_inert_instead_of_failing() -> void:
	var c := CrewNpc.new()
	c.mode_override = &"npc"
	add_child_autofree(c)
	assert_null(c.world)
