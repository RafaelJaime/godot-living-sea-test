extends GutTest
## Specs: npc-life-navigation (typed-edge graph, path queries, connectivity check, local-space storage).

func _diamond() -> NpcWaypointGraph:
	# 0 -(walk 2)- 1 -(walk 2)- 3    and    0 -(walk 3)- 2 -(walk 4)- 3     => route via 1 costs 4, via 2 costs 7
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3(0, 0, 0))
	g.add_node(Vector3(2, 0, 0))
	g.add_node(Vector3(0, 0, 3))
	g.add_node(Vector3(4, 0, 0))
	g.connect_nodes(0, 1, &"walk")
	g.connect_nodes(1, 3, &"walk")
	g.connect_nodes(0, 2, &"walk")
	g.connect_nodes(2, 3, &"walk")
	return g

func test_graph_counts_and_types() -> void:
	var g := NpcWaypointGraph.new()
	for i in 5:
		g.add_node(Vector3(i, 0, 0))
	g.connect_nodes(0, 1, &"walk")
	g.connect_nodes(1, 2, &"stairs")
	g.connect_nodes(2, 3, &"ladder")
	g.connect_nodes(3, 4, &"rope")
	g.connect_nodes(0, 4, &"walk")
	assert_eq(g.node_count(), 5)
	assert_eq(g.edge_count(), 5)
	assert_eq([g.edge_type(0), g.edge_type(1), g.edge_type(2), g.edge_type(3)], [&"walk", &"stairs", &"ladder", &"rope"])
	assert_eq(g.validate().size(), 0)

func test_unknown_edge_type_reported_not_crash() -> void:
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3.ZERO)
	g.add_node(Vector3.RIGHT)
	g.connect_nodes(0, 1, &"teleport")
	var v := g.validate()
	assert_eq(v.size(), 1)
	assert_true(v[0].contains("edge 0") and v[0].contains("teleport"), "names the edge and the type")
	assert_eq(g.find_path_nodes(0, 1).size(), 2, "still usable: the unknown type costs like a walk")

func test_find_path_shortest() -> void:
	var g := _diamond()
	assert_eq(g.find_path_nodes(0, 3), PackedInt32Array([0, 1, 3]), "the cost-4 route, not the cost-7 one")
	assert_almost_eq(g.path_cost(g.find_path_nodes(0, 3)), 4.0, 1e-5)

func test_find_path_from_arbitrary_local_points_snaps_to_nearest_nodes() -> void:
	var g := _diamond()
	var p := g.find_path(Vector3(-0.2, 0, 0.1), Vector3(4.3, 0, -0.2))
	assert_eq(p, PackedInt32Array([0, 1, 3]))

func test_typed_edge_cost_multiplier() -> void:
	# two equal-length routes; one goes over a ladder (cost multiplier) so the walk route wins
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3(0, 0, 0))
	g.add_node(Vector3(2, 0, 0))
	g.add_node(Vector3(0, 0, 2))
	g.add_node(Vector3(2, 0, 2))
	g.connect_nodes(0, 1, &"ladder")
	g.connect_nodes(1, 3, &"ladder")
	g.connect_nodes(0, 2, &"walk")
	g.connect_nodes(2, 3, &"walk")
	assert_eq(g.find_path_nodes(0, 3), PackedInt32Array([0, 2, 3]))
	# explicit per-edge multiplier
	var h := NpcWaypointGraph.new()
	for i in 4:
		h.add_node(Vector3(i % 2 * 2.0, 0, i / 2 * 2.0))
	h.connect_nodes(0, 1, &"walk", 10.0)
	h.connect_nodes(1, 3, &"walk")
	h.connect_nodes(0, 2, &"walk")
	h.connect_nodes(2, 3, &"walk")
	assert_eq(h.find_path_nodes(0, 3), PackedInt32Array([0, 2, 3]))

func test_edge_type_preserved_in_path() -> void:
	var g := NpcWaypointGraph.new()
	for i in 4:
		g.add_node(Vector3(i, 0, 0))
	g.connect_nodes(0, 1, &"walk")
	g.connect_nodes(1, 2, &"ladder")
	g.connect_nodes(2, 3, &"stairs")
	var info := g.path_info(Vector3(0, 0, 0), Vector3(3, 0, 0))
	assert_eq(info["reason"], &"")
	assert_eq(info["edge_types"], [&"walk", &"ladder", &"stairs"])
	assert_eq(info["nodes"], PackedInt32Array([0, 1, 2, 3]))

func test_oneway_edge() -> void:
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3(0, 0, 0))
	g.add_node(Vector3(1, 0, 0))
	g.connect_nodes(0, 1, &"walk", 1.0, true)
	assert_eq(g.find_path_nodes(0, 1).size(), 2)
	assert_eq(g.find_path_nodes(1, 0).size(), 0, "directional edge: no way back")

func test_unreachable_returns_empty_with_reason() -> void:
	var g := _diamond()
	g.add_node(Vector3(9, 0, 9)) # node 4, no edges
	assert_eq(g.find_path_nodes(0, 4).size(), 0)
	var info := g.path_info(Vector3.ZERO, Vector3(9, 0, 9))
	assert_eq(info["reason"], &"unreachable")
	assert_eq(info["nodes"].size(), 0)

func test_nearest_node() -> void:
	var g := _diamond()
	assert_eq(g.nearest_node(Vector3(3.9, 0.2, 0.1)), 3)
	assert_eq(g.nearest_node(Vector3(0.1, 0, 2.7)), 2)
	assert_eq(NpcWaypointGraph.new().nearest_node(Vector3.ZERO), -1, "empty graph")

func test_all_pairs_distance_cache_up_to_256() -> void:
	var g := NpcWaypointGraph.new()
	for i in 200:
		g.add_node(Vector3(i, 0, 0))
		if i > 0:
			g.connect_nodes(i - 1, i, &"walk")
	g.build_distance_cache()
	assert_true(g.has_distance_cache())
	assert_almost_eq(g.distance(0, 199), 199.0, 1e-3)
	assert_almost_eq(g.distance(150, 20), 130.0, 1e-3)
	var big := NpcWaypointGraph.new()
	for i in 300:
		big.add_node(Vector3(i, 0, 0))
		if i > 0:
			big.connect_nodes(i - 1, i, &"walk")
	big.build_distance_cache()
	assert_false(big.has_distance_cache(), "no cache above 256 nodes")
	assert_almost_eq(big.distance(0, 299), 299.0, 1e-3, "still answers, by search")

func test_distance_unreachable_is_inf() -> void:
	var g := _diamond()
	g.add_node(Vector3(9, 0, 9))
	g.build_distance_cache()
	assert_eq(g.distance(0, 4), INF)

func test_connectivity_check_lists_unreachable() -> void:
	var g := _diamond()
	assert_eq(g.check_connectivity(0), [] as Array[int])
	var iso := g.add_node(Vector3(9, 0, 9))
	var iso2 := g.add_node(Vector3(9, 0, 10))
	g.connect_nodes(iso, iso2, &"walk")
	assert_eq(g.check_connectivity(0), [iso, iso2] as Array[int])

func test_graph_stored_in_local_space() -> void:
	var platform := Node3D.new()
	add_child_autofree(platform)
	var gi := NpcWaypointGraphInstance.new()
	gi.graph = _diamond()
	platform.add_child(gi)
	gi.platform_root = platform
	var local := gi.graph.positions[1]
	var w0 := gi.node_world(1)
	platform.rotation.y = 1.0
	platform.position = Vector3(10, 2, -3)
	assert_eq(gi.graph.positions[1], local, "the resource is never rewritten by platform motion")
	assert_false(gi.node_world(1).is_equal_approx(w0), "world position follows the platform")
	assert_true(gi.node_local(1).is_equal_approx(local))
