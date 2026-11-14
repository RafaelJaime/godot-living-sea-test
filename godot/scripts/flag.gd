extends Node3D
## Verlet cloth flag, simulated in WORLD space and driven by the APPARENT wind (true wind - ship velocity) from the same
## WorldState wind field the sails use. The hoist edge is pinned ON the real posed pole (derived from CPU-skinned vertices
## of the mast mesh, principal axis), re-evaluated every frame from the ship pivot transform, so it stays attached while the
## ship rolls, pitches, heaves and yaws.
## Two instances: stern staff (mesh "pavillion_mast") and the main-mast truck ("main_mast").

@export var ship_path := NodePath("../..")
@export var loader_path := NodePath("../Model")
@export var mesh_suffix := "pavillion_mast"
@export var cols := 12
@export var rows := 7
@export var spacing := 0.34   ## along the flag, hoist -> fly (m)
@export var spacing_v := 0.38 ## down the hoist (m)
@export var hoist_drop := 0.25 ## first pinned row below the pole tip (m)
@export var pole_clearance := 0.07 ## pins sit this far from the pole axis (m)
@export var texture_path := "res://assets/ship/flag_pirat.png"
@export var substeps := 4
@export var iterations := 8

var _ship: Node
var _pivot: Node3D
var _pos: PackedVector3Array
var _prev: PackedVector3Array
var _pin_local: PackedVector3Array # hoist pins, ship-pivot space (one per row)
var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _ready_flag := false
var _t := 0.0
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()
var _dbg: Array[MeshInstance3D] = []
var _log_t := 0.0
var _fly_ema := Vector3.ZERO

func _ready() -> void:
	add_to_group("rebase")
	add_to_group("flag_" + mesh_suffix)
	_ship = get_node(ship_path)
	_pivot = get_parent() as Node3D
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.top_level = true
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_mi.extra_cull_margin = 20.0
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(texture_path):
		m.albedo_texture = load(texture_path)
		m.uv1_scale = Vector3(0.975, 0.97, 1.0) # crop the thin margin of the supplied image
		m.uv1_offset = Vector3(0.0125, 0.015, 0.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.9
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.35, 0.35)
	_mi.material_override = m
	add_child(_mi)
	get_node(loader_path).ship_ready.connect(_on_ship_ready.unbind(3))

func rebase(shift: Vector3) -> void:
	for i in _pos.size():
		_pos[i] -= shift
		_prev[i] -= shift

func _on_ship_ready() -> void:
	var model := get_node(loader_path)
	var pole: MeshInstance3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).to_lower().ends_with(mesh_suffix):
			pole = n
	if pole == null:
		push_warning("[flag] pole mesh not found: " + mesh_suffix)
		return
	var pts := ModelUtil.posed_points(pole, _pivot)
	# Pole axis = principal axis of the posed vertices; top = the higher end.
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	var ax := Vector3(0, 1, 0)
	for _i in 12: # power iteration on the covariance
		var nv := Vector3.ZERO
		for p in pts:
			var d := p - c
			nv += d * d.dot(ax)
		ax = nv.normalized()
	if ax.y < 0.0:
		ax = -ax
	var lo := 1.0e9
	var hi := -1.0e9
	for p in pts:
		var t := (p - c).dot(ax)
		lo = minf(lo, t); hi = maxf(hi, t)
	var tip := c + ax * hi
	# Perpendicular offset direction: ship-right (+x) made orthogonal to the pole.
	var off := (Vector3.RIGHT - ax * ax.dot(Vector3.RIGHT)).normalized() * pole_clearance
	_pin_local.resize(rows)
	for r in rows:
		var along := hoist_drop + float(r) * spacing_v
		_pin_local[r] = tip - ax * along + off
	_init_particles()
	_build_topology()
	_ready_flag = true
	print("[flag] ", mesh_suffix, " axis ", ax.snapped(Vector3.ONE * 0.01), " tip ", tip.snapped(Vector3.ONE * 0.01), " length ", snappedf(hi - lo, 0.01))
	if OS.get_cmdline_user_args().has("--debug-pins"):
		for r in rows:
			var sp := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.09; sm.height = 0.18
			sp.mesh = sm
			var mat := StandardMaterial3D.new(); mat.albedo_color = Color(1, 0.1, 0.9); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sp.material_override = mat
			sp.top_level = true
			add_child(sp)
			_dbg.append(sp)
	for _w in 90:
		_simulate(1.0 / 120.0)

func _pin_world(r: int) -> Vector3:
	return _pivot.global_transform * _pin_local[r]

func _init_particles() -> void:
	_pos.resize(rows * cols)
	_prev.resize(rows * cols)
	var dir := _apparent_wind().normalized()
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, 1)
	for r in rows:
		for c in cols:
			var p := _pin_world(r) + dir * spacing * float(c) - Vector3(0, 0.03 * c, 0)
			_pos[r * cols + c] = p
			_prev[r * cols + c] = p

func _build_topology() -> void:
	_uvs.clear(); _idx.clear()
	for r in rows:
		for c in cols:
			_uvs.append(Vector2(float(c) / (cols - 1), float(r) / (rows - 1)))
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			_idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])

## Apparent wind in world space: true wind (WorldState, the same field the sails use) minus the ship's velocity.
func _apparent_wind() -> Vector3:
	var wv := WorldState.wind_vector() * WorldState.wind_speed_ms()
	var fwd: Vector2 = _ship.get("forward") if _ship.get("forward") != null else Vector2(0, -1)
	var spd: float = _ship.get("current_speed") if _ship.get("current_speed") != null else 6.0
	var sv := fwd * spd
	return Vector3(wv.x - sv.x, 0.0, wv.y - sv.y)

func _process(delta: float) -> void:
	if not _ready_flag:
		return
	_t += delta
	var dt := minf(delta, 0.05) / float(substeps)
	for _s in substeps:
		_simulate(dt)
	_update_mesh()
	_fly_ema = _fly_ema.lerp(_pos[(rows / 2) * cols + cols - 1] - _pin_world(rows / 2), 1.0 - exp(-delta / 3.0))
	for r in _dbg.size():
		_dbg[r].global_position = _pin_world(r)
	if OS.get_cmdline_user_args().has("--log-wind"):
		_log_t += delta
		if _log_t > 2.0:
			_log_t = 0.0
			var hoist := _pin_world(rows / 2)
			var fly := _pos[(rows / 2) * cols + cols - 1] - hoist
			var app := _apparent_wind()
			var tw := WorldState.wind_vector() * WorldState.wind_speed_ms()
			print("[wind] ", mesh_suffix, " true=(", snappedf(tw.x, 0.1), ",", snappedf(tw.y, 0.1), ") app=(", snappedf(app.x, 0.1), ",", snappedf(app.z, 0.1),
				") |app|=", snappedf(app.length(), 0.1), " flag fly dir=(", snappedf(fly.x, 0.1), ",", snappedf(fly.y, 0.1), ",", snappedf(fly.z, 0.1),
				") angle to app=", snappedf(rad_to_deg(Vector2(fly.x, fly.z).angle_to(Vector2(app.x, app.z))), 1.0), " deg  EMA fly=", _fly_ema.snapped(Vector3.ONE * 0.1), " heightdrop=", snappedf(fly.y, 0.01), " ship fwd=", _ship.get("forward"), " yaw_rate=", snappedf(float(_ship.get("yaw_rate")), 0.001), " tipvel=", ((_pos[(rows / 2) * cols + cols - 1] - _prev[(rows / 2) * cols + cols - 1]) * 60.0 * substeps).snapped(Vector3.ONE * 0.1))

func _simulate(dt: float) -> void:
	# Particles move in the world frame, so relative air velocity = TRUE wind - particle velocity; the ship's own motion
	# (apparent wind) enters through the pinned hoist dragging the cloth. app is only used for strength/droop decisions.
	var tw := WorldState.wind_vector() * WorldState.wind_speed_ms()
	var truew := Vector3(tw.x, 0.0, tw.y)
	var app := _apparent_wind()
	var w := WorldState
	var speed := app.length()
	var wind_k := clampf(speed / 5.0, 0.0, 1.0)
	var gust := 1.0 + 0.30 * sin(_t * 1.7) * sin(_t * 0.61 + 0.7) + 0.5 * pow(maxf(sin(_t * 0.43 + 1.1), 0.0), 8.0) * (0.3 + w.wind_strength)
	var grav := 0.4 + 1.8 * (1.0 - wind_k)
	var amp := clampf(0.25 + 0.5 * w.wind_strength + 0.5 * w.storm, 0.0, 1.2)
	for r in rows:
		_pos[r * cols] = _pin_world(r)
		_prev[r * cols] = _pos[r * cols]
	for r in rows:
		for c in range(1, cols):
			var i := r * cols + c
			var left := _pos[r * cols + c - 1]
			var right := _pos[r * cols + mini(c + 1, cols - 1)]
			var up := _pos[maxi(r - 1, 0) * cols + c]
			var dn := _pos[mini(r + 1, rows - 1) * cols + c]
			var n := (right - left).cross(dn - up)
			n = n.normalized() if n.length_squared() > 1e-9 else Vector3.UP
			var vel := (_pos[i] - _prev[i]) / dt
			var rel := truew * gust - vel
			# Travelling ripples: a force along the surface normal running from hoist to fly end.
			var ph := _t * 7.5 - float(c) * 0.95 + float(r) * 0.35
			var ripple := n * (sin(ph) + 0.4 * sin(ph * 1.9 + 1.3)) * amp * speed * (0.15 + 0.85 * float(c) / float(cols - 1))
			var acc := rel * 3.2 + n * n.dot(rel) * 0.8 + ripple + Vector3(0.0, -grav, 0.0)
			var np := _pos[i] + (_pos[i] - _prev[i]) * 0.985 + acc * dt * dt
			_prev[i] = _pos[i]
			_pos[i] = np
	var hyp := Vector2(spacing, spacing_v).length()
	for _it in iterations:
		for r in rows:
			for c in cols:
				var i := r * cols + c
				if c < cols - 1:
					_constrain(i, i + 1, spacing, c == 0)
				if r < rows - 1:
					_constrain(i, i + cols, spacing_v, c == 0)
				if c < cols - 1 and r < rows - 1:
					_constrain(i, i + cols + 1, hyp, c == 0)
					_constrain(i + 1, i + cols, hyp, false)
		for r in rows:
			_pos[r * cols] = _pin_world(r)

func _constrain(a: int, b: int, rest: float, a_pinned: bool) -> void:
	var d := _pos[b] - _pos[a]
	var l := d.length()
	if l < 1e-6:
		return
	var diff := (l - rest) / l
	if a_pinned:
		_pos[b] -= d * diff
	else:
		_pos[a] += d * diff * 0.5
		_pos[b] -= d * diff * 0.5

func _update_mesh() -> void:
	var norms := PackedVector3Array()
	norms.resize(_pos.size())
	for r in rows:
		for c in cols:
			var left := _pos[r * cols + maxi(c - 1, 0)]
			var right := _pos[r * cols + mini(c + 1, cols - 1)]
			var up := _pos[maxi(r - 1, 0) * cols + c]
			var dn := _pos[mini(r + 1, rows - 1) * cols + c]
			var n := (right - left).cross(dn - up)
			norms[r * cols + c] = n.normalized() if n.length_squared() > 1e-9 else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _pos
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = _uvs
	arr[Mesh.ARRAY_INDEX] = _idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mi.global_transform = Transform3D.IDENTITY

## Camera pose that looks at the flag from the side (perpendicular to its streaming direction).
func view_pose(dist: float) -> Dictionary:
	var center := _pin_world(rows / 2)
	var fly := _fly_ema
	fly.y = 0.0
	fly = fly.normalized() if fly.length() > 0.2 else Vector3(0, 0, 1)
	var perp := fly.cross(Vector3.UP).normalized()
	var target := center + fly * spacing * cols * 0.45
	return {"pos": target + perp * dist + Vector3(0, 0.6, 0), "look": target}
