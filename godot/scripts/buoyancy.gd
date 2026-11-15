extends RigidBody3D
## PHYSICS SHIP (RigidBody3D, Jolt). Heave/roll/pitch EMERGE from per-column hydrostatics against the FFT water surface;
## sails push with apparent-wind forces at their centres of effort (thrust + heeling); the rudder is a hydrofoil at the stern.
## `legacy_motion = true` keeps the old scripted kinematic motion as a fallback.
## (Old description) Ship motion: sails along its heading (autopilot steers via `rudder_cmd`), plus wave-driven heave/pitch/roll.
## `rudder` (-1 port .. +1 starboard, smoothed) is the shared steering signal (wheel, crew lean, wake...).
## Node layout: Ship (this, position + heading) / Pivot (heave, pitch, roll) / Model + CrewMarkers.

## Cruising speed (m/s); the autopilot scales it with the point of sail (`speed_scale`).
@export var speed := 6.0
@export var legacy_motion := false
@export_group("Physics")
@export var water_density := 1025.0
@export var air_density := 1.2
@export var columns_z := 18
@export var columns_x := 5
@export var gm_target := 1.4 ## metacentric height (m): sets the centre-of-mass height -> roll period emerges from it
@export var roll_gyradius := 4.2 ## m, incl. added mass
@export var pitch_gyradius := 18.0 ## m, incl. added water mass
@export var yaw_gyradius := 11.0
## 1 = every column feels the full local wave height; < 1 blends toward the hull-mean height (Froude-Krylov depth
## attenuation + diffraction: a hull is not a perfect wave follower, so wave slope forces it less than a buoy).
@export_range(0.2, 1.0) var wave_coupling := 0.6
## Soft spring that pulls a keel point back down once it is more than this far above the local water (m).
@export var keel_free_lift := 0.3
@export var keel_suction := 3.0e5 ## N per metre of excess lift (per column)
@export var column_damping := 250.0 ## N s / m^3 of waterplane area (vertical, per column)
@export var heave_damping_ratio := 0.18
@export var roll_damping_ratio := 0.22
@export var pitch_damping_ratio := 0.3
@export var drag_longitudinal := 500.0 ## 0.5 rho Cd A  (N s^2/m^2)
@export var calm_drag_time := 30.0 ## s: time constant of the extra linear hull drag when the wind is too weak to drive the ship (calm), so it stops in ~1-1.5 min
@export var drag_wave := 14.0 ## N s^4/m^4: wave-making drag ~ v^4
@export var drag_lateral := 1.1 ## quadratic coefficient per section: 0.5 rho Cd (times section area)
@export var rudder_area := 5.0
@export var rudder_max_deg := 32.0
@export var sail_cl := 1.6 ## peak lift coefficient of a sail
@export var sail_cn := 1.6
@export var heel_depower_start_deg := 12.0
@export var heel_depower_end_deg := 28.0
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
@export var pitch_gain := 0.12
@export var roll_gain := 0.12
@export_group("Roll / pitch dynamics")
@export_range(8.0, 14.0) var roll_period := 10.0 ## natural roll period (s)
@export_range(4.0, 9.0) var pitch_period := 6.0
@export_range(0.03, 0.4) var roll_damping := 0.1 ## damping ratio (light: it keeps swinging)
@export_range(0.03, 0.4) var pitch_damping := 0.12
@export var swell_gain := 0.24 ## scales the sea_state-driven swell forcing
@export var pitch_ratio := 0.32 ## pitch forcing relative to roll forcing
@export var max_roll_deg := 25.0
@export var max_pitch_deg := 12.0
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
var roll_rate := 0.0  ## rad/s, starboard-up positive
var pitch_rate := 0.0 ## rad/s, bow-up positive
var roll_acc := 0.0
var pitch_acc := 0.0
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
var brace_cmd := 0.0   ## yard brace angle (rad), written by the autopilot (0 = square, + = starboard tack side)
var brace := 0.0       ## smoothed
var sail_defs: Array = [] ## filled by pinnace_rig.gd: {pos: Vector3 (ship local), area: float, name: String}
var sail_power := 1.0  ## 0..1, set by pinnace_rig (furling in storms)
var sail_fill := {}    ## per sail index: signed wind pressure on the sail (for the cloth shader)
var last_thrust := Vector3.ZERO
var last_heel_scale := 1.0
var _cols: Array = []  ## {x, z, yb, dA}
var _col_top := 5.0
var _keel := PackedFloat32Array()
var _wlw := PackedFloat32Array()
var _zr := Vector2.ZERO
var _phys_ready := false
var _com_local := Vector3.ZERO
var _kz := 0.0
var keel_clear_min := -99.0 ## MAX over the run of centreline keel height above the local water (>0 would show the keel)
var keel_mid_lift := -99.0
var peak_heel := 0.0
var min_keel_clear := -99.0 ## min over keel columns of (keel world y - water height); negative = under water
@onready var _pivot: Node3D = get_node(pivot_path)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with('--sail-gain='):
			cloth_sail_gain = float(a.get_slice('=', 1))
	add_to_group("rebase")
	var loader := get_node(loader_path)
	loader.ship_ready.connect(func(l: float, b: float, _r: float) -> void:
		length = l
		beam = b
		if Waves.ocean:
			Waves.ocean.set_ship_footprint(l * 0.46, b * 0.5)
			_bake_hull_profile.call_deferred()
		active = true
		_setup_body())

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
	if not legacy_motion:
		_t += delta
		_update_state(delta)
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
	var slope_pitch := atan2(h_bow - h_stern, half_l * 2.0)
	var slope_roll := atan2(h_stbd - h_port, half_b * 2.0)
	# Steady lean: leeward heel from the wind (wind toward starboard -> starboard down), gusts, outward heel in turns.
	var right := Vector2(cos(yaw), -sin(yaw))
	var side_wind := WorldState.wind_vector().dot(right) * WorldState.wind_strength
	var gust := 1.0 + 0.35 * sin(_t * 0.7) * sin(_t * 0.23 + 1.0)
	var heel := deg_to_rad(wind_heel_deg * 2.0) * side_wind * gust
	var lean_roll := -heel * 0.5 - yaw_rate * current_speed * 0.02 * turn_heel_gain
	# Physical roll / pitch: damped harmonic oscillators with the ship's natural periods, driven by the wave slope under
	# the hull, a swell forcing near (but not at) resonance whose size grows with sea_state, wind/turn lean and a little
	# low-frequency noise so the motion never dies out.
	var sea := clampf(Waves.sea_state, 0.0, 1.0)
	var amp := deg_to_rad(1.0 + 20.0 * pow(sea, 1.6)) * swell_gain # roll forcing amplitude (rad)
	var swell_r := amp * (0.8 * sin(_t * TAU / (roll_period * 1.12) + 0.6) + 0.35 * sin(_t * TAU / (roll_period * 0.86) + 2.1))
	var swell_p := amp * pitch_ratio * (0.8 * sin(_t * TAU / (pitch_period * 1.15) + 1.3) + 0.35 * sin(_t * TAU / (pitch_period * 0.85) + 0.2))
	var lf := deg_to_rad(0.5 + 1.5 * sea)
	var noise_r := lf * (sin(_t * 0.37) + 0.6 * sin(_t * 0.91 + 1.7))
	var noise_p := lf * 0.6 * (sin(_t * 0.43 + 0.5) + 0.6 * sin(_t * 1.07))
	var roll_eq := slope_roll * roll_gain + swell_r + noise_r + lean_roll
	var pitch_eq := slope_pitch * pitch_gain + swell_p + noise_p
	var wr := TAU / roll_period
	var wp := TAU / pitch_period
	var h := minf(delta, 1.0 / 30.0)
	var steps := 2
	for _i in steps:
		var dt := h / steps
		# Stiffening beyond ~15 deg keeps the swing under the clamp without a hard stop.
		var ar := wr * wr * (roll_eq - roll) - 2.0 * roll_damping * wr * _roll_v - wr * wr * 5.0 * roll * roll * roll
		_roll_v += ar * dt
		roll += _roll_v * dt
		var ap := wp * wp * (pitch_eq - pitch) - 2.0 * pitch_damping * wp * _pitch_v - wp * wp * 8.0 * pitch * pitch * pitch
		_pitch_v += ap * dt
		pitch += _pitch_v * dt
		roll_acc = ar
		pitch_acc = ap
	roll = clampf(roll, -deg_to_rad(max_roll_deg), deg_to_rad(max_roll_deg))
	pitch = clampf(pitch, -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	roll_rate = _roll_v
	pitch_rate = _pitch_v
	var r := _smooth(heave, target_heave, _heave_v, heave_smooth_time, delta)
	heave = r.x; _heave_v = r.y

	_pivot.position = Vector3(0, heave, 0)
	_pivot.rotation = Vector3(pitch, 0, roll)

const HULL_BINS := 48
const VOL_Z := 72     ## hull volume bake: z slices
const VOL_Y := 32     ## hull volume bake: height slices
const VOL_Y0 := -6.0  ## pivot-space height range of the bake (waterline = 0)
const VOL_Y1 := 10.0
const VOL_MESHES := ["hull", "deck", "aft", "interior"]
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
	_bake_hull_volume()
	print("[hull] baked waterline profile z=", snappedf(zmin, 0.1), "..", snappedf(zmax, 0.1), " max half-width=", snappedf(Array(sm).max(), 0.01))

## Hull volume for the ocean shader (T3b): table W(z, y) = max |x| of the hull structure in each (z, height) slice, in
## the ship pivot frame. The water shader discards any fragment whose pivot-space position lies inside that cross-section,
## so no water renders inside the hull or over the deck, whatever the heave/pitch/roll or wave height.
func _bake_hull_volume() -> void:
	var zmin := 1.0e9
	var zmax := -1.0e9
	var pts := PackedVector3Array()
	for n in _pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var low := mi.name.to_lower()
		var ok := false
		for k in VOL_MESHES:
			if k in low:
				ok = true
		if not ok or mi.mesh == null:
			continue
		var inv := _pivot.global_transform.affine_inverse() as Transform3D
		var t := inv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, v.size() / 60000)
			for i in range(0, v.size(), step):
				var p := t * v[i]
				pts.append(p)
				zmin = minf(zmin, p.z)
				zmax = maxf(zmax, p.z)
	if pts.size() < 100:
		return
	var tab := PackedFloat32Array()
	tab.resize(VOL_Z * VOL_Y)
	tab.fill(0.0)
	for p in pts:
		var zi := clampi(int((p.z - zmin) / (zmax - zmin) * (VOL_Z - 1) + 0.5), 0, VOL_Z - 1)
		var yi := int((p.y - VOL_Y0) / (VOL_Y1 - VOL_Y0) * (VOL_Y - 1) + 0.5)
		if yi < 0 or yi >= VOL_Y:
			continue
		var idx := yi * VOL_Z + zi
		tab[idx] = maxf(tab[idx], absf(p.x))
	# Close small holes: take the max of the z neighbours, and make each slice at least as wide as the slice below it
	# only up to the point where the structure ends (so overhanging flare is covered but nothing floats above the rails).
	var out := tab.duplicate()
	for yi in VOL_Y:
		for zi in VOL_Z:
			var m := tab[yi * VOL_Z + zi]
			if zi > 0: m = maxf(m, tab[yi * VOL_Z + zi - 1])
			if zi < VOL_Z - 1: m = maxf(m, tab[yi * VOL_Z + zi + 1])
			out[yi * VOL_Z + zi] = m
	# Keel line and waterline half-width per z slice (for the physics columns).
	_keel.resize(VOL_Z)
	_wlw.resize(VOL_Z)
	var y_wl := int((0.0 - VOL_Y0) / (VOL_Y1 - VOL_Y0) * (VOL_Y - 1) + 0.5)
	for zi in VOL_Z:
		var keel_y := 0.0
		for yi in VOL_Y:
			if out[yi * VOL_Z + zi] > 0.3:
				keel_y = VOL_Y0 + float(yi) / float(VOL_Y - 1) * (VOL_Y1 - VOL_Y0)
				break
		_keel[zi] = keel_y
		_wlw[zi] = out[y_wl * VOL_Z + zi]
	_zr = Vector2(zmin, zmax)
	_hull_ready()
	var img := Image.create_from_data(VOL_Z, VOL_Y, false, Image.FORMAT_RF, out.to_byte_array())
	Waves.ocean.set_hull_volume(ImageTexture.create_from_image(img), Vector4(zmin, zmax, VOL_Y0, VOL_Y1))
	print("[hull] baked hull volume z=", snappedf(zmin, 0.1), "..", snappedf(zmax, 0.1))


# =====================================================================================================
# Physics ship
# =====================================================================================================

func _setup_body() -> void:
	if legacy_motion:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		return
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new() # a body needs a shape; it collides with nothing (layer/mask 0)
	var bx := BoxShape3D.new()
	bx.size = Vector3(1, 1, 1)
	cs.shape = bx
	add_child(cs)
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	inertia = Vector3.ONE
	freeze = true # frozen until the hull volume is baked and the crew is placed
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var cm := get_node_or_null("Pivot/CrewMarkers")
	if cm and cm.has_signal("crew_ready"):
		cm.crew_ready.connect(func() -> void:
			_crew_done = true
			_start_physics())

var _dbg := OS.get_cmdline_user_args().has("--debug-phys")
var _dbg_t := 0.0
var _hmean := 0.0
var _hmin := 99.0
var _hmax := -99.0
func _off(n: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with('--phys-off=') and n in a.get_slice('=', 1).split(','):
			return true
	return false
var _crew_done := false
func _hull_ready() -> void:
	_build_columns()
	if _crew_done:
		_start_physics()

func _build_columns() -> void:
	_cols.clear()
	var z0 := _zr.x
	var z1 := _zr.y
	# Trim the stern overhang / bow where the waterline width is nil.
	var nzv := _keel.size()
	var dz := (z1 - z0) / float(columns_z)
	var v0 := 0.0
	var bz := 0.0
	var by := 0.0
	var ix := 0.0
	for zi in columns_z:
		var z := z0 + (float(zi) + 0.5) * dz
		var k := clampi(int((z - z0) / (z1 - z0) * (nzv - 1) + 0.5), 0, nzv - 1)
		var w := _wlw[k]
		var keel := _keel[k]
		if w < 0.4 or keel > -0.3:
			continue
		var dx := 2.0 * w / float(columns_x)
		for xi in columns_x:
			var x := -w + (float(xi) + 0.5) * dx
			var yb := keel * (1.0 - pow(absf(x) / w, 2.2))
			var c := {"x": x, "z": z, "yb": yb, "dA": dx * dz}
			_cols.append(c)
			var d := clampf(0.0 - yb, 0.0, _col_top - yb)
			var dv: float = c["dA"] * d
			v0 += dv
			bz += dv * z
			by += dv * (yb + d * 0.5)
			ix += c["dA"] * x * x * (1.0 if d > 0.0 else 0.0)
	if v0 < 1.0:
		push_warning("[ship] no buoyancy columns")
		return
	bz /= v0
	by /= v0
	mass = water_density * v0
	var bm := ix / v0
	var com_y := by + bm - gm_target
	_com_local = Vector3(0.0, com_y, bz)
	center_of_mass = _com_local
	inertia = Vector3(mass * pow(pitch_gyradius, 2.0), mass * pow(yaw_gyradius, 2.0), mass * pow(roll_gyradius, 2.0))
	_kz = bz
	_phys_ready = true
	print("[ship] physics: columns=", _cols.size(), " displaced=", snappedf(v0, 1.0), " m3 mass=", snappedf(mass / 1000.0, 1.0), " t  B=(z ", snappedf(bz, 0.1), ", y ", snappedf(by, 0.2),
		") BM=", snappedf(bm, 0.01), " m  CoM y=", snappedf(com_y, 0.01), " GM=", gm_target, " m  inertia(pitch,yaw,roll)=", (inertia / 1.0e6).snapped(Vector3.ONE * 0.1), " e6")

func _start_physics() -> void:
	if not _phys_ready or legacy_motion:
		return
	# Settled start: level hull, heave solved so the buoyancy of the columns against the ACTUAL water surface equals the weight
	# (bisection), cruise speed from the start, and the sail force ramps in (see _apply_sails) instead of kicking the hull.
	var gt0 := global_transform
	var lo := -4.0
	var hi := 4.0
	for _i in 28:
		var mid := 0.5 * (lo + hi)
		var f := 0.0
		for c in _cols:
			var wp := gt0 * Vector3(c["x"], c["yb"], c["z"])
			var depth := clampf(Waves.height_at(wp.x, wp.z) - (wp.y + mid), 0.0, _col_top - float(c["yb"]))
			f += water_density * 9.81 * float(c["dA"]) * depth
		if f > mass * 9.81:
			lo = mid # too deep: raise the hull
		else:
			hi = mid
	global_position.y = gt0.origin.y + 0.5 * (lo + hi)
	freeze = false
	_phys_age = 0.0
	settled = false
	linear_velocity = Vector3(forward.x, 0.0, forward.y) * 4.0
	angular_velocity = Vector3.ZERO
	for a in OS.get_cmdline_user_args():
		if a.begins_with('--kick='): # test aid: --kick=roll_rad_s,pitch_rad_s,heave_m_s
			var k := a.get_slice('=', 1).split_floats(',')
			angular_velocity = global_transform.basis * Vector3(k[1], 0.0, k[0])
			linear_velocity.y = k[2]

func _update_state(delta: float) -> void:
	var b := global_transform.basis
	var fwd := -b.z
	forward = Vector2(fwd.x, fwd.z).normalized() if Vector2(fwd.x, fwd.z).length() > 0.01 else forward
	yaw = atan2(-fwd.x, -fwd.z)
	pitch = asin(clampf(fwd.y, -1.0, 1.0))
	roll = asin(clampf(b.x.y, -1.0, 1.0))
	var avl := b.inverse() * angular_velocity
	roll_rate = avl.z
	pitch_rate = avl.x
	yaw_rate = angular_velocity.y
	heave = global_position.y
	current_speed = Vector2(linear_velocity.x, linear_velocity.z).length()
	rudder = move_toward(rudder, clampf(rudder_cmd, -1.0, 1.0), rudder_rate * delta)
	brace = move_toward(brace, brace_cmd, deg_to_rad(6.0) * delta)

func _point_velocity(world_off: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(world_off)

func _physics_process(delta: float) -> void:
	if legacy_motion or not _phys_ready or freeze or Waves.ocean == null:
		return
	_phys_age += delta
	_emit_wobble(delta)
	if not settled and _phys_age >= 6.0:
		settled = true
		settled_changed.emit(true)
		print('[ship] settled at t=', snappedf(_phys_age, 0.1), ' s')
	if _settle_log and _phys_age < 12.0 and int(_phys_age) != int(_phys_age - delta):
		print('[settle] t=', int(_phys_age), ' roll=', snappedf(rad_to_deg(roll), 0.1), ' pitch=', snappedf(rad_to_deg(pitch), 0.1), ' y=', snappedf(global_position.y, 0.02), ' mid keel lift=', snappedf(min_mid, 0.02), ' ends=', snappedf(min_keel_clear, 0.02))
	var gt := global_transform
	var origin := gt.origin
	var com_w := gt * _com_local
	var min_clear := -99.0
	var mid_clear := -99.0
	# --- hydrostatics: one vertical prism of hull per column --------------------------------------------
	var vsub := 0.0
	var hsum := 0.0
	var up := gt.basis.y.normalized()
	var upy := maxf(up.y, 0.5)
	for c in _cols:
		var pb := gt * Vector3(c["x"], c["yb"], c["z"])
		var hw_l := Waves.height_at(pb.x, pb.z)
		var hw := lerpf(_hmean, hw_l, wave_coupling)
		hsum += hw_l
		_hmin = minf(_hmin, hw_l); _hmax = maxf(_hmax, hw_l)
		var span: float = _col_top - float(c["yb"])
		if absf(c["x"]) < 1.2:
			min_clear = maxf(min_clear, pb.y - hw_l) # keel lift above the water along the centreline
			if absf(c["z"] - (_zr.x + _zr.y) * 0.5) < 0.32 * (_zr.y - _zr.x):
				mid_clear = maxf(mid_clear, pb.y - hw_l) # midship keel only (the ends of the keel line rise to stem/stern)
		var depth := clampf((hw - pb.y) / upy, 0.0, span) # submerged length along the hull-fixed column axis
		if depth <= 0.0:
			# Keel point out of the water: suction/slam keeps it from flying (soft spring beyond a small free lift).
			var lift_o := pb.y - hw_l
			if absf(c["x"]) < 1.5 and lift_o > keel_free_lift:
				var fo := minf((lift_o - keel_free_lift) * keel_suction, mass * 9.81 * 0.25)
				apply_force(Vector3(0.0, -fo, 0.0), pb - origin)
			continue
		var dA: float = c["dA"]
		var f := water_density * 9.81 * dA * depth
		var at := pb + up * (depth * 0.5) # centroid of the submerged part of the (tilted) column
		var r := at - com_w
		var vy := _point_velocity(r).y
		f -= column_damping * dA * vy * clampf(depth, 0.0, 1.0)
		apply_force(Vector3(0.0, f, 0.0), at - origin)
		vsub += dA * depth
	min_keel_clear = min_clear
	min_mid = mid_clear
	if _t > 12.0:
		keel_clear_min = maxf(keel_clear_min, min_clear)
		keel_mid_lift = maxf(keel_mid_lift, mid_clear)
		peak_heel = maxf(peak_heel, absf(rad_to_deg(roll)))
	if _cols.size() > 0:
		_hmean = hsum / float(_cols.size())
	if _dbg:
		_dbg_t += delta
		if _dbg_t > 0.25:
			_dbg_t = 0.0
			print('[phys] hrange=', snappedf(_hmin, 0.01), '..', snappedf(_hmax, 0.01), ' y=', snappedf(origin.y, 0.01), ' vy=', snappedf(linear_velocity.y, 0.01), ' vsub=', snappedf(vsub, 1.0), ' (rest ', snappedf(mass / water_density, 1.0), ') roll=', snappedf(rad_to_deg(roll), 0.1), ' pitch=', snappedf(rad_to_deg(pitch), 0.1), ' av=', angular_velocity.snapped(Vector3.ONE * 0.001), ' v=', linear_velocity.snapped(Vector3.ONE * 0.01), ' com_w.y=', snappedf(com_w.y, 0.01))
	# --- global heave / roll / pitch damping (ratios of critical, from the restoring stiffness estimates) ----
	var b := gt.basis
	var avl := b.inverse() * angular_velocity
	var m := mass
	var k_roll := m * 9.81 * gm_target
	var k_pitch := m * 9.81 * 40.0
	var k_heave := water_density * 9.81 * 200.0
	var c_roll := 2.0 * roll_damping_ratio * sqrt(k_roll * inertia.z)
	var c_pitch := 2.0 * pitch_damping_ratio * sqrt(k_pitch * inertia.x)
	var c_heave := 2.0 * heave_damping_ratio * sqrt(k_heave * m)
	var wet := clampf(vsub / 400.0, 0.0, 1.0)
	var qd := 1.0 + 1.7 * absf(avl.z) # quadratic part: large rolls are damped harder (bilge/keel eddies, deck wash)
	apply_torque(b * Vector3(-c_pitch * (1.0 + 2.0 * absf(avl.x)) * avl.x, 0.0, -c_roll * qd * avl.z) * wet)
	apply_central_force(Vector3(0.0, -c_heave * linear_velocity.y * wet, 0.0))
	if _off("all"):
		return
	# --- hull drag: longitudinal quadratic at the centre, lateral per section (keel effect, also damps yaw) ----
	var vl := b.inverse() * linear_velocity
	apply_central_force(b * Vector3(0.0, 0.0, 1.0) * (-drag_longitudinal * absf(vl.z) * vl.z) * wet)
	# Becalmed (true wind < ~5 m/s): rigging windage and wave radiation bleed the speed off; fades out to nothing by 5 m/s so the
	# 11 m/s sail calibration is untouched.
	var calm_k := 1.0 - smoothstep(2.0, 5.0, WindField.mean_speed())
	apply_central_force(b * Vector3(0.0, 0.0, 1.0) * (-vl.z * m / maxf(calm_drag_time, 1.0) * calm_k) * wet)
	# Wave-making resistance rises steeply near hull speed (~sqrt(g L) ~ 19 m/s theoretical, practically ~8 m/s here).
	apply_central_force(b * Vector3(0.0, 0.0, 1.0) * (-drag_wave * pow(absf(vl.z), 4.0) * signf(vl.z)) * wet)
	var nsec := 9
	var dz := (_zr.y - _zr.x) / float(nsec)
	for i in nsec:
		var z := _zr.x + (float(i) + 0.5) * dz
		var r_local := Vector3(0.0, _com_local.y * 0.0 - 1.2, z) # lateral resistance centre ~1.2 m below the waterline
		var r_w := b * (r_local - _com_local)
		var v_loc := b.inverse() * _point_velocity(r_w)
		var area := 3.4 * dz
		var fx := -0.5 * water_density * drag_lateral * area * absf(v_loc.x) * v_loc.x
		var fz := -0.5 * water_density * 0.004 * area * absf(v_loc.z) * v_loc.z
		apply_force(b * Vector3(fx, 0.0, fz) * wet, b * r_local)
	# --- rudder: hydrofoil lift at the stern, proportional to angle x flow^2 -------------------------------
	if _off("rudder"):
		return
	var r_pos := Vector3(0.0, -1.5, _zr.y - 1.0)
	var r_w2 := b * (r_pos - _com_local)
	var v_r := b.inverse() * _point_velocity(r_w2)
	var flow := -v_r.z # speed of water past the rudder (ship moving forward = -z)
	var delta_r := rudder * deg_to_rad(rudder_max_deg)
	var cl := clampf(2.0 * PI * delta_r, -1.1, 1.1) * (1.0 - smoothstep(0.35, 0.6, absf(delta_r)) * 0.4)
	var f_r := 0.5 * water_density * rudder_area * cl * flow * absf(flow)
	# Rudder to starboard (+) pushes the stern to port (-x): the bow goes to starboard.
	apply_force(b * Vector3(-f_r, 0.0, 0.0) * wet, b * r_pos)
	if _off("sails"):
		return
	# --- sails: apparent-wind forces at each sail's centre of effort --------------------------------------
	_apply_sails(gt, b, com_w)
	# --- safety: keep the ship from capsizing or going supersonic (soft, only far outside the normal range) ---
	var rl := rad_to_deg(roll)
	if absf(rl) > 38.0:
		apply_torque(b * Vector3(0.0, 0.0, -signf(roll) * (absf(rl) - 38.0) * m * 900.0))
	if linear_velocity.length() > 14.0:
		apply_central_force(-linear_velocity * m * 0.5)

## Sail forces come from the cloth simulation (what the sails visibly do is what pushes the ship). Falls back to the
## analytic flat-plate model when no cloth rig is present (or `--analytic-sails`).
var _sail_rig: Node
var _analytic_sails := OS.get_cmdline_user_args().has("--analytic-sails")
var cloth_force_used := false
var _analytic_logged := false
var _cloth_logged := false
var settled := false ## false while the start-up ramp runs (~6 s), then true: NPC code may start moving around
var _phys_age := 0.0
var _settle_log := OS.get_cmdline_user_args().has('--settle-log')
var min_mid := -99.0
signal settled_changed(is_settled: bool)
## Emitted at most every 0.5 s when the hull moves noticeably: kind 'roll' / 'pitch' / 'slam' (stem or stern re-entering the water). intensity 0..1.
signal wobble(intensity: float, kind: String)
var _wobble_cd := 0.0
var _wobble_log := OS.get_cmdline_user_args().has('--log-wobble')
var _prev_vy := 0.0
## Calibration of the cloth sail forces against the hull drag (the cloth pressure integration is conservative).
@export var cloth_sail_gain := 4.0 ## calibrated (with drag_wave): beam reach ~4-4.5 m/s at 11 m/s wind
func _apply_sails(gt: Transform3D, b: Basis, com_w: Vector3) -> void:
	if _sail_rig == null or not is_instance_valid(_sail_rig):
		_sail_rig = get_tree().get_first_node_in_group("sail_rig")
	if _sail_rig != null and not _analytic_sails and _sail_rig.has_method("get_sail_forces"):
		var heel_d := 1.0 - smoothstep(heel_depower_start_deg, heel_depower_end_deg, absf(rad_to_deg(roll)))
		var tot := Vector3.ZERO
		for sd in _sail_rig.get_sail_forces():
			var fs: Vector3 = sd["force"] * heel_d * cloth_sail_gain * _canvas_factor()
			if not fs.is_finite():
				continue
			var cap := mass * 9.81 * 0.35 # a single sail can never push harder than 0.35 g of the ship
			if fs.length() > cap:
				fs = fs.normalized() * cap
			var pw: Vector3 = gt * (sd["point"] as Vector3)
			apply_force(b * fs, pw - gt.origin)
			tot += fs
		last_thrust = tot
		last_heel_scale = heel_d
		cloth_force_used = true
		if not _cloth_logged:
			_cloth_logged = true
			print('[ship] sail path: cloth forces')
		return
	cloth_force_used = false
	if not _analytic_logged:
		_analytic_logged = true
		print('[ship] sail path: analytic (WindField per sail)')
	var heel := rad_to_deg(roll)
	var depower := 1.0 - smoothstep(heel_depower_start_deg, heel_depower_end_deg, absf(heel))
	last_heel_scale = depower
	var total := Vector3.ZERO
	var br := Basis(Vector3.UP, brace)
	var n_local := br * Vector3(0.0, 0.0, -1.0)
	var bi := b.inverse()
	for i in sail_defs.size():
		var sd: Dictionary = sail_defs[i]
		var pos: Vector3 = sd["pos"]
		var area: float = sd["area"] * sail_power * depower
		var pw := gt * pos
		var r := pw - com_w
		var wsm := WindField.sample(pw) # same gusty, sheared field the cloth sees, at this sail's centre
		var vrel := bi * (Vector3(wsm.x, 0.0, wsm.z) - _point_velocity(r)) # air relative to the sail, ship frame
		vrel.y = 0.0
		var wn := vrel.dot(n_local)
		sail_fill[i] = wn
		var f_local := sail_force_local(vrel, n_local, area)
		var fw := b * f_local
		apply_force(fw, pw - global_transform.origin)
		total += fw
	last_thrust = bi * total

## Aerodynamic force (ship frame) on a sail of `area` with plane normal n and air velocity `vrel` relative to it:
## flat-plate lift/drag model. Lift ~ sin(2 alpha) up to the stall angle, then plate drag; lift points to the side the
## sail is pushed (sign of the wind component on the normal), so the sail can drive the ship even at ~70 deg off the wind.
func sail_force_local(vrel: Vector3, n: Vector3, area: float) -> Vector3:
	var speed := vrel.length()
	if speed < 0.05 or area <= 0.0:
		return Vector3.ZERO
	var wv := vrel / speed
	var wn := vrel.dot(n)
	var sgn := 1.0 if wn >= 0.0 else -1.0
	var alpha := asin(clampf(absf(wn) / speed, 0.0, 1.0)) # angle between wind and the sail plane
	var cl := sail_cl * sin(2.0 * alpha) * (1.0 - smoothstep(0.7, 1.2, alpha))
	var cd := 0.05 + 1.3 * sin(alpha) * sin(alpha)
	var lift_dir := n * sgn - wv * (n * sgn).dot(wv)
	lift_dir = lift_dir.normalized() if lift_dir.length() > 0.001 else Vector3.ZERO
	return (lift_dir * cl + wv * cd) * (0.5 * air_density * area * speed * speed)

## Brace angle that maximises forward thrust for the current wind (used by the autopilot).
func best_brace(max_deg := 72.0) -> float:
	var wv := WindField.sample(global_position + Vector3(0.0, 12.0, 0.0)) # same gusty field the cloth sees
	var vrel_w := Vector3(wv.x, 0.0, wv.z) - Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var vrel := global_transform.basis.inverse() * vrel_w
	vrel.y = 0.0
	var best := 0.0
	var best_f := -1.0e9
	var steps := 37
	for i in steps:
		var a := deg_to_rad(-max_deg + 2.0 * max_deg * float(i) / float(steps - 1))
		var n := Basis(Vector3.UP, a) * Vector3(0, 0, -1)
		var fl := sail_force_local(vrel, n, 1.0)
		var score := -fl.z - 0.12 * absf(fl.x)
		if score > best_f:
			best_f = score
			best = a
	return best


## Effective sail area: the crew reefs and furls as the storm builds (tied to the cloth furl state), and the start-up ramps in.
func _canvas_factor() -> float:
	var reef := 1.0 - 0.94 * smoothstep(0.35, 0.9, WorldState.storm)
	var furl_k: float = clampf(sail_power, 0.1, 1.0) if "sail_power" in self else 1.0
	return reef * lerpf(1.0, furl_k, 0.8) * smoothstep(0.0, 6.0, _phys_age)


func _emit_wobble(delta: float) -> void:
	_wobble_cd -= delta
	var vy := linear_velocity.y
	var acc_y := (vy - _prev_vy) / maxf(delta, 0.001)
	_prev_vy = vy
	if _wobble_cd > 0.0 or not settled:
		return
	var roll_i := clampf((absf(roll_rate) - 0.18) / 0.35, 0.0, 1.0)
	var pitch_i := clampf((absf(pitch_rate) - 0.10) / 0.2, 0.0, 1.0)
	var slam_i := clampf((absf(acc_y) - 6.0) / 8.0, 0.0, 1.0)
	var best := maxf(roll_i, maxf(pitch_i, slam_i))
	if best <= 0.0:
		return
	var kind := "slam" if best == slam_i else ("roll" if best == roll_i else "pitch")
	_wobble_cd = 0.5
	wobble.emit(best, kind)
	if _wobble_log:
		print("[wobble] ", kind, " ", snappedf(best, 0.01))
