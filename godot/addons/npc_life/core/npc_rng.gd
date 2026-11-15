class_name NpcRng
extends RefCounted
## Seeded random stream. Never the global RNG: every agent owns streams derived from (world seed, agent id, stream name), so one agent's
## history does not depend on another agent existing, and the same seed reproduces the same run.

var draws := 0 ## number of draws so far (logged as the RNG draw index)
var _rng := RandomNumberGenerator.new()

func _init(rng_seed: int = 0) -> void:
	_rng.seed = rng_seed

## 63-bit FNV-1a over "world_seed|agent_id|stream": stable across runs, platforms and engine versions (unlike `hash()` of containers).
static func seed_for(world_seed: int, agent_id: StringName, stream: StringName) -> int:
	var h := -3750763034362895579 # FNV-1a 64-bit offset basis 0xcbf29ce484222325 as a signed int64 (the arithmetic wraps)
	var bytes := ("%d|%s|%s" % [world_seed, String(agent_id), String(stream)]).to_utf8_buffer()
	for b in bytes:
		h = (h ^ int(b)) * 0x100000001b3
	return h & 0x7fffffffffffffff

func randf() -> float:
	draws += 1
	return _rng.randf()

func randi() -> int:
	draws += 1
	return _rng.randi()

func randf_range(from: float, to: float) -> float:
	draws += 1
	return _rng.randf_range(from, to)

func randi_range(from: int, to: int) -> int:
	draws += 1
	return _rng.randi_range(from, to)
