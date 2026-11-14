extends WorldEnvironment
## Procedural sky, warm late-afternoon sun, aerial-perspective fog and filmic tonemapping.

@export var sun_path := NodePath("../Sun")
## Direction TO the sun (world space): ahead-left of the ship, low in the sky.
@export var sun_azimuth_deg := -30.0 ## 0 = straight ahead (-Z), negative = toward port
@export var sun_elevation_deg := 20.0
@export var sun_energy := 2.4
@export var fog_density := 0.00022
@export var day_cycle := false
@export var day_length_seconds := 300.0

var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _t := 0.0

func _ready() -> void:
	_sun = get_node(sun_path)
	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = fog_density
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.0
	env.fog_light_color = Color(0.70, 0.78, 0.86)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	environment = env
	_sun.light_color = Color(1.0, 0.82, 0.62)
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY # Canto billboard is the visible sun
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 140.0
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_blur = 1.5
	_apply(sun_elevation_deg)

func _apply(elev_deg: float) -> void:
	var az := deg_to_rad(sun_azimuth_deg)
	var el := deg_to_rad(elev_deg)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	_sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	var k := clampf(inverse_lerp(-4.0, 24.0, elev_deg), 0.0, 1.0) # 0 = night/dusk, 1 = day
	_sun.light_energy = sun_energy * smoothstep(-2.0, 12.0, elev_deg)
	_sun.light_color = Color(1.0, 0.55, 0.32).lerp(Color(1.0, 0.84, 0.66), k)
	_sky_mat.sky_top_color = Color(0.03, 0.05, 0.14).lerp(Color(0.22, 0.42, 0.75), k)
	_sky_mat.sky_horizon_color = Color(0.45, 0.28, 0.30).lerp(Color(0.80, 0.80, 0.80), k)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = Color(0.02, 0.05, 0.1).lerp(Color(0.18, 0.30, 0.42), k)
	_sky_mat.sky_curve = 0.12
	_sky_mat.sun_angle_max = 9.0
	_sky_mat.sun_curve = 0.2
	environment.fog_light_color = Color(0.20, 0.17, 0.25).lerp(Color(0.70, 0.78, 0.86), k)
	environment.ambient_light_energy = lerpf(0.25, 0.9, k)

func _process(delta: float) -> void:
	if not day_cycle:
		return
	_t += delta
	var phase := sin(_t / day_length_seconds * TAU)
	_apply(lerpf(-6.0, 55.0, phase * 0.5 + 0.5))
