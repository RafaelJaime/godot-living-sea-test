class_name PlanarReflection
extends Node
## OPT-IN proof of concept (default OFF): planar reflection of the ship on the water.
##   --planar-reflection=off|hull|ship     (hull = hull/deck meshes only, ship = every mesh of the ship model; crew excluded)
##   --planar-scale=<0.25..1>              reflection viewport scale vs the main viewport (default 0.5)
##   --planar-gain=<x>  --planar-distort=<x>   shader gain (default 2.5) and normal distortion (default 0.03)
##   --planar-log                          prints the selected meshes and the viewport size
## A SubViewport (shares the main World3D, HDR 2D = linear, transparent background, no TAA/MSAA) renders layer 20 only from a camera
## mirrored in the plane y = mean sea level. The ocean material samples it (uniforms planar_tex / planar_gain / planar_distort,
## declared at the end of shaders/ocean_fft.gdshader; gain 0 = the shader path costs one branch).
## The mirrored camera has the same pixel->direction mapping as the real one reflected, with the X axis negated to keep a proper
## rotation, so the shader samples at (1 - SCREEN_UV.x, SCREEN_UV.y). Known limit: no oblique near plane in Godot, so the part of
## the hull below the waterline can occlude the reflection from grazing angles (the ocean already discards water inside the hull).

const LAYER_BIT := 1 << 19 # visual layer 20
var mode := "off"
var _vp: SubViewport
var _cam: Camera3D
var _scale := 0.5
var _gain := 2.5
var _distort := 0.03
var _log := false
var _mat: ShaderMaterial
var _tagged := false
var _frames := 0
var _sky: WorldEnvironment
var _env: Environment
var _dump_at := 0

func _ready() -> void:
	process_priority = 2000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--planar-reflection="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--planar-scale="):
			_scale = clampf(float(a.get_slice("=", 1)), 0.25, 1.0)
		elif a.begins_with("--planar-gain="):
			_gain = float(a.get_slice("=", 1))
		elif a.begins_with("--planar-distort="):
			_distort = float(a.get_slice("=", 1))
		elif a.begins_with("--planar-dump="): # saves the reflection viewport at that frame to _shots/planar_vp.png
			_dump_at = int(a.get_slice("=", 1))
		elif a == "--planar-log":
			_log = true
	if mode != "hull" and mode != "ship":
		set_process(false)
		return
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.use_hdr_2d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.use_taa = false
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(960, 540)
	_vp.disable_3d = false
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = LAYER_BIT
	_vp.add_child(_cam)
	_cam.current = true
	_cam.compositor = Compositor.new() # the WorldEnvironment compositor (SC2 clouds) must not run in the reflection pass
	print("[planar] mode=", mode, " scale=", _scale, " gain=", _gain, " distort=", _distort)

func _tag_meshes() -> void:
	var model := get_tree().root.get_node_or_null("Main/Ship/Pivot/Model")
	if model == null:
		model = get_tree().root.get_node_or_null("Main/Ship")
	if model == null:
		return
	var n := 0
	for c in model.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var nm := str(mi.name).to_lower()
		var is_ship_geo := nm.begins_with("geo_ship") or nm.contains("pinnace")
		if not is_ship_geo:
			continue
		var is_hull := nm.contains("hull") or nm.contains("deck") or nm.contains("aft") or nm.contains("details") or nm.contains("pinnace") and not nm.contains("sail") and not nm.contains("rig")
		if mode == "hull" and (not is_hull or nm.contains("sail") or nm.contains("rig") or nm.contains("flag")):
			continue
		mi.layers |= LAYER_BIT
		n += 1
		if _log:
			print("[planar] tagged ", mi.get_path(), " layers=", mi.layers)
	_tagged = n > 0
	if _log:
		print("[planar] tagged meshes: ", n)

func _process(_dt: float) -> void:
	_frames += 1
	if _dump_at > 0 and _frames == _dump_at:
		var im := _vp.get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		im.save_png(ProjectSettings.globalize_path("res://_shots/planar_vp.png"))
		print("[planar] dumped vp ", im.get_size())
	if _mat == null and Waves.ocean != null:
		_mat = Waves.ocean.get("_mat") as ShaderMaterial
		if _mat:
			_mat.set_shader_parameter("planar_tex", _vp.get_texture())
			_mat.set_shader_parameter("planar_gain", _gain)
			_mat.set_shader_parameter("planar_distort", _distort)
	if not _tagged and _frames > 20 and _frames % 10 == 0:
		_tag_meshes()
	if _sky == null:
		_sky = get_tree().root.get_node_or_null("Main/Sky") as WorldEnvironment
	if _sky and _env == null and _sky.environment:
		_env = _sky.environment.duplicate() # linear, no post: the main camera tonemaps the sum
		_env.background_mode = Environment.BG_CLEAR_COLOR
		_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_env.glow_enabled = false
		_env.ssao_enabled = false
		_env.ssil_enabled = false
		_env.ssr_enabled = false
		_env.fog_enabled = false
		_env.volumetric_fog_enabled = false
		_env.adjustment_enabled = false
		_cam.environment = _env
		var ca := CameraAttributesPractical.new()
		ca.auto_exposure_enabled = false
		_cam.attributes = ca
	if _env and _sky.environment:
		var e := _sky.environment
		_env.ambient_light_energy = e.ambient_light_energy
		_env.ambient_light_color = e.ambient_light_color
		_env.ambient_light_sky_contribution = e.ambient_light_sky_contribution
	var main := get_viewport().get_camera_3d()
	if main == null or main == _cam:
		return
	var want := Vector2i((Vector2(get_viewport().get_visible_rect().size) * _scale).round())
	if want != _vp.size and want.x > 8:
		_vp.size = want
		if _log:
			print("[planar] vp size ", want)
	var plane_y := 0.0 # mean sea level
	var t := main.global_transform
	var o := t.origin
	var r := t.basis.x
	var u := t.basis.y
	var f := -t.basis.z
	var refl := func(v: Vector3) -> Vector3: return Vector3(v.x, -v.y, v.z)
	var po := Vector3(o.x, 2.0 * plane_y - o.y, o.z)
	var nf: Vector3 = refl.call(f)
	var nu: Vector3 = refl.call(u)
	var nr: Vector3 = -(refl.call(r) as Vector3)
	var b := Basis(nr, nu, -nf).orthonormalized()
	_cam.global_transform = Transform3D(b, po)
	_cam.fov = main.fov
	_cam.near = main.near
	_cam.far = minf(main.far, 400.0)
	_cam.keep_aspect = main.keep_aspect
