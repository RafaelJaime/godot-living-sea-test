extends SceneTree
## Prints the baked crew graph's route between the waist and the forecastle (and to the aloft stations), to see which stairs / ladders it takes.
func _init() -> void:
	var g := load("res://ship/crew_graph.tres") as NpcWaypointGraph
	for pair in [["n_waist_b", "n_fore_b"], ["n_waist_s", "n_fore_bow"], ["n_waist_b", "yard_aloft_2_p"], ["n_waist_b", "yard_aloft_4_s"], ["n_waist_b", "yard_aloft_8_p"], ["n_waist_b", "helm"]]:
		var a: int = g.node_tags.find(StringName(pair[0]))
		var b: int = g.node_tags.find(StringName(pair[1]))
		var path := g.find_path_nodes(a, b)
		var names := []
		for n in path:
			names.append(String(g.node_tags[n]))
		print("[path] ", pair[0], " -> ", pair[1], " cost=", snappedf(g.path_cost(path), 0.1), " : ", " > ".join(names))
	quit()
