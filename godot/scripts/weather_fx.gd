extends Node3D
## Storm effects: rain curtain around the camera and rare lightning flashes (storm only).

var _rain: GPUParticles3D
var _flash_light: DirectionalLight3D
var _next_strike := 8.0
var _pattern: Array = [] # [Vector2(delay, intensity)] queue
var _pat_t := 0.0
var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _rain_mat: StandardMaterial3D

## Rain particle budget per quality preset: RAIN_BASE x Quality.particle_scale (dev 1750, final 7000), logged at start.
const RAIN_BASE := 7000

func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = int(RAIN_BASE * Quality.particle_scale)
	print("[weather] rain particles cap=", _rain.amount, " (", Quality.name_, ", particle_scale=", Quality.particle_scale, ")")
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
	# Drops that pass within a few metres of the camera would be 0.75 m streaks several hundred pixels long (the "thick white diagonal
	# line"): fade them out inside 2.5-8 m.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 2.5
	m.distance_fade_max_distance = 8.0
	cap.material = m
	_rain_mat = m
	_rain.draw_pass_1 = cap
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_fog = true
	_bolt_mat.albedo_color = Color(0.75, 0.82, 1.0)
	_bolt = MeshInstance3D.new()
	_bolt.material_override = _bolt_mat
	_bolt.top_level = true
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.extra_cull_margin = 5000.0
	_bolt.visible = false
	add_child(_bolt)
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
	# Rain streaks are unshaded: dim them with the light so they never glow at night or under a dark storm deck.
	_rain_mat.albedo_color = Color(0.78, 0.84, 0.95, 0.26) * (0.28 + 0.72 * w.daylight)
	_rain_mat.albedo_color.a = 0.26
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
			var dist := _spawn_bolt()
			w.thunder.emit(dist / 343.0, clampf(1.2 - dist / 1500.0, 0.2, 1.0))
	if not _pattern.is_empty():
		_pat_t += delta
		while not _pattern.is_empty() and _pat_t >= _pattern[0].x:
			w.flash = maxf(w.flash, _pattern[0].y)
			_pattern.pop_front()
	_flash_light.light_energy = w.flash * 2.5
	_bolt.visible = w.flash > 0.04
	_bolt_mat.albedo_color = Color(0.75, 0.82, 1.0) * clampf(w.flash * 1.6, 0.0, 1.6)
	_bolt_mat.albedo_color.a = clampf(w.flash * 1.5, 0.0, 1.0)

## Jagged branching bolt: midpoint-displaced polyline from the cloud base to the sea, plus 1-2 branches, as a camera-facing
## ribbon that is only lit while the flash lasts (the pattern re-lights the same bolt, giving the flicker).
func _jag(a: Vector3, b: Vector3, side: Vector3, amp: float, iters: int) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	for _i in iters:
		var out := PackedVector3Array()
		for k in pts.size() - 1:
			out.append(pts[k])
			var mid := (pts[k] + pts[k + 1]) * 0.5
			mid += side * randf_range(-1.0, 1.0) * amp
			out.append(mid)
		out.append(pts[pts.size() - 1])
		pts = out
		amp *= 0.55
	return pts

func _ribbon(st: SurfaceTool, pts: PackedVector3Array, side: Vector3, w0: float, w1: float) -> void:
	for k in pts.size() - 1:
		var t0 := float(k) / float(pts.size() - 1)
		var t1 := float(k + 1) / float(pts.size() - 1)
		var wa := lerpf(w0, w1, t0) * 0.5
		var wb := lerpf(w0, w1, t1) * 0.5
		var a0 := pts[k] - side * wa
		var a1 := pts[k] + side * wa
		var b0 := pts[k + 1] - side * wb
		var b1 := pts[k + 1] + side * wb
		for v in [a0, a1, b0, a1, b1, b0]:
			st.add_vertex(v)

func _spawn_bolt() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 900.0
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized().rotated(Vector3.UP, deg_to_rad(randf_range(-32.0, 32.0)))
	var dist := randf_range(500.0, 1300.0)
	var ground := cam.global_position + fwd * dist
	ground.y = 0.0
	var side := fwd.cross(Vector3.UP).normalized()
	var top := ground + Vector3(randf_range(-80, 80), randf_range(420, 560), randf_range(-80, 80))
	var main := _jag(top, ground, side, 90.0, 6)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := dist * 0.0085
	_ribbon(st, main, side, w * 0.55, w)
	for _b in randi_range(1, 2):
		var i := randi_range(int(main.size() * 0.25), int(main.size() * 0.7))
		var start := main[i]
		var end := start + Vector3(randf_range(-1, 1) * 170.0, -randf_range(120, 240), randf_range(-1, 1) * 60.0)
		_ribbon(st, _jag(start, end, side, 35.0, 5), side, w * 0.4, w * 0.12)
	_bolt.mesh = st.commit()
	_bolt.global_transform = Transform3D.IDENTITY
	return dist
