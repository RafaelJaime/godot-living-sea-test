extends GutTest
## Specs: npc-life-editor-tools. The editor classes themselves only run in the editor (checked by a headless editor start and by the manual notes in
## the evidence); here: the pure geometry and edit operations they are built on, and runtime isolation.

func _diamond() -> NpcWaypointGraph:
	var g := NpcWaypointGraph.new()
	g.add_node(Vector3(0, 0, 0))
	g.add_node(Vector3(2, 0, 0))
	g.add_node(Vector3(2, 0, 2))
	g.connect_nodes(0, 1, &"walk")
	g.connect_nodes(1, 2, &"walk")
	return g

func test_add_and_connect_saved_in_resource() -> void:
	var g := NpcWaypointGraph.new()
	var a := NpcGraphEditing.add_node_at_world(g, null, Vector3(1, 0, 0))
	var b := NpcGraphEditing.add_node_at_world(g, null, Vector3(3, 0, 0))
	var e := NpcGraphEditing.connect_nodes(g, a, b, &"walk")
	assert_eq(g.node_count(), 2)
	assert_eq(g.edge_count(), 1)
	assert_eq(e, 0)
	var path := "user://npc_graph_edit_test.tres"
	assert_eq(ResourceSaver.save(g, path), OK)
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NpcWaypointGraph
	assert_eq(back.node_count(), 2, "saved with the scene or resource")
	assert_eq(back.edge_count(), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_node_placed_at_world_point_is_stored_in_local_coordinates() -> void:
	var platform := Node3D.new()
	add_child_autofree(platform)
	platform.rotation.y = deg_to_rad(90.0)
	platform.position = Vector3(10, 2, -4)
	var g := NpcWaypointGraph.new()
	var world_pt := Vector3(10, 2, -6) # 2 m "in front" in the rotated frame
	var i := NpcGraphEditing.add_node_at_world(g, platform, world_pt)
	var local := g.positions[i]
	assert_true((platform.global_transform * local).is_equal_approx(world_pt), "converts back to the same world point")
	assert_false(local.is_equal_approx(world_pt), "and is NOT stored in world coordinates")

func test_remove_node_reindexes_edges() -> void:
	var g := _diamond()
	NpcGraphEditing.remove_node(g, 0)
	assert_eq(g.node_count(), 2)
	assert_eq(g.edge_count(), 1, "the edge touching the removed node is gone")
	assert_eq(g.edges, PackedInt32Array([0, 1]), "remaining indices shifted down")

func test_connect_rejects_self_and_duplicates() -> void:
	var g := _diamond()
	assert_eq(NpcGraphEditing.connect_nodes(g, 1, 1, &"walk"), -1)
	assert_eq(NpcGraphEditing.connect_nodes(g, 1, 0, &"walk"), -1, "same pair, either direction")
	assert_eq(g.edge_count(), 2)

func test_edge_type_change_changes_resource_and_colour() -> void:
	var g := _diamond()
	var before := NpcGraphEditing.edge_color(g.edge_type(0))
	NpcGraphEditing.set_edge_type(g, 0, &"ladder")
	assert_eq(g.edge_type(0), &"ladder")
	assert_ne(NpcGraphEditing.edge_color(&"ladder"), before, "ladder draws in another colour than walk")
	var cols := {}
	for t in [&"walk", &"stairs", &"ladder", &"rope", &"weird"]:
		cols[NpcGraphEditing.edge_color(t)] = true
	assert_eq(cols.size(), 5, "every type (and unknown) has its own colour")

func test_graph_geometry_one_line_per_edge_coloured_by_type() -> void:
	var g := _diamond()
	NpcGraphEditing.set_edge_type(g, 1, &"rope")
	var rows := NpcGizmoGeometry.graph_lines(g)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["color"], NpcGraphEditing.edge_color(&"walk"))
	assert_eq(rows[1]["color"], NpcGraphEditing.edge_color(&"rope"))
	assert_eq(rows[1]["a"], g.positions[1])

func test_station_geometry_anchor_approach_facing_slots() -> void:
	var st := NpcStation.new()
	add_child_autofree(st)
	st.approach_offset = Vector3(0, 0, 0.8)
	st.facing_deg = 90.0
	st.slot_count = 3
	var geo := NpcGizmoGeometry.station(st)
	assert_eq(geo["anchor"], Vector3.ZERO)
	assert_eq(geo["approach"], Vector3(0, 0, 0.8))
	var dir: Vector3 = (geo["facing_tip"] as Vector3).normalized()
	assert_true(dir.is_equal_approx(Vector3(-1, 0, 0)), "facing 90 degrees is -X (port): %s" % dir)
	assert_eq((geo["slots"] as PackedVector3Array).size(), 3, "a marker per slot")
	assert_gt((geo["lines"] as PackedVector3Array).size(), 4, "arrow lines")
	st.must_staff = true
	assert_ne(NpcGizmoGeometry.station(st)["color"], NpcGizmoGeometry.station(NpcStation.new())["color"], "must-staff stations draw in another colour")

func test_runtime_scripts_reference_no_editor_classes() -> void:
	var banned := ["EditorPlugin", "EditorNode3DGizmoPlugin", "EditorInspectorPlugin", "EditorInterface", "EditorUndoRedoManager", "EditorNode3DGizmo"]
	var offenders: Array[String] = []
	_scan("res://addons/npc_life", banned, offenders)
	assert_eq(offenders, [] as Array[String], "editor classes only appear under editor/ and plugin.gd: %s" % [offenders])

func _scan(dir: String, banned: Array, offenders: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() != "gd":
			continue
		if dir.ends_with("/editor") or f == "plugin.gd":
			continue
		var txt := FileAccess.get_file_as_string(dir + "/" + f)
		for b in banned:
			if txt.contains(b):
				offenders.append("%s/%s uses %s" % [dir, f, b])
	for sub in d.get_directories():
		_scan(dir + "/" + sub, banned, offenders)
