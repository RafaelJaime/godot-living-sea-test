extends Node3D
## The ship's rowing boat: split out of the hull mesh (export_pinnace.py), turned into its own RigidBody3D that is held to
## the deck by a stiff spring-damper "lashing" (position + orientation) plus four visible ropes. In heavy rolls and
## accelerations it shifts a few centimetres and rocks slightly, but it can never fall off (spring + hard travel limit).

@export var ship_path := NodePath("../Ship")
@export var loader_path := NodePath("../Ship/Pivot/Model")
@export var mesh_name := "geo_ship_boat"
@export var boat_mass := 450.0
@export var pos_freq := 1.8   ## Hz of the lashing (lower = more play)
@export var rot_freq := 1.6
@export var pos_zeta := 0.35
@export var rot_zeta := 0.45
@export var max_travel := 0.35 ## m: beyond this the boat is pulled back hard

var _ship: RigidBody3D
var _body: RigidBody3D
var _rest_local := Transform3D.IDENTITY
var _ropes: Array[MeshInstance3D] = []
var _rope_boat_pts: Array[Vector3] = [Vector3(-0.8, 0.45, -2.1), Vector3(0.8, 0.45, -2.1), Vector3(-0.8, 0.45, 2.1), Vector3(0.8, 0.45, 2.1)] # boat space
var _rope_deck_pts: Array[Vector3] = [] # ship-pivot space, set from the rest pose
var _inertia := Vector3.ONE

func _ready() -> void:
	add_to_group("rebase")
	_ship = get_node(ship_path)
	get_node(loader_path).ship_ready.connect(_on_ship_ready.unbind(3), CONNECT_DEFERRED)

func rebase(shift: Vector3) -> void:
	if _body:
		_body.global_position -= shift

func _on_ship_ready() -> void:
	var model := get_node(loader_path)
	var mi: MeshInstance3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) == mesh_name:
			mi = n
	if mi == null:
		push_warning("[boat] mesh not found: " + mesh_name)
		return
	var box: AABB = mi.global_transform * mi.get_aabb()
	var size := box.size
	_body = RigidBody3D.new()
	_body.name = "BoatBody"
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.can_sleep = false
	_body.mass = boat_mass
	_body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_body.gravity_scale = 1.0
	_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	_body.add_child(cs)
	add_child(_body)
	_body.global_transform = Transform3D(Basis.IDENTITY, box.get_center())
	mi.reparent(_body, true)
	# Inertia of a box.
	_inertia = Vector3(boat_mass * (size.y * size.y + size.z * size.z) / 12.0, boat_mass * (size.x * size.x + size.z * size.z) / 12.0, boat_mass * (size.x * size.x + size.y * size.y) / 12.0)
	_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_body.center_of_mass = Vector3.ZERO
	_body.inertia = _inertia
	# Rest pose relative to the ship, ropes anchored to the deck.
	var ship_inv := _ship.global_transform.affine_inverse()
	_rest_local = ship_inv * _body.global_transform
	_rope_boat_pts = [Vector3(-size.x * 0.5, size.y * 0.3, -size.z * 0.42), Vector3(size.x * 0.5, size.y * 0.3, -size.z * 0.42),
		Vector3(-size.x * 0.5, size.y * 0.3, size.z * 0.42), Vector3(size.x * 0.5, size.y * 0.3, size.z * 0.42)] as Array[Vector3]
	for p in _rope_boat_pts:
		var out := Vector3(p.x * 1.5, -size.y * 0.9, p.z * 1.02) # anchor slightly outboard and lower, on the cradle/deck
		_rope_deck_pts.append(_rest_local * out)
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.55, 0.45, 0.28)
	rope_mat.roughness = 1.0
	for i in 4:
		var r := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025; cm.bottom_radius = 0.025; cm.height = 1.0; cm.radial_segments = 5
		r.mesh = cm
		r.material_override = rope_mat
		r.top_level = true
		add_child(r)
		_ropes.append(r)
	print("[boat] split out: size ", size.snapped(Vector3.ONE * 0.01), " mass ", boat_mass, " kg, ropes 4")

var _age := 0.0
var max_play := 0.0
var max_tilt := 0.0
var _log_t := 0.0
var _log := OS.get_cmdline_user_args().has('--log-boat')
var _apply_load := not OS.get_cmdline_user_args().has('--no-lash-load') ## test aid: --no-lash-load leaves the ship unaffected by the boat (A/B)
var _load_n := 0.0       ## |lashing force| of the last step (N)
var _offset_m := 0.0
var _tilt_rad := 0.0
var _peak_load := 0.0
var _in_cradle := true
var _left_cradle := false
func _physics_process(_delta: float) -> void:
	if _body == null or _ship.freeze:
		if _body and _ship.freeze:
			_body.freeze = true
		return
	_body.freeze = false
	var m := boat_mass
	var target := _ship.global_transform * _rest_local
	# --- position spring (world), the ship's own motion enters through the moving target ---
	var kp := m * pow(TAU * pos_freq, 2.0)
	var cp := 2.0 * pos_zeta * sqrt(kp * m)
	var err := target.origin - _body.global_position
	var rel_v := _body.linear_velocity - _ship.linear_velocity - _ship.angular_velocity.cross(_body.global_position - _ship.global_position)
	var f := err * kp - rel_v * cp
	var over := err.length() - max_travel
	if over > 0.0:
		f += err.normalized() * over * kp * 6.0 # hard travel limit
	_body.apply_central_force(f + Vector3(0.0, m * 9.81, 0.0)) # weight is carried by the cradle: the spring only handles deviations
	var ship_torque := Vector3.ZERO
	# --- orientation spring ---
	var q_err := (target.basis.get_rotation_quaternion() * _body.global_transform.basis.get_rotation_quaternion().inverse()).normalized()
	if q_err.w < 0.0:
		q_err = -q_err
	var axis_angle := q_err.get_axis() * q_err.get_angle() if q_err.get_angle() > 1e-5 else Vector3.ZERO
	var i_avg := (_inertia.x + _inertia.y + _inertia.z) / 3.0
	var kr := i_avg * pow(TAU * rot_freq, 2.0)
	var cr := 2.0 * rot_zeta * sqrt(kr * i_avg)
	var rel_w := _body.angular_velocity - _ship.angular_velocity
	var boat_torque := axis_angle * kr - rel_w * cr
	_body.apply_torque(boat_torque)
	# Newton's third law: the lashings push back on the ship with the same force (at the boat's position) and torque. Only the
	# dynamic part is returned: the boat's weight stays inside the ship's own mass.
	_load_n = f.length()
	_offset_m = err.length()
	_tilt_rad = axis_angle.length()
	_peak_load = maxf(_peak_load, _load_n)
	_in_cradle = err.length() < max_travel * 0.98
	if _age > 12.0 and not _in_cradle:
		_left_cradle = true
	if _apply_load:
		_ship.apply_force(-f, _body.global_position - _ship.global_position)
		_ship.apply_torque(-boat_torque)
	_age += _delta
	if _age > 12.0: # ignore the start-up settling
		max_play = maxf(max_play, err.length())
		max_tilt = maxf(max_tilt, axis_angle.length())
	_log_t += _delta
	if _log and _log_t > 10.0:
		_log_t = 0.0
		print('[boat] max play so far ', snappedf(max_play * 100.0, 0.1), ' cm, max tilt ', snappedf(rad_to_deg(max_tilt), 0.1), ' deg, load now ', snappedf(_load_n, 1.0), ' N (peak ', snappedf(_peak_load, 1.0), ' N), applied to ship: ', _apply_load, ', left cradle: ', _left_cradle)

func _process(_delta: float) -> void:
	if _body == null:
		return
	var bt := _body.get_global_transform_interpolated()
	var st := _ship.get_global_transform_interpolated()
	for i in _ropes.size():
		var a := bt * _rope_boat_pts[i]
		var b := st * _rope_deck_pts[i]
		var d := b - a
		var l := d.length()
		var r := _ropes[i]
		if l < 0.01:
			r.visible = false
			continue
		r.visible = true
		var y := d / l
		var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		r.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)

## Read-only state for gameplay/NPC code: offset from the rest pose (m), tilt (deg), current lashing load (N), whether the boat is inside its
## cradle travel (it never leaves: spring plus hard limit; `left_cradle` latches if it ever does after the start-up settling).
func state() -> Dictionary:
	return {"offset_m": _offset_m, "tilt_deg": rad_to_deg(_tilt_rad), "lashing_load_n": _load_n, "in_cradle": _in_cradle, "left_cradle": _left_cradle}
