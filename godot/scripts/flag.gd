extends Node3D
## Verlet cloth flag on the pavilion (stern) mast. The left column is pinned to the staff; the rest is driven by the
## apparent wind in ship space (same model as the sails), gravity and per-particle gusts. Rendered as a double-sided
## mesh rebuilt every frame (the texture is drawn at startup: black field, tattered edge, shield with crown).

@export var ship_path := NodePath("../..")
@export var loader_path := NodePath("../Model")
@export var staff_mesh_name := "pavillion_mast"
@export var cols := 17
@export var rows := 10
@export var spacing := 0.2
@export var attach_drop := 0.35 ## the flag hangs this far below the staff tip

var _ship: Node
var _pos: Array[Vector3] = []
var _prev: Array[Vector3] = []
var _pin: Array[Vector3] = []
var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _acc_t := 0.0
var _ready_flag := false
var _t := 0.0
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()

func _ready() -> void:
	_ship = get_node(ship_path)
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_mi.extra_cull_margin = 5.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = _make_texture()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.9
	m.backlight_enabled = true
	m.backlight = Color(0.3, 0.3, 0.3)
	_mi.material_override = m
	_mi.top_level = false
	add_child(_mi)
	get_node(loader_path).ship_ready.connect(_on_ship_ready)

func _on_ship_ready(_l: float, _b: float, _r: float) -> void:
	var staff := get_node(loader_path).find_child("*" + staff_mesh_name + "*", true, false) as MeshInstance3D
	var tip := Vector3(0.0, 13.0, 19.6)
	if staff:
		var pivot_inv := get_parent().global_transform.affine_inverse() as Transform3D
		var box: AABB = (pivot_inv * staff.global_transform) * staff.get_aabb()
		# Tip of the staff: highest point, centred on x.
		var skinned := ModelUtil.local_aabb(staff)
		var b := (pivot_inv * staff.global_transform) * skinned if skinned.size.length() > 0.0 else box
		tip = Vector3(b.get_center().x, b.end.y, b.get_center().z)
	position = Vector3.ZERO
	_pos.clear(); _prev.clear(); _pin.clear()
	var top := tip - Vector3(0, attach_drop, 0)
	for r in rows:
		for c in cols:
			var p := top + Vector3(0.0, -float(r) * spacing, -float(c) * spacing) # initial: streaming toward the bow
			_pos.append(p); _prev.append(p)
			if c == 0:
				_pin.append(p)
			else:
				_pin.append(Vector3.INF)
	_build_topology()
	_ready_flag = true
	print("[flag] staff tip ", tip)

func _build_topology() -> void:
	_uvs.clear(); _idx.clear()
	for r in rows:
		for c in cols:
			_uvs.append(Vector2(float(c) / (cols - 1), float(r) / (rows - 1)))
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			_idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])

func _process(delta: float) -> void:
	if not _ready_flag:
		return
	_t += delta
	_acc_t += minf(delta, 0.05)
	var step := 1.0 / 60.0
	var w := WorldState
	var yaw: float = _ship.get("yaw") if _ship.get("yaw") != null else 0.0
	var speed: float = _ship.get("current_speed") if _ship.get("current_speed") != null else 6.0
	var wl := Basis(Vector3.UP, yaw).inverse() * Vector3(w.wind_vector().x, 0.0, w.wind_vector().y)
	var app := wl * w.wind_speed_ms() + Vector3(0.0, 0.0, speed)
	while _acc_t >= step:
		_acc_t -= step
		_simulate(step, app, w)
	_update_mesh()

func _simulate(dt: float, wind: Vector3, w: Node) -> void:
	var gust: float = 1.0 + 0.35 * float(w.wind_strength) + 0.9 * float(w.storm)
	for i in _pos.size():
		if _pin[i] != Vector3.INF:
			_pos[i] = _pin[i]
			_prev[i] = _pin[i]
	# Normals for the aerodynamic force.
	for r in rows:
		for c in cols:
			var i := r * cols + c
			if _pin[i] != Vector3.INF:
				continue
			var right := _pos[r * cols + mini(c + 1, cols - 1)] - _pos[r * cols + maxi(c - 1, 0)]
			var down := _pos[mini(r + 1, rows - 1) * cols + c] - _pos[maxi(r - 1, 0) * cols + c]
			var n := right.cross(down)
			if n.length_squared() < 1e-8:
				n = Vector3.UP
			n = n.normalized()
			var vel := (_pos[i] - _prev[i]) / dt
			var local_wind: Vector3 = wind * (gust + 0.35 * sin(_t * 3.1 + float(c) * 0.9 + float(r) * 0.5)) \
				+ Vector3(0.0, 0.6 * sin(_t * 2.3 + float(c)), 0.0) * (0.3 + float(w.wind_strength))
			var rel: Vector3 = local_wind - vel
			var f: Vector3 = n * n.dot(rel) * 0.18 + rel * 0.04  # lift-like pressure + a little drag
			var acc: Vector3 = f + Vector3(0.0, -2.2, 0.0)
			var np := _pos[i] + (_pos[i] - _prev[i]) * 0.985 + acc * dt * dt * 60.0
			_prev[i] = _pos[i]
			_pos[i] = np
	# Structural + shear constraints.
	for _it in 5:
		for r in rows:
			for c in cols:
				var i := r * cols + c
				if c < cols - 1:
					_constrain(i, i + 1, spacing)
				if r < rows - 1:
					_constrain(i, i + cols, spacing)
				if c < cols - 1 and r < rows - 1:
					_constrain(i, i + cols + 1, spacing * 1.4142)
					_constrain(i + 1, i + cols, spacing * 1.4142)

func _constrain(a: int, b: int, rest: float) -> void:
	var d := _pos[b] - _pos[a]
	var l := d.length()
	if l < 1e-6:
		return
	var diff := (l - rest) / l
	var pa := _pin[a] != Vector3.INF
	var pb := _pin[b] != Vector3.INF
	if pa and pb:
		return
	if pa:
		_pos[b] -= d * diff
	elif pb:
		_pos[a] += d * diff
	else:
		_pos[a] += d * diff * 0.5
		_pos[b] -= d * diff * 0.5

func _update_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(_pos.size())
	norms.resize(_pos.size())
	for r in rows:
		for c in cols:
			var i := r * cols + c
			verts[i] = _pos[i]
			var right := _pos[r * cols + mini(c + 1, cols - 1)] - _pos[r * cols + maxi(c - 1, 0)]
			var down := _pos[mini(r + 1, rows - 1) * cols + c] - _pos[maxi(r - 1, 0) * cols + c]
			norms[i] = right.cross(down).normalized() if right.cross(down).length_squared() > 1e-8 else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = _uvs
	arr[Mesh.ARRAY_INDEX] = _idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

## Pirate flag: black field, ragged trailing edge (alpha), shield with gold crown and blue/white inner shields.
func _make_texture() -> ImageTexture:
	var W := 256
	var H := 160
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	for y in H:
		for x in W:
			var a := 1.0
			# Tattered trailing edge (right side) and slightly torn corners.
			var tear := 0.5 + 0.5 * noise.get_noise_2d(x * 1.3, y * 2.0)
			var edge := float(x) / W
			if edge > 0.82:
				a = 1.0 if tear > (edge - 0.82) * 5.5 else 0.0
			var v := 0.04 + 0.03 * noise.get_noise_2d(x * 3.0, y * 3.0)
			img.set_pixel(x, y, Color(v, v, v * 1.1, a))
	var cx := int(W * 0.40)
	var cy := int(H * 0.52)
	# Gold crown (zigzag band + base).
	for x in range(cx - 26, cx + 27):
		for y in range(cy - 62, cy - 40):
			var t := float(x - (cx - 26)) / 52.0
			var tooth := 0.5 + 0.5 * absf(sin(t * PI * 3.0))
			if y > cy - 62 + int((1.0 - tooth) * 14.0) or y > cy - 48:
				img.set_pixel(x, y, Color(0.92, 0.72, 0.2, 1.0))
	# Shield: red border, white field, five blue marks.
	for y in range(cy - 40, cy + 46):
		for x in range(cx - 34, cx + 35):
			var dy := float(y - (cy - 40)) / 86.0
			var half := 34.0 * (1.0 - pow(maxf(dy - 0.55, 0.0) / 0.45, 1.6))
			if absf(x - cx) <= half:
				var inner := absf(x - cx) <= half - 6.0 and y >= cy - 34 and dy < 0.93
				img.set_pixel(x, y, Color(0.92, 0.93, 0.95, 1.0) if inner else Color(0.78, 0.1, 0.1, 1.0))
	for p in [Vector2(0, -22), Vector2(-14, -4), Vector2(14, -4), Vector2(0, 8), Vector2(0, 28)]:
		for yy in range(-6, 7):
			for xx in range(-5, 6):
				var px := cx + int(p.x) + xx
				var py := cy + int(p.y) + yy
				if px >= 0 and px < W and py >= 0 and py < H and absf(xx) + absf(yy) * 0.7 < 7.0:
					img.set_pixel(px, py, Color(0.1, 0.2, 0.62, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
