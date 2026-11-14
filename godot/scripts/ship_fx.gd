extends Node3D
## Ship water effects, all in world space so they stay behind as the ship sails:
## - Wake: long-lived foam blobs emitted at the stern (fade over ~20 s), plus bow-wave foam along the hull sides.
## - Bow spray: GPU particles whose rate follows how hard the bow slams into the water (immersion rate) and sea_state.
## Foam blobs are snapped onto the rendered FFT surface by wake_foam.gdshader.

@export var pivot_path := NodePath("../Pivot")
@export var wake_lifetime := 22.0
@export var wake_rate := 80.0 ## blobs per second
@export var bow_foam_lifetime := 6.0

var _pivot: Node3D
var _length := 22.0
var _beam := 7.0
var _wake: GPUParticles3D
var _bow_foam: GPUParticles3D
var _spray: GPUParticles3D
var _foam_mat: ShaderMaterial
var _prev_immersion := 0.0
var _slam := 0.0
var _have_prev := false
var _blob_tex: GradientTexture2D
var _scales_set := false

func _ready() -> void:
	_pivot = get_node(pivot_path)
	_blob_tex = GradientTexture2D.new()
	_blob_tex.width = 128
	_blob_tex.height = 128
	_blob_tex.fill = GradientTexture2D.FILL_RADIAL
	_blob_tex.fill_from = Vector2(0.5, 0.5)
	_blob_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_blob_tex.gradient = g
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.seamless = true
	ntex.width = 256
	ntex.height = 256
	_foam_mat = ShaderMaterial.new()
	_foam_mat.shader = load("res://shaders/wake_foam.gdshader")
	_foam_mat.set_shader_parameter("blob_tex", _blob_tex)
	_foam_mat.set_shader_parameter("noise_tex", ntex)
	_foam_mat.render_priority = 2
	var loader := get_node_or_null("../Pivot/Model")
	if loader and loader.has_signal("ship_ready"):
		loader.ship_ready.connect(_on_ship_ready)
	_build()

func _on_ship_ready(l: float, b: float, _r: float) -> void:
	_length = l
	_beam = b
	_wake.position = Vector3(0, 0, l * 0.36)
	(_wake.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(b * 0.32, 0.0, 0.4)
	_bow_foam.position = Vector3(0, 0, -l * 0.40)
	_spray.position = Vector3(0, 0.3, -l * 0.42)
	(_spray.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(b * 0.18, 0.1, 0.5)

func _foam_system(lifetime: float, rate: float, mat: ParticleProcessMaterial, quad_size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(lifetime * rate)
	p.lifetime = lifetime
	p.local_coords = false
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-220, -10, -220), Vector3(440, 20, 440))
	p.process_material = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(quad_size, quad_size)
	plane.subdivide_width = 12
	plane.subdivide_depth = 12
	plane.material = _foam_mat
	p.draw_pass_1 = plane
	add_child(p)
	return p

func _ramp(alpha_peak: float, fade_in: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, alpha_peak), Color(1, 1, 1, alpha_peak * 0.55), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, fade_in, 0.55, 1.0])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _scale_curve(a: float, b: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	var t := CurveTexture.new()
	t.curve = c
	return t

func _build() -> void:
	# Stern wake: wide, slow, long-lived.
	var wm := ParticleProcessMaterial.new()
	wm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	wm.emission_box_extents = Vector3(1.1, 0.0, 0.4)
	wm.direction = Vector3(0, 0, 1)
	wm.spread = 90.0
	wm.flatness = 1.0
	wm.initial_velocity_min = 0.15
	wm.initial_velocity_max = 0.9
	wm.gravity = Vector3.ZERO
	wm.damping_min = 0.15
	wm.damping_max = 0.3
	wm.scale_min = 2.2
	wm.scale_max = 3.6
	wm.scale_curve = _scale_curve(0.55, 1.7)
	wm.color_ramp = _ramp(0.10, 0.02)
	_wake = _foam_system(wake_lifetime, wake_rate, wm, 1.0)
	# Bow wave foam: thrown sideways from the stem, left behind along the hull as a V.
	var bm := ParticleProcessMaterial.new()
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bm.emission_box_extents = Vector3(0.5, 0.0, 0.3)
	bm.direction = Vector3(0, 0, 1)
	bm.spread = 180.0
	bm.flatness = 1.0
	bm.initial_velocity_min = 1.2
	bm.initial_velocity_max = 3.2
	bm.gravity = Vector3.ZERO
	bm.damping_min = 0.5
	bm.damping_max = 0.9
	bm.scale_min = 1.6
	bm.scale_max = 2.6
	bm.scale_curve = _scale_curve(0.7, 1.5)
	bm.color_ramp = _ramp(0.22, 0.1)
	_bow_foam = _foam_system(bow_foam_lifetime, 34.0, bm, 1.0)
	# Bow spray (billboards, additive-ish white), amount driven per frame.
	_spray = GPUParticles3D.new()
	_spray.amount = 400
	_spray.lifetime = 1.5
	_spray.local_coords = false
	_spray.amount_ratio = 0.0
	_spray.emitting = false
	_spray.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(1.2, 0.1, 0.5)
	sm.direction = Vector3(0, 1, -0.55)
	sm.spread = 38.0
	sm.initial_velocity_min = 3.0
	sm.initial_velocity_max = 8.0
	sm.gravity = Vector3(0, -9.0, 0)
	sm.scale_min = 0.5
	sm.scale_max = 1.3
	sm.scale_curve = _scale_curve(0.6, 1.8)
	sm.color_ramp = _ramp(0.55, 0.08)
	_spray.process_material = sm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = _blob_tex
	qm.albedo_color = Color(0.95, 0.98, 1.0)
	qm.disable_fog = false
	quad.material = qm
	_spray.draw_pass_1 = quad
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spray)

func _process(delta: float) -> void:
	if Waves.ocean == null or delta <= 0.0:
		return
	if not _scales_set:
		var scales := PackedVector4Array()
		for p: WaveCascadeParameters in Waves.ocean.parameters:
			var uv: Vector2 = Vector2.ONE / p.tile_length
			scales.append(Vector4(uv.x, uv.y, p.displacement_scale, p.normal_scale))
		_foam_mat.set_shader_parameter("map_scales", scales)
		_scales_set = true
	# Immersion of the stem: water height above the hull's waterline point at the bow.
	var bow_world := _pivot.global_transform * Vector3(0, 0, -_length * 0.42)
	var water := Waves.height_at(bow_world.x, bow_world.z)
	var immersion := water - bow_world.y
	if _have_prev:
		var rate := (immersion - _prev_immersion) / delta
		# Positive rate = bow dropping into / water rising against the stem.
		_slam = maxf(_slam - delta * 2.2, clampf((rate - 0.4) / 2.2, 0.0, 1.0) if immersion > -0.3 else 0.0)
	_prev_immersion = immersion
	_have_prev = true
	var base := 0.05 + 0.30 * Waves.sea_state if immersion > -0.2 else 0.0
	var ratio := clampf(maxf(_slam, base), 0.0, 1.0)
	_spray.amount_ratio = ratio
	_spray.emitting = ratio > 0.03
