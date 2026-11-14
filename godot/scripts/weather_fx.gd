extends Node3D
## Storm effects: rain curtain around the camera and rare lightning flashes (storm only).

var _rain: GPUParticles3D
var _flash_light: DirectionalLight3D
var _next_strike := 8.0
var _pattern: Array = [] # [Vector2(delay, intensity)] queue
var _pat_t := 0.0

func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 7000
	_rain.lifetime = 0.9
	_rain.local_coords = false
	_rain.amount_ratio = 0.0
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 0.5, 24)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	_rain.process_material = pm
	var cap := CapsuleMesh.new()
	cap.radius = 0.0035
	cap.height = 0.75
	cap.radial_segments = 4
	cap.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.84, 0.95, 0.26)
	cap.material = m
	_rain.draw_pass_1 = cap
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	_flash_light = DirectionalLight3D.new()
	_flash_light.light_color = Color(0.75, 0.8, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.rotation_degrees = Vector3(-70, 20, 0)
	add_child(_flash_light)

func _process(delta: float) -> void:
	var w := WorldState
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Rain falls in a box above the camera; it drifts with the wind.
		_rain.global_position = cam.global_position + Vector3(0, 16, 0)
		var wv := w.wind_vector() * 0.35
		(_rain.process_material as ParticleProcessMaterial).direction = Vector3(wv.x, -1, wv.y)
	if "--lightning" in OS.get_cmdline_user_args():
		_next_strike = minf(_next_strike, 2.5)
	var amt := smoothstep(0.35, 0.8, w.storm)
	_rain.amount_ratio = amt
	_rain.emitting = amt > 0.02
	# Lightning (storm only): rare double/triple flashes.
	var dt := delta * w.time_scale
	if w.storm > 0.7 and _pattern.is_empty():
		_next_strike -= dt
		if _next_strike <= 0.0:
			_next_strike = randf_range(9.0, 26.0)
			_pattern = [Vector2(0.0, 1.0), Vector2(0.11, 0.65), Vector2(0.23, 0.9)] if randf() < 0.6 else [Vector2(0.0, 0.95)]
			_pat_t = 0.0
			_flash_light.rotation_degrees = Vector3(randf_range(-80, -55), randf_range(0, 360), 0)
	if not _pattern.is_empty():
		_pat_t += delta
		while not _pattern.is_empty() and _pat_t >= _pattern[0].x:
			w.flash = maxf(w.flash, _pattern[0].y)
			_pattern.pop_front()
	_flash_light.light_energy = w.flash * 2.5
