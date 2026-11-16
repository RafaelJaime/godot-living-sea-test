class_name OptionalVfx
extends RefCounted
## Optional Vefects packs (free, but their license forbids redistribution: they live in res://Vefects/, outside git; see godot/README.md).
## Everything here is a no-op when the folder is missing: detection is ResourceLoader.exists, never preload, so a clean checkout runs the
## built-in effects with no errors or warnings.

const CANDLE_FLAME := "res://Vefects/Candle VFX/Flames/Particles/VFX_Candle_Flame_01.tscn"
const ZAP_WHITE := "res://Vefects/Zap VFX/VFX/Zap/Particles/VFX_Zap_06_White.tscn"

static func available(path: String) -> bool:
	return ResourceLoader.exists(path)

## Instance of the scene, or null when the pack is not installed.
static func spawn(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() if ps != null else null

## Fires every one-shot particle system of an instance.
static func fire(n: Node) -> void:
	for p in n.find_children("*", "GPUParticles3D", true, false):
		(p as GPUParticles3D).restart()
		(p as GPUParticles3D).emitting = true
