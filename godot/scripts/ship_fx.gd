extends Node3D
## Bow spray: sharp velocity-aligned droplets plus a little mist, emitted in world space.
## Emission rate follows how hard the stem slams into the water (immersion rate) and sea_state.
## (The foam wake lives in wake_ribbon.gd.)

@export var pivot_path := NodePath("../Pivot")

var _pivot: Node3D
var _length := 22.0
var _beam := 7.0
var _drops: GPUParticles3D
var _mist: GPUParticles3D
var _prev_immersion := 0.0
var _slam := 0.0
var _have_prev := false
var _soft_tex: GradientTexture2D

func _ready() -> void:
	_pivot = get_node(pivot_path)
	_soft_tex = GradientTexture2D.new()
	_soft_tex.width = 64
	_soft_tex.height = 64
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_soft_tex.gradient = g
	var loader := get_node_or_null("../Pivot/Model")
	if loader and loader.has_signal("ship_ready"):
		loader.ship_ready.connect(_on_ship_ready)
	_build()

func _on_ship_ready(l: float, b: float, _r: float) -> void:
	_length = l
	_beam = b
	for p in [_drops, _mist]:
		p.position = Vector3(0, 0.3, -l * 0.42)
		(p.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(b * 0.2, 0.1, 0.5)

func _ramp(alpha_peak: float, fade_in: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, alpha_peak), Color(1, 1, 1, alpha_peak * 0.6), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, fade_in, 0.6, 1.0])
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
	# Droplets: tiny capsules aligned to their velocity (a thin, sharp streak), unshaded white.
	_drops = GPUParticles3D.new()
	_drops.amount = 1400
	_drops.lifetime = 1.3
	_drops.local_coords = false
	_drops.amount_ratio = 0.0
	_drops.emitting = false
	_drops.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(1.4, 0.1, 0.5)
	dm.direction = Vector3(0, 1, -0.5)
	dm.spread = 42.0
	dm.initial_velocity_min = 3.5
	dm.initial_velocity_max = 9.0
	dm.gravity = Vector3(0, -9.5, 0)
	dm.particle_flag_align_y = true
	dm.scale_min = 0.5
	dm.scale_max = 1.3
	dm.color_ramp = _ramp(0.95, 0.04)
	_drops.process_material = dm
	var cap := CapsuleMesh.new()
	cap.radius = 0.011
	cap.height = 0.17
	cap.radial_segments = 5
	cap.rings = 2
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.vertex_color_use_as_albedo = true
	cm.albedo_color = Color(0.97, 0.99, 1.0)
	cap.material = cm
	_drops.draw_pass_1 = cap
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drops)
	# Mist: few, small, faint soft sprites (not the main read).
	_mist = GPUParticles3D.new()
	_mist.amount = 120
	_mist.lifetime = 1.6
	_mist.local_coords = false
	_mist.amount_ratio = 0.0
	_mist.emitting = false
	_mist.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mm.emission_box_extents = Vector3(1.2, 0.1, 0.5)
	mm.direction = Vector3(0, 1, -0.4)
	mm.spread = 35.0
	mm.initial_velocity_min = 1.5
	mm.initial_velocity_max = 4.0
	mm.gravity = Vector3(0, -2.0, 0)
	mm.scale_min = 0.25
	mm.scale_max = 0.6
	mm.scale_curve = _scale_curve(0.5, 1.6)
	mm.color_ramp = _ramp(0.16, 0.1)
	_mist.process_material = mm
	var quad := QuadMesh.new()
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = _soft_tex
	quad.material = qm
	_mist.draw_pass_1 = quad
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mist)

func _process(delta: float) -> void:
	if Waves.ocean == null or delta <= 0.0:
		return
	var bow_world := _pivot.global_transform * Vector3(0, 0, -_length * 0.42)
	var water := Waves.height_at(bow_world.x, bow_world.z)
	var immersion := water - bow_world.y
	if _have_prev:
		var rate := (immersion - _prev_immersion) / delta
		_slam = maxf(_slam - delta * 2.2, clampf((rate - 0.4) / 2.2, 0.0, 1.0) if immersion > -0.3 else 0.0)
	_prev_immersion = immersion
	_have_prev = true
	var base := 0.05 + 0.30 * Waves.sea_state if immersion > -0.2 else 0.0
	var ratio := clampf(maxf(_slam, base), 0.0, 1.0)
	_drops.amount_ratio = ratio
	_drops.emitting = ratio > 0.03
	_mist.amount_ratio = ratio
	_mist.emitting = ratio > 0.03
