class_name NpcNeeds
extends RefCounted
## Per-agent need levels (0..1). Needs grow over time at the rates of the character definition (per minute) and are satisfied by finished
## jobs; the scorer reads them to make an agent want certain kinds of jobs.

var _levels: Dictionary = {} # need -> 0..1
var _growth: Dictionary = {} # need -> per minute

func _init(def: NpcCharacterDef = null) -> void:
	if def:
		for k in def.needs:
			_growth[k] = def.needs[k]
			_levels[k] = 0.0

func level(need: StringName) -> float:
	return _levels.get(need, 0.0)

func advance(dt_s: float) -> void:
	for k in _growth:
		_levels[k] = clampf(_levels.get(k, 0.0) + _growth[k] * dt_s / 60.0, 0.0, 1.0)

func satisfy(need: StringName, amount: float) -> void:
	if _levels.has(need):
		_levels[need] = clampf(_levels[need] - amount, 0.0, 1.0)
