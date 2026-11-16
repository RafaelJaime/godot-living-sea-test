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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dolphin-min-speed="):
			dolphin_min_speed = float(a.get_slice("=", 1))
	add_to_group("rebase")
	add_to_group("ambient_system")
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
	var plank := _plank_mesh()
	var barrel := _barrel_mesh()
	var weed_meshes: Array[ArrayMesh] = [_weed_patch_mesh(11), _weed_patch_mesh(23), _weed_patch_mesh(37)]
	var wood := _wood_mat(Color(0.62, 0.56, 0.5))
	var iron := _iron_mat()
	var wood_two_sided := wood
	# Seaweed: translucent, irregular, vertex-coloured patches (darker olive core fading to a pale transparent rim), half drowned in the swell.
	var weed := StandardMaterial3D.new()
	weed.vertex_color_use_as_albedo = true
	weed.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	weed.cull_mode = BaseMaterial3D.CULL_DISABLED
	weed.roughness = 0.9
	for i in _flot_count():
		var n := Node3D.new()
		var kind := i % 4
		if kind == 0:
			var m := MeshInstance3D.new(); m.mesh = plank; m.material_override = wood; n.add_child(m)
			n.add_child(_contact_foam(Vector2(3.2, 0.9), 0.03))
		elif kind == 1:
			var m := MeshInstance3D.new(); m.mesh = barrel; m.rotation.z = deg_to_rad(80.0)
			m.set_surface_override_material(0, wood_two_sided); m.set_surface_override_material(1, iron); n.add_child(m)
			n.add_child(_contact_foam(Vector2(1.4, 1.1), 0.13))
		else:
			var m := MeshInstance3D.new(); m.mesh = weed_meshes[i % weed_meshes.size()]; m.material_override = weed
			m.scale = Vector3.ONE * randf_range(0.8, 1.6)
			m.rotation.y = randf() * TAU
			n.add_child(m)
		add_child(n)
		_flot.append({"node": n, "pos": Vector3.ZERO, "spin": randf_range(-0.15, 0.15), "yaw": randf() * TAU, "kind": kind,
			"vel": Vector3.ZERO, "spinv": 0.0, "dip": 0.0, "radius": 1.2 if kind == 0 else (0.5 if kind == 1 else 1.6)})
		_respawn_flot(_flot[i], true)

## One irregular seaweed patch: 3-5 lobes of 14-point noisy polygons with a slight dome, plus a few thin trailing strands.
func _weed_patch_mesh(seed_i: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var core := Color(0.075, 0.052, 0.018, 0.88)
	var rim := Color(0.115, 0.082, 0.032, 0.05)
	for lobe in rng.randi_range(3, 5):
		var c := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
		var r := rng.randf_range(0.4, 0.95)
		var pts := PackedVector3Array()
		var n := 14
		var phase := rng.randf() * TAU
		for k in n:
			var a := float(k) / n * TAU
			var rr := r * (0.55 + 0.6 * rng.randf()) * (1.0 + 0.25 * sin(a * 3.0 + phase))
			pts.append(c + Vector3(cos(a) * rr, rng.randf_range(-0.02, 0.02), sin(a) * rr * 0.8))
		var top := c + Vector3(0, 0.07, 0)
		for k in n:
			var p0 := pts[k]
			var p1 := pts[(k + 1) % n]
			for v in [[top, core], [p0, rim], [p1, rim]]:
				st.set_color(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	for sI in rng.randi_range(3, 6):
		var a0 := rng.randf() * TAU
		var o := Vector3(cos(a0), 0.0, sin(a0)) * rng.randf_range(0.2, 0.9)
		var dir := Vector3(cos(a0 + rng.randf_range(-0.6, 0.6)), 0.0, sin(a0 + rng.randf_range(-0.6, 0.6)))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.04
		var len := rng.randf_range(0.5, 1.2)
		for v in [[o - side, core], [o + side, core], [o + dir * len, rim]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()

## Height of the node origin above the local surface: the plank rides almost awash, the barrel (r 0.27 m) sits about two thirds
## under, the seaweed just under the film.
func _waterline(kind: int) -> float:
	match kind:
		0: return -0.025
		1: return -0.10
	return 0.0

## Soft foam ring at the waterline of a floating prop: a flat dot sprite of the given size, a hair above the surface.
func _contact_foam(size: Vector2, y: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_dot()
	m.albedo_color = Color(0.92, 0.97, 1.0, 0.28)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Aged, wet, dark wood (Poly Haven "Dark Wooden Planks", CC0, 1k) tinted darker; used by planks and barrel staves.
func _wood_mat(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/ambient/flotsam/dwp_diff.jpg") as Texture2D
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/ambient/flotsam/dwp_nor_gl.jpg") as Texture2D
	m.roughness_texture = load("res://assets/ambient/flotsam/dwp_rough.jpg") as Texture2D
	m.roughness = 0.75
	m.clearcoat_enabled = true # waterlogged sheen
	m.clearcoat = 0.35
	m.clearcoat_roughness = 0.25
	m.uv1_triplanar = false
	return m

func _iron_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.075, 0.065)
	m.metallic = 0.75
	m.roughness = 0.55
	return m

## Broken plank: 2.4 x 0.28 x 0.07 m, bowed and slightly twisted, one square end and one jagged break; UVs run along the grain.
func _plank_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 2.4
	var W := 0.28
	var T := 0.07
	var segs := 8
	var rows: Array = []
	for i in segs + 1:
		var u := float(i) / segs
		var x := (u - 0.5) * L
		var bow := 0.05 * sin(u * PI)
		var tw := 0.08 * (u - 0.5)
		var hw := W * 0.5 * (1.0 - (0.35 * smoothstep(0.78, 1.0, u) * rng.randf_range(0.5, 1.0)))
		rows.append([x, bow, tw, hw, u])
	var corners := func(r: Array) -> Array:
		var x: float = r[0]
		return [Vector3(x, r[1] + T * 0.5, -r[3] + r[2]), Vector3(x, r[1] + T * 0.5, r[3] + r[2]), Vector3(x, r[1] - T * 0.5, r[3] + r[2]), Vector3(x, r[1] - T * 0.5, -r[3] + r[2])]
	for i in segs:
		var c0: Array = corners.call(rows[i])
		var c1: Array = corners.call(rows[i + 1])
		var u0: float = rows[i][4] * 2.0
		var u1: float = rows[i + 1][4] * 2.0
		# top, bottom, two sides
		for q in [[0, 1], [1, 2], [2, 3], [3, 0]]:
			var a: int = q[0]
			var b: int = q[1]
			var nrm: Vector3 = ((c0[b] as Vector3) - (c0[a] as Vector3)).cross((c1[a] as Vector3) - (c0[a] as Vector3)).normalized()
			for v in [[c0[a], Vector2(u0, 0.0)], [c1[a], Vector2(u1, 0.0)], [c0[b], Vector2(u0, 0.25)], [c0[b], Vector2(u0, 0.25)], [c1[a], Vector2(u1, 0.0)], [c1[b], Vector2(u1, 0.25)]]:
				st.set_normal(nrm)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	# end caps
	for end in [0, segs]:
		var c: Array = corners.call(rows[end])
		var nrm: Vector3 = Vector3(-1, 0, 0) if end == 0 else Vector3(1, 0, 0)
		for idx in ([0, 1, 2, 0, 2, 3] if end == 0 else [0, 2, 1, 0, 3, 2]):
			st.set_normal(nrm)
			st.set_uv(Vector2(0.0, 0.1))
			st.add_vertex(c[idx])
	st.generate_tangents()
	return st.commit()

## Barrel: bulged lathe (16 staves) lying on its side, with three iron hoops; surface 0 wood, surface 1 iron.
func _barrel_mesh() -> ArrayMesh:
	var h := 0.72
	var rings := 10
	var sides := 16
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := func(t: float) -> float: # t in -1..1 along the axis
		return 0.27 * (1.0 - 0.2 * t * t)
	for r in rings:
		var t0 := -1.0 + 2.0 * float(r) / rings
		var t1 := -1.0 + 2.0 * float(r + 1) / rings
		for k in sides:
			var a0 := float(k) / sides * TAU
			var a1 := float(k + 1) / sides * TAU
			var pts := [[t0, a0], [t0, a1], [t1, a0], [t1, a1]]
			var vs := []
			for p in pts:
				var rad: float = prof.call(p[0])
				var pos := Vector3(cos(p[1]) * rad, p[0] * h * 0.5, sin(p[1]) * rad)
				var nrm := Vector3(cos(p[1]), -p[0] * 0.2 * 0.6, sin(p[1])).normalized()
				vs.append([pos, nrm, Vector2(float(k) / sides * 2.0, (p[0] * 0.5 + 0.5) * 1.0)])
			for idx in [0, 1, 2, 1, 3, 2]:
				wood.set_normal(vs[idx][1])
				wood.set_uv(vs[idx][2])
				wood.add_vertex(vs[idx][0])
	for sgn in [-1.0, 1.0]: # lids
		var rad: float = prof.call(sgn)
		for k in sides:
			var a0 := float(k) / sides * TAU
			var a1 := float(k + 1) / sides * TAU
			var lid := [Vector3(0, sgn * h * 0.5, 0), Vector3(cos(a0) * rad * 0.97, sgn * h * 0.5, sin(a0) * rad * 0.97), Vector3(cos(a1) * rad * 0.97, sgn * h * 0.5, sin(a1) * rad * 0.97)]
			if sgn > 0.0:
				lid = [lid[0], lid[2], lid[1]]
			for v in lid:
				wood.set_normal(Vector3(0, sgn, 0))
				wood.set_uv(Vector2(0.5 + v.x * 1.5, 0.5 + v.z * 1.5))
				wood.add_vertex(v)
	wood.generate_tangents()
	var mesh := wood.commit()
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ty in [-0.78, -0.3, 0.3, 0.78]:
		var hw := 0.028
		for sub in [-1.0, 1.0]:
			pass
		var rad_c: float = prof.call(ty) + 0.008
		var y0: float = ty * h * 0.5 - hw
		var y1: float = ty * h * 0.5 + hw
		for k in sides:
			var a0 := float(k) / sides * TAU
			var a1 := float(k + 1) / sides * TAU
			var q := [Vector3(cos(a0) * rad_c, y0, sin(a0) * rad_c), Vector3(cos(a1) * rad_c, y0, sin(a1) * rad_c), Vector3(cos(a0) * rad_c, y1, sin(a0) * rad_c), Vector3(cos(a1) * rad_c, y1, sin(a1) * rad_c)]
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			for idx in [0, 1, 2, 1, 3, 2]:
				iron.set_normal(n0 if idx in [0, 2] else n1)
				iron.add_vertex(q[idx])
	iron.commit(mesh)
	return mesh

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
		node.global_position = Vector3(p.x, h + _waterline(int(f["kind"])) - 0.22 * float(f["dip"]), p.z)
		node.rotation = Vector3(-hz * 0.8, float(f["yaw"]), hx * 0.8)

# ---------------------------------------------------------------- dolphins
## Real dolphin: Sketchfab "Dolphin" by Alex_Pfe (CC BY 4.0, see ATTRIBUTION.md), converted by export_dolphin.py (swim loop, 1k textures).
## The model faces +Z with its origin 0.5 m above the body centre; DOLPHIN_SCALE brings the 3.1 m model to about 2.5 m.
const DOLPHIN_GLB := "res://assets/ambient/dolphin/dolphin.glb"
const DOLPHIN_SCALE := 0.8
const POD_MAX := 5
const FLOTSAM_BASE := 16
## Pods only pace the bow above this ship speed (m/s; 1.5 so slow ships get company too); `--dolphin-min-speed=<m/s>` overrides it for tests.
var dolphin_min_speed := 1.5

func _build_dolphins() -> void:
	var packed := load(DOLPHIN_GLB) as PackedScene
	for i in _pod_max():
		var n := Node3D.new()
		var model: Node3D = packed.instantiate()
		model.rotation.y = PI # the model's nose is +Z, look_at points -Z along the velocity
		model.scale = Vector3.ONE * DOLPHIN_SCALE
		model.position = Vector3(0.0, 0.5, 0.15) * DOLPHIN_SCALE
		for m in model.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # small, fast, mostly airborne
		n.add_child(model)
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var anim := ap.get_animation(&"swim")
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(&"swim")
			ap.pause()
		n.visible = false
		add_child(n)
		_dolphins.append({"node": n, "ap": ap, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "state": 0, "t": -1.0, "swim_for": 2.0, "left": 0, "delay": 0.0,
			"lat": 0.0, "ahead": 0.0, "phase": randf() * 2.0})
	# Splashes: a pool of one-shot droplet bursts (small soft billboards that arc up, fall and fade), not flat discs.
	var drop := QuadMesh.new(); drop.size = Vector2(0.22, 0.22)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = _soft_dot()
	dm.disable_fog = false
	drop.material = dm
	for i in 8:
		var g := GPUParticles3D.new()
		g.amount = maxi(int(36 * Quality.particle_scale), 8)
		g.lifetime = 1.0
		g.one_shot = true
		g.explosiveness = 0.95
		g.emitting = false
		g.local_coords = false
		g.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 10, 16))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.5
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 55.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 5.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.85))
		ramp.set_color(1, Color(0.9, 0.96, 1.0, 0.0))
		var rt := GradientTexture1D.new(); rt.gradient = ramp
		pm.color_ramp = rt
		g.process_material = pm
		g.draw_pass_1 = drop
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_splashes.append({"node": g, "t": 9.0})

## Radial soft white dot used as the droplet sprite.
func _soft_dot() -> Texture2D:
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = gr
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t

func _splash(at: Vector3, big: float) -> void:
	Audio.play_at(&"splash", Vector3(at.x, Waves.height_at(at.x, at.z), at.z), {"db": 3.0 * (big - 1.0), "pitch": 1.0 / maxf(big, 0.7)})
	for sp in _splashes:
		if float(sp["t"]) >= 1.0:
			sp["t"] = 0.0
			var g: GPUParticles3D = sp["node"]
			g.global_position = Vector3(at.x, Waves.height_at(at.x, at.z) + 0.1, at.z)
			(g.process_material as ParticleProcessMaterial).initial_velocity_max = 3.5 + 2.0 * big
			g.restart()
			g.emitting = true
			return

func _start_dolphin_event() -> void:
	# A pod of 2-5 riding the bow wave: they swim just ahead of the stem on both sides, alternate swimming and leaps, then peel off.
	var fwd := _ship_fwd()
	var count := randi_range(mini(2, _dolphins.size()), _dolphins.size())
	print("[ambient] dolphin pod of ", count, " at t=", snappedf(_t, 0.1))
	for i in _dolphins.size():
		var d: Dictionary = _dolphins[i]
		d["left"] = randi_range(2, 4) if i < count else 0
		d["delay"] = float(i) * 0.4
		d["lat"] = (4.5 + floorf(i * 0.5) * 3.0 + randf_range(0.0, 1.5)) * (1.0 if i % 2 == 0 else -1.0)
		d["ahead"] = 16.0 + float(i) * 2.5 + randf_range(0.0, 3.0)
		d["state"] = 0
		d["t"] = -1.0
		var sp := _ship.global_position + fwd * float(d["ahead"]) + fwd.cross(Vector3.UP) * float(d["lat"])
		d["pos"] = Vector3(sp.x, Waves.height_at(sp.x, sp.z) - 1.6, sp.z)
		d["vel"] = _ship_vel()

## state 0 = swimming at the surface (back awash, tracks the bow zone), 1 = leap (ballistic), 2 = peeling off (diving away).
func _tick_dolphins(dt: float) -> void:
	var fwd := _ship_fwd()
	var right := fwd.cross(Vector3.UP)
	var sv := _ship_vel()
	var sspeed := maxf(sv.length(), 2.0)
	for d in _dolphins:
		var node: Node3D = d["node"]
		var ap: AnimationPlayer = d["ap"]
		if float(d["delay"]) > 0.0:
			d["delay"] = float(d["delay"]) - dt
			continue
		var t: float = d["t"]
		var pos: Vector3 = d["pos"]
		var v: Vector3 = d["vel"]
		var state: int = d["state"]
		if t < 0.0: # first frame of this pod member: surface and start swimming
			if int(d["left"]) <= 0:
				node.visible = false
				if ap: ap.pause()
				continue
			d["t"] = 0.0
			d["swim_for"] = randf_range(1.4, 3.0)
			node.visible = true
			t = 0.0
			state = 0
			d["state"] = 0
			_splash(pos + Vector3(0, 1.6, 0), 0.7)
		t += dt
		d["t"] = t
		var sea := Waves.height_at(pos.x, pos.z)
		if state == 0:
			# Ride the bow wave: chase a point ahead of the stem, back awash with a gentle porpoising bob.
			var tgt := _ship.global_position + fwd * (float(d["ahead"]) + 3.0 * sin(_t * 0.9 + float(d["phase"]))) + right * float(d["lat"])
			var want := Vector3(tgt.x, 0.0, tgt.z)
			var cur := Vector3(pos.x, 0.0, pos.z)
			var nv := sv + (want - cur) * 1.2
			nv = nv.limit_length(sspeed * 1.6 + 2.0)
			v = v.lerp(Vector3(nv.x, 0.0, nv.z), 1.0 - exp(-dt * 3.0))
			pos += v * dt
			sea = Waves.height_at(pos.x, pos.z)
			var bob := -0.25 + 0.35 * sin(_t * 2.6 + float(d["phase"]) * 3.0)
			pos.y = lerpf(pos.y, sea + bob, 1.0 - exp(-dt * 4.0))
			if t >= float(d["swim_for"]):
				if int(d["left"]) > 0:
					d["left"] = int(d["left"]) - 1
					state = 1
					# Launch from the surface: horizontal speed of the ship plus a push ahead, about 2.5 m of air.
					v = sv + fwd * randf_range(3.5, 5.5) + right * randf_range(-1.0, 1.0) + Vector3(0, randf_range(6.5, 8.0), 0)
					_splash(pos, 1.0)
				else:
					state = 2
		elif state == 1:
			v.y -= 9.81 * dt
			pos += v * dt
			sea = Waves.height_at(pos.x, pos.z)
			if v.y < 0.0 and pos.y < sea - 0.55:
				_splash(pos, 1.3)
				if int(d["left"]) > 0:
					# Re-enter and come back up swimming at the bow.
					state = 0
					d["swim_for"] = randf_range(1.0, 2.4)
					t = 0.0
					v = Vector3(v.x, 0.0, v.z) * 0.5
					pos.y = sea - 0.6
				else:
					state = 2
		else:
			v = v.lerp(Vector3(sv.x, -1.2, sv.z) * 0.8, 1.0 - exp(-dt * 2.0))
			pos += v * dt
			if pos.y < sea - 2.2:
				node.visible = false
				d["left"] = 0
				d["t"] = -1.0
				if ap: ap.pause()
				continue
		d["t"] = t
		if _force and d == _dolphins[0] and int(_t * 2.0) != int((_t - dt) * 2.0):
			print("[dolphin0] t=", snappedf(_t, 0.1), " state=", state, " rel=", snappedf(pos.x - _ship.global_position.x, 0.1), ",", snappedf(pos.y, 0.1), ",", snappedf(pos.z - _ship.global_position.z, 0.1), " sea=", snappedf(sea, 0.1))
		d["state"] = state
		d["pos"] = pos
		d["vel"] = v
		node.global_position = pos
		if v.length() > 0.2:
			node.look_at(pos + v, Vector3.UP)
		if ap:
			# Tail beat follows the speed: a fast loop while swimming, slower in the air.
			if not ap.is_playing():
				ap.play(&"swim")
			ap.speed_scale = clampf(v.length() / 4.0, 0.5, 2.0) * (0.6 if state == 1 else 1.0)

func _tick_splashes(dt: float) -> void:
	for sp in _splashes:
		if float(sp["t"]) < 1.0:
			sp["t"] = float(sp["t"]) + dt / 1.3

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
	if not "--far-ship-test" in OS.get_cmdline_user_args(): return # passing_ships.gd owns the passing ships now (M4b1)
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
		if w.daylight > 0.45 and w.storm < 0.5 and _ship_vel().length() >= dolphin_min_speed:
			_start_dolphin_event()
			_dol_next = randf_range(40.0, 100.0) if not _force else 12.0
		else:
			_dol_next = 8.0


# ---------------------------------------------------------------- director hooks (see ambient_director.gd)
func _flot_count() -> int:
	return maxi(4, int(round(FLOTSAM_BASE * Quality.ambient_scale)))

func _pod_max() -> int:
	return maxi(2, int(round(POD_MAX * Quality.ambient_scale)))

func ambient_pools() -> Dictionary:
	return {"flotsam": _flot.size(), "dolphins": _dolphins.size(), "splashes": _splashes.size(), "whale_spout": 1, "horizon_ship": 1}

func ambient_stats() -> Dictionary:
	var dol := 0
	for d in _dolphins:
		if (d["node"] as Node3D).visible:
			dol += 1
	var splash := 0
	for sp in _splashes:
		if float(sp["t"]) < 1.0:
			splash += 1
	return {"flotsam": _flot.size(), "dolphins": dol, "splashes": splash, "whale_spout": 1 if _whale_left > 0 else 0, "horizon_ship": 1 if _far != null else 0}
