extends GutTest
## Spec ship-crew-stations (H3): the waypoint graph exported from the ship markers (pivot-local, typed edges, every station reachable).

const SCENE := "res://ship/ship_stations.tscn"
const ROOT_NODE := &"n_waist_b"

var pivot: Node3D
var prov: ShipStations
var g: NpcWaypointGraph

func before_each() -> void:
	pivot = Node3D.new()
	add_child_autofree(pivot)
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	pivot.add_child(root)
	prov = root.get_node("Provider") as ShipStations
	prov.set_sail_positions([Vector3(0, 12, -8), Vector3(0, 12, 2), Vector3(0, 12, 12)])
	prov.rebuild()
	g = prov.build_graph()

func _node_of(tag: StringName) -> int:
	return g.node_tags.find(tag)

func test_graph_validates_clean() -> void:
	assert_eq(g.validate().size(), 0, "no validation problems: %s" % [g.validate()])
	assert_gt(g.node_count(), 20)
	assert_gt(g.edge_count(), 20)

func test_every_station_has_a_node_and_every_node_is_reachable() -> void:
	for st in prov.provide_stations():
		assert_gte(_node_of(st.station_id), 0, "node for station %s" % st.station_id)
	var root := _node_of(ROOT_NODE)
	assert_gte(root, 0, "root node exists")
	assert_eq(g.check_connectivity(root), [] as Array[int], "unreachable: 0")

func test_typed_edges_present() -> void:
	var types := {}
	for i in g.edge_count():
		types[g.edge_type(i)] = true
	assert_true(types.has(&"walk"), "walk edges")
	assert_true(types.has(&"stairs"), "stairs edges")
	assert_true(types.has(&"rope"), "rope edges (ratlines)")

func test_crows_nest_reachable_through_rope_edges() -> void:
	var from := _node_of(&"helm")
	var to := _node_of(&"crows_nest")
	var info := g.path_info(g.positions[from], g.positions[to])
	assert_eq(info["reason"], &"", "path found")
	assert_true((info["edge_types"] as Array).has(&"rope"), "the climb uses rope edges")
	assert_true((info["edge_types"] as Array).has(&"stairs"), "and the stairs down from the poop")

func test_station_nodes_sit_on_their_anchors() -> void:
	for st in prov.provide_stations():
		var n := _node_of(st.station_id)
		assert_lt(g.positions[n].distance_to(st.position), 0.01, "station node of %s is the anchor" % st.station_id)

func test_graph_is_pivot_local_data() -> void:
	# The resource holds plain local coordinates: nothing about the ship's world transform can leak in.
	pivot.global_transform = Transform3D(Basis(Vector3(1, 0, 0), 0.3), Vector3(100, 5, -80))
	var g2 := prov.build_graph()
	assert_eq(g2.positions, g.positions)

func test_far_station_is_reported_as_unlinked() -> void:
	var m := Marker3D.new()
	m.name = "far_mop"
	m.position = Vector3(0, 15, 50)
	m.set_meta("kind", &"mop_zone")
	m.set_meta("slots", 1)
	prov.get_parent().get_node("Markers").add_child(m)
	prov.rebuild()
	prov.build_graph()
	var rep := prov.last_graph_report()
	assert_true((rep["unlinked"] as Array).has(&"far_mop"), "reported: %s" % [rep["unlinked"]])
