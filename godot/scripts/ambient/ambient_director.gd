extends Node
## Ambient director: one place that knows the ambient systems (birds, dolphins, flotsam, whale spout, passing ship, lighthouse beams).
## Systems join the group `ambient_system` and expose `ambient_pools() -> Dictionary` (fixed pool sizes, already scaled by
## `Quality.ambient_scale`) and `ambient_stats() -> Dictionary` (active counts). `stats()` merges them; the director logs the pools
## once at start and the stats every 30 game seconds (`--ambient-log=<seconds>` changes the period, `--ambient-log=0` silences it).
## Runs at priority 120, after the systems it reports on.

var _t := 0.0
var _period := 30.0
var _next := 30.0
var _pools_logged := false

func _ready() -> void:
	process_priority = 120
	add_to_group("ambient_director")
	add_child((load("res://scripts/ambient/deck_wet.gd") as GDScript).new())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ambient-log="):
			_period = float(a.get_slice("=", 1))
			_next = _period

## {system: active_count} over every registered ambient system plus the lighthouse beams that are lit.
func stats() -> Dictionary:
	var out := {}
	for n in get_tree().get_nodes_in_group("ambient_system"):
		if n.has_method("ambient_stats"):
			out.merge(n.ambient_stats())
	var beams := get_tree().get_nodes_in_group("lighthouse_beam")
	var lit := 0
	for b in beams:
		if b.has_method("is_on") and b.is_on():
			lit += 1
	out["lighthouse_beams"] = lit
	return out

## {system: pool_size}: what each system allocated at start.
func pools() -> Dictionary:
	var out := {}
	for n in get_tree().get_nodes_in_group("ambient_system"):
		if n.has_method("ambient_pools"):
			out.merge(n.ambient_pools())
	out["lighthouse_beams"] = get_tree().get_nodes_in_group("lighthouse_beam").size()
	return out

func _process(delta: float) -> void:
	_t += delta
	if not _pools_logged and _t > 0.5:
		_pools_logged = true
		print("[ambient] pools (", Quality.name_, ", ambient_scale=", Quality.ambient_scale, "): ", pools())
	if _period > 0.0 and _t >= _next:
		_next += _period
		print("[ambient] stats t=", int(_t), " ", stats())
