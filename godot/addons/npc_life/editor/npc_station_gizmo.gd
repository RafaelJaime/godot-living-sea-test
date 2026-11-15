@tool
extends EditorNode3DGizmoPlugin
## Station gizmo: anchor (origin), approach point and facing arrow (draggable handles with undo), slot markers, must-staff colour.
## Editor-only (no class_name: only plugin.gd loads it).

var undo_redo: EditorUndoRedoManager

func _init() -> void:
	create_material("main", NpcGizmoGeometry.COLOR_STATION)
	create_material("must", NpcGizmoGeometry.COLOR_MUST_STAFF)
	create_handle_material("handles")

func _get_gizmo_name() -> String:
	return "NpcStation"

func _has_gizmo(node: Node3D) -> bool:
	return node is NpcStation

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var st := gizmo.get_node_3d() as NpcStation
	var geo := NpcGizmoGeometry.station(st)
	gizmo.add_lines(geo["lines"], get_material("must" if st.must_staff else "main", gizmo))
	gizmo.add_handles(PackedVector3Array([geo["approach"], geo["facing_tip"]]), get_material("handles", gizmo), PackedInt32Array([0, 1]))

func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return "Approach point" if id == 0 else "Facing"

func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	var st := gizmo.get_node_3d() as NpcStation
	return st.approach_offset if id == 0 else st.facing_deg

func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var st := gizmo.get_node_3d() as NpcStation
	var origin := camera.project_ray_origin(screen_pos)
	var normal := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, st.global_position.y).intersects_ray(origin, normal)
	if hit == null:
		return
	var local := st.to_local(hit as Vector3)
	if id == 0:
		st.approach_offset = Vector3(local.x, 0.0, local.z)
	elif absf(local.x) + absf(local.z) > 0.05:
		st.facing_deg = snappedf(rad_to_deg(atan2(-local.x, -local.z)), 1.0)
	st.update_gizmos()

func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var st := gizmo.get_node_3d() as NpcStation
	var prop := "approach_offset" if id == 0 else "facing_deg"
	if cancel:
		st.set(prop, restore)
		return
	if undo_redo == null:
		return
	undo_redo.create_action("Move station %s" % ("approach point" if id == 0 else "facing"))
	undo_redo.add_do_property(st, prop, st.get(prop))
	undo_redo.add_undo_property(st, prop, restore)
	undo_redo.commit_action()
