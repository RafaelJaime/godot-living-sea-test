class_name NpcGroundProbe
extends RefCounted
## Optional abstract height correction: a game can lift agents onto stairs, uneven decks or a swaying gangway. The default does nothing
## (agents keep the height of the waypoint path).

## Ground height at a platform-local position, or NAN for "no correction".
func height_at(_local_pos: Vector3) -> float:
	return NAN
