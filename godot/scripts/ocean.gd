extends Node3D
## FFT ocean (compute pipeline from addons/ocean_fft) rendered with a camera-following geometry clipmap.
## - One `sea_state` (0 calm .. 1 storm) drives wind speed, whitecaps and foam.
## - Displacement maps are read back asynchronously so buoyancy samples the SAME surface that is drawn.
## - Island shallows and the ship's hull-contact foam are fed to the water shader as uniforms.

@export_range(0.0, 1.0) var sea_state := 0.35:
	set(v):
		sea_state = clampf(v, 0.0, 1.0)
		_sea_dirty = true
@export var wind_direction_deg := 60.0
var map_size := 512 # from Quality.fft_size
var updates_per_second := 40.0 # from Quality
var readback_hz := 20.0
@export_color_no_alpha var water_color := Color(0.02, 0.15, 0.30)
@export_color_no_alpha var foam_color := Color(0.80, 0.84, 0.86)
@export var ship_path := NodePath("../Ship")
@export_group("Clipmap")
@export var base_cell := 0.8
@export var cells_per_level := 96 ## multiple of 4
var levels := 11 ## from Quality (11 rings reach ~40 km: the sea meets the horizon)

## Cascade tile sizes (m). Free: rebase shifts are folded in per cascade (cascade_shifts()).
const TILES := [211.0, 79.0, 23.0] # deliberately non-integer ratios: no visible super-tiling
const CPU_CASCADES := 2 ## cascades with non-zero displacement (the third is normal/foam detail only)
const MAX_ISLANDS := 10

var parameters: Array[WaveCascadeParameters] = []
var wave_generator: WaveGenerator
var displacement_maps := Texture2DArrayRD.new()
var normal_maps := Texture2DArrayRD.new()
var _mat: ShaderMaterial
var _level_nodes: Array[MeshInstance3D] = []
var _level_cell: Array[float] = []
var _time := 0.0
var _next_update := 0.0
var _sea_dirty := true
var _readback_t := 0.0
var _imgs: Array[Image] = [null, null, null]
var _imgs_prev: Array[Image] = [null, null, null]
var _img_age := 0.0 ## seconds since the current readback arrived (used to blend prev -> current)
var _ship: Node3D
var _islands := PackedVector4Array()
var _island_count := 0

func _ready() -> void:
	levels = Quality.ocean_levels
	map_size = Quality.fft_size
	updates_per_second = Quality.fft_updates_per_second
	print("[quality] ocean: rings=", levels, " fft=", map_size, " cascades=", Quality.ocean_cascades)
	readback_hz = Quality.readback_hz
	process_priority = 100 # after camera
	_ship = get_node_or_null(ship_path)
	RenderingServer.global_shader_parameter_set(&"water_color", water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&"foam_color", foam_color.srgb_to_linear())
	_make_parameters()
	_setup_generator()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ocean_fft.gdshader")
	_mat.set_shader_parameter("roughness", 0.3)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hull-foam="):
			_mat.set_shader_parameter("hull_foam_gain", float(a.get_slice("=", 1)))
		elif a.begins_with("--wake-turb="): # M2b.8 candidates: gain of the turbulence channel (0 = off)
			_mat.set_shader_parameter("wake_turb_gain", float(a.get_slice("=", 1)))
		elif a.begins_with("--wake-ridge="): # M2b.8 candidates: gain of the ridge channel (0 = off)
			_mat.set_shader_parameter("wake_ridge_gain", float(a.get_slice("=", 1)))
		elif a.begins_with("--water-debug="):
			_mat.set_shader_parameter("debug_mode", float(a.get_slice("=", 1)))
	_islands.resize(MAX_ISLANDS)
	_update_scales()
	for l in levels:
		var cell := base_cell * pow(2.0, l)
		var mi := MeshInstance3D.new()
		mi.mesh = _build_level(cell, false) # full squares: levels overlap, nothing is cut out (seam cracks cannot open)
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 200.0
		add_child(mi)
		_level_nodes.append(mi)
		_level_cell.append(cell)
	_snap(Vector3.ZERO)
	Waves.register_ocean(self)

func _make_parameters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var defs := [
		{"tile": TILES[0], "disp": 1.0, "norm": 1.0, "fetch": 150.0, "swell": 0.8, "spread": 0.2},
		{"tile": TILES[1], "disp": 0.75, "norm": 1.0, "fetch": 150.0, "swell": 0.8, "spread": 0.4},
		{"tile": TILES[2], "disp": 0.0, "norm": 0.25, "fetch": 550.0, "swell": 0.8, "spread": 0.4},
	]
	for i in mini(defs.size(), Quality.ocean_cascades):
		var p := WaveCascadeParameters.new()
		var d: Dictionary = defs[i]
		p.tile_length = Vector2(d["tile"], d["tile"])
		p.displacement_scale = d["disp"]
		p.normal_scale = d["norm"]
		p.fetch_length = d["fetch"]
		p.swell = d["swell"]
		p.spread = d["spread"]
		p.spectrum_seed = Vector2i(rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000))
		p.time = 120.0 + PI * i # offset so cascades do not interfere
		p.scale_changed.connect(_update_scales)
		parameters.append(p)
	_apply_sea_state()

func _setup_generator() -> void:
	wave_generator = WaveGenerator.new()
	wave_generator.map_size = map_size
	wave_generator.normal_mips = Quality.normal_mips
	wave_generator.init_gpu(maxi(2, parameters.size()))
	add_child(wave_generator)
	displacement_maps.texture_rd_rid = wave_generator.descriptors[&"displacement_map"].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors[&"normal_map"].rid
	RenderingServer.global_shader_parameter_set(&"num_cascades", parameters.size())
	RenderingServer.global_shader_parameter_set(&"displacements", displacement_maps)
	RenderingServer.global_shader_parameter_set(&"normals", normal_maps)

func _update_scales() -> void:
	if _mat == null:
		return
	var scales := PackedVector4Array()
	scales.resize(parameters.size())
	for i in parameters.size():
		var p := parameters[i]
		var uv := Vector2.ONE / p.tile_length
		scales[i] = Vector4(uv.x, uv.y, p.displacement_scale, p.normal_scale)
	_mat.set_shader_parameter("map_scales", scales)

## sea_state -> wind speed, whitecap threshold, foam amount for every cascade.
func _apply_sea_state() -> void:
	var s := sea_state
	var wind := [lerpf(3.0, 17.0, s), lerpf(2.5, 10.0, s), lerpf(6.0, 21.0, s)]
	var whitecap := [lerpf(0.18, 0.5, s), lerpf(0.1, 0.3, s), lerpf(0.1, 0.3, s)]
	var foam := [lerpf(2.5, 6.0, s), lerpf(0.3, 2.5, s), lerpf(0.8, 2.5, s)]
	# Wave HEIGHT scale: the FFT spectrum is far taller than a sailor's calm sea, so small sea_state shrinks the displacement.
	var amp := lerpf(0.12, 0.46, pow(s, 0.9))
	var base_disp := [1.0, 0.75, 0.0]
	for i in parameters.size():
		var p := parameters[i]
		p.displacement_scale = base_disp[i] * amp
		p.wind_speed = wind[i]
		p.wind_direction = wind_direction_deg + float(i) * 4.0
		p.whitecap = whitecap[i]
		p.foam_amount = foam[i]
	_sea_dirty = false

func _process(delta: float) -> void:
	if _sea_dirty:
		_apply_sea_state()
	if updates_per_second == 0.0 or _time >= _next_update:
		var target := 1.0 / (updates_per_second + 1e-10)
		var d := delta if updates_per_second == 0.0 else target + (_time - _next_update)
		_next_update = _time + target
		wave_generator.update(d, parameters)
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam:
		_snap(cam.global_position)
	_push_dynamic()
	_readback_t += delta
	_img_age += delta
	if _readback_t >= 1.0 / readback_hz:
		_readback_t = 0.0
		_request_readback()

## World offset (accumulated rebase shifts, doubles) modulo each cascade tile, for shaders that sample the FFT maps.
func cascade_shifts() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in parameters:
		out.append(Vector2(fposmod(Waves.offset_x, p.tile_length.x), fposmod(Waves.offset_z, p.tile_length.y)))
	while out.size() < 8:
		out.append(Vector2.ZERO)
	return out

func _push_dynamic() -> void:
	_mat.set_shader_parameter("cascade_shift", cascade_shifts())
	_mat.set_shader_parameter("islands", _islands)
	_mat.set_shader_parameter("island_count", _island_count)
	if _ship:
		var pv := _ship.get_node_or_null("Pivot") as Node3D
		if pv:
			_mat.set_shader_parameter("hull_inv", pv.get_global_transform_interpolated().affine_inverse())
		var y: float = _ship.get("yaw") if _ship.get("yaw") != null else 0.0
		# Ship forward is -Z; "right" in the shader is +X local, "back" is +Z local.
		_mat.set_shader_parameter("ship_speed", float(_ship.get("current_speed")) if _ship.get("current_speed") != null else 6.0)
		_mat.set_shader_parameter("ship_a", Vector4(_ship.global_position.x, _ship.global_position.z, cos(y), sin(y)))

## islands: array of Vector4(x, z, radius_x, radius_z) in world space (waterline ellipses).
func set_islands(list: PackedVector4Array) -> void:
	_island_count = mini(list.size(), MAX_ISLANDS)
	for i in MAX_ISLANDS:
		_islands[i] = list[i] if i < _island_count else Vector4.ZERO

var ship_half_len := 18.3 ## ship footprint (half length, half beam) as given by set_ship_footprint(); the wake field reads it
var ship_half_beam := 4.4

func set_ship_footprint(half_length: float, half_beam: float) -> void:
	ship_half_len = half_length
	ship_half_beam = half_beam
	_mat.set_shader_parameter("ship_half", Vector2(half_length, half_beam))

## Waterline outline of the hull: half-width per bin from bow (first) to stern (last), and the z range it spans.
func set_hull_volume(tex: Texture2D, dims: Vector4) -> void:
	_mat.set_shader_parameter("hull_tex", tex)
	_mat.set_shader_parameter("hull_dims", dims)
	_mat.set_shader_parameter("hull_volume_on", true)

## World-anchored wake foam field (see wake_field.gd): texture, window origin (local coords) and size (m).
func set_wake(tex: Texture2D, origin_local: Vector2, size: float) -> void:
	_mat.set_shader_parameter("wake_tex", tex)
	_mat.set_shader_parameter("wake_origin", origin_local)
	_mat.set_shader_parameter("wake_size", size)

func set_hull_profile(widths: PackedFloat32Array, z_bow: float, z_stern: float) -> void:
	_mat.set_shader_parameter("hull_w", widths)
	_mat.set_shader_parameter("hull_z", Vector2(z_bow, z_stern))

# --- CPU surface (async GPU readback) ----------------------------------------------------------

## Note: texture_get_data_async on a texture-array layer crashes Godot 4.7.2 intermittently
## ("Index p_index out of bounds" in LocalVector), so the layers are read back synchronously at readback_hz.
func _request_readback() -> void:
	var rd := RenderingServer.get_rendering_device()
	var rid: RID = wave_generator.descriptors[&"displacement_map"].rid
	for i in CPU_CASCADES:
		var data := rd.texture_get_data(rid, i)
		if data.size() < map_size * map_size * 8:
			continue
		_imgs_prev[i] = _imgs[i]
		_imgs[i] = Image.create_from_data(map_size, map_size, false, Image.FORMAT_RGBAH, data)
	_img_age = 0.0

func _sample(layer: int, x: float, z: float) -> Vector3:
	var cur := _sample_img(_imgs[layer], layer, x, z)
	var prev_img := _imgs_prev[layer]
	if prev_img == null:
		return cur
	# Blend the previous readback into the current one so the CPU surface moves smoothly between 20 Hz updates.
	var a := clampf(_img_age * readback_hz, 0.0, 1.0)
	return _sample_img(prev_img, layer, x, z).lerp(cur, a)

func _sample_img(img: Image, layer: int, x: float, z: float) -> Vector3:
	if img == null:
		return Vector3.ZERO
	var p := parameters[layer]
	var fx := (x + fposmod(Waves.offset_x, p.tile_length.x)) / p.tile_length.x * map_size - 0.5
	var fz := (z + fposmod(Waves.offset_z, p.tile_length.y)) / p.tile_length.y * map_size - 0.5
	var x0 := floorf(fx)
	var z0 := floorf(fz)
	var tx := fx - x0
	var tz := fz - z0
	var ix0 := posmod(int(x0), map_size)
	var iz0 := posmod(int(z0), map_size)
	var ix1 := (ix0 + 1) % map_size
	var iz1 := (iz0 + 1) % map_size
	var c00 := img.get_pixel(ix0, iz0)
	var c10 := img.get_pixel(ix1, iz0)
	var c01 := img.get_pixel(ix0, iz1)
	var c11 := img.get_pixel(ix1, iz1)
	var r := c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), tz)
	return Vector3(r.r, r.g, r.b) * p.displacement_scale

func displacement_at(x: float, z: float) -> Vector3:
	var d := Vector3.ZERO
	for i in CPU_CASCADES:
		d += _sample(i, x, z)
	return d

## Surface height at world column (x, z): the displaced surface moves points horizontally, so the rest
## position is found by fixed-point iteration, exactly like the vertex shader displaces the grid.
func height_at(x: float, z: float) -> float:
	var px := x
	var pz := z
	for _i in 2:
		var d := displacement_at(px, pz)
		px = x - d.x
		pz = z - d.z
	return displacement_at(px, pz).y

# --- Clipmap (unchanged geometry from the Gerstner version) -------------------------------------

func _build_level(cell: float, with_hole: bool) -> ArrayMesh:
	var n := cells_per_level
	var half := n * cell * 0.5
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var hole_lo := n / 4 + 1
	var hole_hi := n - n / 4 - 1
	for z in n + 1:
		for x in n + 1:
			verts.append(Vector3(-half + x * cell, 0.0, -half + z * cell))
	for z in n:
		for x in n:
			if with_hole and x >= hole_lo and x < hole_hi and z >= hole_lo and z < hole_hi:
				continue
			var i0 := z * (n + 1) + x
			var i1 := i0 + 1
			var i2 := i0 + n + 1
			var i3 := i2 + 1
			idx.append_array([i0, i1, i2, i1, i3, i2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-half, -30.0, -half), Vector3(half * 2.0, 60.0, half * 2.0))
	return m

func _snap(cam_pos: Vector3) -> void:
	for l in levels:
		var c := _level_cell[l]
		_level_nodes[l].global_position = Vector3(snappedf(cam_pos.x, c), 0.0, snappedf(cam_pos.z, c))
		_level_nodes[l].set_instance_shader_parameter("lod_bias", 0.08 * float(l))

func _exit_tree() -> void:
	# Detach the compute textures before the generator frees them (avoids RID errors on shutdown).
	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
