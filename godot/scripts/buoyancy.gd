extends Node3D
## Ship motion: sails along its heading (autopilot steers via `rudder_cmd`), plus wave-driven heave/pitch/roll.
## `rudder` (-1 port .. +1 starboard, smoothed) is the shared steering signal (wheel, crew lean, wake...).
## Node layout: Ship (this, position + heading) / Pivot (heave, pitch, roll) / Model + CrewMarkers.

## Cruising speed (m/s); the autopilot scales it with the point of sail (`speed_scale`).
@export var speed := 6.0
@export_group("Steering")
## Yaw rate at full rudder and cruising speed (deg/s).
@export var max_turn_rate_deg := 5.5
@export var rudder_rate := 0.45 ## how fast the rudder moves (units/s) toward the command
@export var turn_heel_gain := 0.9 ## outward lean while turning
@export var pivot_path := NodePath("Pivot")
@export var loader_path := NodePath("Pivot/Model")
@export_group("Buoyancy")
@export var length := 22.0
@export var beam := 7.0
## Fraction of the half-length/half-beam where the sampling points sit.
@export var sample_length_frac := 0.8
@export var sample_beam_frac := 0.8
@export var heave_smooth_time := 0.45
@export var rotate_smooth_time := 0.55
@export var heave_gain := 0.9
@export var pitch_gain := 0.8
@export var roll_gain := 0.7
@export_group("Wind & wander")
@export var wind_heel_deg := 3.5
@export var yaw_wander_deg := 3.0
## Distance from origin at which the world is rebased (shifted back to the origin).
@export var rebase_distance := 1000.0

var active := false
var heave := 0.0
var pitch := 0.0
var roll := 0.0
var yaw := 0.0
var yaw_rate := 0.0 ## rad/s (positive = turning to port)
var rudder := 0.0 ## smoothed, -1 port .. +1 starboard
var rudder_cmd := 0.0 ## written by the autopilot
var speed_scale := 1.0
var current_speed := 6.0
var forward := Vector2(0, -1) ## heading as a world (x, z) unit vector
var _heave_v := 0.0
var _pitch_v := 0.0
var _roll_v := 0.0
var _t := 0.0
@onready var _pivot: Node3D = get_node(pivot_path)

func _ready() -> void:
	add_to_group("rebase")
	var loader := get_node(loader_path)
	loader.ship_ready.connect(func(l: float, b: float, _r: float) -> void:
		length = l
		beam = b
		if Waves.ocean:
			Waves.ocean.set_ship_footprint(l * 0.46, b * 0.5)
			_bake_hull_profile.call_deferred()
		active = true)

func rebase(shift: Vector3) -> void:
	global_position -= shift

static func _smooth(cur: float, target: float, vel: float, smooth_time: float, dt: float) -> Vector2:
	# Critically damped spring (Unity-style SmoothDamp). Returns (value, velocity).
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var temp := (vel + omega * change) * dt
	var new_vel := (vel - omega * temp) * e
	var out := target + (change + temp) * e
	return Vector2(out, new_vel)

func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	# Steering: the rudder follows the command, yaw rate follows the rudder (turning radius ~ speed / rate).
	rudder = move_toward(rudder, clampf(rudder_cmd, -1.0, 1.0), rudder_rate * delta)
	current_speed = lerpf(current_speed, speed * speed_scale, 1.0 - exp(-0.35 * delta))
	var rate_target := -rudder * deg_to_rad(max_turn_rate_deg) * clampf(current_speed / maxf(speed, 0.1), 0.3, 1.3)
	yaw_rate = lerpf(yaw_rate, rate_target, 1.0 - exp(-1.2 * delta))
	yaw += yaw_rate * delta + deg_to_rad(sin(_t * 0.07) * yaw_wander_deg * 0.2) * delta
	rotation.y = yaw
	forward = Vector2(-sin(yaw), -cos(yaw))
	global_position += Vector3(forward.x, 0.0, forward.y) * current_speed * delta

	var half_l := length * 0.5 * sample_length_frac
	var half_b := beam * 0.5 * sample_beam_frac
	var yb := Basis(Vector3.UP, yaw)
	var c := global_position
	var hs := func(lx: float, lz: float) -> float:
		var p := yb * Vector3(lx, 0, lz)
		return Waves.height_at(c.x + p.x, c.z + p.z)
	var h_bow: float = hs.call(0.0, -half_l)
	var h_stern: float = hs.call(0.0, half_l)
	var h_port: float = hs.call(-half_b, 0.0)
	var h_stbd: float = hs.call(half_b, 0.0)
	var h_c: float = hs.call(0.0, 0.0)
	# Corners add resolution for the heave estimate.
	var h_corners: float = (hs.call(-half_b, -half_l) + hs.call(half_b, -half_l)
		+ hs.call(-half_b, half_l) + hs.call(half_b, half_l)) * 0.25
	var target_heave := ((h_bow + h_stern) * 0.5 * 0.25 + (h_port + h_stbd) * 0.5 * 0.25
		+ h_c * 0.25 + h_corners * 0.25) * heave_gain
	var target_pitch := atan2(h_bow - h_stern, half_l * 2.0) * pitch_gain
	# Heel: leeward lean from the wind (wind pushing toward starboard -> starboard down) plus outward lean in turns.
	var right := Vector2(cos(yaw), -sin(yaw))
	var side_wind := WorldState.wind_vector().dot(right) * WorldState.wind_strength
	var heel := deg_to_rad(wind_heel_deg * 2.0) * side_wind
	var target_roll := atan2(h_stbd - h_port, half_b * 2.0) * roll_gain - heel * 0.5 - yaw_rate * current_speed * 0.02 * turn_heel_gain # starboard-up positive

	var r := _smooth(heave, target_heave, _heave_v, heave_smooth_time, delta)
	heave = r.x; _heave_v = r.y
	r = _smooth(pitch, target_pitch, _pitch_v, rotate_smooth_time, delta)
	pitch = r.x; _pitch_v = r.y
	r = _smooth(roll, target_roll, _roll_v, rotate_smooth_time, delta)
	roll = r.x; _roll_v = r.y

	_pivot.position = Vector3(0, heave, 0)
	_pivot.rotation = Vector3(pitch, 0, roll)

const HULL_BINS := 48
## Bakes the hull's waterline outline: vertices within a band around the waterline (pivot space y in [-0.7, 0.9])
## give the max half-width per slice along z. The ocean shader hugs foam to this outline.
func _bake_hull_profile() -> void:
	if Waves.ocean == null:
		return
	var verts := ModelUtil.sample_vertices(_pivot, 150000)
	var zs := PackedFloat32Array()
	var xs := PackedFloat32Array()
	for v in verts:
		if v.y > -0.7 and v.y < 0.9 and absf(v.x) < beam * 0.75:
			zs.append(v.z)
			xs.append(absf(v.x))
	if zs.size() < 50:
		return
	var zmin := 1.0e9
	var zmax := -1.0e9
	for z in zs:
		zmin = minf(zmin, z)
		zmax = maxf(zmax, z)
	var w := PackedFloat32Array()
	w.resize(HULL_BINS)
	w.fill(-1.0)
	for i in zs.size():
		var k := clampi(int((zs[i] - zmin) / (zmax - zmin) * (HULL_BINS - 1) + 0.5), 0, HULL_BINS - 1)
		w[k] = maxf(w[k], xs[i])
	# Fill empty bins from neighbours, then smooth lightly.
	for i in HULL_BINS:
		if w[i] < 0.0:
			var j := i
			while j > 0 and w[j] < 0.0: j -= 1
			var l := w[j] if w[j] >= 0.0 else 0.0
			j = i
			while j < HULL_BINS - 1 and w[j] < 0.0: j += 1
			var r := w[j] if w[j] >= 0.0 else 0.0
			w[i] = (l + r) * 0.5
	var sm := w.duplicate()
	for i in range(1, HULL_BINS - 1):
		sm[i] = (w[i - 1] + 2.0 * w[i] + w[i + 1]) * 0.25
	Waves.ocean.set_hull_profile(sm, zmin, zmax)
	print("[hull] baked waterline profile z=", snappedf(zmin, 0.1), "..", snappedf(zmax, 0.1), " max half-width=", snappedf(Array(sm).max(), 0.01))
