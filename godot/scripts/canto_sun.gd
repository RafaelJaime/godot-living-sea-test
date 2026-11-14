extends MeshInstance3D
## Canto, the sun god: a camera-facing additive billboard placed far away exactly along the
## DirectionalLight3D direction, so the light visibly comes from his face.

@export var sun_path := NodePath("../Sun")
@export var texture_path := "res://assets/sky/canto_sun.png"
@export var distance := 9000.0
## Angular size of the whole quad in degrees (the face is ~40% of it).
@export var angular_size_deg := 20.0
@export var base_glow := 1.5
@export var pulse_glow := 0.25
@export var pulse_scale := 0.025
@export var pulse_speed := 0.7

var _sun: Node3D
var _mat: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	process_priority = 200 # after camera
	_sun = get_node(sun_path)
	if not ResourceLoader.exists(texture_path):
		push_warning("Canto texture missing: " + texture_path)
		visible = false
		return
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 2.0 * distance * tan(deg_to_rad(angular_size_deg) * 0.5)
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/canto.gdshader")
	_mat.set_shader_parameter("canto_tex", load(texture_path))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 100000.0
	visible = not OS.get_cmdline_user_args().has("--no-canto")
	custom_aabb = AABB(Vector3(-20000, -20000, -20000), Vector3(40000, 40000, 40000))

func _process(delta: float) -> void:
	if _mat == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_t += delta
	var to_sun := _sun.global_transform.basis.z.normalized() # light shines along -Z, so +Z points at the sun
	var s := 1.0 + sin(_t * pulse_speed) * pulse_scale
	global_transform = Transform3D(cam.global_transform.basis.scaled(Vector3(s, s, 1.0)),
		cam.global_position + to_sun * distance)
	# Canto dims toward the horizon, vanishes at night and is veiled by clouds / storms.
	var w := WorldState
	var vis := smoothstep(-5.0, 7.0, w.sun_elevation_deg) * (1.0 - 0.93 * w.storm) * (1.0 - 0.5 * w.cloud)
	visible = vis > 0.01 and not OS.get_cmdline_user_args().has("--no-canto")
	_mat.set_shader_parameter("glow", (base_glow + sin(_t * pulse_speed * 1.3 + 1.0) * pulse_glow) * vis)
