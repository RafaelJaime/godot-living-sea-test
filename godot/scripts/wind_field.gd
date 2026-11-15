extends Node
## ONE wind model for everything that reacts to air (sails, flags, later the rigid-body ship).
##
## True wind (world space, m/s) = mean wind from WorldState (direction + speed)
##   x atmospheric boundary-layer profile (power law, ~ (h/10 m)^0.14)
##   x travelling gusts: a 2-D noise field ADVECTED downwind at ~0.8 x wind speed (gust fronts really move across
##     the ship: they hit the bow sails first and the stern flag last when the wind comes from ahead)
##   + small-scale turbulence (direction + speed jitter, advected as well).
## The field is continuous across the world rebase (uses Waves.offset_* to get absolute coordinates) and the advection
## is integrated in time (not t * speed), so speed changes never make the gust pattern jump.
##
## API:  sample(pos, t) -> Vector3 true wind;  apparent(pos, point_velocity, t) -> true wind - point velocity;
##       gust_factor(pos) -> scalar gust multiplier (1 = mean wind), for logs / HUD.
## Test aids (user args): --wind-ms=N forces the mean speed (0 = dead calm), --gust-test schedules a strong gust pulse
## that crosses the ship downwind (see add_gust_pulse), --gust-amp=X scales random gusts.

const GUST_SPEED_RATIO := 0.8 ## gust fronts travel at this fraction of the mean wind speed
const GUST_LENGTH := 55.0 ## m, typical gust size along the wind

var time := 0.0
var speed_override := -1.0 ## m/s, < 0 = follow WorldState
var gust_scale := 1.0
var pulses: Array[Dictionary] = [] ## {s0: along-wind coordinate of the front at t0, t0, amp, sigma, cross: [lo,hi] or null}

var _mean := Vector3.ZERO ## mean true wind this frame (world, m/s), updated on the main thread
var _dir := Vector3(0, 0, 1)
var _perp := Vector3(1, 0, 0)
var _speed := 6.0
var _advect := Vector2.ZERO ## integrated advection of the gust pattern (m)
var _gust := FastNoiseLite.new()
var _turb := FastNoiseLite.new()
var _off := Vector2.ZERO

## --- Gust texture for the ocean shader (cat's paws, M4c1) ---------------------------------------------------------------
## The SAME `_gust` noise the sails and flags feel, rasterised natively (Noise.get_image) around the ship every 0.25 s, so the
## darker ripple patches on the water are the gusts that hit the sails. Texel value = (n + 1) / 2 with n the raw noise of
## gust_factor(): the shader rebuilds the factor with the skew and gust_amp() below. Exposed as the global shader parameters
## `gust_tex` (sampler2D), `gust_win` (vec4: origin x, origin z, size x, size z, LOCAL metres, rebase-safe) and `gust_amp`.
const GUST_TEX_W_FULL := 64 ## 64 x 116 texels over ~1 km (16 m per texel in x): enough for 55 m gusts, ~4x cheaper than 128 x 232
const GUST_REFRESH := 0.25 ## s
const GUST_STRETCH := 1.8

var GUST_TEX_W := GUST_TEX_W_FULL
var GUST_TEX_H := 116
var GUST_CELL := 16.0 ## m per texel in x (z texel is GUST_CELL / 1.8: the z stretch of the noise)
var gust_refresh_peak_us := 0.0 ## worst refresh so far (microseconds)
var _gust_adv_b := Vector2.ZERO ## advect value the texture was built with
var _gust_org := Vector2.ZERO ## window origin (local) at build time
var _gust_tex_built_once := false
var gust_refresh_us := 0.0 ## cost of the last refresh (microseconds), for the perf logs
var _gust_img := FastNoiseLite.new()
var _gust_tex: ImageTexture
var _gust_win := Vector4.ZERO
var _gust_t := 1.0e9
var _gust_enabled := true

func _ready() -> void:
	process_priority = -1000 # first: joins last frame's cloth step before anyone touches cloth data
	var launcher := Node.new()
	launcher.set_script(preload("res://scripts/cloth_launcher.gd"))
	launcher.process_priority = 100 # last: owners have set this frame's pin targets
	add_child(launcher)
	_gust.seed = 4242
	_gust.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gust.frequency = 1.0
	_gust.fractal_type = FastNoiseLite.FRACTAL_FBM
	_gust.fractal_octaves = 2
	_gust_img.seed = _gust.seed
	_gust_img.noise_type = _gust.noise_type
	_gust_img.fractal_type = _gust.fractal_type
	_gust_img.fractal_octaves = _gust.fractal_octaves
	_gust_img.frequency = GUST_CELL / GUST_LENGTH
	_turb.seed = 99
	_turb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_turb.frequency = 1.0
	_turb.fractal_octaves = 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wind-ms="):
			speed_override = float(a.get_slice("=", 1))
		elif a == "--no-gust-tex":
			_gust_enabled = false
		elif a.begins_with("--gust-amp="):
			gust_scale = float(a.get_slice("=", 1))
	_refresh(0.0)
	_refresh_gust_texture() # creates the global shader parameters before any ocean shader compiles
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cloth-demo"):
			var d := (load("res://scripts/cloth_demo.gd") as GDScript).new() as Node
			get_tree().root.add_child.call_deferred(d)

func _refresh(delta: float) -> void:
	var wv: Vector2 = WorldState.wind_vector()
	_dir = Vector3(wv.x, 0.0, wv.y)
	_perp = Vector3(-wv.y, 0.0, wv.x)
	_speed = speed_override if speed_override >= 0.0 else WorldState.wind_speed_ms()
	_mean = _dir * _speed
	_off = Vector2(Waves.offset_x, Waves.offset_z)
	_advect += Vector2(wv.x, wv.y) * (_speed * GUST_SPEED_RATIO * delta)

var _tt := 0.0
var _tt_step := 0

## `--gust-tex-test`: at 2 s and 7 s checks the texels against gust_factor()'s noise and dumps the texture to res://_shots.
func _gust_test(delta: float) -> void:
	_tt += delta
	var times := [2.0, 7.0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rebase-test="):
			times = [2.0, 7.0, 40.0, 60.0, 80.0] # spans several rebases
	if _tt_step >= times.size() or _tt < times[_tt_step]:
		return
	var img := _gust_tex.get_image()
	var w := _gust_win
	var err := 0.0
	var mx := 0.0
	var cz := w.w / float(GUST_TEX_H)
	var cx := w.z / float(GUST_TEX_W)
	for k in 40:
		var i := (k * 37) % GUST_TEX_W
		var j := (k * 91) % GUST_TEX_H
		var wx := w.x + (float(i) + 0.0) * cx + _off.x # absolute
		var wz := w.y + (float(j) + 0.0) * cz + _off.y
		var n := _gust.get_noise_2d((wx - _advect.x) / GUST_LENGTH, (wz - _advect.y) / GUST_LENGTH * GUST_STRETCH)
		var tex := img.get_pixel(i, j).r * 2.0 - 1.0
		err = maxf(err, absf(n - tex))
		mx = maxf(mx, absf(n))
	print("[gust-tex] t=", snappedf(_tt, 0.1), " win=", w, " advect=", _advect.snapped(Vector2.ONE * 0.1), " max|n-texel|=", snappedf(err, 0.0001), " (max|n| ", snappedf(mx, 0.01), ") refresh_us=", snappedf(gust_refresh_us, 1.0), " peak_us=", snappedf(gust_refresh_peak_us, 1.0), " mean_speed=", snappedf(_speed, 0.1))
	img.save_png(ProjectSettings.globalize_path("res://_shots/gust_t%d.png" % int(times[_tt_step])))
	_tt_step += 1

## The cloth step of the last frame is still running on the worker threads when the tree is torn down: join it first, so no
## worker touches cloth data (or the engine) while it is being dismantled. WindField is an autoload, so it exits after the owners.
func _exit_tree() -> void:
	ClothSolver.sync()

func _process(delta: float) -> void:
	ClothSolver.sync()
	if "--gust-tex-test" in OS.get_cmdline_user_args() and _gust_tex != null:
		_gust_test(delta)
	time += delta
	_refresh(delta)
	_gust_t += delta
	if _gust_enabled and _gust_t >= GUST_REFRESH:
		_gust_t = 0.0
		_refresh_gust_texture()
	elif _gust_tex != null:
		# Between refreshes the pattern keeps travelling downwind: slide the window instead of rebuilding the texture.
		var d := _advect - _gust_adv_b
		_gust_win = Vector4(_gust_org.x + d.x, _gust_org.y + d.y, _gust_win.z, _gust_win.w)
		RenderingServer.global_shader_parameter_set(&"gust_win", _gust_win)

## Window origin (local metres) and size (m) of the gust texture: x, z origin, x, z extent.
func gust_window() -> Vector4:
	return _gust_win

func gust_texture() -> ImageTexture:
	return _gust_tex

## Same amplitude gust_factor() uses (so the shader reproduces the factor from the texel).
func gust_amp() -> float:
	return (0.22 + 0.55 * WorldState.wind_strength + 0.25 * WorldState.storm) * gust_scale

func _refresh_gust_texture() -> void:
	var t0 := Time.get_ticks_usec()
	var ship := get_node_or_null("/root/Main/Ship") as Node3D
	var c := Vector2(ship.global_position.x, ship.global_position.z) if ship != null else Vector2.ZERO
	var cell_z := GUST_CELL / GUST_STRETCH
	var span := Vector2(float(GUST_TEX_W) * GUST_CELL, float(GUST_TEX_H) * cell_z)
	# Absolute coordinates, snapped to whole texels so the pattern never shimmers when the window follows the ship.
	var o_abs := Vector2(snappedf(c.x + _off.x - span.x * 0.5, GUST_CELL), snappedf(c.y + _off.y - span.y * 0.5, cell_z))
	# Noise input for texel (i, j) is ((o_abs - advect) * f + (i, j) * step), with step = GUST_CELL * f (z stretch in the offset).
	_gust_img.offset = Vector3((o_abs.x - _advect.x) / GUST_CELL, (o_abs.y - _advect.y) * GUST_STRETCH / GUST_CELL, 0.0)
	var img := _gust_img.get_image(GUST_TEX_W, GUST_TEX_H, false, false, false)
	if _gust_tex == null:
		_gust_tex = ImageTexture.create_from_image(img)
		RenderingServer.global_shader_parameter_add(&"gust_tex", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, _gust_tex)
		RenderingServer.global_shader_parameter_add(&"gust_win", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
		RenderingServer.global_shader_parameter_add(&"gust_amp", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	else:
		_gust_tex.update(img)
	_gust_adv_b = _advect
	_gust_org = Vector2(o_abs.x - _off.x, o_abs.y - _off.y)
	_gust_win = Vector4(_gust_org.x, _gust_org.y, span.x, span.y)
	RenderingServer.global_shader_parameter_set(&"gust_win", _gust_win)
	RenderingServer.global_shader_parameter_set(&"gust_amp", gust_amp())
	gust_refresh_peak_us = maxf(gust_refresh_peak_us, float(Time.get_ticks_usec() - t0)) if _gust_tex_built_once else 0.0
	_gust_tex_built_once = true
	gust_refresh_us = lerpf(gust_refresh_us, float(Time.get_ticks_usec() - t0), 0.2) if gust_refresh_us > 0.0 else float(Time.get_ticks_usec() - t0)

## Mean wind speed (m/s) and unit direction (world x, z) this frame.
func mean_speed() -> float:
	return _speed

func mean_dir() -> Vector3:
	return _dir

## Schedules a gust pulse: a Gaussian speed bump (peak = amp x mean speed) whose front starts `upwind_dist` metres
## upwind of `origin` (world) and then travels downwind at GUST_SPEED_RATIO x wind speed. Spans the whole cross-wind
## extent. Returns the (absolute) along-wind coordinate of the front at t0 for logging.
func add_gust_pulse(origin: Vector3, upwind_dist: float, amp: float, sigma: float, start_time := -1.0) -> void:
	var o := Vector2(origin.x + _off.x, origin.z + _off.y)
	var along := o.dot(Vector2(_dir.x, _dir.z)) - upwind_dist
	pulses.append({"s0": along, "t0": time if start_time < 0.0 else start_time, "amp": amp, "sigma": sigma, "v": _speed * GUST_SPEED_RATIO})

## Gust multiplier at a world position (1 = mean wind). Thread-safe for reads (called from cloth worker threads).
func gust_factor(pos: Vector3, _t := -1.0) -> float:
	var ax := pos.x + _off.x
	var az := pos.z + _off.y
	var qx := ax - _advect.x
	var qz := az - _advect.y
	var f := 1.0 / GUST_LENGTH
	var n := _gust.get_noise_2d(qx * f, qz * f * 1.8) # elongated along the wind -> streaky gust bands
	# Skew: lulls are shallow, gusts sharp (wind speed distributions are right-skewed).
	var amp := (0.22 + 0.55 * WorldState.wind_strength + 0.25 * WorldState.storm) * gust_scale
	var g := 1.0 + amp * (n * 1.6 if n > 0.0 else n * 0.9)
	var along := ax * _dir.x + az * _dir.z
	for p in pulses:
		var front: float = p["s0"] + p["v"] * (time - p["t0"])
		var d: float = (along - front) / p["sigma"]
		g += p["amp"] * exp(-0.5 * d * d)
	return maxf(g, 0.05)

## True wind at a world position, m/s.
func sample(pos: Vector3, _t := -1.0) -> Vector3:
	var h := clampf(pos.y, 1.0, 40.0)
	var shear := pow(h / 10.0, 0.14)
	var g := gust_factor(pos)
	var ax := pos.x + _off.x
	var az := pos.z + _off.y
	var qx := ax - _advect.x
	var qz := az - _advect.y
	# Turbulence: ~6 m eddies advected with the gusts, ~1.5 Hz decorrelation.
	var tk := 0.17
	var n1 := _turb.get_noise_3d(qx * tk, pos.y * tk * 1.4, qz * tk + time * 1.1)
	var n2 := _turb.get_noise_3d(qx * tk + 31.7, pos.y * tk * 1.4 + 7.0, qz * tk - time * 0.9)
	var turb := 0.10 + 0.14 * WorldState.wind_strength + 0.10 * WorldState.storm
	var w := _mean * (g * shear)
	w += _perp * (n1 * turb * _speed * g) + Vector3.UP * (n2 * turb * 0.7 * _speed * g)
	w += _dir * (n2 * turb * 0.5 * _speed * g)
	return w

## Wind seen by a point moving with `point_velocity` (world, m/s): what the cloth/aerofoil actually feels.
func apparent(pos: Vector3, point_velocity: Vector3, t := -1.0) -> Vector3:
	return sample(pos, t) - point_velocity
