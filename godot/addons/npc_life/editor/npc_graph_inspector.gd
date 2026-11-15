@tool
extends EditorInspectorPlugin
## Inspector buttons for NpcWaypointGraphInstance: "Add node at cursor", "Connect selected", edge type dropdown and "Set type", "Check connectivity".
## Every edit goes through the editor's undo/redo. Editor-only (no class_name: only plugin.gd loads it).

var undo_redo: EditorUndoRedoManager

func _can_handle(object: Object) -> bool:
	return object is NpcWaypointGraphInstance

func _parse_begin(object: Object) -> void:
	var gi := object as NpcWaypointGraphInstance
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Waypoint graph editing (platform-local space)"
	box.add_child(title)
	var type_row := HBoxContainer.new()
	var type_pick := OptionButton.new()
	for t in NpcWaypointGraph.KNOWN_TYPES:
		type_pick.add_item(String(t))
	type_row.add_child(type_pick)
	var edge_spin := SpinBox.new()
	edge_spin.min_value = 0
	edge_spin.max_value = 9999
	edge_spin.prefix = "edge #"
	type_row.add_child(edge_spin)
	var set_type := Button.new()
	set_type.text = "Set type"
	type_row.add_child(set_type)
	var add_btn := Button.new()
	add_btn.text = "Add node at cursor"
	var conn_btn := Button.new()
	conn_btn.text = "Connect selected"
	var check_btn := Button.new()
	check_btn.text = "Check connectivity"
	var result := Label.new()
	box.add_child(add_btn)
	box.add_child(conn_btn)
	box.add_child(type_row)
	box.add_child(check_btn)
	box.add_child(result)
	add_custom_control(box)
	var type_of := func() -> StringName: return StringName(type_pick.get_item_text(type_pick.selected))
	add_btn.pressed.connect(func() -> void: _add_node(gi, result))
	conn_btn.pressed.connect(func() -> void: _connect_selected(gi, type_of.call(), result))
	set_type.pressed.connect(func() -> void: _set_type(gi, int(edge_spin.value), type_of.call(), result))
	check_btn.pressed.connect(func() -> void: result.text = _check(gi))

func _cursor_world(gi: NpcWaypointGraphInstance) -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	var plane_y := gi.platform().global_position.y
	var hit: Variant = Plane(Vector3.UP, plane_y).intersects_ray(cam.project_ray_origin(vp.get_mouse_position()), cam.project_ray_normal(vp.get_mouse_position()))
	if hit == null: # cursor not over the floor plane: put it in front of the camera, on the plane below it
		return Vector3(cam.global_position.x, plane_y, cam.global_position.z)
	return hit as Vector3

func _add_node(gi: NpcWaypointGraphInstance, result: Label) -> void:
	if gi.graph == null:
		result.text = "no graph assigned"
		return
	var local := gi.platform().global_transform.affine_inverse() * _cursor_world(gi)
	undo_redo.create_action("Add waypoint node")
	undo_redo.add_do_method(gi.graph, "add_node", local, &"")
	undo_redo.add_undo_method(gi.graph, "remove_node", gi.graph.node_count())
	undo_redo.add_do_method(gi, "update_gizmos")
	undo_redo.add_undo_method(gi, "update_gizmos")
	undo_redo.commit_action()
	result.text = "added node %d at %s" % [gi.graph.node_count() - 1, local.snapped(Vector3(0.01, 0.01, 0.01))]

func _connect_selected(gi: NpcWaypointGraphInstance, type: StringName, result: Label) -> void:
	if gi.graph == null or gi.selected.size() < 2:
		result.text = "touch two node handles first (the last two touched are connected)"
		return
	var a := gi.selected[0]
	var b := gi.selected[1]
	if NpcGraphEditing.connect_nodes(gi.graph.duplicate(), a, b, type) < 0:
		result.text = "nodes %d and %d are already connected (or identical)" % [a, b]
		return
	undo_redo.create_action("Connect waypoint nodes")
	undo_redo.add_do_method(gi.graph, "connect_nodes", a, b, type)
	undo_redo.add_undo_method(gi.graph, "remove_edge", gi.graph.edge_count())
	undo_redo.add_do_method(gi, "update_gizmos")
	undo_redo.add_undo_method(gi, "update_gizmos")
	undo_redo.commit_action()
	result.text = "connected %d - %d as %s" % [a, b, type]

func _set_type(gi: NpcWaypointGraphInstance, edge: int, type: StringName, result: Label) -> void:
	if gi.graph == null or edge < 0 or edge >= gi.graph.edge_count():
		result.text = "no such edge"
		return
	var old := gi.graph.edge_type(edge)
	undo_redo.create_action("Set edge type")
	undo_redo.add_do_method(gi.graph, "set_edge_type", edge, type)
	undo_redo.add_undo_method(gi.graph, "set_edge_type", edge, old)
	undo_redo.add_do_method(gi, "update_gizmos")
	undo_redo.add_undo_method(gi, "update_gizmos")
	undo_redo.commit_action()
	result.text = "edge %d: %s -> %s" % [edge, old, type]

func _check(gi: NpcWaypointGraphInstance) -> String:
	if gi.graph == null or gi.graph.node_count() == 0:
		return "empty graph"
	var root := gi.selected[0] if gi.selected.size() > 0 else 0
	var bad := gi.graph.check_connectivity(root)
	var problems := gi.graph.validate()
	var text := "unreachable from node %d: %d" % [root, bad.size()]
	if not bad.is_empty():
		text += " %s" % [bad]
	if not problems.is_empty():
		text += "\n" + "\n".join(problems)
	print("[npc_life] ", text)
	return text
