extends WorldEnvironment
## Sky, sun, moon, fog and ambient light, all driven every frame by WorldState (day/night + weather).
## The sky is a custom shader (gradient, stars, moon, clouds); the sun disc itself is the Canto billboard.

@export var sun_path := NodePath("../Sun")
@export var moon_path := NodePath("../Moon")
@export var sun_energy := 2.4
@export var base_fog_density := 0.00022

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_mat: ShaderMaterial

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
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 140.0
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_blur = 1.5
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	if _moon:
		_moon.shadow_enabled = false
		_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		_moon.light_color = Color(0.62, 0.72, 1.0)
	_update()

func _process(_delta: float) -> void:
	_update()

func _look_dir(light: Node3D, to_light: Vector3) -> void:
	var d := -to_light.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
	light.transform = Transform3D(Basis.looking_at(d, up), Vector3.ZERO)

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
	# Lights.
	_look_dir(_sun, w.sun_dir)
	var sunk := smoothstep(-2.0, 10.0, elev)
	_sun.light_energy = sun_energy * sunk * (1.0 - 0.62 * cloud - 0.25 * storm)
	_sun.light_color = Color(1.0, 0.55, 0.32).lerp(Color(1.0, 0.84, 0.66), smoothstep(0.0, 24.0, elev))
	_sun.visible = _sun.light_energy > 0.01
	if _moon:
		_look_dir(_moon, w.moon_dir)
		_moon.light_energy = 0.55 * w.night * (1.0 - 0.7 * cloud)
		_moon.visible = _moon.light_energy > 0.01
	# Ambient / fog.
	var env := environment
	env.ambient_light_energy = lerpf(0.28, 0.9, k) * (1.0 - 0.3 * storm)
	env.fog_density = base_fog_density * (1.0 + 0.9 * cloud + 4.0 * storm)
	env.fog_light_color = hor.lerp(Color(0.5, 0.55, 0.65), 0.15) * (0.55 + 0.45 * k)
	env.fog_light_energy = lerpf(0.5, 1.0, k)
