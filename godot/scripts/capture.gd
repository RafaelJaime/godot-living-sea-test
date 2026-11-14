extends Node
## Active only with the user arg `--capture`: saves screenshots to res://_shots and quits.
## godot --path <project> -- --capture

const SHOT_DIR := "res://_shots"
# [capture time (s), camera shot index]
var PLAN: Array = [[3.0, 11, 0.2], [6.0, 14, 0.2], [9.0, 2, 0.2], [13.0, 11, 0.9], [16.0, 14, 0.9], [19.0, 2, 0.9]]

var _active := false
var _t := 0.0
var _step := 0
var _jumped := false

var _jitter := false
var _log_secs := 0.0
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
	if _jitter:
		_active = true
		return
	_active = "--capture" in OS.get_cmdline_user_args()
	_active = _active or _log_secs > 0.0
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
					'sky': PLAN = [[3.0, 5], [6.0, 6], [9.0, 2], [12.0, 3], [15.0, 0], [18.0, 5]]
		for a in OS.get_cmdline_user_args():
			if a.begins_with('--shots='):
				PLAN = []
				var k := 0
				for i in a.get_slice('=', 1).split(','):
					PLAN.append([3.0 + 2.5 * k, int(i)])
					k += 1
		print('[capture] active')

func _process(delta: float) -> void:
	_t += delta
	if _log_secs > 0.0:
		_log_t += delta
		if fmod(_log_t, 2.0) < delta:
			var sh := get_tree().root.get_node('Main/Ship')
			var ap := get_tree().root.get_node('Main/Ship/Autopilot')
			print('[log] t=', snappedf(_log_t, 0.1), ' pos=(', snappedf(sh.global_position.x, 1.0), ',', snappedf(sh.global_position.z, 1.0), ') yaw=', snappedf(rad_to_deg(sh.yaw), 1.0), ' rudder=', snappedf(sh.rudder, 0.01), ' speed=', snappedf(sh.current_speed, 0.1), ' tacking=', ap.tacking, ' target_dist=', snappedf(Vector2(sh.global_position.x, sh.global_position.z).distance_to(ap.target), 1.0), ' wind_ang=', snappedf(rad_to_deg(WorldState.wind_angle), 1.0), ' day=', snappedf(WorldState.day_phase, 0.01), ' cloud=', snappedf(WorldState.cloud, 0.01), ' storm=', snappedf(WorldState.storm, 0.01), ' sea=', snappedf(WorldState.sea_state, 0.01))
		if _log_t >= _log_secs:
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
	if _step < PLAN.size() and PLAN[_step].size() > 2:
		WorldState.override_sea = float(PLAN[_step][2])
	if not _jumped and _t >= when - 0.8:
		_jumped = true
		var d := get_tree().get_first_node_in_group("camera_director")
		if d:
			d.jump_to(cam_idx, true)
	if '--lightning' in OS.get_cmdline_user_args() and _step == 2 and _t >= when - 0.08:
		if WorldState.flash < 0.5:
			get_tree().root.get_node('Main/Weather')._spawn_bolt()
		WorldState.flash = 1.0
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
	var to_local := Basis(Vector3.UP, ship.rotation.y).inverse()
	var rel := to_local * (cam.global_position - ship.global_position)
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
