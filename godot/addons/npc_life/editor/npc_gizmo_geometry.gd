@tool
class_name NpcGizmoGeometry
extends RefCounted
## Pure geometry of the editor gizmos (station anchor / approach / facing arrow / slots, graph edges by type), in the owner's local space.

const COLOR_STATION := Color(0.35, 0.75, 1.0)
const COLOR_MUST_STAFF := Color(1.0, 0.4, 0.3)

static func station(st: NpcStation) -> Dictionary:
	var dir := Basis(Vector3.UP, deg_to_rad(st.facing_deg)) * Vector3(0, 0, -1)
	var tip := dir * 0.9
	var side := dir.cross(Vector3.UP).normalized() * 0.15
	var lines := PackedVector3Array([
		Vector3.ZERO, tip, tip, tip - dir * 0.2 + side, tip, tip - dir * 0.2 - side, # facing arrow
		Vector3.ZERO, st.approach_offset, # anchor -> approach
	])
	var slots := PackedVector3Array()
	for i in st.capacity():
		var p := Vector3.ZERO
		for c in st.get_children():
			if c is NpcStationSlot and (c as NpcStationSlot).slot_index == i:
				p = (c as Node3D).position
		slots.append(p)
		lines.append_array(PackedVector3Array([p + Vector3(-0.1, 0, 0), p + Vector3(0.1, 0, 0), p + Vector3(0, 0, -0.1), p + Vector3(0, 0, 0.1)]))
	return {"anchor": Vector3.ZERO, "approach": st.approach_offset, "facing_tip": tip, "slots": slots, "lines": lines, "color": COLOR_MUST_STAFF if st.must_staff else COLOR_STATION}

## One row per edge: {a, b (node positions), color}.
static func graph_lines(g: NpcWaypointGraph) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for e in g.edge_count():
		var a := g.edges[e * 2]
		var b := g.edges[e * 2 + 1]
		if a < 0 or b < 0 or a >= g.node_count() or b >= g.node_count():
			continue
		rows.append({"a": g.positions[a], "b": g.positions[b], "color": NpcGraphEditing.edge_color(g.edge_type(e))})
	return rows
