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
