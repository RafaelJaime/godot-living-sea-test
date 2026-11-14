extends Node3D
## Keeps the world numerically safe: when the ship gets too far from the origin everything in
## group "rebase" is shifted back and the wave phase absorbs the shift (Waves.add_world_shift).

@export var ship_path := NodePath("Ship")
## Any value works: the cascade phase shift is folded into the ocean shader and the CPU sampling.
@export var rebase_distance := 1600.0
@export var rebase_step := 1600.0

var _ship: Node3D
var total_shifted := 0.0

func _ready() -> void:
	_ship = get_node(ship_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rebase-test="): # test aid: rebase every N meters
			rebase_distance = float(a.get_slice("=", 1))
			rebase_step = rebase_distance

func _process(_delta: float) -> void:
	var p := _ship.global_position
	if absf(p.z) > rebase_distance or absf(p.x) > rebase_distance:
		var shift := Vector3(snappedf(p.x, rebase_step), 0.0, snappedf(p.z, rebase_step))
		var probe := Vector2(p.x + 3.0, p.z + 7.0)
		var h_before: float = Waves.height_at(probe.x, probe.y)
		for n in get_tree().get_nodes_in_group("rebase"):
			n.rebase(shift)
		Waves.add_world_shift(shift.x, shift.z)
		var h_after: float = Waves.height_at(probe.x - shift.x, probe.y - shift.z)
		print("[rebase] wave continuity at a fixed world point: before ", snappedf(h_before, 0.001), " after ", snappedf(h_after, 0.001))
		total_shifted += shift.length()
		print("[rebase] shifted ", shift, " total=", total_shifted)
