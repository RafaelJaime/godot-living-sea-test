extends Node3D
## Ship motion: constant forward sailing along -Z plus wave-driven heave/pitch/roll.
## Node layout: Ship (this, position + yaw wander) / Pivot (heave, pitch, roll) / Model + CrewMarkers.

@export var speed := 6.0
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
	global_position.z -= speed * delta
	yaw = deg_to_rad(sin(_t * 0.07) * yaw_wander_deg + sin(_t * 0.131 + 1.3) * yaw_wander_deg * 0.5)
	rotation.y = yaw

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
	var heel := deg_to_rad(wind_heel_deg) * (1.0 + 0.25 * sin(_t * 0.31))
	var target_roll := atan2(h_stbd - h_port, half_b * 2.0) * roll_gain - heel * 0.5 # starboard-up positive; wind from starboard heels to port

	var r := _smooth(heave, target_heave, _heave_v, heave_smooth_time, delta)
	heave = r.x; _heave_v = r.y
	r = _smooth(pitch, target_pitch, _pitch_v, rotate_smooth_time, delta)
	pitch = r.x; _pitch_v = r.y
	r = _smooth(roll, target_roll, _roll_v, rotate_smooth_time, delta)
	roll = r.x; _roll_v = r.y

	_pivot.position = Vector3(0, heave, 0)
	_pivot.rotation = Vector3(pitch, 0, roll)
