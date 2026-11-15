class_name NpcWorldInputs
extends RefCounted
## Blackboard: the game writes world facts (`storm`, `daylight`, ...) with `set_value`; job sources, the scorer and rosters read only this.
## Every change is logged with a sequence number (no wall-clock), so decisions can be replayed and compared.

signal value_changed(key: StringName, old: Variant, new: Variant)

var max_log := 256
var _values: Dictionary = {}
var _log: Array[Dictionary] = []
var _seq := 0
var _consult: Dictionary = {}
var _consulting := false

func set_value(key: StringName, value: Variant) -> void:
	var had := _values.has(key)
	var old: Variant = _values.get(key)
	if had and old == value and typeof(old) == typeof(value):
		return
	_values[key] = value
	_seq += 1
	_log.append({"seq": _seq, "key": key, "old": old, "new": value})
	if _log.size() > max_log:
		_log = _log.slice(_log.size() - max_log)
	value_changed.emit(key, old, value)

func get_value(key: StringName, default: Variant = null) -> Variant:
	if _consulting:
		_consult[String(key)] = true
	return _values.get(key, default)

func has_value(key: StringName) -> bool:
	return _values.has(key)

func change_log() -> Array[Dictionary]:
	return _log

## Records which keys are read until `end_consult()`; the decision log snapshots them.
func begin_consult() -> void:
	_consult.clear()
	_consulting = true

func end_consult() -> PackedStringArray:
	_consulting = false
	var keys := _consult.keys()
	keys.sort()
	return PackedStringArray(keys)
