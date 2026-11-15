@tool
extends EditorPlugin
## NPC Life editor plugin: station and waypoint-graph gizmos and the graph inspector buttons. No autoload and no project settings; everything it adds is removed
## when it is disabled. Runtime scripts never reference the editor classes (they live in editor/, loaded only from here).

const StationGizmo := preload("res://addons/npc_life/editor/npc_station_gizmo.gd")
const GraphGizmo := preload("res://addons/npc_life/editor/npc_graph_gizmo.gd")
const GraphInspector := preload("res://addons/npc_life/editor/npc_graph_inspector.gd")

var _station_gizmo: EditorNode3DGizmoPlugin
var _graph_gizmo: EditorNode3DGizmoPlugin
var _inspector: EditorInspectorPlugin

func _enter_tree() -> void:
	_station_gizmo = StationGizmo.new()
	_station_gizmo.undo_redo = get_undo_redo()
	_graph_gizmo = GraphGizmo.new()
	_graph_gizmo.undo_redo = get_undo_redo()
	_inspector = GraphInspector.new()
	_inspector.undo_redo = get_undo_redo()
	add_node_3d_gizmo_plugin(_station_gizmo)
	add_node_3d_gizmo_plugin(_graph_gizmo)
	add_inspector_plugin(_inspector)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--npc-editor-demo"):
			_demo.call_deferred(a.get_slice("=", 1)) # documentation aid: frames the example scene so the gizmos can be photographed

func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_station_gizmo)
	remove_node_3d_gizmo_plugin(_graph_gizmo)
	remove_inspector_plugin(_inspector)
	_station_gizmo = null
	_graph_gizmo = null
	_inspector = null

## `godot --editor ... res://addons/npc_life/examples/workshop/workshop.tscn -- --npc-editor-demo=graph|station`: selects one node and aims the 3D editor camera at it.
func _demo(mode: String) -> void:
	await get_tree().create_timer(2.5).timeout
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var sel := EditorInterface.get_selection()
	sel.clear()
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if mode == "station":
		sel.add_node(root.find_child("Workbench", true, false))
		cam.global_position = Vector3(6.6, 1.9, 2.6)
		cam.look_at(Vector3(5.2, 0.3, 0.0))
	else:
		sel.add_node(root.find_child("GraphView", true, false))
		cam.global_position = Vector3(-1.0, 6.0, 7.5)
		cam.look_at(Vector3(0.0, 0.0, 0.0))
