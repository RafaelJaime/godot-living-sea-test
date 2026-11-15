extends WorldEnvironment
## Sky, sun, moon, fog and ambient light, all driven every frame by WorldState (day/night + weather).
## The sky is a custom shader (gradient, stars, moon, clouds); the sun disc itself is the Canto billboard.

@export var sun_path := NodePath("../Sun")
@export var moon_path := NodePath("../Moon")
@export var sun_energy := 2.4
@export var base_fog_density := 0.00022

## Colours other systems may read (ocean agent: prefer the global shader parameters registered by WorldState).
var horizon_color := Color(0.8, 0.8, 0.8)
var zenith_color := Color(0.22, 0.42, 0.75)
var fog_color := Color(0.8, 0.8, 0.8)
## True when the volumetric (Sunshine Clouds 2) layer is drawing the clouds; the sky shader's fbm layer then hides.
var volumetric_clouds := false

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _cam_attr: CameraAttributesPractical
## Deterministic exposure (M3.5): a pure function of sun elevation, cloud cover and storm; lightning never feeds it.
var exposure := 1.0
var sun_energy_now := 0.0
## Quality-gated ambient occlusion state, for logs and the probe ("off", "ssao+ssil").
var ao_state := "off"

func _ready() -> void:
	_sun = get_node(sun_path)
	_moon = get_node_or_null(moon_path)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/sky_night.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.0
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	environment = env
	# No auto exposure (it pumps on camera cuts and lightning and makes captures irreproducible): `exposure_multiplier` is
	# computed from WorldState in _update() (see _exposure_for).
	_cam_attr = CameraAttributesPractical.new()
	_cam_attr.auto_exposure_enabled = false
	camera_attributes = _cam_attr
	# Ship shadows: four cascades over 160 m (about 1.5 cm texels on the deck, 4096 atlas), soft blur. Dev drops the
	# shadows altogether (Quality.shadows) so the cascade layout only matters in final.
	_sun.shadow_enabled = Quality.shadows and not _has_arg("--no-shadows") # --no-shadows: A/B cost runs
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 160.0
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.18
	_sun.directional_shadow_split_3 = 0.5
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.9
	_sun.shadow_blur = 1.3
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 1.2
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	if _moon:
		_moon.shadow_enabled = false
		_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		_moon.light_color = Color(0.62, 0.72, 1.0)
	_update()
	_apply_ao()
	if _has_arg("--sky-log") or _has_arg("--sky-shots"):
		var probe: Node = (load("res://scripts/sky_probe.gd") as GDScript).new()
		probe.set("sky", self)
		add_child(probe)

func _has_arg(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == prefix or a.begins_with(prefix + "="):
			return true
	return false

## SSAO / SSIL come from Quality (`ssao`, `ssao_quality`, `ssil`; final: SSAO q0, SSIL off; dev: both off). Half-res, one blur pass,
## faded out beyond 60-250 m. Quality no longer touches these. Test aids: `--no-ao`, `--ao=both|ssao|ssil`, `--ao-quality=0..3`.
func _apply_ao() -> void:
	var want_ssao: bool = Quality.ssao
	var want_ssil: bool = Quality.ssil
	var quality: int = Quality.ssao_quality
	for a in OS.get_cmdline_user_args():
		if a == "--no-ao":
			want_ssao = false
			want_ssil = false
		elif a.begins_with("--ao="):
			var m := a.get_slice("=", 1)
			want_ssao = m != "ssil"
			want_ssil = m != "ssao"
		elif a.begins_with("--ao-quality="):
			quality = int(a.get_slice("=", 1))
	var env := environment
	env.ssao_enabled = want_ssao
	env.ssil_enabled = want_ssil
	if want_ssao or want_ssil:
		RenderingServer.environment_set_ssao_quality(quality as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 1, 60.0, 250.0)
		RenderingServer.environment_set_ssil_quality(quality as RenderingServer.EnvironmentSSILQuality, true, 0.5, 4, 60.0, 250.0)
		env.ssao_radius = 1.8
		env.ssao_intensity = 1.6
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.06
		env.ssao_sharpness = 0.9
		env.ssao_light_affect = 0.35
		env.ssil_radius = 6.0
		env.ssil_intensity = 0.7
		env.ssil_sharpness = 0.9
		env.ssil_normal_rejection = 1.0
	ao_state = "ssao=%s ssil=%s q%d" % [want_ssao, want_ssil, quality]
	print("[sky] ", Quality.name_, ": ", ao_state, ", shadows=", _sun.shadow_enabled, " splits=4 max_dist=", _sun.directional_shadow_max_distance)

func _process(delta: float) -> void:
	_update()
	_perf_probe(delta)

# Test aid: `--perf` prints the average frame time every 6 s and quits after 4 windows.
var _pf_t := 0.0
var _pf_n := 0
var _pf_win := 0
func _perf_probe(delta: float) -> void:
	if not "--perf" in OS.get_cmdline_user_args():
		return
	_pf_t += delta
	_pf_n += 1
	if _pf_t >= 6.0:
		print("[perf] window ", _pf_win, " avg frame ms=", snappedf(_pf_t / _pf_n * 1000.0, 0.01), " fps=", snappedf(_pf_n / _pf_t, 0.1))
		_pf_t = 0.0
		_pf_n = 0
		_pf_win += 1
		if _pf_win >= 4:
			get_tree().quit()

func _look_dir(light: Node3D, to_light: Vector3) -> void:
	var d := -to_light.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
	light.transform = Transform3D(Basis.looking_at(d, up), Vector3.ZERO)

## Deterministic exposure: tames noon highlights (clear sky, high sun), leaves dusk and night alone, and darkens storms.
## Smooth in all three inputs, so a `--timescale` run cannot make it oscillate.
static func _exposure_for(elev_deg: float, cloud: float, storm: float) -> float:
	var bright := smoothstep(6.0, 40.0, elev_deg) * (1.0 - 0.45 * cloud) * (1.0 - storm)
	return lerpf(1.0, 0.82, bright) * lerpf(1.0, 0.86, storm)

func _update() -> void:
	var w := WorldState
	var elev := w.sun_elevation_deg
	var k: float = w.daylight
	var cloud: float = w.cloud
	var storm: float = w.storm
	var dusk: float = exp(-pow((elev - 3.0) / 9.0, 2.0)) * (1.0 - 0.6 * storm)
	# Sky colours: night -> day, tinted by dusk, then pulled toward overcast grey.
	var top := Color(0.008, 0.015, 0.05).lerp(Color(0.22, 0.42, 0.75), k).lerp(Color(0.28, 0.30, 0.52), dusk * 0.7)
	var hor := Color(0.03, 0.045, 0.09).lerp(Color(0.80, 0.80, 0.80), k).lerp(Color(0.95, 0.55, 0.38), dusk)
	var g: float = clampf(cloud * 0.5 + storm * 0.4, 0.0, 0.95)
	var gray_top := Color(0.44, 0.47, 0.52).lerp(Color(0.14, 0.16, 0.20), storm) * (0.12 + 0.88 * k)
	var gray_hor := Color(0.62, 0.64, 0.68).lerp(Color(0.24, 0.26, 0.30), storm) * (0.10 + 0.90 * k)
	top = top.lerp(gray_top, g)
	hor = hor.lerp(gray_hor, g)
	_sky_mat.set_shader_parameter("sky_top", top)
	_sky_mat.set_shader_parameter("sky_horizon", hor)
	_sky_mat.set_shader_parameter("ground_color", hor.lerp(Color(0.04, 0.08, 0.12), 0.55))
	_sky_mat.set_shader_parameter("sun_dir", w.sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", w.moon_dir)
	_sky_mat.set_shader_parameter("star_visibility", w.night)
	_sky_mat.set_shader_parameter("cloud_cover", cloud)
	_sky_mat.set_shader_parameter("storminess", storm)
	_sky_mat.set_shader_parameter("daylight", k)
	_sky_mat.set_shader_parameter("cloud_scroll", w.cloud_scroll)
	_sky_mat.set_shader_parameter("flash", w.flash)
	_sky_mat.set_shader_parameter("layer_clouds", 0.0 if volumetric_clouds else 1.0)
	_sky_mat.set_shader_parameter("rainbow", w.rainbow)
	horizon_color = hor
	zenith_color = top
	# Lights.
	_look_dir(_sun, w.sun_dir)
	var sunk := smoothstep(-2.0, 10.0, elev)
	_sun.light_energy = sun_energy * sunk * (1.0 - 0.62 * cloud - 0.25 * storm)
	sun_energy_now = _sun.light_energy
	_sun.light_color = Color(1.0, 0.55, 0.32).lerp(Color(1.0, 0.84, 0.66), smoothstep(0.0, 24.0, elev))
	_sun.visible = _sun.light_energy > 0.01
	if _moon:
		_look_dir(_moon, w.moon_dir)
		_moon.light_energy = 0.22 * w.night * (1.0 - 0.7 * cloud)
		_moon.visible = _moon.light_energy > 0.01
	# Ambient / fog. Morning fog bank thickens the exponential fog and warms it; storms thicken it too.
	var env := environment
	var bank: float = w.fog_bank
	env.ambient_light_energy = lerpf(0.22, 0.9, k) * (1.0 - 0.3 * storm)
	env.fog_density = base_fog_density * (1.0 + 0.9 * cloud + 6.0 * storm + 16.0 * bank)
	fog_color = hor.lerp(Color(0.5, 0.55, 0.65), 0.15).lerp(Color(0.86, 0.80, 0.74), 0.5 * bank) * (0.55 + 0.45 * k)
	env.fog_light_color = fog_color
	env.fog_light_energy = lerpf(0.5, 1.0, k)
	# Storms desaturate; exposure (below) darkens them.
	env.adjustment_saturation = lerpf(1.08, 0.78, storm)
	exposure = _exposure_for(elev, cloud, storm)
	_cam_attr.exposure_multiplier = exposure
	# Published to every shader (ocean agent: declare `global uniform vec3 sky_horizon_color;` etc.).
	var sun_col := _sun.light_color * _sun.light_energy
	RenderingServer.global_shader_parameter_set("sky_horizon_color", Vector3(hor.r, hor.g, hor.b))
	RenderingServer.global_shader_parameter_set("sky_zenith_color", Vector3(top.r, top.g, top.b))
	RenderingServer.global_shader_parameter_set("sky_fog_color", Vector3(fog_color.r, fog_color.g, fog_color.b))
	RenderingServer.global_shader_parameter_set("sky_sun_color", Vector3(sun_col.r, sun_col.g, sun_col.b))
	RenderingServer.global_shader_parameter_set("sky_sun_dir", w.sun_dir)
	RenderingServer.global_shader_parameter_set("sky_fog_density", env.fog_density)
	RenderingServer.global_shader_parameter_set("sky_storminess", storm)
	RenderingServer.global_shader_parameter_set("sky_night", w.night)
	RenderingServer.global_shader_parameter_set("sky_rain", smoothstep(0.35, 0.8, storm))
	RenderingServer.global_shader_parameter_set("sky_biolum", w.biolum)
