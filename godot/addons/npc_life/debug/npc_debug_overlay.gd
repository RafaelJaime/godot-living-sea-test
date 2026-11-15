class_name NpcDebugOverlay
extends CanvasLayer
## Debug overlay, created only on demand (`NpcWorld.set_debug(true)` / `--npc-debug`): a Label3D over every agent (job, phase, idle timer), a label per station
## with its occupancy, a line along every agent's path, and a CanvasLayer list with the last decision of each agent (reason and top scores). Off = no node exists.

var world: NpcWorld
var _list: Label
var _lines: MeshInstance3D
var _station_labels: Dictionary = {} # NpcStation -> Label3D

func _ready() -> void:
	add_to_group(&"npc_debug_overlay")
	layer = 100
	_list = Label.new()
	_list.position = Vector2(12, 12)
	_list.add_theme_font_size_override("font_size", 13)
	add_child(_list)
	_lines = MeshInstance3D.new()
	_lines.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.2)
	_lines.material_override = m
	_lines.top_level = true
	world.add_child(_lines)

func _process(_delta: float) -> void:
	refresh()

## Updates every label, the path lines and the decision list (called every frame; tests call it directly).
func refresh() -> void:
	if world == null:
		return
	for id in world.agent_ids():
		var a := world.get_agent(id) as NpcAgent
		var lab := a.get_node_or_null("NpcDebugLabel") as Label3D
		if lab == null:
			lab = Label3D.new()
			lab.name = "NpcDebugLabel"
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.no_depth_test = true
			lab.pixel_size = 0.004
			lab.position = Vector3(0, 2.1, 0)
			a.add_child(lab)
		var j := a.current_job()
		lab.text = "%s\n%s | %s\nidle %.1f s" % [a.agent_id, j.id if j else "-", a.phase(), a.idle_s]
	for st in world.get_stations():
		var sl: Label3D = _station_labels.get(st)
		if sl == null:
			sl = Label3D.new()
			sl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sl.no_depth_test = true
			sl.pixel_size = 0.003
			sl.position = Vector3(0, 0.5, 0)
			st.add_child(sl)
			_station_labels[st] = sl
		sl.text = "%s %d/%d" % [st.station_id, st.capacity() - st.free_slots(), st.capacity()]
		sl.modulate = Color(1.0, 0.45, 0.35) if st.free_slots() == 0 else Color(0.5, 1.0, 0.5)
	_draw_paths()
	_list.text = summary_text()

func _draw_paths() -> void:
	var im := _lines.mesh as ImmediateMesh
	im.clear_surfaces()
	var any := false
	for id in world.agent_ids():
		var a := world.get_agent(id) as NpcAgent
		var pts := a.executor.navigator.path_points()
		if pts.size() < 2 or a.executor.navigator.finished:
			continue
		if not any:
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		var parent := a.get_parent() as Node3D
		var xf := parent.global_transform if parent else Transform3D.IDENTITY
		for i in range(pts.size() - 1):
			im.surface_add_vertex(xf * (pts[i] + Vector3(0, 0.05, 0)))
			im.surface_add_vertex(xf * (pts[i + 1] + Vector3(0, 0.05, 0)))
	if any:
		im.surface_end()

## Text of the CanvasLayer list: last decision of each agent (pick, reason, top scores).
func summary_text() -> String:
	var rows := PackedStringArray()
	for id in world.agent_ids():
		var a := world.get_agent(id) as NpcAgent
		var d: Dictionary = a.last_decision
		rows.append("%s: %s  [%s]  %s" % [id, d.get("job", "-"), d.get("reason", "-"), d.get("top", "")])
	return "\n".join(rows)

## Removes every node this overlay created.
func teardown() -> void:
	for id in world.agent_ids():
		var lab := (world.get_agent(id) as NpcAgent).get_node_or_null("NpcDebugLabel")
		if lab:
			lab.free()
	for st in _station_labels:
		if is_instance_valid(_station_labels[st]):
			(_station_labels[st] as Node).free()
	_station_labels.clear()
	if is_instance_valid(_lines):
		_lines.free()
