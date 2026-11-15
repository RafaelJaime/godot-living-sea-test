class_name NpcRoster
extends Resource
## The watches of a world (see NpcWatchDef) as one resource.

@export var watches: Array[NpcWatchDef] = []

func validate(known_stations := PackedStringArray(), known_agents := PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	for w in watches:
		out.append_array(w.validate(known_stations, known_agents))
	return out
