class_name LookDev
extends Node
## Look-dev A/B candidates. Created by sky.gd ONLY when `--look=<tokens>` is on the command line, so default behaviour is untouched.
## Tokens are comma separated, `key` or `key:v1:v2..`; every candidate is applied after sky.gd each frame (process priority 500).
##   tm:filmic|aces|agx|reinhard|linear   tonemapper          white:N        tonemap white point
##   exp:X                                exposure multiplier on top of Sky.exposure
##   glow:intensity[:bloom[:threshold[:strength]]]   glow overrides (final only; dev has glow off)
##   sat:X  con:X  bri:X                  adjustment multipliers (sat/con) and brightness (absolute) on top of sky.gd values
##   lut[:strength]                       procedural 3D colour grade (warm highlights at low sun, cool shadows at night/storm)
##   vfog[:density[:anisotropy[:length]]] volumetric fog (albedo/emission follow the sky fog colour)
##   probe[:update_s]                     ReflectionProbe under Ship/Pivot (box around the hull), re-rendered every update_s (default 8)
##   matdump                              log every ship material (name, albedo, rough, metal, normal scale)
##   hull_rough:X                         multiply roughness of ship materials named hull/wood
##   tshadow:X                            shadow_blur override (contact softness)

var _tokens := {}
var _env: Environment
var _lut_t := 0.0
var _lut_key := ""
var _probe: ReflectionProbe
var _probe_t := 0.0
var _probe_period := 8.0
var _mat_done := false

func _ready() -> void:
	process_priority = 500
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			for tok in a.get_slice("=", 1).split(",", false):
				var parts := tok.split(":")
				_tokens[parts[0]] = parts.slice(1)
	print("[look] tokens=", _tokens)

func _f(key: String, idx: int, default: float) -> float:
	var arr: Array = _tokens[key]
	return float(arr[idx]) if arr.size() > idx and str(arr[idx]) != "" else default

func _process(delta: float) -> void:
	var s := get_parent() as WorldEnvironment
	if s == null:
		return
	_env = s.environment
	var cam_attr := s.camera_attributes as CameraAttributesPractical
	if _tokens.has("tm"):
		var m: String = str(_tokens["tm"][0])
		_env.tonemap_mode = {
			"linear": Environment.TONE_MAPPER_LINEAR, "reinhard": Environment.TONE_MAPPER_REINHARDT,
			"filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES, "agx": Environment.TONE_MAPPER_AGX
		}.get(m, Environment.TONE_MAPPER_AGX)
	if _tokens.has("white"):
		_env.tonemap_white = _f("white", 0, 6.0)
	if _tokens.has("exp") and cam_attr:
		cam_attr.exposure_multiplier *= _f("exp", 0, 1.0)
	if _tokens.has("glow"):
		_env.glow_enabled = true
		_env.glow_intensity = _f("glow", 0, 0.5)
		_env.glow_bloom = _f("glow", 1, 0.04)
		_env.glow_hdr_threshold = _f("glow", 2, 1.1)
		_env.glow_strength = _f("glow", 3, 1.0)
	if _tokens.has("sat"):
		_env.adjustment_saturation *= _f("sat", 0, 1.0)
	if _tokens.has("con"):
		_env.adjustment_contrast *= _f("con", 0, 1.0)
	if _tokens.has("bri"):
		_env.adjustment_brightness = _f("bri", 0, 1.0)
	if _tokens.has("lut"):
		_update_lut(delta)
	if _tokens.has("vfog"):
		_update_vfog()
	if _tokens.has("tshadow"):
		var sun := get_tree().root.get_node_or_null("Main/Sun") as DirectionalLight3D
		if sun:
			sun.shadow_blur = _f("tshadow", 0, 1.3)
	if _tokens.has("probe"):
		_update_probe(delta)
	if (_tokens.has("matdump") or _tokens.has("hull_rough")) and not _mat_done and Engine.get_frames_drawn() > 120:
		_mat_done = true
		_materials()

func _update_vfog() -> void:
	_env.volumetric_fog_enabled = true
	var storm: float = WorldState.storm
	var night: float = WorldState.night
	_env.volumetric_fog_density = _f("vfog", 0, 0.004) * (1.0 + 2.5 * storm)
	_env.volumetric_fog_anisotropy = _f("vfog", 1, 0.55)
	_env.volumetric_fog_length = _f("vfog", 2, 140.0)
	_env.volumetric_fog_detail_spread = 2.0
	_env.volumetric_fog_ambient_inject = 0.5
	_env.volumetric_fog_sky_affect = 0.0
	_env.volumetric_fog_temporal_reprojection_enabled = true
	var fc: Color = _env.fog_light_color
	_env.volumetric_fog_albedo = fc.lightened(0.2)
	_env.volumetric_fog_emission = fc * (0.02 + 0.04 * night)
	_env.volumetric_fog_emission_energy = 1.0

## 16^3 grade: warm highlights / cool shadows, strength follows sun elevation (golden hour warm), storm (cool, desaturated), night (blue shadows).
func _update_lut(delta: float) -> void:
	_lut_t += delta
	if _lut_t < 1.0 and _lut_key != "":
		return
	_lut_t = 0.0
	var elev: float = WorldState.sun_elevation_deg
	var golden := clampf(1.0 - absf(elev - 6.0) / 20.0, 0.0, 1.0) * (1.0 - WorldState.storm)
	var storm: float = WorldState.storm
	var night: float = WorldState.night
	var strength := _f("lut", 0, 1.0)
	var key := "%.2f/%.2f/%.2f" % [snappedf(golden, 0.05), snappedf(storm, 0.05), snappedf(night, 0.05)]
	if key == _lut_key:
		return
	_lut_key = key
	var n := 16
	var imgs: Array[Image] = []
	var warm := Color(1.06, 1.0, 0.90)
	var cool := Color(0.93, 0.99, 1.07)
	var night_shadow := Color(0.90, 0.97, 1.12)
	for z in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var c := Color(x / float(n - 1), y / float(n - 1), z / float(n - 1))
				var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
				var sh := 1.0 - smoothstep(0.0, 0.55, l) # shadow weight
				var hi := smoothstep(0.45, 1.0, l) # highlight weight
				var tint := Color(1, 1, 1)
				tint = tint.lerp(cool, 0.5 * sh * (1.0 - night))
				tint = tint.lerp(night_shadow, sh * night)
				tint = tint.lerp(warm, hi * golden)
				tint = tint.lerp(Color(0.96, 1.0, 1.04), 0.6 * storm)
				var o := Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)
				var g := o.r * 0.2126 + o.g * 0.7152 + o.b * 0.0722
				o = Color(g, g, g).lerp(o, 1.0 - 0.18 * storm)
				img.set_pixel(x, y, c.lerp(o, strength).clamp())
		imgs.append(img)
	var t3 := ImageTexture3D.new()
	t3.create(Image.FORMAT_RGB8, n, n, n, false, imgs)
	_env.adjustment_enabled = true
	_env.adjustment_color_correction = t3

func _update_probe(delta: float) -> void:
	if _probe == null:
		var pivot := get_tree().root.get_node_or_null("Main/Ship/Pivot") as Node3D
		if pivot == null:
			return
		_probe = ReflectionProbe.new()
		_probe.name = "LookProbe"
		_probe.size = Vector3(18, 14, 36)
		_probe.origin_offset = Vector3(0, 1.0, 0)
		_probe.position = Vector3(0, 4.5, 0)
		_probe.interior = false
		_probe.box_projection = true
		_probe.enable_shadows = false
		_probe.max_distance = 0.0
		_probe.intensity = 1.0
		_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_probe_period = _f("probe", 0, 8.0)
		pivot.add_child(_probe)
		print("[look] reflection probe added size=", _probe.size)
	_probe_t += delta
	if _probe_t >= _probe_period:
		_probe_t = 0.0
		_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
		await get_tree().process_frame
		await get_tree().process_frame
		if is_instance_valid(_probe):
			_probe.update_mode = ReflectionProbe.UPDATE_ONCE

func _materials() -> void:
	var seen := {}
	var ship := get_tree().root.get_node_or_null("Main/Ship")
	if ship == null:
		return
	for mi in ship.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat: Material = m.get_active_material(i)
			if mat == null or seen.has(mat):
				continue
			seen[mat] = true
			if mat is BaseMaterial3D:
				var b := mat as BaseMaterial3D
				print("[look] mat ", mat.resource_name, " (", m.name, ") albedo=", b.albedo_color, " rough=", b.roughness, " metal=", b.metallic,
					" normal=", b.normal_enabled, "/", b.normal_scale, " rim=", b.rim_enabled, " tex=", b.albedo_texture != null)
				var nm := str(mat.resource_name)
				if _tokens.has("hull_rough") and (nm.findn("wood") >= 0 or nm.findn("hull") >= 0):
					b.roughness = clampf(b.roughness * _f("hull_rough", 0, 1.0), 0.0, 1.0)
			else:
				print("[look] mat ", mat.resource_name, " (", m.name, ") ", mat.get_class())
