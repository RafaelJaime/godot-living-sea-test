extends Node3D
## Passing ships (M4b1): a small pool of far ships on lanes 800-3000 m from the player ship, with low-poly silhouettes (or flat impostors),
## running lights at night and a real OmniLight only inside 300 m at `final`. A slot is recycled only after its ship left the range.
## Joins the group `ambient_system` (ambient_director.gd reports `passing_ships` in stats()); pool size = BASE * Quality.ambient_scale.
## Style is MIXED by distance: a 3D low-poly hull inside CROSS_NEAR, a flat camera-facing silhouette beyond CROSS_FAR, alpha cross-fade between
## the two (no pop). Test aids: `--passing-test=<style>,<count>,<dist>[,<spread_deg>]` places `count` ships `dist` m ahead (fixed, still),
## style = mixed | hull | flat; `--passing-cross=<speed>` one ship starts 2000 m ahead and comes in at that speed (logs `[passing_ships] cross`);
## `--passing-style=mixed|hull|flat` forces the style of the live pool; `--no-passing` disables.

const BASE := 4
const RANGE_MIN := 800.0
const RANGE_MAX := 3000.0
const LEAVE := 3300.0
const LIGHT_RANGE := 300.0
const CROSS_NEAR := 1050.0 ## below: hull only
const CROSS_FAR := 1350.0 ## above: flat only (centre 1200 m)

@export var ship_path := NodePath("../Ship")
var style := "mixed"
var _cross_speed := 0.0
var _ship: Node3D
var _slots: Array[Dictionary] = []
var _mat_light := {}
var _t := 0.0
var _test := false
var _recycled := 0
var _log_recycle := false

func _ready() -> void:
	if "--no-passing" in OS.get_cmdline_user_args():
		queue_free()
		return
	add_to_group("rebase")
	add_to_group("ambient_system")
	_ship = get_node(ship_path)
	var count := maxi(1, int(round(BASE * Quality.ambient_scale)))
	var test_dist := 0.0
	var spread := 24.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--passing-style="):
			style = a.get_slice("=", 1)
		elif a.begins_with("--passing-test="):
			var p := a.get_slice("=", 1).split(",")
			style = p[0]
			count = int(p[1])
			test_dist = float(p[2])
			spread = float(p[3]) if p.size() > 3 else 24.0
			_test = true
		elif a.begins_with("--passing-cross="):
			_cross_speed = float(a.get_slice("=", 1))
			count = 1
			test_dist = 2000.0
			spread = 0.0
			_test = true
		elif a == "--passing-log":
			_log_recycle = true
	_mat_light[&"white"] = _glow(Color(1.0, 0.9, 0.6))
	_mat_light[&"red"] = _glow(Color(1.0, 0.1, 0.05))
	_mat_light[&"green"] = _glow(Color(0.1, 1.0, 0.3))
	for i in count:
		var s := _build()
		add_child(s)
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.75, 0.4)
		omni.omni_range = 60.0
		omni.light_energy = 2.0
		omni.shadow_enabled = false
		omni.visible = false
		omni.position = Vector3(0, 9, 0)
		s.add_child(omni)
		var slot := {"node": s, "vel": Vector3.ZERO, "active": false, "wait": randf_range(5.0, 150.0), "omni": omni, "lights": s.get_meta("lights")}
		_slots.append(slot)
		s.visible = false
		if _test:
			_place_test(slot, i, count, test_dist, spread)
		elif randf() < 0.55:
			_spawn(slot, true) # part of the traffic is already under way at start: scattered, never a regular line-up

func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # silhouette: the scene fog does the aerial perspective
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # per-ship alpha drives the hull <-> flat cross-fade
	return m

func _glow(c: Color) -> StandardMaterial3D:
	var m := _unshaded(c)
	m.disable_fog = true
	return m

func rebase(shift: Vector3) -> void:
	for s in _slots:
		(s["node"] as Node3D).global_position -= shift

# ---------------------------------------------------------------- geometry
const HULL_COL := Color(0.07, 0.06, 0.055)
const SAIL_COL := Color(0.62, 0.58, 0.5)

## One ship = hull group (3D) + flat group (impostor) + running lights, each style with its own materials (per-ship alpha).
func _build() -> Node3D:
	var n := Node3D.new()
	var m_hull := _unshaded(HULL_COL)
	var m_sail := _unshaded(SAIL_COL)
	var m_flat := _unshaded(SAIL_COL)
	var hull_root := Node3D.new()
	var flat_root := Node3D.new()
	n.add_child(hull_root)
	n.add_child(flat_root)
	# Flat impostor: hull trapezoid + three mast tiers of sails in one thin double-sided mesh, side view along X.
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(s, [Vector3(-17, 0, 0), Vector3(17, 0, 0), Vector3(21, 5, 0), Vector3(-19, 4.2, 0)])
	for mx in [-9.0, 1.5, 11.0]:
		for tier in 3:
			var w := 5.5 - tier * 1.0
			var y0 := 6.0 + tier * 7.5
			_quad(s, [Vector3(mx - w, y0, 0), Vector3(mx + w, y0, 0), Vector3(mx + w - 0.8, y0 + 6.6, 0), Vector3(mx - w + 0.8, y0 + 6.6, 0)])
		_quad(s, [Vector3(mx - 0.25, 4, 0), Vector3(mx + 0.25, 4, 0), Vector3(mx + 0.25, 31, 0), Vector3(mx - 0.25, 31, 0)])
	var fm := MeshInstance3D.new()
	fm.mesh = s.commit()
	fm.material_override = m_flat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flat_root.add_child(fm)
	# Low-poly hull: box hull + prism bow + masts + box sails.
	var hull := MeshInstance3D.new(); var hb := BoxMesh.new(); hb.size = Vector3(9.0, 4.0, 34.0); hull.mesh = hb
	hull.material_override = m_hull; hull.position = Vector3(0, 2.0, 0); hull_root.add_child(hull)
	var bow := MeshInstance3D.new(); var pb := PrismMesh.new(); pb.size = Vector3(9.0, 4.0, 8.0); bow.mesh = pb
	bow.material_override = m_hull; bow.rotation.x = deg_to_rad(-90.0); bow.position = Vector3(0, 2.0, -21.0); hull_root.add_child(bow)
	for mz in [-10.0, 1.0, 11.0]:
		var mast := MeshInstance3D.new(); var mc := CylinderMesh.new(); mc.top_radius = 0.3; mc.bottom_radius = 0.5; mc.height = 34.0; mc.radial_segments = 5
		mast.mesh = mc; mast.material_override = m_hull; mast.position = Vector3(0, 17.0, mz); hull_root.add_child(mast)
		for tier in 3:
			var sl := MeshInstance3D.new(); var sb := BoxMesh.new(); sb.size = Vector3(11.0 - tier * 2.5, 7.0 - tier * 0.8, 0.35); sl.mesh = sb
			sl.material_override = m_sail; sl.position = Vector3(0, 9.0 + tier * 8.0, mz - 0.6); hull_root.add_child(sl)
	var lights: Array[MeshInstance3D] = []
	lights.append(_light(n, Vector3(0, 6.5, 16.0), &"white"))
	lights.append(_light(n, Vector3(-4.6, 4.5, -8.0), &"red"))
	lights.append(_light(n, Vector3(4.6, 4.5, -8.0), &"green"))
	lights.append(_light(n, Vector3(0, 33.0, 1.0), &"white"))
	n.set_meta("lights", lights)
	n.set_meta("parts", {"hull_root": hull_root, "flat_root": flat_root, "m_hull": m_hull, "m_sail": m_sail, "m_flat": m_flat})
	return n

func _quad(s: SurfaceTool, p: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		s.add_vertex(p[i])

func _light(parent: Node3D, pos: Vector3, kind: StringName) -> MeshInstance3D:
	var l := MeshInstance3D.new()
	var sp := SphereMesh.new(); sp.radius = 1.0; sp.height = 2.0; sp.radial_segments = 6; sp.rings = 3
	l.mesh = sp
	l.material_override = _mat_light[kind]
	l.position = pos
	l.visible = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l

# ---------------------------------------------------------------- placement and motion
func _fwd() -> Vector3:
	var f := Vector3.ZERO
	if _ship is RigidBody3D:
		f = (_ship as RigidBody3D).linear_velocity
	if f.length() < 0.5:
		f = -_ship.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _place_test(slot: Dictionary, i: int, count: int, dist: float, spread_deg: float) -> void:
	var fwd := _fwd()
	var a := deg_to_rad(lerpf(-spread_deg, spread_deg, (float(i) + 0.5) / float(count)))
	var sp := _ship.global_position
	var n := slot["node"] as Node3D
	n.visible = true
	n.position = Vector3(sp.x, 0, sp.z) + fwd.rotated(Vector3.UP, a) * (dist * (1.0 + 0.12 * float(i % 2)))
	n.look_at(n.position + fwd.rotated(Vector3.UP, a + PI * 0.5), Vector3.UP) # broadside to the player
	n.rotate_object_local(Vector3.UP, PI)
	slot["active"] = true
	if _cross_speed > 0.0:
		slot["vel"] = -fwd * _cross_speed # comes straight in so the 1200 m hand-over is crossed at a known time

func _spawn(slot: Dictionary, anywhere := false) -> void:
	var fwd := _fwd()
	var sp := _ship.global_position
	# Prefer the forward half so ships are seen; lanes cross the line of sight at 4-9 m/s.
	var ang := atan2(fwd.z, fwd.x) + randf_range(-1.7, 1.7)
	if anywhere:
		ang = randf() * TAU
	var dist := RANGE_MIN + (RANGE_MAX - RANGE_MIN) * pow(randf(), 0.8) # spread over the whole 800-3000 m band
	for other in _slots: # keep apart from the others: not in the same spot or line of sight
		if other != slot and other["active"]:
			var o := (other["node"] as Node3D).position
			for _try in 6:
				var cand := Vector3(sp.x + cos(ang) * dist, 0.0, sp.z + sin(ang) * dist)
				if Vector2(cand.x - o.x, cand.z - o.z).length() > 350.0 and absf(angle_difference(ang, atan2(o.z - sp.z, o.x - sp.x))) > 0.12:
					break
				ang = atan2(fwd.z, fwd.x) + randf_range(-1.7, 1.7) if not anywhere else randf() * TAU
				dist = randf_range(RANGE_MIN, RANGE_MAX)
	var n := slot["node"] as Node3D
	n.position = Vector3(sp.x + cos(ang) * dist, 0.0, sp.z + sin(ang) * dist)
	var tang := Vector3(-sin(ang), 0, cos(ang)) * (1.0 if randf() < 0.5 else -1.0)
	slot["vel"] = tang.rotated(Vector3.UP, randf_range(-0.9, 0.9)) * randf_range(3.0, 10.0)
	n.look_at(n.position + (slot["vel"] as Vector3), Vector3.UP)
	n.rotate_object_local(Vector3.UP, PI)
	var sc := randf_range(0.7, 1.7)
	n.scale = Vector3.ONE * sc
	n.visible = true
	slot["active"] = true

func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	_t += dt
	var w := WorldState
	var day := clampf(w.daylight, 0.0, 1.0)
	var lit := w.night > 0.15 or w.storm > 0.6
	var sp := _ship.global_position
	var cam := get_viewport().get_camera_3d()
	for slot in _slots:
		var n := slot["node"] as Node3D
		if not slot["active"]:
			if _test:
				continue
			slot["wait"] = float(slot["wait"]) - dt
			if float(slot["wait"]) <= 0.0:
				_spawn(slot)
			continue
		if not _test or _cross_speed > 0.0:
			n.position += (slot["vel"] as Vector3) * dt
		var dist := Vector2(n.global_position.x - sp.x, n.global_position.z - sp.z).length()
		n.position.y = Waves.height_at(n.position.x, n.position.z) * 0.6 + sin(_t * 0.4 + float(n.get_instance_id() % 7)) * 0.15
		var parts: Dictionary = n.get_meta("parts")
		var flat_a := smoothstep(CROSS_NEAR, CROSS_FAR, dist) # 0 = hull only, 1 = flat only
		if style == "hull":
			flat_a = 0.0
		elif style == "flat":
			flat_a = 1.0
		(parts["hull_root"] as Node3D).visible = flat_a < 0.999
		(parts["flat_root"] as Node3D).visible = flat_a > 0.001
		var hc := HULL_COL * (0.2 + 0.8 * day)
		var sc := SAIL_COL * (0.12 + 0.88 * day)
		(parts["m_hull"] as StandardMaterial3D).albedo_color = Color(hc.r, hc.g, hc.b, 1.0 - flat_a)
		(parts["m_sail"] as StandardMaterial3D).albedo_color = Color(sc.r, sc.g, sc.b, 1.0 - flat_a)
		(parts["m_flat"] as StandardMaterial3D).albedo_color = Color(sc.r, sc.g, sc.b, flat_a)
		if flat_a > 0.001 and cam:
			# Impostor: turn the flat silhouette to face the camera (world yaw) while the hull keeps the ship heading.
			var to := cam.global_position - n.global_position
			(parts["flat_root"] as Node3D).global_rotation.y = atan2(to.x, to.z)
		if _cross_speed > 0.0 and int(_t * 2.0) != int((_t - dt) * 2.0):
			print("[passing_ships] cross t=", snappedf(_t, 0.1), " dist=", snappedf(dist, 1.0), " flat_alpha=", snappedf(flat_a, 0.01))
		# Running lights would be 1-2 px at km range: grow them with distance so they read as points of light.
		var ls := maxf(1.0, dist * 0.0035 / maxf(n.scale.x, 0.1))
		for l: MeshInstance3D in slot["lights"]:
			l.visible = lit
			l.scale = Vector3.ONE * ls
		(slot["omni"] as OmniLight3D).visible = lit and dist < LIGHT_RANGE and Quality.name_ == "final"
		if not _test and dist > LEAVE:
			n.visible = false
			slot["active"] = false
			slot["wait"] = randf_range(15.0, 140.0)
			_recycled += 1
			if _log_recycle:
				print("[passing_ships] recycled slot after leaving range dist=", snappedf(dist, 1.0), " total=", _recycled)

# ---------------------------------------------------------------- director hooks
func ambient_pools() -> Dictionary:
	return {"passing_ships": _slots.size()}

func ambient_stats() -> Dictionary:
	var a := 0
	for s in _slots:
		if s["active"]:
			a += 1
	return {"passing_ships": a}
