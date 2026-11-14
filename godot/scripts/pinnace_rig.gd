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
	print("[sails] cloth=", cloth, " hidden furled/duplicate=", hidden, " rudder_bone=", _rudder_bone)

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

func _process(delta: float) -> void:
	_time += delta
	var w := WorldState
	var yaw: float = _ship.get("yaw") if _ship.get("yaw") != null else 0.0
	var speed: float = _ship.get("current_speed") if _ship.get("current_speed") != null else 6.0
	# Apparent wind in ship space (x starboard, z aft): true wind minus the ship's own velocity (-z forward).
	var wl := Basis(Vector3.UP, yaw).inverse() * Vector3(w.wind_vector().x, 0.0, w.wind_vector().y)
	var app := wl * w.wind_speed_ms() + Vector3(0.0, 0.0, speed)
	# Forward push (-z) fills the sails; air coming from ahead presses them aft / makes them luff.
	var drive := -app.z
	var fill_t := clampf(drive / 9.0, -0.25, 1.0)
	var luffing := 1.0 - smoothstep(0.0, 0.35, fill_t)
	var flut_t := clampf(0.12 + 0.55 * w.wind_strength + 0.9 * w.storm + 0.8 * luffing * (0.3 + w.wind_strength), 0.0, 1.5)
	var k := 1.0 - exp(-1.6 * delta)
	_fill = lerpf(_fill, fill_t, k)
	_flutter = lerpf(_flutter, flut_t, k)
	# Gusts: slow noise-like modulation.
	var gust := 1.0 + 0.18 * sin(_time * 0.9) * w.wind_strength + 0.1 * sin(_time * 2.3 + 1.0) * (0.3 + w.storm)
	var furl_t := smoothstep(furl_storm - 0.06, furl_storm + 0.06, w.storm)
	_furl = move_toward(_furl, furl_t, furl_speed * delta)
	for s in _sails:
		for m in s.mats:
			m.set_shader_parameter("fill", clampf(_fill * gust * s.gain, -0.3, 1.1))
			m.set_shader_parameter("flutter", _flutter)
			m.set_shader_parameter("furl", _furl)
			m.set_shader_parameter("time", _time)
		s.mi.visible = _furl < 0.985
	# Furled bundles appear only once the sails are mostly up.
	for f in _furled:
		f.visible = _furl > 0.9
	# Rudder follows the helm (rudder > 0 = starboard).
	if _skel and _rudder_bone >= 0:
		var rud: float = _ship.get("rudder") if _ship.get("rudder") != null else 0.0
		var q := Quaternion(Vector3.UP, -rud * deg_to_rad(28.0))
		_skel.set_bone_pose_rotation(_rudder_bone, _rudder_rest * q)
