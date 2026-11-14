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
	_turb.seed = 99
	_turb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_turb.frequency = 1.0
	_turb.fractal_octaves = 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wind-ms="):
			speed_override = float(a.get_slice("=", 1))
		elif a.begins_with("--gust-amp="):
			gust_scale = float(a.get_slice("=", 1))
	_refresh(0.0)
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

func _process(delta: float) -> void:
	ClothSolver.sync()
	time += delta
	_refresh(delta)

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
