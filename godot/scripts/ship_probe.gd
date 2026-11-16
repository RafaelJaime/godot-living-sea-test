class_name ShipProbe
extends Node
## ReflectionProbe riding on the ship (Ship/Pivot) so hull, deck and brass pick up environment reflections.
## UPDATE_ONCE only: re-rendered when the time-of-day band or the weather band changes (a few times per day), never periodically.
## Created by sky.gd only with `--probe` (off by default: no visible hull gain, p95 +3..5 ms). `--probe-log` logs refreshes.

var _probe: ReflectionProbe
var _band := -1
var _busy := false

func _process(_delta: float) -> void:
	if _probe == null:
		var pivot := get_tree().root.get_node_or_null("Main/Ship/Pivot") as Node3D
		if pivot == null:
			return
		_probe = ReflectionProbe.new()
		_probe.name = "ShipProbe"
		_probe.size = Vector3(18, 14, 36)
		_probe.position = Vector3(0, 4.5, 0)
		_probe.origin_offset = Vector3(0, 1.0, 0)
		_probe.interior = false
		_probe.box_projection = true
		_probe.enable_shadows = false
		_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		pivot.add_child(_probe)
	var w := WorldState
	var b := int(floor(w.daylight * 4.0)) * 10 + int(floor(w.storm * 3.0)) + (100 if w.night > 0.5 else 0)
	if b != _band and not _busy:
		_band = b
		_refresh()

func _refresh() -> void:
	_busy = true
	await get_tree().create_timer(1.5).timeout # let the sky radiance catch up with the new band
	if is_instance_valid(_probe):
		_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(_probe):
			_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		if "--probe-log" in OS.get_cmdline_user_args():
			print("[probe] refreshed band=", _band)
	_busy = false
