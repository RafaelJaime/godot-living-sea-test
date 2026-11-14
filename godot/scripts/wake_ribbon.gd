extends MeshInstance3D
## Ship wake as ribbon meshes built from the ship's path history (stern wake + two bow-wave lines).
## Vertices are snapped onto the FFT surface in wake_ribbon.gdshader, so the foam rides the waves.
## Points live in world space and are shifted on world rebase.

@export var ship_path := NodePath("../Ship")
@export var spacing := 0.7 ## metres between history points
@export var stern_life := 26.0
@export var bow_life := 9.0
@export var across_verts := 9

class Track:
	var pts: Array[Vector2] = []   # world xz
	var ages: Array[float] = []
	var dirs: Array[Vector2] = []  # unit direction of travel at the point
	var dist: Array[float] = []    # cumulative distance (UV.y)
	var life := 20.0
	var w0 := 2.0
	var w1 := 10.0
	var strength := 1.0

var _ship: Node3D
var _mat: ShaderMaterial
var _tracks: Array[Track] = []
var _last := Vector2(INF, INF)
var _travel := 0.0
var _length := 22.0
var _beam := 7.0
var _scales_set := false

func _ready() -> void:
	add_to_group("rebase")
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 400.0
	custom_aabb = AABB(Vector3(-100000, -50, -100000), Vector3(200000, 100, 200000))
	_ship = get_node(ship_path)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/wake_ribbon.gdshader")
	_mat.set_shader_parameter("noise_tex", tex)
	_mat.render_priority = 2
	material_override = _mat
	var loader := get_node_or_null("../Ship/Pivot/Model")
	if loader and loader.has_signal("ship_ready"):
		loader.ship_ready.connect(func(l: float, b: float, _r: float) -> void:
			_length = l
			_beam = b)
	# 0 = stern wake, 1/2 = bow lines (port / starboard)
	var stern := Track.new(); stern.life = stern_life; stern.w0 = 3.0; stern.w1 = 15.0; stern.strength = 1.0
	var bp := Track.new(); bp.life = bow_life; bp.w0 = 0.9; bp.w1 = 3.5; bp.strength = 0.9
	var bs := Track.new(); bs.life = bow_life; bs.w0 = 0.9; bs.w1 = 3.5; bs.strength = 0.9
	_tracks = [stern, bp, bs]
	mesh = ArrayMesh.new()

func rebase(shift: Vector3) -> void:
	var s := Vector2(shift.x, shift.z)
	for t in _tracks:
		for i in t.pts.size():
			t.pts[i] -= s
	_last -= s

func _process(delta: float) -> void:
	if Waves.ocean == null:
		return
	if not _scales_set:
		var scales := PackedVector4Array()
		for p: WaveCascadeParameters in Waves.ocean.parameters:
			var uv: Vector2 = Vector2.ONE / p.tile_length
			scales.append(Vector4(uv.x, uv.y, p.displacement_scale, p.normal_scale))
		_mat.set_shader_parameter("map_scales", scales)
		_scales_set = true
	var pos := Vector2(_ship.global_position.x, _ship.global_position.z)
	var yaw := _ship.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))   # ship forward is -Z rotated by yaw about Y
	var right := Vector2(fwd.y * -1.0, fwd.x)  # perpendicular
	right = Vector2(cos(yaw), -sin(yaw))
	if _last.x == INF or pos.distance_to(_last) >= spacing:
		var step := 0.0 if _last.x == INF else pos.distance_to(_last)
		_travel += step
		_last = pos
		var stern_pos := pos - fwd * (_length * 0.40)
		var bow_pos := pos + fwd * (_length * 0.36)
		_push(_tracks[0], stern_pos, fwd)
		_push(_tracks[1], bow_pos - right * (_beam * 0.30), fwd)
		_push(_tracks[2], bow_pos + right * (_beam * 0.30), fwd)
	var intensity := clampf(0.55 + 0.6 * Waves.sea_state, 0.0, 1.0)
	_tracks[0].strength = intensity
	for t in _tracks:
		for i in t.ages.size():
			t.ages[i] += delta
		while t.ages.size() > 0 and t.ages[0] > t.life:
			t.pts.pop_front(); t.ages.pop_front(); t.dirs.pop_front(); t.dist.pop_front()
	_rebuild(pos, fwd)

func _push(t: Track, p: Vector2, d: Vector2) -> void:
	t.pts.append(p)
	t.ages.append(0.0)
	t.dirs.append(d)
	t.dist.append(_travel)

func _rebuild(ship_pos: Vector2, fwd: Vector2) -> void:
	var m := mesh as ArrayMesh
	m.clear_surfaces()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var av := across_verts
	for t in _tracks:
		var n := t.pts.size()
		if n < 2:
			continue
		var base := verts.size()
		for i in n:
			var age_k := t.ages[i] / t.life
			var fade := (1.0 - age_k) * smoothstep(0.0, 0.06, age_k + 0.02) # fast fade-in at the source
			fade = fade * fade * (3.0 - 2.0 * fade) if fade < 1.0 else 1.0
			fade *= t.strength
			var w := lerpf(t.w0, t.w1, sqrt(age_k)) * 0.5
			var d := t.dirs[i]
			var perp := Vector2(d.y, -d.x)
			for k in av:
				var u := float(k) / float(av - 1)
				var off := (u * 2.0 - 1.0) * w
				var q := t.pts[i] + perp * off
				verts.append(Vector3(q.x, 0.0, q.y))
				uvs.append(Vector2(u, t.dist[i]))
				cols.append(Color(absf(u * 2.0 - 1.0), 0.0, 0.0, fade))
		for i in n - 1:
			for k in av - 1:
				var a := base + i * av + k
				var b := a + 1
				var c := a + av
				var e := c + 1
				idx.append_array([a, c, b, b, c, e])
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-100000, -50, -100000), Vector3(200000, 100, 200000))
