extends Node
## Rig of the Poly Haven pinnace: shows the deployed sails (*_down) instead of the furled ones (*_top), turns them into
## wind-driven cloth (sail_cloth.gdshader), furls them in the worst storm and moves the rudder with Ship.rudder.

@export var ship_path := NodePath("../..")
@export var loader_path := NodePath("../Model")
@export var pivot_path := NodePath("..")
@export var furl_storm := 0.86 ## storminess above which the sails are furled
@export var furl_speed := 0.07 ## 1/s

class Sail:
	var mi: MeshInstance3D
	var mats: Array[ShaderMaterial] = []
	var seed := 0.0
	var gain := 1.0 # per-sail billow factor (topsails fill a bit less than courses)

var _sails: Array[Sail] = []
var _furled: Array[MeshInstance3D] = []
var _ship: Node
var _pivot: Node3D
var _skel: Skeleton3D
var _sail_bones: Array = []  # per sail: Array[int] bone indices
var _mast_ship: Array = []   # per sail: Vector3 mast position (ship/pivot space)
var _last_brace := 0.0
var _rudder_bone := -1
var _rudder_rest := Quaternion.IDENTITY
var _fill := 0.0
var _flutter := 0.3
var _furl := 0.0
var _time := 0.0

func _ready() -> void:
	_ship = get_node(ship_path)
	_pivot = get_node(pivot_path)
	get_node(loader_path).ship_ready.connect(_on_ship_ready)

func _on_ship_ready(_l: float, _b: float, _r: float) -> void:
	var model := get_node(loader_path)
	var shader := load("res://shaders/sail_cloth.gdshader") as Shader
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0]
		_rudder_bone = _skel.find_bone("def_rudder")
		if _rudder_bone >= 0:
			_rudder_rest = _skel.get_bone_rest(_rudder_bone).basis.get_rotation_quaternion()
	var pivot_inv := _pivot.global_transform.affine_inverse()
	var hidden := 0
	var cloth := 0
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := mi.name.to_lower()
		var is_sail := nm.contains("_sails_") or nm.contains("sailsmain")
		if is_sail and nm.ends_with("_top") or nm.ends_with("_course_top") or nm.contains("spritsail_top"):
			mi.visible = false
			hidden += 1
			_furled.append(mi)
			continue
		if nm.contains("rigging_") and not nm.contains("_down") and _has_down(model, nm):
			mi.visible = false
			hidden += 1
			continue
		if is_sail and nm.contains("_down"):
			_make_cloth(mi, shader, pivot_inv)
			cloth += 1
	var tot := 0.0
	if "sail_defs" in _ship:
		for d in _ship.sail_defs: tot += float(d["area"])
	print("[sails] total area m2=", snappedf(tot, 1.0), " cloth=", cloth, " hidden furled/duplicate=", hidden, " rudder_bone=", _rudder_bone)

func _has_down(model: Node, nm: String) -> bool:
	return model.find_child(nm + "_down", true, false) != null or model.find_child(nm.replace("geo_", "geo_") + "_down", true, false) != null

func _make_cloth(mi: MeshInstance3D, shader: Shader, pivot_inv: Transform3D) -> void:
	var to_ship: Transform3D = pivot_inv * mi.global_transform
	var box: AABB = to_ship * mi.get_aabb()
	var sail := Sail.new()
	sail.mi = mi
	sail.seed = randf() * 20.0
	sail.gain = 0.8 if box.size.y < 6.0 else 1.0
	# One cloth material per surface, each keeping its own textures (some sails mix sail and rope textures).
	for si in mi.mesh.get_surface_count():
		var src := mi.get_active_material(si)
		var m := ShaderMaterial.new()
		m.shader = shader
		if src is BaseMaterial3D:
			var b := src as BaseMaterial3D
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			m.set_shader_parameter("normal_tex", b.normal_texture)
		m.set_shader_parameter("to_ship", to_ship)
		m.set_shader_parameter("from_ship", to_ship.affine_inverse())
		m.set_shader_parameter("bmin", box.position)
		m.set_shader_parameter("bmax", box.end)
		m.set_shader_parameter("seed", sail.seed)
		mi.set_surface_override_material(si, m)
		sail.mats.append(m)
	mi.extra_cull_margin = 30.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_sails.append(sail)
	var bl: Array = []
	if _skel != null and mi.skin != null:
		for bi in mi.skin.get_bind_count():
			var bidx := _skel.find_bone(mi.skin.get_bind_name(bi))
			if bidx >= 0 and not bl.has(bidx):
				bl.append(bidx)
	_sail_bones.append(bl)
	_mast_ship.append(Vector3(0.0, box.get_center().y, box.get_center().z))
	for m2 in sail.mats:
		m2.set_shader_parameter("mast_pos", Vector3(0.0, box.get_center().y, box.get_center().z))
	if "sail_defs" in _ship:
		_ship.sail_defs.append({"pos": box.get_center(), "area": box.size.x * box.size.y * 0.85, "name": String(mi.name)})

func _process(delta: float) -> void:
	_time += delta
	var w := WorldState
	var yaw: float = _ship.get("yaw") if _ship.get("yaw") != null else 0.0
	var speed: float = _ship.get("current_speed") if _ship.get("current_speed") != null else 6.0
	# Apparent wind in ship space (x starboard, z aft): true wind minus the ship's own velocity (-z forward).
	var wl := Basis(Vector3.UP, yaw).inverse() * Vector3(w.wind_vector().x, 0.0, w.wind_vector().y)
	var app := wl * w.wind_speed_ms() + Vector3(0.0, 0.0, speed)
	# The masts swing with the hull: velocity of the sails' centre (~14 m up) enters the apparent wind.
	var rr: float = _ship.get("roll_rate") if _ship.get("roll_rate") != null else 0.0
	var pr: float = _ship.get("pitch_rate") if _ship.get("pitch_rate") != null else 0.0
	app.x += 14.0 * rr
	app.z -= 14.0 * pr
	# Forward push (-z) fills the sails; air coming from ahead presses them aft / makes them luff.
	var drive := -app.z
	var fill_t := clampf(drive / 9.0, -0.25, 1.0)
	var luffing := 1.0 - smoothstep(0.0, 0.35, fill_t)
	var flut_t := clampf(0.12 + 0.55 * w.wind_strength + 0.9 * w.storm + 0.8 * luffing * (0.3 + w.wind_strength) + 0.6 * (absf(rr) + absf(pr)), 0.0, 1.5)
	var k := 1.0 - exp(-1.6 * delta)
	_fill = lerpf(_fill, fill_t, k)
	_flutter = lerpf(_flutter, flut_t, k)
	# Gusts: slow noise-like modulation.
	var gust := 1.0 + 0.18 * sin(_time * 0.9) * w.wind_strength + 0.1 * sin(_time * 2.3 + 1.0) * (0.3 + w.storm)
	var furl_t := smoothstep(furl_storm - 0.06, furl_storm + 0.06, w.storm)
	_furl = move_toward(_furl, furl_t, furl_speed * delta)
	if "sail_power" in _ship:
		_ship.sail_power = 1.0 - 0.75 * _furl # storm canvas: furled sails keep a little drive
	var fills: Dictionary = _ship.get("sail_fill") if _ship.get("sail_fill") != null else {}
	for si in _sails.size():
		var s := _sails[si]
		var phys_fill: float = clampf(float(fills[si]) / 8.0, -0.3, 1.1) if fills.has(si) else _fill
		for m in s.mats:
			m.set_shader_parameter("fill", clampf(lerpf(_fill, phys_fill, 0.8) * gust * s.gain, -0.3, 1.1))
			m.set_shader_parameter("flutter", _flutter)
			m.set_shader_parameter("furl", _furl)
			m.set_shader_parameter("time", _time)
		s.mi.visible = _furl < 0.985
	# Yard bracing: rotate the sails' bones (sail + yard + running rigging) about the vertical axis through the mast.
	var br: float = _ship.get("brace") if _ship.get("brace") != null else 0.0
	if _skel != null and absf(br - _last_brace) > 0.003:
		_last_brace = br
		_apply_brace(br)
	for sx in _sails:
		for mx in sx.mats:
			mx.set_shader_parameter("brace", br)
	# Furled bundles appear only once the sails are mostly up.
	for f in _furled:
		f.visible = _furl > 0.9
	# Rudder follows the helm (rudder > 0 = starboard).
	if _skel and _rudder_bone >= 0:
		var rud: float = _ship.get("rudder") if _ship.get("rudder") != null else 0.0
		var q := Quaternion(Vector3.UP, -rud * deg_to_rad(28.0))
		_skel.set_bone_pose_rotation(_rudder_bone, _rudder_rest * q)

func _apply_brace(beta: float) -> void:
	var rot := Basis(Vector3.UP, beta)
	var seen := {}
	for si in _sails.size():
		var pv_local: Vector3 = _mast_ship[si]
		var ps: Vector3 = _skel.global_transform.affine_inverse() * (_pivot.global_transform * pv_local)
		var t := Transform3D(rot, ps - rot * ps)
		var bl: Array = _sail_bones[si]
		bl.sort() # parents come before children in Godot's bone order
		for bidx in bl:
			if seen.has(bidx):
				continue # a bone shared between sails keeps the first mast's pivot
			seen[bidx] = true
			var rest_g := _skel.get_bone_global_rest(bidx)
			var parent := _skel.get_bone_parent(bidx)
			var pg := _skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
			var local := pg.affine_inverse() * (t * rest_g)
			_skel.set_bone_pose_position(bidx, local.origin)
			_skel.set_bone_pose_rotation(bidx, local.basis.orthonormalized().get_rotation_quaternion())
