extends Node
## QA driver for the cloth + wind track (only created by WindField when `--cloth-demo=<name>` is given).
##   godot --path godot -- --cloth-demo=full     calm -> moderate -> storm-wind -> travelling gust, with captures + logs
## Captures go to res://_shots/cloth_*.png and the logs to stdout ([cloth] lines). Runs focus-free (see README).
## The ship is put on a constant heading (autopilot off), the wind blows from `wind_rel` degrees off the stern so the sails
## fill; the stern flag, the sails and the masthead flag then see the same WindField.

const SHOT_DIR := "res://_shots"
var wind_rel := 18.0 ## degrees: wind blows toward heading + this
var _t := 0.0
var _ship: Node3D
var _dir: Node
var _stage := ""
var _steps: Array = []
var _next := 0
var _log_every := 1.0
var _log_t := 0.0
var _frame_ms := PackedFloat32Array()
var _shots_extra := {}
var _gust_t0 := -1.0
var _soak := false
var _brace_t := 0.0

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var which := "full"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cloth-demo="):
			which = a.get_slice("=", 1)
		elif a.begins_with("--wind-rel="):
			wind_rel = float(a.get_slice("=", 1))
	_ship = get_tree().root.get_node("Main/Ship") as Node3D
	var ap := _ship.get_node_or_null("Autopilot")
	if ap:
		ap.process_mode = Node.PROCESS_MODE_DISABLED
	_ship.set("rudder_cmd", 0.0)
	_ship.set("rudder", 0.0)
	var t0 := 0.0
	_steps = []
	match which:
		"calm": t0 = _stage_steps("calm", t0, 0.0, 0.0, wind_rel, 16.0)
		"moderate": t0 = _stage_steps("mod", t0, 12.0, 1.0, wind_rel, 14.0)
		"storm": t0 = _stage_steps("storm", t0, 26.0, 1.0, wind_rel, 14.0)
		"beam": t0 = _stage_steps("beam", t0, 12.0, 1.0, 100.0, 14.0)
		"soak": # endurance: wind 3..28 m/s, bearing sweeping through run / beam / head wind, --soak-secs=N
			_soak = true
			_log_every = 10.0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--soak-secs="):
					t0 = float(a.get_slice("=", 1))
			_steps.append([0.0, "wind", ["soak", 12.0, 1.0, wind_rel]])
		"gust": t0 = _gust_steps(t0, wind_rel, "gust")
		"gusthead": t0 = _gust_steps(t0, 150.0, "gusthead")
		_:
			t0 = _stage_steps("calm", t0, 0.0, 0.0, wind_rel, 16.0)
			t0 = _stage_steps("mod", t0, 12.0, 1.0, wind_rel, 14.0)
			t0 = _stage_steps("storm", t0, 26.0, 1.0, wind_rel, 14.0)
			t0 = _stage_steps("beam", t0, 12.0, 1.0, 100.0, 14.0)
			t0 = _gust_steps(t0, wind_rel, "gust")
			t0 = _gust_steps(t0, 150.0, "gusthead")
	_steps.append([t0 + 1.0, "quit", 0])
	_steps.sort_custom(func(x, y): return x[0] < y[0])
	print("[cloth] demo '", which, "' ", _steps.size(), " steps")

## Settle for `settle` s, then 4 shots (stern flag, main flag, sails from the side and from the bow).
func _stage_steps(tag: String, t0: float, ms: float, ship_scale: float, rel: float, settle: float) -> float:
	_steps.append([t0, "wind", [tag, ms, ship_scale, rel]])
	var t := t0 + settle
	for v in [["sails_side", "sails_side"], [15, "flag_stern"], [16, "flag_main"], ["sails_bow", "sails_bow"], ["sails_top", "sails_top"], ["sails_starboard", "sails_starboard"], ["sails_stern", "sails_stern"]]:
		_steps.append([t, "cam", v[0]])
		_steps.append([t + 0.8, "shot", "%s_%s" % [tag, v[1]]])
		t += 1.0
	return t + 0.5

## A gust pulse crosses the ship: the front starts 45 m upwind of it and travels at 0.8 x wind speed. With a following
## wind the stern flag meets it first; with wind from the bow quarter the sails do and the stern flag last.
func _gust_steps(t0: float, rel: float, tag: String) -> float:
	_steps.append([t0, "wind", [tag, 12.0, 1.0, rel]])
	_steps.append([t0 + 10.0, "gustlog", 0.5])
	_steps.append([t0 + 10.0, "pulse", 45.0])
	var t := t0 + 10.0
	for k in 8:
		t = t0 + 12.0 + float(k) * 2.4
		_steps.append([t, "cam", "sails_side" if k % 2 == 0 else 15])
		_steps.append([t + 0.7, "shot", "%s_%d" % [tag, k]])
	_steps.append([t0 + 38.0, "gustoff", 0])
	return t0 + 39.0

func _cams() -> Dictionary:
	return {
		"sails_side": {"pos": Vector3(-36.0, 13.0, 0.0), "look": Vector3(0.0, 12.0, -1.0), "fov": 60.0},
		"sails_stern": {"pos": Vector3(-12.0, 10.0, 36.0), "look": Vector3(0.0, 11.0, 4.0), "fov": 58.0},
		"sails_top": {"pos": Vector3(0.5, 48.0, 0.5), "look": Vector3(0.0, 0.0, -2.0), "fov": 45.0},
		"sails_starboard": {"pos": Vector3(34.0, 12.0, 0.0), "look": Vector3(0.0, 12.0, -1.0), "fov": 60.0},
		"sails_bow": {"pos": Vector3(-18.0, 7.0, -34.0), "look": Vector3(0.0, 12.0, -4.0), "fov": 58.0},
	}

func _cam_index(arg) -> int:
	if arg is int:
		return arg
	if not _shots_extra.has(arg):
		var c: Dictionary = _cams()[arg]
		_dir.shots.append({"name": arg, "mode": "raw", "pos": c["pos"], "look": c["look"], "fov": c["fov"]})
		_shots_extra[arg] = _dir.shots.size() - 1
	return _shots_extra[arg]

func _set_wind(ms: float, rel_ship_speed: float) -> void:
	WindField.speed_override = ms
	_ship.set("speed_scale", rel_ship_speed)
	# rigid-body ship: a frozen hull = dead calm for the flags (apparent wind = true wind)
	_ship.set("freeze", rel_ship_speed == 0.0)

func _process(delta: float) -> void:
	_t += delta
	if _dir == null:
		_dir = get_tree().get_first_node_in_group("camera_director")
		if _dir == null:
			return
	# keep the wind on a fixed bearing relative to the heading
	if _soak:
		WindField.speed_override = 15.5 + 12.5 * sin(_t / 11.0)
		wind_rel = 95.0 + 85.0 * sin(_t / 23.0)
	_brace_t += delta
	if _brace_t > 0.5 and _ship.has_method("best_brace"):
		_brace_t = 0.0
		_ship.set("brace_cmd", _ship.best_brace()) # the autopilot does this in normal play
	var f: Vector2 = _ship.get("forward")
	WorldState.override_wind_deg = rad_to_deg(atan2(f.y, f.x)) + wind_rel
	if _t > 1.0:
		_frame_ms.append(delta * 1000.0)
	while _next < _steps.size() and _t >= _steps[_next][0]:
		_do(_steps[_next])
		_next += 1
	_log_t += delta
	if _log_t >= _log_every:
		_log_t = 0.0
		_log()

func _do(s: Array) -> void:
	match s[1]:
		"wind":
			var a: Array = s[2]
			_stage = a[0]; wind_rel = a[3]; _set_wind(a[1], a[2])
		"cam":
			_dir.jump_to(_cam_index(s[2]), true)
		"shot":
			var img := get_viewport().get_texture().get_image()
			var p := "%s/cloth_%s.png" % [SHOT_DIR, s[2]]
			img.save_png(ProjectSettings.globalize_path(p))
			print("[cloth] saved ", p, " stage=", _stage, " ", _summary())
		"gustlog":
			_log_every = float(s[2])
		"gustoff":
			_log_every = 1.0; _gust_t0 = -1.0
		"pulse":
			_gust_t0 = _t
			WindField.add_gust_pulse(_ship.global_position, float(s[2]), 1.4, 10.0)
			print("[cloth] gust pulse injected: +140% peak, sigma 10 m, front 45 m upwind, travels ", snappedf(WindField.mean_speed() * WindField.GUST_SPEED_RATIO, 0.1), " m/s")
		"quit":
			_report()
			get_tree().quit()

func _flags() -> Array:
	var out := []
	for g in ["flag_pavillion_mast", "flag_main_mast"]:
		var n := get_tree().get_first_node_in_group(g)
		if n:
			out.append(n)
	return out

func _rig() -> Node:
	return get_tree().get_first_node_in_group("sail_rig")

func _summary() -> String:
	var parts := PackedStringArray()
	parts.append("wind=%.1f" % WindField.mean_speed())
	parts.append("ship=%.1f m/s brace=%.0fdeg" % [float(_ship.get("current_speed")), rad_to_deg(float(_ship.get("brace")))])
	for fl2 in _flags():
		parts.append("staff_shift_%s=%.2fm" % [fl2.mesh_suffix.left(4), fl2.staff_shift()])
	for fl in _flags():
		var d: Dictionary = fl.debug_info()
		parts.append("%s tension=%sN p=%sPa g=%s droop=%s" % [fl.mesh_suffix.left(4), d["tension"], d["pressure"], d["gust"], d["droop"]])
	var rig := _rig()
	if rig:
		var tot: Dictionary = rig.total_sail_force()
		parts.append("sailsF=(%.0f,%.0f,%.0f)N" % [tot["force"].x, tot["force"].y, tot["force"].z])
	return " | ".join(parts)

func _log() -> void:
	var line := "[cloth] t=%.1f %s fps=%d cloth_task_ms=%.2f main_stall_ms=%.2f" % [_t, _stage, Engine.get_frames_per_second(), ClothSolver.step_ms, ClothSolver.stall_ms]
	if _gust_t0 >= 0.0:
		line = "[gust] t=%.2f" % (_t - _gust_t0)
		var rig := _rig()
		if rig:
			for s in rig.get_sail_forces():
				if s["name"] in ["sails_spritsail_down", "sails_forecourse_down", "sails_main_course_down", "sails_mizzen_course_down", "sails_main_down", "sails_mizzen_topsail_down"]:
					line += " %s[p=%.0f g=%.2f %s]" % [String(s["name"]).trim_prefix("sails_").trim_suffix("_down"), s["pressure"], s["gust"], s["state"]]
		for fl in _flags():
			var d: Dictionary = fl.debug_info()
			line += " flag_%s[T=%s g=%s]" % [fl.mesh_suffix.left(4), d["tension"], d["gust"]]
	else:
		line += " " + _summary()
	var rg := _rig()
	if rg:
		var ms := 0.0
		for q in rg.get_sail_forces():
			ms = maxf(ms, q["stretch"])
		line += " maxstretch=%.3f" % ms
	print(line)

func _report() -> void:
	var sum := 0.0
	var mx := 0.0
	for m in _frame_ms:
		sum += m
		mx = maxf(mx, m)
	var avg := sum / maxf(float(_frame_ms.size()), 1.0)
	print("[cloth] FRAME avg=%.2f ms (%.0f fps) max=%.1f ms frames=%d cloth_task_ms=%.2f main_stall_ms=%.2f" % [avg, 1000.0 / maxf(avg, 0.001), mx, _frame_ms.size(), ClothSolver.step_ms, ClothSolver.stall_ms])
	var rig := _rig()
	if rig:
		var nres := 0
		for fl in _flags():
			nres += fl._cloth.resets
		for sc in rig._sails:
			nres += sc.cloth.resets
		print("[cloth] self-heal resets (all cloths): ", nres)
		for s in rig.get_sail_forces():
			print("[cloth] sail ", s["name"], " area=", snappedf(s["area"], 0.1), " F=", s["force"].snapped(Vector3.ONE), " CoE=", s["point"].snapped(Vector3.ONE * 0.1), " state=", s["state"], " bulge_z=", snappedf(s["bulge"], 0.01), " stretch=", snappedf(s["stretch"], 0.001))
