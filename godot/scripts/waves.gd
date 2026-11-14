extends Node
## Thin facade over the FFT ocean so the rest of the scene (buoyancy, camera, ...) does not need to know about it.
## The ocean node registers itself on _ready.

var ocean: Node = null
## Accumulated world shift (doubles). Rebase steps are multiples of every cascade tile, so waves never jump.
var offset_x := 0.0
var offset_z := 0.0

## 0 (calm) .. 1 (storm). Forwarded to the ocean; T4 animates this.
var sea_state := 0.35:
	set(v):
		sea_state = clampf(v, 0.0, 1.0)
		if ocean:
			ocean.sea_state = sea_state

func register_ocean(o: Node) -> void:
	ocean = o
	ocean.sea_state = sea_state

## Surface height at world column (x, z), read back from the same FFT displacement maps that are rendered.
var flat := OS.get_cmdline_user_args().has("--flat") ## test aid: perfectly flat sea for the physics
func height_at(x: float, z: float) -> float:
	if flat:
		return 0.0
	return ocean.height_at(x, z) if ocean else 0.0

func add_world_shift(shift_x: float, shift_z: float) -> void:
	offset_x += shift_x
	offset_z += shift_z
