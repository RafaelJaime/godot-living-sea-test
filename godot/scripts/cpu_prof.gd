class_name CpuProf
extends Node
## Per-script _process / _physics_process cost profiler (flag `--cpu-prof=<secs>`, e.g. with --quality=final --uncap).
## After a 6 s warm-up it takes over the engine dispatch of every GDScript node that has a processing callback: it calls set_process(false) /
## set_physics_process(false) on them and invokes the callbacks itself from here, sorted by (process_priority, tree order) exactly as the engine
## does, timing each call. It prints the top entries (mean / p95 / max ms per frame, aggregated per script) and frame-level render counters,
## then quits. Limits: nodes created after the takeover are not measured (they keep running normally); native work (skeleton/animation
## updates, physics step, rendering submission, GPU wait) is not GDScript and shows up only in the "unaccounted" line.
## Ordering and results are close to, not identical to, normal dispatch: use for ranking, not for exact budgets.

var _secs := 20.0
var _t := 0.0
var _taken := false
var _proc: Array = [] # [node, key, priority, order]
var _phys: Array = []
var _acc := {} # key -> PackedFloat64Array of per-frame ms (process)
var _acc_phys := {}
var _frame_ms := PackedFloat64Array()
var _frame_script_ms := PackedFloat64Array()
var _draw := PackedFloat64Array()
var _prims := PackedFloat64Array()
var _warm := 6.0

func _ready() -> void:
	process_priority = -2000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cpu-prof="):
			_secs = float(a.get_slice("=", 1))

func _collect(node: Node, order: Array) -> void:
	order[0] += 1
	var s := node.get_script() as Script
	if s != null and node != self and node.get_parent() != self:
		var key := s.resource_path.get_file() if s.resource_path != "" else str(node.get_class())
		if node.is_processing() and node.has_method("_process"):
			_proc.append([node, key, node.process_priority, order[0]])
		if node.is_physics_processing() and node.has_method("_physics_process"):
			_phys.append([node, key, node.process_physics_priority, order[0]])
	for c in node.get_children():
		_collect(c, order)

static func _sorter(a: Array, b: Array) -> bool:
	if a[2] != b[2]:
		return a[2] < b[2]
	return a[3] < b[3]

func _take_over() -> void:
	_collect(get_tree().root, [0])
	_proc.sort_custom(_sorter)
	_phys.sort_custom(_sorter)
	for e in _proc:
		(e[0] as Node).set_process(false)
	for e in _phys:
		(e[0] as Node).set_physics_process(false)
	_taken = true
	print("[cpuprof] took over ", _proc.size(), " _process and ", _phys.size(), " _physics_process callbacks")

func _process(delta: float) -> void:
	_t += delta
	if not _taken:
		if _t >= _warm:
			_take_over()
			_t = 0.0
		return
	var total := 0.0
	var fr := {}
	for e in _proc:
		var n := e[0] as Node
		if not is_instance_valid(n):
			continue
		var t0 := Time.get_ticks_usec()
		n._process(delta)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		fr[e[1]] = float(fr.get(e[1], 0.0)) + ms # several instances of one script inside a frame count as one sample
	for k in fr.keys():
		if not _acc.has(k):
			_acc[k] = PackedFloat64Array()
		var arr: PackedFloat64Array = _acc[k]
		arr.append(fr[k])
		_acc[k] = arr
	_frame_script_ms.append(total)
	_frame_ms.append(delta * 1000.0)
	_draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _t >= _secs:
		_report()
		get_tree().quit()

func _physics_process(delta: float) -> void:
	if not _taken:
		return
	for e in _phys:
		var n := e[0] as Node
		if not is_instance_valid(n):
			continue
		var t0 := Time.get_ticks_usec()
		n._physics_process(delta)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if not _acc_phys.has(e[1]):
			_acc_phys[e[1]] = PackedFloat64Array()
		var arr: PackedFloat64Array = _acc_phys[e[1]]
		arr.append(ms)
		_acc_phys[e[1]] = arr

static func _stats(a: PackedFloat64Array) -> Array:
	if a.is_empty():
		return [0.0, 0.0, 0.0]
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in a:
		sum += v
	return [sum / a.size(), s[int(s.size() * 0.95)], s[s.size() - 1]]

func _dump(title: String, d: Dictionary, per_frame_div: float) -> void:
	var rows: Array = []
	for k in d.keys():
		var st := _stats(d[k])
		rows.append([k, st[0] * (d[k].size() / per_frame_div) if per_frame_div > 0.0 else st[0], st[1], st[2]])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	print("[cpuprof] ", title, " (mean ms per frame (per call for physics), p95, max):")
	for i in mini(rows.size(), 18):
		print("[cpuprof]   %-34s mean=%6.3f p95=%6.3f max=%7.3f" % [rows[i][0], rows[i][1], rows[i][2], rows[i][3]])

func _report() -> void:
	var fs := _stats(_frame_ms)
	var ss := _stats(_frame_script_ms)
	var ds := _stats(_draw)
	var ps := _stats(_prims)
	print("[cpuprof] frames=", _frame_ms.size(), " frame_ms mean=", snappedf(fs[0], 0.01), " p95=", snappedf(fs[1], 0.01),
		" | all GDScript _process mean=", snappedf(ss[0], 0.01), " p95=", snappedf(ss[1], 0.01), " max=", snappedf(ss[2], 0.01),
		" | unaccounted (native, render submit, GPU wait) mean=", snappedf(fs[0] - ss[0], 0.01))
	print("[cpuprof] draw_calls mean=", int(ds[0]), " max=", int(ds[2]), " primitives mean=", int(ps[0]), " nodes=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		" objects=", int(Performance.get_monitor(Performance.OBJECT_COUNT)), " vram_mb=", snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 1))
	_dump("_process per script", _acc, float(maxi(_frame_ms.size(), 1)))
	_dump("_physics_process per script", _acc_phys, 0.0)
