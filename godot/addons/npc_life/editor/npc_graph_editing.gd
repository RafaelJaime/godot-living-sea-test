@tool
class_name NpcGraphEditing
extends RefCounted
## Pure edit operations and colours shared by the editor tools (and tests). No editor classes: safe to load in a game.

const COLORS := {&"walk": Color(0.3, 0.9, 0.35), &"stairs": Color(0.95, 0.85, 0.2), &"ladder": Color(1.0, 0.55, 0.15), &"rope": Color(0.85, 0.35, 0.95)}
const UNKNOWN_COLOR := Color(1.0, 0.2, 0.2)

static func edge_color(type: StringName) -> Color:
	return COLORS.get(type, UNKNOWN_COLOR)

## Adds a node at a WORLD point; it is stored in the platform's local space. Returns its index.
static func add_node_at_world(graph: NpcWaypointGraph, platform: Node3D, world_pos: Vector3, tag := &"") -> int:
	var local := platform.global_transform.affine_inverse() * world_pos if platform else world_pos
	return graph.add_node(local, tag)

## Connects two nodes; -1 for a self loop or a pair that is already connected (either direction).
static func connect_nodes(graph: NpcWaypointGraph, a: int, b: int, type := &"walk") -> int:
	if a == b or a < 0 or b < 0 or a >= graph.node_count() or b >= graph.node_count():
		return -1
	for e in graph.edge_count():
		var x := graph.edges[e * 2]
		var y := graph.edges[e * 2 + 1]
		if (x == a and y == b) or (x == b and y == a):
			return -1
	return graph.connect_nodes(a, b, type)

static func remove_node(graph: NpcWaypointGraph, i: int) -> void:
	graph.remove_node(i)

static func set_edge_type(graph: NpcWaypointGraph, e: int, type: StringName) -> void:
	graph.set_edge_type(e, type)
