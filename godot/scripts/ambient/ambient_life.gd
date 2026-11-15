extends Node3D
## Autonomous, randomised, cheap ambient life around the ship: dolphin pods jumping at the bow, distant whale spouts,
## ships passing on the horizon (lanterns at night) and flotsam / seaweed drifting on the swell.
## Everything is procedural (primitive meshes), world-space and registered for floating-origin rebases.
## Test aids: `--ambient-now` (trigger every event within ~3 s, repeatedly), `--no-ambient`.
## Hooks for other systems: WorldState.biolum / global shader parameter `sky_biolum` (night bioluminescence for the ocean agent).

@export var ship_path := NodePath("../Ship")
## Half-width (m) of the strip along the ship's heading where flotsam never spawns.
const CORRIDOR := 10.0

var _ship: Node3D
var _force := false
var _t := 0.0
# flotsam
var _flot: Array[Dictionary] = []
# dolphins
var _dol_next := 30.0
var _dolphins: Array[Dictionary] = []
var _splashes: Array[Dictionary] = []
# whale
var _whale_next := 40.0
var _whale_left := 0
var _whale_t := 0.0
var _whale_pos := Vector3.ZERO
var _whale_back: MeshInstance3D
var _spout: GPUParticles3D
# passing ship
var _ship_next := 25.0
var _far: Node3D
var _far_vel := Vector3.ZERO
var _far_lanterns: Array[MeshInstance3D] = []
var _far_mat_lantern: StandardMaterial3D

func _ready() -> void:
	if "--no-ambient" in OS.get_cmdline_user_args():
		queue_free()
		return
	_ship = get_node(ship_path)
	_force = "--ambient-now" in OS.get_cmdline_user_args()
	add_to_group("rebase")
	_build_flotsam()
	if "--flotsam-test" in OS.get_cmdline_user_args(): # test aid: one plank dead ahead on the keel line, logged while it is pushed aside
		var f0: Dictionary = _flot[0]
		f0["test"] = true
		f0["pos"] = _ship.global_position + _hull_fwd() * 55.0
		f0["yaw"] = PI * 0.5
		f0["spin"] = 0.0
		set_meta("flotsam_test", f0)
	_build_dolphins()
	_build_whale()
	if _force:
		_dol_next = 4.0
		_whale_next = 3.0
		_ship_next = 1.0
	if "--far-ship-test" in OS.get_cmdline_user_args():
		_ship_next = 1.0

func rebase(shift: Vector3) -> void:
	var s := Vector3(shift.x, 0.0, shift.z)
	for f in _flot:
		f["pos"] = (f["pos"] as Vector3) - s
	for d in _dolphins:
		d["pos"] = (d["pos"] as Vector3) - s
	_whale_pos -= s
	if _far:
		_far.position -= s

func _ship_fwd() -> Vector3:
	var f := Vector3.ZERO
	if _ship is RigidBody3D:
		f = (_ship as RigidBody3D).linear_velocity
		f.y = 0.0
	if f.length() < 0.5:
		f = -_ship.global_transform.basis.z
		f.y = 0.0
	return f.normalized()

func _ship_vel() -> Vector3:
	if _ship is RigidBody3D:
		var v := (_ship as RigidBody3D).linear_velocity
		v.y = 0.0
		return v
	return Vector3.ZERO

func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

# ---------------------------------------------------------------- flotsam / seaweed
func _build_flotsam() -> void:
	var plank := BoxMesh.new(); plank.size = Vector3(2.4, 0.08, 0.28)
	var barrel := CylinderMesh.new(); barrel.top_radius = 0.28; barrel.bottom_radius = 0.28; barrel.height = 0.62; barrel.radial_segments = 8
	var weed_mesh := SphereMesh.new(); weed_mesh.radius = 0.5; weed_mesh.height = 0.2; weed_mesh.radial_segments = 8; weed_mesh.rings = 3
	var wood := _mat(Color(0.32, 0.22, 0.13))
	var weed := _mat(Color(0.12, 0.2, 0.08))
	for i in 16:
		var n := Node3D.new()
		var kind := i % 4
		if kind == 0:
			var m := MeshInstance3D.new(); m.mesh = plank; m.material_override = wood; n.add_child(m)
		elif kind == 1:
			var m := MeshInstance3D.new(); m.mesh = barrel; m.material_override = wood; m.rotation.z = deg_to_rad(80.0); n.add_child(m)
		else:
			for k in 6:
				var m := MeshInstance3D.new(); m.mesh = weed_mesh; m.material_override = weed
				m.position = Vector3(randf_range(-1.1, 1.1), 0.0, randf_range(-1.1, 1.1))
				m.scale = Vector3.ONE * randf_range(0.7, 1.5)
				n.add_child(m)
		add_child(n)
		_flot.append({"node": n, "pos": Vector3.ZERO, "spin": randf_range(-0.15, 0.15), "yaw": randf() * TAU, "kind": kind,
			"vel": Vector3.ZERO, "spinv": 0.0, "dip": 0.0, "radius": 1.2 if kind == 0 else (0.5 if kind == 1 else 1.6)})
		_respawn_flot(_flot[i], true)

func _respawn_flot(f: Dictionary, anywhere: bool) -> void:
	var fwd := _ship_fwd()
	var sp := _ship.global_position
	var ang := randf_range(-1.1, 1.1)
	var dist := randf_range(15.0, 200.0) if anywhere else randf_range(150.0, 230.0)
	var dir := fwd.rotated(Vector3.UP, ang)
	if anywhere and randf() < 0.3:
		dir = -dir
	var p := sp + dir * dist
	# Never spawn in the ship's path: keep CORRIDOR m clear of the heading line (the hull pushes the rest aside, see _hull_push).
	var hf := _hull_fwd()
	var side := (p - sp).dot(Vector3(-hf.z, 0.0, hf.x))
	if absf(side) < CORRIDOR and (p - sp).dot(hf) > -20.0:
		p += Vector3(-hf.z, 0.0, hf.x) * ((CORRIDOR + randf_range(0.0, 8.0)) * (1.0 if side >= 0.0 else -1.0) - side)
	f["pos"] = p
	f["yaw"] = randf() * TAU
	f["vel"] = Vector3.ZERO

## Hull heading from the model (the velocity-based `_ship_fwd` is for things that must lead the motion).
func _hull_fwd() -> Vector3:
	var f := -_ship.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

## The hull and its bow wave push floating objects aside: outside the hull ellipse (grown by the object radius and a bow-wave
## margin) there is no effect; inside, the object gets an outward velocity proportional to the ship speed and how deep it is in
## the zone, a yaw kick away from the keel line, and a short dip that the wave then lifts (bobbing).
func _hull_push(f: Dictionary, p: Vector3, dt: float) -> void:
	var hf := _hull_fwd()
	var hr := Vector3(-hf.z, 0.0, hf.x)
	var rel := p - _ship.global_position
	var along := rel.dot(hf)
	var side := rel.dot(hr)
	var len_h: float = float(_ship.get("length")) * 0.5 if _ship.get("length") != null else 11.0
	var beam_h: float = float(_ship.get("beam")) * 0.5 if _ship.get("beam") != null else 3.5
	var r: float = f["radius"]
	var lz := len_h + r + (4.0 if along > 0.0 else 1.0) # bow wave: wider and longer ahead of the stem
	var bz := beam_h + r + (3.0 if along > -len_h * 0.3 else 1.5)
	var d := sqrt((along / lz) * (along / lz) + (side / bz) * (side / bz))
	if d >= 1.0:
		return
	var depth := 1.0 - d
	var n := (hr * (side / (bz * bz)) + hf * (along / (lz * lz)))
	if n.length() < 1e-5:
		n = hr * (1.0 if randf() < 0.5 else -1.0)
	n = n.normalized()
	# More of the push goes sideways than ahead, so a plank on the keel line slides off the bow instead of riding it.
	n = (n + hr * signf(side) * 0.6).normalized()
	var spd := maxf(_ship_vel().length(), 1.5)
	f["vel"] = (f["vel"] as Vector3) + n * spd * depth * 6.0 * dt
	f["spinv"] = float(f["spinv"]) + signf(side) * depth * 2.2 * dt
	f["dip"] = maxf(float(f["dip"]), depth)

func _tick_flotsam(dt: float) -> void:
	var sp := _ship.global_position
	var fwd := _ship_fwd()
	var wv := WorldState.wind_vector() * 0.35
	var drift := Vector3(wv.x, 0, wv.y)
	for f in _flot:
		var p: Vector3 = f["pos"]
		_hull_push(f, p, dt)
		var v: Vector3 = f["vel"]
		v *= exp(-dt * 1.2) # water drag: the push dies out within a few seconds
		f["vel"] = v
		f["spinv"] = float(f["spinv"]) * exp(-dt * 1.0)
		f["dip"] = float(f["dip"]) * exp(-dt * 1.5)
		p += (drift + v) * dt
		var rel := p - sp
		if not f.get("test", false) and (rel.length() > 260.0 or rel.dot(fwd) < -70.0):
			_respawn_flot(f, false)
			p = f["pos"]
		f["pos"] = p
		f["yaw"] = float(f["yaw"]) + (float(f["spin"]) + float(f["spinv"])) * dt
		var node: Node3D = f["node"]
		var h := Waves.height_at(p.x, p.z)
		var hx := Waves.height_at(p.x + 0.8, p.z) - h
		var hz := Waves.height_at(p.x, p.z + 0.8) - h
		node.global_position = Vector3(p.x, h + 0.03 - 0.22 * float(f["dip"]), p.z)
		node.rotation = Vector3(-hz * 0.8, float(f["yaw"]), hx * 0.8)

# ---------------------------------------------------------------- dolphins
func _build_dolphins() -> void:
	var body := SphereMesh.new(); body.radius = 0.5; body.height = 1.0; body.radial_segments = 10; body.rings = 6
	var fin := PrismMesh.new(); fin.size = Vector3(0.06, 0.38, 0.4)
	var fluke := BoxMesh.new(); fluke.size = Vector3(0.75, 0.05, 0.28)
	var skin := _mat(Color(0.2, 0.27, 0.33), 0.3)
	var belly := _mat(Color(0.72, 0.76, 0.8), 0.4)
	for i in 3:
		var n := Node3D.new()
		var b := MeshInstance3D.new(); b.mesh = body; b.material_override = skin; b.scale = Vector3(0.5, 0.48, 2.3); n.add_child(b)
		var bl := MeshInstance3D.new(); bl.mesh = body; bl.material_override = belly; bl.scale = Vector3(0.44, 0.3, 2.0); bl.position = Vector3(0, -0.12, 0.05); n.add_child(bl)
		var f := MeshInstance3D.new(); f.mesh = fin; f.material_override = skin; f.position = Vector3(0, 0.5, -0.1); f.rotation.x = deg_to_rad(-25.0); n.add_child(f)
		var tail := MeshInstance3D.new(); tail.mesh = fluke; tail.material_override = skin; tail.position = Vector3(0, 0, -1.2); n.add_child(tail)
		n.visible = false
		add_child(n)
		_dolphins.append({"node": n, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "t": -1.0, "left": 0, "delay": 0.0})
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 0.5; sm.radial_segments = 8; sm.rings = 3
	var splash_mat := StandardMaterial3D.new()
	splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.5)
	for i in 8:
		var s := MeshInstance3D.new(); s.mesh = sm; s.material_override = splash_mat.duplicate(); s.visible = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		_splashes.append({"node": s, "t": 9.0})

func _splash(at: Vector3, big: float) -> void:
	for s in _splashes:
		if float(s["t"]) >= 1.0:
			s["t"] = 0.0
			s["big"] = big
			(s["node"] as Node3D).global_position = Vector3(at.x, Waves.height_at(at.x, at.z), at.z)
			return

func _start_dolphin_event() -> void:
	# A pod riding the bow wave: dolphins alternate port / starboard of the stem, a few metres ahead of it.
	var fwd := _ship_fwd()
	var right := fwd.cross(Vector3.UP)
	var ahead := _ship.global_position + fwd * randf_range(22.0, 28.0)
	for i in _dolphins.size():
		var d: Dictionary = _dolphins[i]
		d["left"] = randi_range(2, 3)
		d["delay"] = float(i) * 0.35
		d["base"] = ahead + right * ((6.0 + float(i) * 2.0) * (1.0 if i % 2 == 0 else -1.0)) + fwd * (float(i) * 2.0)
		d["t"] = -1.0

func _tick_dolphins(dt: float) -> void:
	var fwd := _ship_fwd()
	var sv := _ship_vel()
	for d in _dolphins:
		var node: Node3D = d["node"]
		if float(d["delay"]) > 0.0:
			d["delay"] = float(d["delay"]) - dt
			continue
		var t: float = d["t"]
		if t < 0.0:
			if int(d["left"]) <= 0:
				node.visible = false
				continue
			# Start a jump: horizontal speed matches the ship + a little, launch speed gives ~2.5 m of air.
			d["left"] = int(d["left"]) - 1
			var jitter := fwd.cross(Vector3.UP) * randf_range(-3.0, 3.0) + fwd * randf_range(-4.0, 4.0)
			var p: Vector3 = (d["base"] as Vector3) + jitter
			d["base"] = (d["base"] as Vector3) + fwd * 6.0
			d["pos"] = Vector3(p.x, Waves.height_at(p.x, p.z) - 0.6, p.z)
			d["vel"] = sv * 1.0 + fwd * randf_range(3.5, 5.5) + Vector3(0, randf_range(6.5, 8.0), 0)
			d["t"] = 0.0
			node.visible = true
			_splash(d["pos"], 1.0)
			continue
		t += dt
		d["t"] = t
		var v: Vector3 = d["vel"]
		v.y -= 9.81 * dt
		d["vel"] = v
		var pos: Vector3 = d["pos"] + v * dt
		d["pos"] = pos
		var sea := Waves.height_at(pos.x, pos.z)
		node.global_position = pos
		if v.length() > 0.1:
			node.look_at(pos + v, Vector3.UP)
		if v.y < 0.0 and pos.y < sea - 0.5:
			node.visible = false
			_splash(pos, 1.3)
			d["t"] = -1.0
			d["delay"] = randf_range(0.8, 2.0)

func _tick_splashes(dt: float) -> void:
	for s in _splashes:
		var t: float = s["t"]
		if t >= 1.0:
			continue
		t += dt * 1.6
		s["t"] = t
		var n: MeshInstance3D = s["node"]
		n.visible = t < 1.0
		var k := float(s.get("big", 1.0))
		n.scale = Vector3(1.0 + t * 3.2, 0.7 + t * 1.2, 1.0 + t * 3.2) * k
		(n.material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - t)

# ---------------------------------------------------------------- whale spout
func _build_whale() -> void:
	_spout = GPUParticles3D.new()
	_spout.amount = 70
	_spout.lifetime = 2.4
	_spout.one_shot = true
	_spout.emitting = false
	_spout.explosiveness = 0.35
	_spout.local_coords = false
	_spout.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, -7.0, 0)
	pm.scale_min = 2.5
	pm.scale_max = 5.5
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.55))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = ramp
	pm.color_ramp = gt
	_spout.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2.ONE
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(0.92, 0.96, 1.0)
	q.material = qm
	_spout.draw_pass_1 = q
	_spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spout)
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 10; sm.rings = 5
	_whale_back = MeshInstance3D.new()
	_whale_back.mesh = sm
	_whale_back.material_override = _mat(Color(0.1, 0.13, 0.17), 0.35)
	_whale_back.scale = Vector3(3.2, 2.6, 11.0)
	_whale_back.visible = false
	_whale_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_whale_back)

func _tick_whale(dt: float) -> void:
	var w := WorldState
	if _whale_left <= 0:
		_whale_next -= dt
		if _whale_next <= 0.0 and w.daylight > 0.25 and w.storm < 0.6:
			var fwd := _ship_fwd()
			var dir := fwd.rotated(Vector3.UP, randf_range(0.5, 1.2) * (1.0 if randf() < 0.5 else -1.0))
			var p := _ship.global_position + dir * randf_range(170.0, 300.0)
			_whale_pos = Vector3(p.x, 0.0, p.z)
			_whale_left = randi_range(2, 4)
			_whale_t = 0.0
			_whale_next = randf_range(60.0, 140.0) if not _force else 20.0
		elif _whale_next <= 0.0:
			_whale_next = 10.0
	if _whale_left > 0:
		_whale_t += dt
		var sea := Waves.height_at(_whale_pos.x, _whale_pos.z)
		var up := sin(clampf(_whale_t / 3.0, 0.0, 1.0) * PI)
		_whale_back.visible = up > 0.05
		_whale_back.global_position = Vector3(_whale_pos.x, sea - 1.9 + up * 1.7, _whale_pos.z)
		_whale_back.look_at(_whale_back.global_position + _ship_fwd().rotated(Vector3.UP, 1.4), Vector3.UP)
		if _whale_t > 0.8 and not _spout.emitting and _spout.get_meta("shot", -1) != _whale_left:
			_spout.set_meta("shot", _whale_left)
			_spout.global_position = Vector3(_whale_pos.x, sea + 1.0, _whale_pos.z)
			_spout.restart()
			_spout.emitting = true
		if _whale_t > 6.5:
			_whale_left -= 1
			_whale_t = 0.0
			_whale_pos += _ship_fwd().rotated(Vector3.UP, 1.2) * 38.0
			_whale_back.visible = false

# ---------------------------------------------------------------- passing ship on the horizon
func _build_far_ship() -> Node3D:
	var n := Node3D.new()
	var hull := MeshInstance3D.new(); var hb := BoxMesh.new(); hb.size = Vector3(9.0, 4.0, 34.0); hull.mesh = hb
	hull.material_override = _mat(Color(0.09, 0.07, 0.06)); hull.position = Vector3(0, 2.0, 0); n.add_child(hull)
	var bow := MeshInstance3D.new(); var pb := PrismMesh.new(); pb.size = Vector3(9.0, 4.0, 8.0); bow.mesh = pb
	bow.material_override = hull.material_override; bow.rotation.x = deg_to_rad(-90.0); bow.position = Vector3(0, 2.0, -21.0)
	n.add_child(bow)
	var sail_mat := _mat(Color(0.72, 0.68, 0.6), 0.9)
	var mast_mat := _mat(Color(0.1, 0.08, 0.07))
	for mz in [-10.0, 1.0, 11.0]:
		var mast := MeshInstance3D.new(); var mc := CylinderMesh.new(); mc.top_radius = 0.3; mc.bottom_radius = 0.5; mc.height = 34.0; mast.mesh = mc
		mast.material_override = mast_mat; mast.position = Vector3(0, 17.0, mz); n.add_child(mast)
		for tier in 3:
			var s := MeshInstance3D.new(); var sb := BoxMesh.new(); sb.size = Vector3(11.0 - tier * 2.5, 7.0 - tier * 0.8, 0.35); s.mesh = sb
			s.material_override = sail_mat; s.position = Vector3(0, 9.0 + tier * 8.0, mz - 0.6); n.add_child(s)
	_far_mat_lantern = StandardMaterial3D.new()
	_far_mat_lantern.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_far_mat_lantern.albedo_color = Color(1.0, 0.72, 0.3)
	_far_mat_lantern.disable_fog = true
	_far_lanterns.clear()
	for lp in [Vector3(0, 6.5, 16.0), Vector3(0, 9.0, -10.0), Vector3(0, 8.0, 1.0)]:
		var l := MeshInstance3D.new(); var ls := SphereMesh.new(); ls.radius = 1.2; ls.height = 2.4; ls.radial_segments = 8; ls.rings = 4; l.mesh = ls
		l.material_override = _far_mat_lantern; l.position = lp; n.add_child(l); _far_lanterns.append(l)
	n.scale = Vector3.ONE * randf_range(1.0, 1.6)
	return n

func _tick_far_ship(dt: float) -> void:
	var w := WorldState
	if _far == null:
		_ship_next -= dt
		if _ship_next <= 0.0:
			var sp := _ship.global_position
			var ang := randf() * TAU
			var dist := randf_range(1300.0, 2000.0)
			if "--far-ship-test" in OS.get_cmdline_user_args(): # test aid: 1.1 km ahead, `--far-ship-angle=<rad>` off the heading
				var ff := _ship_fwd()
				var off := 0.45
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--far-ship-angle="):
						off = float(a.get_slice("=", 1))
				ang = atan2(ff.z, ff.x) + off
				dist = 1100.0
			_far = _build_far_ship()
			add_child(_far)
			_far.position = Vector3(sp.x + cos(ang) * dist, 0.0, sp.z + sin(ang) * dist)
			# Moves roughly across the line of sight, slowly.
			var tang := Vector3(-sin(ang), 0, cos(ang)) * (1.0 if randf() < 0.5 else -1.0)
			_far_vel = tang.rotated(Vector3.UP, randf_range(-0.4, 0.4)) * randf_range(4.0, 7.0)
			_far.look_at(_far.position + _far_vel, Vector3.UP)
			_far.rotate_object_local(Vector3.UP, PI) # bow (-Z of the model) points along the velocity
			if "--far-ship-test" in OS.get_cmdline_user_args():
				print("[ambient] far ship spawned at ", _far.position - sp, " dist=", snappedf(dist, 1.0), " ship_fwd=", _ship_fwd())
	else:
		_far.position += _far_vel * dt
		var sp := _ship.global_position
		_far.position.y = Waves.height_at(_far.position.x, _far.position.z) * 0.6 + sin(_t * 0.4) * 0.15
		var lit := w.night > 0.15 or w.storm > 0.6
		# Lanterns would be 1-2 px at 1-2 km: grow them with distance so the running lights read as points of light.
		var dist := (_far.position - sp).length()
		var ls := maxf(1.0, dist * 0.0035 / (1.2 * _far.scale.x))
		for l in _far_lanterns:
			l.visible = lit
			l.scale = Vector3.ONE * ls
		if (_far.position - sp).length() > 2800.0:
			_far.queue_free()
			_far = null
			_ship_next = randf_range(80.0, 180.0) if not _force else 40.0

func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	_t += dt
	if has_meta("flotsam_test") and int(_t * 2.0) != int((_t - dt) * 2.0):
		var ft: Dictionary = get_meta("flotsam_test")
		var rl: Vector3 = (ft["pos"] as Vector3) - _ship.global_position
		var hf := _hull_fwd()
		print("[flotsam-test] t=%.1f along=%.1f side=%.1f push_vel=%.2f dip=%.2f yaw=%.0f ship_speed=%.1f" % [_t, rl.dot(hf), rl.dot(Vector3(-hf.z, 0, hf.x)),
			(ft["vel"] as Vector3).length(), ft["dip"], rad_to_deg(ft["yaw"]), _ship_vel().length()])
	_tick_flotsam(dt)
	_tick_dolphins(dt)
	_tick_splashes(dt)
	_tick_whale(dt)
	_tick_far_ship(dt)
	var w := WorldState
	_dol_next -= dt
	if _dol_next <= 0.0:
		if w.daylight > 0.45 and w.storm < 0.5:
			_start_dolphin_event()
			_dol_next = randf_range(40.0, 100.0) if not _force else 12.0
		else:
			_dol_next = 8.0
