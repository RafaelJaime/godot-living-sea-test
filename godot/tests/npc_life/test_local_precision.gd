extends GutTest
## Reproducibility on a platform far from the world origin (a ship sails kilometres away): positions in platform space must come from local
## transforms, not from global ones, whose float precision there is centimetres (C2.4: same seed, different timing on the ship).

var platform: Node3D
var world: NpcWorld
var station: NpcStation

func before_each() -> void:
	platform = Node3D.new()
	platform.position = Vector3(250000.0, 0.0, -310000.0)
	platform.rotation = Vector3(0.03, 1.1, -0.02)
	add_child_autofree(platform)
	world = NpcWorld.new()
	world.platform_root = platform
	platform.add_child(world)
	station = NpcStation.new()
	station.station_id = &"s"
	station.kind = &"k"
	station.position = Vector3(3.25, 1.5, -7.125)
	station.approach_offset = Vector3.ZERO
	platform.add_child(station)

func test_approach_point_is_exact_far_from_the_origin() -> void:
	var a := station.approach_local(0, platform)
	assert_lt(a.distance_to(Vector3(3.25, 1.5, -7.125)), 1e-5, "approach point equals the local position, got %s" % a)

func test_anchor_is_exact_far_from_the_origin() -> void:
	var t := station.anchor_local(0, platform)
	assert_lt(t.origin.distance_to(station.position), 1e-5, "anchor origin equals the local position")

func test_distance_uses_local_positions() -> void:
	var d := NpcCharacterDef.new()
	d.agent_id = &"a"
	var ag := NpcAgent.new()
	ag.def = d
	ag.position = Vector3(1.0, 1.5, -2.0)
	platform.add_child(ag)
	var expected := Vector3(1.0, 1.5, -2.0).distance_to(Vector3(3.25, 1.5, -7.125))
	assert_almost_eq(world.distance_to(ag, station), expected, 1e-4, "straight-line distance in platform space, not through global transforms")
