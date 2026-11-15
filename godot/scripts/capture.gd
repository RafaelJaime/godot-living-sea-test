extends Node
## Active only with the user arg `--capture`: saves screenshots to res://_shots and quits.
## godot --path <project> -- --capture

const SHOT_DIR := "res://_shots"
# [capture time (s), camera shot index]
var PLAN: Array = [[3.0, 11, 0.2], [6.0, 14, 0.2], [9.0, 2, 0.2], [13.0, 11, 0.9], [16.0, 14, 0.9], [19.0, 2, 0.9]]

var _active := false
var _t := 0.0
var _step := 0
var _seq_n := 0
var _seq_h := 15.0
var _seq_i := 0
var _seq_t0 := 0.0
var _seq_speed := 0.0
var _sweep_n := 0
var _sweep_h := 40.0
var _jumped := false

## Fixed regression presets (design Decision 13): name, day_phase, weather, sea_state, wind direction (deg).
const REG_PRESETS := [
	{"name": "day_calm", "phase": 0.45, "weather": "clear", "sea": 0.2, "wind": -100.0},
	{"name": "dusk_moderate", "phase": 0.73, "weather": "cloudy", "sea": 0.5, "wind": -100.0},
	{"name": "storm", "phase": 0.55, "weather": "storm", "sea": 0.9, "wind": -100.0},
	{"name": "night", "phase": 0.02, "weather": "clear", "sea": 0.35, "wind": -100.0},
]
const REG_SHOTS := [1, 14, 0] # camera shot indices (side low, top down, 3/4 bow)
const REG_SETTLE := 8.0

var _perf_secs := 0.0
var _spike_log := false
var _spike_times := PackedFloat64Array()
var _spike_thr_ms := 35.0
var _perf_t := 0.0
var _perf_frame: PackedFloat64Array = PackedFloat64Array()
var _perf_cpu: PackedFloat64Array = PackedFloat64Array()
var _perf_phys: PackedFloat64Array = PackedFloat64Array()
var _perf_gpu: PackedFloat64Array = PackedFloat64Array()
var _reg := false
var _reg_i := 0
var _reg_shot := 0
var _reg_t := 0.0
var _reg_state := 0 # 0 apply, 1 settle, 2 shots
var _poll_state := false
var _jitter := false
var _log_secs := 0.0
var _log_period := 2.0
var _roll_thr := 0.0
var _roll_sign := 1.0
var _roll_samples: Array = []
var _log_t := 0.0
var _prev_rel: Vector3
var _prev_d: Vector3
var _prev_fwd: Vector3
var _prev_dfwd: Vector3
var _frames := 0
var _max_d := 0.0
var _max_dd := 0.0
var _max_ang := 0.0
var _max_dang := 0.0
var _max_delta := 0.0
var _sum_delta := 0.0

func _has_prefix(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return true
	return false

func _ready() -> void:
	if "--capture" in OS.get_cmdline_user_args() or "--jitter-test" in OS.get_cmdline_user_args() or _has_prefix("--autopilot-log="):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true) # never steal keyboard focus
	process_priority = 1000 # measure after camera/ship have updated this frame
	_jitter = "--jitter-test" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with('--autopilot-log='):
			_log_secs = float(a.get_slice('=', 1))
		elif a.begins_with('--perf-log='):
			_perf_secs = float(a.get_slice('=', 1))
		elif a == '--spike-log': # prints every frame whose process time exceeds the threshold, then the interval statistics
			_spike_log = true
		elif a.begins_with('--spike-ms='):
			_spike_thr_ms = float(a.get_slice('=', 1))
		elif a == '--spike-probe' or a.begins_with('--spike-probe=') or a == '--spike-nodes' or a.begins_with('--spike-nodes='):
			var sp := Node.new()
			sp.set_script(load('res://scripts/spike_probe.gd'))
			sp.name = 'SpikeProbe'
			get_tree().root.add_child.call_deferred(sp)
		elif a.begins_with('--frame-seq='): # M6 popping test: N consecutive frames saved as _shots/seq_NNN.png from a ship-space camera at the given height
			_seq_n = int(a.get_slice('=', 1).get_slice(',', 0))
			_seq_h = float(a.get_slice('=', 1).get_slice(',', 1)) if a.count(',') >= 1 else 15.0
			_seq_speed = float(a.get_slice('=', 1).get_slice(',', 2)) if a.count(',') >= 2 else 0.0
		elif a == '--deck-survey':
			var ds := Node.new()
			ds.set_script(load('res://scripts/deck_survey.gd'))
			get_tree().root.add_child.call_deferred(ds)
		elif a == '--poll-sail-state':
			_poll_state = true
		elif a == '--plan=regression':
			_reg = true
		elif a.begins_with('--roll-extreme='):
			_roll_thr = float(a.get_slice('=', 1))
		elif a.begins_with('--log-period='):
			_log_period = float(a.get_slice('=', 1))
	if _jitter:
		_active = true
		return
	_active = "--capture" in OS.get_cmdline_user_args()
	_active = _active or _log_secs > 0.0 or _perf_secs > 0.0 or _reg or _seq_n > 0
	if _perf_secs > 0.0:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	set_process(_active)
	if _active:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
		for a in OS.get_cmdline_user_args():
			if a.begins_with('--plan='):
				match a.get_slice('=', 1):
					'world': PLAN = [[3.0, 0], [6.0, 5], [9.0, 3], [12.0, 2], [15.0, 6], [18.0, 4], [21.0, 0]]
					'crew': PLAN = [[3.0, 12], [6.0, 12], [9.0, 13], [12.0, 13], [15.0, 10], [18.0, 3]]
					'foam': PLAN = [[3.0, 14], [6.0, 11], [9.0, 1], [12.0, 0]]
					'ship': PLAN = [[3.0, 0], [6.0, 2], [9.0, 14], [12.0, 7], [15.0, 8], [18.0, 9], [21.0, 10], [24.0, 12]]
					'lights': PLAN = [[3.0, 3], [5.0, 14], [18.0, 3], [20.0, 14], [22.0, 1]]
					'boat': PLAN = [[3.0, 4], [6.0, 4], [9.0, 2]]
					'windcal': PLAN = [[70.0, 15], [72.0, 16], [74.0, 1], [76.0, 0], [78.0, 2]] # long settle: a becalmed ship needs ~60 s to stop
					'catpaw': PLAN = [[20.0, 2], [25.0, 2], [30.0, 1], [35.0, 1]] # two captures 5 s apart per view (M4c1)
					'sky': PLAN = [[3.0, 5], [6.0, 6], [9.0, 2], [12.0, 3], [15.0, 0], [18.0, 5]]
		for a in OS.get_cmdline_user_args():
			if a.begins_with('--shots='):
				PLAN = []
				var k := 0
				for i in a.get_slice('=', 1).split(','):
					PLAN.append([3.0 + 2.5 * k, int(i)])
					k += 1
		for a in OS.get_cmdline_user_args():
			if a.begins_with('--cam-sweep='): # M6.1: N shots turning the debug camera through 360 deg (needs a --cam to create the shot)
				_sweep_n = int(a.get_slice('=', 1).get_slice(',', 0))
				_sweep_h = float(a.get_slice('=', 1).get_slice(',', 1)) if ',' in a else 40.0
				PLAN = []
				for k in _sweep_n:
					PLAN.append([3.0 + 2.5 * k, -1])
		print('[capture] active')
		get_tree().create_timer(0.1).timeout.connect(func() -> void: pass)

func _process(delta: float) -> void:
	_t += delta
	if _seq_n > 0:
		_seq_step(delta)
		return
	if _perf_secs > 0.0:
		_perf_step(delta)
		return
	if _reg:
		_reg_step(delta)
		return
	if _log_secs > 0.0:
		_log_t += delta
		if fmod(_log_t, _log_period) < delta:
			var sh := get_tree().root.get_node('Main/Ship')
			var ap := get_tree().root.get_node('Main/Ship/Autopilot')
			if _poll_state:
				var rg := get_tree().get_first_node_in_group('sail_rig')
				if rg:
					var st: Dictionary = rg.sail_state()
					print('[sail_state] ', st)
			print('[log] t=', snappedf(_log_t, 0.1), ' pos=(', snappedf(sh.global_position.x, 1.0), ',', snappedf(sh.global_position.z, 1.0), ') yaw=', snappedf(rad_to_deg(sh.yaw), 1.0), ' roll=', snappedf(rad_to_deg(sh.roll), 0.1), ' pitch=', snappedf(rad_to_deg(sh.pitch), 0.1), ' rudder=', snappedf(sh.rudder, 0.01), ' speed=', snappedf(sh.current_speed, 0.1), ' tack_side=', ap._tack_side, ' tacking=', ap.tacking, ' target_dist=', snappedf(Vector2(sh.global_position.x, sh.global_position.z).distance_to(ap.target), 1.0), ' wind_ang=', snappedf(rad_to_deg(WorldState.wind_angle), 1.0), ' day=', snappedf(WorldState.day_phase, 0.01), ' cloud=', snappedf(WorldState.cloud, 0.01), ' storm=', snappedf(WorldState.storm, 0.01), ' sea=', snappedf(WorldState.sea_state, 0.01))
		var sh2 := get_tree().root.get_node('Main/Ship')
		_roll_samples.append([_log_t, rad_to_deg(sh2.roll), rad_to_deg(sh2.pitch)])
		if _log_t >= _log_secs:
			_report_motion()
			get_tree().quit()
		return
	if _jitter:
		_jitter_step(delta)
		return
	if _step >= PLAN.size():
		print("[capture] done")
		get_tree().quit()
		return
	var when: float = PLAN[_step][0]
	var cam_idx: int = PLAN[_step][1]
	if cam_idx < 0:
		var dd0 := get_tree().get_first_node_in_group('camera_director')
		cam_idx = dd0.shots.size() - 1 if dd0 else 0
	if _step < PLAN.size() and PLAN[_step].size() > 2:
		WorldState.override_sea = float(PLAN[_step][2])
	if not _jumped and _t >= when - 0.8:
		_jumped = true
		var d := get_tree().get_first_node_in_group("camera_director")
		if d:
			for ca in OS.get_cmdline_user_args():
				if ca == '--cam-island' or ca.begins_with('--cam-island='):
					_aim_debug_cam_at_shore(d, cam_idx, float(ca.get_slice('=', 1)) if '=' in ca else 5.0)
			if _sweep_n > 0:
				var yaw := TAU * float(_step) / float(_sweep_n)
				var dirv := Vector3(sin(yaw), 0.0, -cos(yaw))
				d.shots[cam_idx]["pos"] = Vector3(0.0, _sweep_h, 0.0)
				d.shots[cam_idx]["look"] = Vector3(0.0, _sweep_h - 3.0, 0.0) + dirv * 300.0
				d.shots[cam_idx]["fov"] = 70.0
			d.jump_to(cam_idx, true)
	if '--lightning' in OS.get_cmdline_user_args() and _step == 2 and _t >= when - 0.08:
		if WorldState.flash < 0.5:
			get_tree().root.get_node('Main/Weather')._spawn_bolt()
		WorldState.flash = 1.0
	if _roll_thr > 0.0 and _t >= when and _t < when + 45.0:
		# Wait for the ship to reach a roll extreme (alternating sides) before the shot.
		var rd := rad_to_deg(get_tree().root.get_node('Main/Ship').roll)
		if rd * _roll_sign < _roll_thr:
			return
		_roll_sign = -_roll_sign
	if _t >= when:
		var img := get_viewport().get_texture().get_image()
		var path := "%s/shot_%02d.png" % [SHOT_DIR, _step + 1]
		img.save_png(ProjectSettings.globalize_path(path))
		print("[capture] saved ", path, " size=", img.get_size(), " fps=", Engine.get_frames_per_second(), " cam=", get_viewport().get_camera_3d().global_position, " ship=", get_tree().root.get_node("Main/Ship").global_position)
		_step += 1
		_jumped = false

## Camera jitter report: per-frame camera motion relative to the ship (position and view angle),
## plus the second difference, which exposes high-frequency shake that smooth motion does not have.
func _jitter_step(delta: float) -> void:
	if _t < 4.0:
		if _t > 3.0 and not _jumped:
			_jumped = true
			for a in OS.get_cmdline_user_args():
				if a.begins_with('--jitter-shot='):
					get_tree().get_first_node_in_group('camera_director').jump_to(int(a.get_slice('=', 1)), true)
		return
	var cam := get_viewport().get_camera_3d()
	var ship := get_tree().root.get_node("Main/Ship") as Node3D
	# Measured in the ship's yaw frame: a turning ship legitimately swings the camera around it in world space.
	var ist: Transform3D = ship.get_global_transform_interpolated()
	var ifwd := -ist.basis.z
	var to_local := Basis(Vector3.UP, atan2(-ifwd.x, -ifwd.z)).inverse()
	var rel := to_local * (cam.global_position - ship.get_global_transform_interpolated().origin)
	var fwd := to_local * (-cam.global_transform.basis.z)
	if _frames > 0:
		var d := rel - _prev_rel
		var dfwd := fwd - _prev_fwd
		# normalize by frame time so different fps compare
		var v := d / delta
		var av := dfwd / delta
		_max_d = maxf(_max_d, v.length())
		_max_ang = maxf(_max_ang, rad_to_deg(av.length()))
		if _frames > 1:
			var acc := (v - _prev_d).length() / delta
			if acc > 40.0:
				print('[jitter] spike t=', snappedf(_t, 0.01), ' acc=', snappedf(acc, 0.1), ' delta=', snappedf(delta, 0.0001), ' v=', v, ' prev=', _prev_d)
			_max_dd = maxf(_max_dd, acc)
			_max_dang = maxf(_max_dang, rad_to_deg((av - _prev_dfwd).length()) / delta)
		_prev_d = v
		_prev_dfwd = av
	_max_delta = maxf(_max_delta, delta)
	_sum_delta += delta
	_prev_rel = rel
	_prev_fwd = fwd
	_frames += 1
	if _frames == 1 or _frames % 60 == 0:
		pass
	if _t > 14.0:
		print("[jitter] frametime avg=", snappedf(_sum_delta / maxf(_frames, 1) * 1000.0, 0.01), "ms max=", snappedf(_max_delta * 1000.0, 0.1), "ms  frames=", _frames, " max cam speed(rel ship)=", snappedf(_max_d, 0.01), " m/s  max accel=", snappedf(_max_dd, 0.1),
			" m/s2  max view ang speed=", snappedf(_max_ang, 0.01), " deg/s  max ang accel=", snappedf(_max_dang, 0.1), " deg/s2")
		get_tree().quit()

## Period and amplitude of roll / pitch from the recorded samples (zero crossings of the de-meaned signal).
func _report_motion() -> void:
	var shp := get_tree().root.get_node('Main/Ship')
	print('[keel] max centreline keel lift above the water over the run (m, <= 0 = keel never visible): ', snappedf(shp.keel_clear_min, 0.01), '  peak |roll| ', snappedf(shp.peak_heel, 0.1), ' deg  midship-only lift ', snappedf(shp.keel_mid_lift, 0.01), '  final speed ', snappedf(shp.current_speed, 0.1))
	for ch in [1, 2]:
		var name := "roll" if ch == 1 else "pitch"
		var vals: Array = []
		var times: Array = []
		for r in _roll_samples:
			if r[0] > 8.0:
				vals.append(r[ch]); times.append(r[0])
		if vals.size() < 10:
			continue
		var mean := 0.0
		for v in vals: mean += v
		mean /= vals.size()
		var mx := -1e9; var mn := 1e9
		var ups: Array = []
		for i in vals.size():
			var v: float = vals[i] - mean
			mx = maxf(mx, vals[i]); mn = minf(mn, vals[i])
			if i > 0 and (vals[i - 1] - mean) < 0.0 and v >= 0.0:
				ups.append(times[i])
		var period := 0.0
		if ups.size() >= 2:
			period = (ups[ups.size() - 1] - ups[0]) / float(ups.size() - 1)
		print("[motion] ", name, " mean=", snappedf(mean, 0.1), " deg  min=", snappedf(mn, 0.1), " max=", snappedf(mx, 0.1), " deg  peak amplitude=", snappedf((mx - mn) * 0.5, 0.1), " deg  mean period=", snappedf(period, 0.1), " s  (", ups.size(), " cycles)")


# --- --perf-log=<secs>: percentiles of frame time, CPU and GPU after a 5 s warm-up -----------------------------------
func _pct(a: PackedFloat64Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(ceil(q * float(b.size()))) - 1, 0, b.size() - 1)]

func _perf_step(delta: float) -> void:
	_perf_t += delta
	if _perf_t > 5.0:
		_perf_frame.append(delta * 1000.0)
		_perf_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_perf_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_perf_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		if _spike_log and _perf_cpu[_perf_cpu.size() - 1] > _spike_thr_ms:
			_spike_times.append(_perf_t)
			print('[spike] t=%.2f frame=%.1f ms process=%.1f ms physics=%.1f ms objects=%d orphans=%d static_mem=%.1f MB draw_calls=%d' % [_perf_t, delta * 1000.0, _perf_cpu[_perf_cpu.size() - 1], _perf_phys[_perf_phys.size() - 1], int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if _perf_t >= 5.0 + _perf_secs:
		var res := get_viewport().get_visible_rect().size
		var p99 := _pct(_perf_frame, 0.99)
		var spp := get_tree().root.get_node_or_null('SpikeProbe')
		if spp:
			spp.report()
		if _spike_log:
			var iv := PackedFloat64Array()
			for i in range(1, _spike_times.size()):
				iv.append(_spike_times[i] - _spike_times[i - 1])
			print('[spike] count=', _spike_times.size(), ' in ', snappedf(_perf_secs, 0.1), ' s; interval p50=', snappedf(_pct(iv, 0.5), 0.01), ' s  min=', snappedf(_pct(iv, 0.0), 0.01), ' s  p90=', snappedf(_pct(iv, 0.9), 0.01), ' s')
		print("[perf] preset=%s quality=%s res=%dx%d frames=%d frame_ms p50=%.2f p95=%.2f p99=%.2f 1%%low_fps=%.1f avg_fps=%.1f cpu_ms p50=%.2f p95=%.2f phys_ms p50=%.2f gpu_ms p50=%.2f p95=%.2f" % [
			Quality.name_, Quality.name_, int(res.x), int(res.y), _perf_frame.size(), _pct(_perf_frame, 0.5), _pct(_perf_frame, 0.95), p99,
			1000.0 / maxf(p99, 0.001), 1000.0 / maxf(_pct(_perf_frame, 0.5), 0.001), _pct(_perf_cpu, 0.5), _pct(_perf_cpu, 0.95),
			_pct(_perf_phys, 0.5), _pct(_perf_gpu, 0.5), _pct(_perf_gpu, 0.95)])
		get_tree().quit()

# --- --plan=regression: 4 fixed presets x 3 shots -> reg_<preset>_<n>.png ------------------------------------------------
func _reg_step(delta: float) -> void:
	_reg_t += delta
	if _reg_i >= REG_PRESETS.size():
		print("[capture] regression done: ", REG_PRESETS.size() * REG_SHOTS.size(), " images")
		get_tree().quit()
		return
	var pr: Dictionary = REG_PRESETS[_reg_i]
	if _reg_state == 0:
		WorldState.day_enabled = false
		WorldState.day_phase = float(pr["phase"])
		WorldState.set_weather(String(pr["weather"]), true)
		WorldState.override_sea = float(pr["sea"])
		WorldState.override_wind_deg = float(pr["wind"])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
		_reg_state = 1
		_reg_t = 0.0
		print("[capture] preset ", pr["name"], ": phase=", pr["phase"], " weather=", pr["weather"], " sea=", pr["sea"])
	elif _reg_state == 1:
		if str(pr["name"]) == "night" and _reg_t > 1.0:
			for l in ShipLights.get_lanterns():
				ShipLights.light(l["id"])
		if _reg_t >= REG_SETTLE:
			_reg_state = 2
			_reg_t = 0.0
			_reg_shot = 0
			var d := get_tree().get_first_node_in_group("camera_director")
			if d:
				d.jump_to(REG_SHOTS[0], true)
	else:
		if _reg_t >= 1.2:
			var img := get_viewport().get_texture().get_image()
			var path := "%s/reg_%s_%d.png" % [SHOT_DIR, pr["name"], _reg_shot + 1]
			img.save_png(ProjectSettings.globalize_path(path))
			print("[capture] saved ", path, " ", img.get_size())
			_reg_shot += 1
			_reg_t = 0.0
			if _reg_shot >= REG_SHOTS.size():
				_reg_i += 1
				_reg_state = 0
			else:
				var d2 := get_tree().get_first_node_in_group("camera_director")
				if d2:
					d2.jump_to(REG_SHOTS[_reg_shot], true)

## Test aid --cam-island: puts the debug camera (shot `idx`, the one --cam appended) just off the shore of the nearest island,
## looking at the shallows (a --cam value is still needed to create the shot; its pose is overwritten here).
func _aim_debug_cam_at_shore(d: Node, idx: int, height: float) -> void:
	var isl := get_tree().root.get_node_or_null("Main/Islands")
	var ship := get_tree().root.get_node_or_null("Main/Ship") as Node3D
	idx = d.shots.size() - 1 # the shot --cam appended is always the last one
	if isl == null or ship == null or idx < 0:
		print("[capture] cam-island: missing node or shot (isl=", isl != null, " ship=", ship != null, " idx=", idx, " shots=", d.shots.size(), ")")
		return
	var best := {}
	var best_d := INF
	for t in isl.targets():
		var dd: float = (t["pos"] - Vector2(ship.global_position.x, ship.global_position.z)).length()
		if dd < best_d:
			best_d = dd
			best = t
	if best.is_empty():
		print("[capture] cam-island: no island target yet")
		return
	var c: Vector2 = best["pos"]
	var shore: float = float(best["radius"]) - 40.0
	var dir := (Vector2(ship.global_position.x, ship.global_position.z) - c).normalized()
	var cam_xz := c + dir * (shore + 38.0 + height)
	var look_xz := c + dir * (shore - 6.0)
	var to_ship: Transform3D = d._frame().affine_inverse()
	d.shots[idx]["pos"] = to_ship * Vector3(cam_xz.x, height, cam_xz.y)
	d.shots[idx]["look"] = to_ship * Vector3(look_xz.x + dir.x * 6.0, -1.0, look_xz.y + dir.y * 6.0)
	d.shots[idx]["fov"] = 60.0
	print("[capture] cam-island: island at ", snappedf(best_d, 1.0), " m, shore radius ", snappedf(shore, 1.0))

## --frame-seq=N[,height]: after a 6 s settle, saves N consecutive frames (use `--fixed-fps 30` so every frame is 1/30 s of simulation).
## The camera (the shot appended by --cam, pose rewritten here) hangs in the ship frame at `height`, looking at the horizon 3 degrees below.
func _seq_step(_delta: float) -> void:
	var d := get_tree().get_first_node_in_group('camera_director')
	if _seq_i == 0 and _t >= 5.0 and d and _seq_t0 == 0.0:
		var idx: int = d.shots.size() - 1
		d.shots[idx]["pos"] = Vector3(0.0, _seq_h, 20.0)
		d.shots[idx]["look"] = Vector3(0.0, _seq_h - 12.0, -230.0)
		d.shots[idx]["fov"] = 60.0
		d.jump_to(idx, true)
		_seq_t0 = _t
	if _seq_t0 > 0.0 and _seq_speed != 0.0 and d:
		var idx2: int = d.shots.size() - 1
		var z := 20.0 - _seq_speed * (_t - _seq_t0)
		d.shots[idx2]["pos"] = Vector3(0.0, _seq_h, z)
		d.shots[idx2]["look"] = Vector3(0.0, _seq_h - 12.0, z - 250.0)
		d.jump_to(idx2, true)
	if _seq_t0 > 0.0 and _t >= _seq_t0 + 1.0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/seq_%03d.png" % [SHOT_DIR, _seq_i]))
		_seq_i += 1
		if _seq_i >= _seq_n:
			print("[capture] frame sequence saved: ", _seq_n, " frames")
			get_tree().quit()
