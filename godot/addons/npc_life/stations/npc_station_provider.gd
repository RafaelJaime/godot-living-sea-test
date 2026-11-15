class_name NpcStationProvider
extends Node
## Source of stations for an NpcWorld. The default implementation returns every NpcStation in the scene group `npc_station`; a game
## extends it to create stations from its own data (markers, props, rig parts) and emits `stations_changed` when the set changes.

signal stations_changed()

func provide_stations() -> Array[NpcStation]:
	var out: Array[NpcStation] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(&"npc_station"):
		if n is NpcStation:
			out.append(n)
	return out
