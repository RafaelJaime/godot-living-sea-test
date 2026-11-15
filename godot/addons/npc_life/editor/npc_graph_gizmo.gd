@tool
extends EditorNode3DGizmoPlugin
## Waypoint graph gizmo (on NpcWaypointGraphInstance): edges coloured by type, one draggable handle per node (stored in the platform's local space, undoable).
## Editor-only (no class_name: only plugin.gd loads it).

var undo_redo: EditorUndoRedoManager

func _init() -> void:
	for t in NpcGraphEditing.COLORS:
		create_material(String(t), NpcGraphEditing.COLORS[t])
	create_material("unknown", NpcGraphEditing.UNKNOWN_COLOR)
	create_handle_material("handles")

func _get_gizmo_name() -> String:
	return "NpcWaypointGraph"

func _has_gizmo(node: Node3D) -> bool:
	return node is NpcWaypointGraphInstance

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var gi := gizmo.get_node_3d() as NpcWaypointGraphInstance
	if gi.graph == null:
		return
	for e in gi.graph.edge_count():
		var a := gi.graph.edges[e * 2]
		var b := gi.graph.edges[e * 2 + 1]
		if a < 0 or b < 0 or a >= gi.graph.node_count() or b >= gi.graph.node_count():
			continue
		var t := gi.graph.edge_type(e)
		var mat := get_material(String(t) if NpcGraphEditing.COLORS.has(t) else "unknown", gizmo)
		gizmo.add_lines(PackedVector3Array([gi.to_instance_space(gi.graph.positions[a]), gi.to_instance_space(gi.graph.positions[b])]), mat)
	var pts := PackedVector3Array()
	var ids := PackedInt32Array()
	for i in gi.graph.node_count():
		pts.append(gi.to_instance_space(gi.graph.positions[i]))
		ids.append(i)
	gizmo.add_handles(pts, get_material("handles", gizmo), ids)

func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return "Node %d" % id

func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	var gi := gizmo.get_node_3d() as NpcWaypointGraphInstance
	gi.mark_selected(id) # touching a handle selects the node (the inspector connects the last two)
	return gi.graph.positions[id]

func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var gi := gizmo.get_node_3d() as NpcWaypointGraphInstance
	var world_now := gi.platform().global_transform * gi.graph.positions[id]
	var hit: Variant = Plane(Vector3.UP, world_now.y).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	gi.graph.set_node_position(id, gi.platform().global_transform.affine_inverse() * (hit as Vector3))
	gi.update_gizmos()

func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var gi := gizmo.get_node_3d() as NpcWaypointGraphInstance
	if cancel:
		gi.graph.set_node_position(id, restore)
		return
	if undo_redo == null:
		return
	undo_redo.create_action("Move waypoint node %d" % id)
	undo_redo.add_do_method(gi.graph, "set_node_position", id, gi.graph.positions[id])
	undo_redo.add_undo_method(gi.graph, "set_node_position", id, restore)
	undo_redo.add_do_method(gi, "update_gizmos")
	undo_redo.add_undo_method(gi, "update_gizmos")
	undo_redo.commit_action()
