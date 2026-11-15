extends Node3D
## Bow spray: sharp velocity-aligned droplets plus a little mist, emitted in world space.
## Emission rate: ratio = clamp((U / 5)^2, 0, 1.6) * (0.05 + 0.30 * sea_state) * immersion + slam impulse, U = surge speed relative to the water;
## slam = downward velocity of the stem relative to the water surface (from Waves.height_at at the stem).
## (The foam wake lives in wake_field.gd.)

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
var _ship: Node
var _log := false
var _log_t := 0.0
var _no_spray := false
var _test_speed := 1.0 ## --fx-test-speed=<k>: scales the relative speed (rate-ratio check; the ship cannot be slowed by flag)

func _ready() -> void:
	_pivot = get_node(pivot_path)
	_ship = _pivot.get_parent()
	for a in OS.get_cmdline_user_args():
		if a == "--fx-log":
			_log = true
		elif a == "--no-spray":
			_no_spray = true
		elif a.begins_with("--fx-test-speed="):
			_test_speed = float(a.get_slice("=", 1))
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
	print("[fx] spray cap: drops=", _drops.amount, " mist=", _mist.amount, " (particle_scale=", Quality.particle_scale, ", preset ", Quality.name_, ")")

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
	_drops.amount = int(1400 * Quality.particle_scale)
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
	_mist.amount = maxi(8, int(120 * Quality.particle_scale))
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
	var slam_now := 0.0
	if _have_prev:
		var rate := (immersion - _prev_immersion) / delta # + = the stem moves down relative to the surface
		slam_now = clampf((rate - 0.4) / 2.2, 0.0, 1.0) if immersion > -0.3 else 0.0
		_slam = maxf(_slam - delta * 2.2, slam_now)
	_prev_immersion = immersion
	_have_prev = true
	# Surge speed relative to the water (no current: the water is at rest apart from the waves).
	var u := 0.0
	if "linear_velocity" in _ship and _ship.get("forward") != null:
		var fwd: Vector2 = _ship.get("forward")
		var v: Vector3 = _ship.linear_velocity
		u = maxf(Vector2(v.x, v.z).dot(fwd), 0.0)
	elif _ship.get("current_speed") != null:
		u = float(_ship.get("current_speed"))
	u *= _test_speed
	var imm := smoothstep(-0.25, 0.25, immersion)
	var base := clampf((u / 5.0) * (u / 5.0), 0.0, 1.6) * (0.05 + 0.30 * Waves.sea_state) * imm
	var slam_eff := _slam * smoothstep(0.5, 3.0, u) # a ship at rest bobbing on the swell throws no spray
	var ratio := 0.0 if _no_spray else clampf(base + slam_eff, 0.0, 1.0)
	_drops.amount_ratio = ratio
	_drops.emitting = ratio > 0.03
	_mist.amount_ratio = ratio
	_mist.emitting = ratio > 0.03
	if _log:
		_log_t += delta
		if _log_t >= 1.0:
			_log_t = 0.0
			var rate_s := ratio * float(_drops.amount) / _drops.lifetime
			print("[fx] spray U=", snappedf(u, 0.01), " m/s sea=", snappedf(Waves.sea_state, 0.01), " base=", snappedf(base, 0.001), " slam=", snappedf(slam_eff, 0.001), " ratio=", snappedf(ratio, 0.001), " drops/s=", snappedf(rate_s, 0.1))
