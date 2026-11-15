@tool
class_name NpcWaypointGraphInstance
extends Node3D
## Binds an NpcWaypointGraph (stored in platform-local space) to a platform node so editor tools and debug code can draw it and convert
## node positions to world space on demand. The resource itself is never rewritten by platform motion.

@export var graph: NpcWaypointGraph
@export var platform_root: Node3D

func node_local(i: int) -> Vector3:
	return graph.positions[i]

func node_world(i: int) -> Vector3:
	var root: Node3D = platform_root if platform_root else self
	return root.global_transform * graph.positions[i]

## Editor helpers: the last two nodes the user touched (for "Connect selected") and conversions between the graph's platform-local space and this node's space.
var selected := PackedInt32Array()

func mark_selected(i: int) -> void:
	if selected.has(i):
		selected.remove_at(selected.find(i))
	selected.append(i)
	while selected.size() > 2:
		selected.remove_at(0)

func platform() -> Node3D:
	return platform_root if platform_root else self

func to_instance_space(local: Vector3) -> Vector3:
	return global_transform.affine_inverse() * (platform().global_transform * local)

func from_instance_space(p: Vector3) -> Vector3:
	return platform().global_transform.affine_inverse() * (global_transform * p)
