extends Node
## Debug aid for CPU spikes (flag --spike-probe[=ms]): probes at several process priorities measure how long each priority band of the
## frame's _process work takes. Frames longer than the threshold (default 25 ms between two frame ends) print the bands; a summary compares
## the band means of normal and slow frames and the spacing of the slow frames.
## Bands are named by the process_priority of the last system inside: wind join (-1000) | world_state (-90) | camera (10) | ocean + cloth launch (100)
## | ambient (120) | wake (150) | canto/cloth probe (200) | end. "rest" = frame time minus all bands = physics, rendering, vsync wait.

const PRIOS := [-1100, -999, -95, 0, 15, 90, 101, 130, 160, 250, 999]
var _stamps := PackedInt64Array()
var _last_end := 0
var _thr_ms := 25.0
var _sum_fast := PackedFloat64Array()
var _sum_slow := PackedFloat64Array()
var _n_fast := 0
var _n_slow := 0
var _slow_times := PackedFloat64Array()
var _t := 0.0
var _rest_fast := 0.0
var _rest_slow := 0.0
var _phys_fast := 0.0
var _phys_slow := 0.0
var _warm := 5.0
var _last_phys_us := 0
var _phys_us_acc := 0

class Probe extends Node:
	var idx := 0
	var owner_probe: Node
	func _process(_d: float) -> void:
		owner_probe.stamp(idx)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spike-probe="):
			_thr_ms = float(a.get_slice("=", 1))
	_stamps.resize(PRIOS.size())
	_sum_fast.resize(PRIOS.size())
	_sum_slow.resize(PRIOS.size())
	for i in PRIOS.size():
		var p := Probe.new()
		p.idx = i
		p.owner_probe = self
		p.process_priority = PRIOS[i]
		add_child(p)
	set_physics_process(true)
	for a in OS.get_cmdline_user_args():
		if a == "--spike-nodes" or a.begins_with("--spike-nodes="):
			if a.begins_with("--spike-nodes="):
				_np_thr_ms = float(a.get_slice("=", 1))
			install_node_probes.call_deferred(_np_thr_ms)

func _physics_process(_d: float) -> void:
	pass

func stamp(i: int) -> void:
	_stamps[i] = Time.get_ticks_usec()
	if i == 0:
		_np_frame_start_us = _stamps[0]
	if i != PRIOS.size() - 1:
		return
	var now := _stamps[i]
	if _last_end == 0:
		_last_end = now
		return
	var frame_us := now - _last_end
	_last_end = now
	_t += frame_us / 1.0e6
	if _t < _warm:
		return
	var bands := PackedFloat64Array()
	var script_us := 0.0
	for k in range(1, PRIOS.size()):
		var d := float(_stamps[k] - _stamps[k - 1]) / 1000.0
		bands.append(d)
		script_us += d
	var frame_ms := frame_us / 1000.0
	var rest := frame_ms - script_us
	if frame_ms > _thr_ms:
		_n_slow += 1
		_slow_times.append(_t)
		_rest_slow += rest
		for k in bands.size():
			_sum_slow[k] += bands[k]
		var row := "[probe] t=%.2f frame=%.1f rest=%.1f bands(ms):" % [_t, frame_ms, rest]
		for k in bands.size():
			row += " %d:%.2f" % [PRIOS[k + 1], bands[k]]
		print(row)
	else:
		_n_fast += 1
		_rest_fast += rest
		for k in bands.size():
			_sum_fast[k] += bands[k]

func report() -> void:
	var iv := PackedFloat64Array()
	for i in range(1, _slow_times.size()):
		iv.append(_slow_times[i] - _slow_times[i - 1])
	iv.sort()
	print("[probe] normal frames=", _n_fast, " slow frames (> ", _thr_ms, " ms)=", _n_slow)
	var rf := "[probe] mean ms per band, normal | slow:"
	for k in range(1, PRIOS.size()):
		rf += "  <=%d: %.2f | %.2f" % [PRIOS[k], _sum_fast[k] / maxf(_n_fast, 1), _sum_slow[k] / maxf(_n_slow, 1)]
	print(rf)
	print("[probe] mean rest (physics, render, wait): normal %.2f ms | slow %.2f ms" % [_rest_fast / maxf(_n_fast, 1), _rest_slow / maxf(_n_slow, 1)])
	if iv.size() > 0:
		print("[probe] slow-frame spacing: min %.2f s  p50 %.2f s  max %.2f s" % [iv[0], iv[iv.size() / 2], iv[iv.size() - 1]])

# --- --spike-nodes[=ms]: node-level attribution inside the default-priority band --------------------------------------------------
# Inserts a tiny probe node before every node under Main that processes (so tree order, hence processing order, is unchanged) and reports,
# for any interval longer than the threshold, which node's _process (plus unprobed descendants) the time was spent in.
class NodeProbe extends Node:
	var label := ""
	var owner_probe: Node
	func _process(_d: float) -> void:
		owner_probe.node_stamp(label)

var _np_last_us := 0
var _np_last_label := ""
var _np_thr_ms := 8.0
var _np_t := 0.0
var _np_frame_start_us := 0

func install_node_probes(thr_ms: float) -> int:
	_np_thr_ms = thr_ms
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return 0
	var targets: Array[Node] = []
	for n in main.find_children("*", "", true, false):
		if n.get_script() != null and n.is_processing() and not (n is NodeProbe) and n.get_parent() != null:
			targets.append(n)
	for n in targets:
		var p := NodeProbe.new()
		p.label = String(n.get_path()).trim_prefix("/root/Main/")
		p.owner_probe = self
		var par := n.get_parent()
		par.add_child(p)
		par.move_child(p, n.get_index())
	print("[nodeprobe] installed ", targets.size(), " probes")
	return targets.size()

func node_stamp(label: String) -> void:
	var now := Time.get_ticks_usec()
	if _np_last_label != "" and _t >= _warm:
		var ms := float(now - _np_last_us) / 1000.0
		if ms > _np_thr_ms and _np_last_us >= _np_frame_start_us:
			print("[nodeprobe] t=%.2f %.1f ms in node(s) starting at '%s' (until '%s')" % [_t, ms, _np_last_label, label])
	_np_last_us = now
	_np_last_label = label
