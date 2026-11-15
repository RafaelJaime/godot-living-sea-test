extends Node
## World-anchored wake: a 1024^2 foam field (float16) in a 320 m window that follows the ship in whole-texel steps,
## updated by a ping-pong pair of SubViewports (advect + decay + stamp, see wake_update.gdshader). Window origins are
## tracked in accumulated world coordinates, so a world rebase does not disturb it. The ocean shader samples it.

@export var ship_path := NodePath("../Ship")
@export var size := 320.0
var resolution := 1024 # from Quality.wake_resolution

var _ship: Node3D
var _vp: Array[SubViewport] = []
var _mat: Array[ShaderMaterial] = []
var _cur := 0
# Window origin in accumulated world coordinates, as two separate 64-bit GDScript floats: a Vector2 holds 32-bit floats, which
# lose the 8-texel step after a few hundred kilometres of sailing.
var _ox := INF
var _oy := INF
var _time := 0.0
var _accum := 0.0
var _test_speed := 1.0   ## test aid --wake-test-speed=<k>: scale the relative speed fed to the stamps (Froude check, stopped ship)
var _far := 0.0          ## test aid --wake-far=<m>: pretend the world origin is this far away (both axes)
var _log := false
var _log_t := 0.0
var _log_now := false
var _max_off_grid := 0.0 ## largest distance of a window step from a whole 8-texel multiple, in texels
var _steps := 0
var _half_len := 18.3
var _half_beam := 4.4

func _ready() -> void:
	process_priority = 150
	resolution = Quality.wake_resolution
	print("[quality] wake: ", resolution, "^2 at ", Quality.wake_updates_per_second, " Hz fixed step")
	_ship = get_node(ship_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wake-far="):
			_far = float(a.get_slice("=", 1))
		elif a.begins_with("--wake-test-speed="):
			_test_speed = float(a.get_slice("=", 1))
		elif a == "--wake-log":
			_log = true
	var sh := load("res://shaders/wake_update.gdshader") as Shader
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(resolution, resolution)
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(resolution, resolution)
		var m := ShaderMaterial.new()
		m.shader = sh
		rect.material = m
		vp.add_child(rect)
		add_child(vp)
		_vp.append(vp)
		_mat.append(m)

func _process(delta: float) -> void:
	if Waves.ocean == null or delta <= 0.0:
		return
	_time += delta
	# Fixed-rate update (independent of the frame rate): one ping-pong step per 1/Hz of accumulated time, always with dt = 1/Hz.
	var hz: float = Quality.wake_updates_per_second if Quality.wake_updates_per_second > 0.0 else 30.0
	var step := 1.0 / hz
	_accum = minf(_accum + delta, step * 3.0)
	if _accum < step:
		return
	_accum -= step
	delta = step
	var ship_wx: float = _ship.global_position.x + Waves.offset_x + _far
	var ship_wy: float = _ship.global_position.z + Waves.offset_z + _far
	var texel := size / float(resolution)
	var grid := texel * 8.0
	var nx := snappedf(ship_wx - size * 0.5, grid)
	var ny := snappedf(ship_wy - size * 0.5, grid)
	if _ox == INF:
		_ox = nx
		_oy = ny
		print("[wake] first step, far=", _far)
	if absf(_half_len - Waves.ocean.ship_half_len) > 0.001 or absf(_half_beam - Waves.ocean.ship_half_beam) > 0.001 or _steps == 0:
		_half_len = Waves.ocean.ship_half_len # the footprint arrives with ship_ready, after the first frames
		_half_beam = Waves.ocean.ship_half_beam
		print("[wake] footprint half_len=", snappedf(_half_len, 0.01), " half_beam=", snappedf(_half_beam, 0.01))
	_steps += 1
	var delta_uv := Vector2((nx - _ox) / size, (ny - _oy) / size)
	if _log:
		for v in [(nx - _ox) / grid, (ny - _oy) / grid]:
			_max_off_grid = maxf(_max_off_grid, absf(v - roundf(v)) * 8.0)
		_log_t += delta
		_log_now = false
		if _log_t >= 5.0:
			_log_t = 0.0
			_log_now = true
			print("[wake] origin=(", snappedf(nx, 0.01), ", ", snappedf(ny, 0.01), ") steps=", _steps, " max off-grid step=", snappedf(_max_off_grid, 0.0001), " texels")
	var prev_i := _cur
	var next_i := 1 - _cur
	var m := _mat[next_i]
	m.set_shader_parameter("prev", _vp[prev_i].get_texture())
	m.set_shader_parameter("delta_uv", delta_uv)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("dt", delta)
	m.set_shader_parameter("ship_uv", Vector2((ship_wx - nx) / size, (ship_wy - ny) / size))
	var fwd: Vector2 = _ship.get("forward") if _ship.get("forward") != null else Vector2(0, -1)
	m.set_shader_parameter("fwd", fwd)
	# Velocity relative to the water (no current in this world: the water is at rest apart from the waves).
	var vel := Vector2.ZERO
	if "linear_velocity" in _ship:
		vel = Vector2(_ship.linear_velocity.x, _ship.linear_velocity.z)
	elif _ship.get("current_speed") != null:
		vel = fwd * float(_ship.get("current_speed"))
	var surge := maxf(vel.dot(fwd), 0.0) * _test_speed
	var sway := vel.dot(Vector2(-fwd.y, fwd.x))
	var vdir := vel.normalized() if vel.length() > 0.8 else fwd
	var froude := surge / sqrt(9.81 * maxf(_half_len * 2.0 / 0.92, 1.0)) # hull length ~ footprint / 0.46
	var roll: float = _ship.get("roll") if _ship.get("roll") != null else 0.0
	var heel := clampf(-roll / deg_to_rad(15.0), -1.0, 1.0)             # roll is starboard-up positive
	m.set_shader_parameter("speed", surge)
	m.set_shader_parameter("vdir", vdir)
	m.set_shader_parameter("froude", froude)
	m.set_shader_parameter("heel", heel)
	if _log_now:
		print("[wake] relative speed surge=", snappedf(surge, 0.01), " sway=", snappedf(sway, 0.01), " m/s froude=", snappedf(froude, 0.001), " heel=", snappedf(heel, 0.01))
	m.set_shader_parameter("half_len", _half_len)
	m.set_shader_parameter("half_beam", _half_beam)
	m.set_shader_parameter("seed_t", _time)
	_vp[next_i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_ox = nx
	_oy = ny
	_cur = next_i
	Waves.ocean.set_wake(_vp[next_i].get_texture(), Vector2(_ox - Waves.offset_x - _far, _oy - Waves.offset_z - _far), size)
