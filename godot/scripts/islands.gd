extends Node3D
## Procedural low-poly tropical islands spawned ahead of the ship on both sides and recycled once
## they are far behind, plus a far horizon mountain silhouette that follows the ship.

@export var island_count := 7
@export var min_lateral := 260.0
@export var max_lateral := 900.0
@export var ahead_min := 600.0
@export var ahead_max := 1900.0
@export var behind_recycle := 300.0
@export var seed_base := 1337
@export var ship_path := NodePath("../Ship")
@export var horizon_radius := 6200.0

var _ship: Node3D
var _counter := 0
var _side := 1.0
var _islands: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _island_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _palm_mesh: ArrayMesh
var _ring: MeshInstance3D

func _ready() -> void:
	add_to_group("rebase")
	_ship = get_node(ship_path)
	_rng.seed = seed_base
	_island_mat = StandardMaterial3D.new()
	_island_mat.vertex_color_use_as_albedo = true
	_island_mat.roughness = 0.95
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.36, 0.25, 0.15)
	_trunk_mat.roughness = 1.0
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_color = Color(0.12, 0.42, 0.14)
	_leaf_mat.roughness = 0.9
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_palm_mesh = _build_palm_mesh()
	_build_horizon()
	for i in island_count:
		_spawn(_ship.global_position.z + 150.0 - (float(i) / island_count) * 1900.0 - _rng.randf() * 120.0)

func rebase(shift: Vector3) -> void:
	for isl in _islands:
		isl.global_position -= shift

func _process(_delta: float) -> void:
	_ring.global_position = Vector3(_ship.global_position.x, 0.0, _ship.global_position.z)
	for isl in _islands.duplicate():
		if isl.global_position.z > _ship.global_position.z + behind_recycle + float(isl.get_meta("radius")):
			_islands.erase(isl)
			isl.queue_free()
			_spawn(_ship.global_position.z - _rng.randf_range(ahead_min + 400.0, ahead_max))

func _spawn(z: float) -> void:
	_counter += 1
	var seed_i := seed_base + _counter * 7919
	var r := RandomNumberGenerator.new()
	r.seed = seed_i
	var radius := r.randf_range(70.0, 190.0)
	var peak := r.randf_range(22.0, 62.0)
	_side = -_side
	var lateral := maxf(r.randf_range(min_lateral, max_lateral), radius + 170.0)
	var isl := _make_island(seed_i, radius, peak)
	isl.set_meta("radius", radius)
	add_child(isl)
	isl.global_position = Vector3(_ship.global_position.x + _side * lateral, 0.0, z)
	_islands.append(isl)

func _make_island(seed_i: int, radius: float, peak: float) -> Node3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_i
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = seed_i + 1
	shape_noise.frequency = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var stretch := Vector2(rng.randf_range(0.8, 1.35), rng.randf_range(0.8, 1.35))
	var height_fn := func(x: float, z: float) -> float:
		var ang := atan2(z, x)
		var edge := radius * (0.75 + 0.35 * shape_noise.get_noise_2d(cos(ang) * 1.5, sin(ang) * 1.5))
		var q := Vector2(x / stretch.x, z / stretch.y).length() / edge
		var shape := clampf(1.0 - q, 0.0, 1.0)
		var n := noise.get_noise_2d(x, z)
		var ridge := 1.0 - absf(n) * 1.6
		return -7.0 + (peak + 7.0) * pow(shape, 1.25) * (0.75 + 0.45 * ridge) + 3.0 * shape_noise.get_noise_2d(x * 0.05, z * 0.05) * shape
	var node := Node3D.new()
	var ext := radius * 1.45
	var cells := 46
	var step := ext * 2.0 / cells
	var grid: Array[PackedFloat32Array] = []
	for zi in cells + 1:
		var row := PackedFloat32Array()
		for xi in cells + 1:
			row.append(height_fn.call(-ext + xi * step, -ext + zi * step))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in cells:
		for xi in cells:
			var h00 := grid[zi][xi]; var h10 := grid[zi][xi + 1]
			var h01 := grid[zi + 1][xi]; var h11 := grid[zi + 1][xi + 1]
			if maxf(maxf(h00, h10), maxf(h01, h11)) < -3.0:
				continue # fully deep underwater, never visible
			var x0 := -ext + xi * step; var z0 := -ext + zi * step
			var p00 := Vector3(x0, h00, z0); var p10 := Vector3(x0 + step, h10, z0)
			var p01 := Vector3(x0, h01, z0 + step); var p11 := Vector3(x0 + step, h11, z0 + step)
			_tri(st, p00, p01, p10, peak, noise)
			_tri(st, p10, p01, p11, peak, noise)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _island_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	# Palms on the green band.
	var palms := int(radius / 10.0)
	for i in palms:
		var x := rng.randf_range(-radius, radius)
		var z := rng.randf_range(-radius, radius)
		var h: float = height_fn.call(x, z)
		if h > 1.1 and h < peak * 0.4:
			var palm := MeshInstance3D.new()
			palm.mesh = _palm_mesh
			palm.position = Vector3(x, h - 0.2, z)
			palm.rotation.y = rng.randf() * TAU
			var s := rng.randf_range(0.8, 1.5)
			palm.scale = Vector3(s, s, s)
			palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(palm)
	if seed_i % 3 == 0:
		node.add_child(_make_lighthouse(height_fn.call(0.0, 0.0)))
	return node

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, peak: float, noise: FastNoiseLite) -> void:
	var h := (a.y + b.y + c.y) / 3.0
	var cen := (a + b + c) / 3.0
	var n := noise.get_noise_2d(cen.x * 3.0, cen.z * 3.0) * 0.5 + 0.5
	var col: Color
	if h < 0.3:
		col = Color(0.62, 0.55, 0.38) # wet sand / shallows
	elif h < 2.4:
		col = Color(0.88, 0.80, 0.58) # beach
	elif h < peak * 0.62:
		col = Color(0.16, 0.46, 0.17).lerp(Color(0.30, 0.55, 0.20), n) # jungle
	else:
		col = Color(0.46, 0.43, 0.40).lerp(Color(0.60, 0.57, 0.53), n) # rock
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)

func _make_lighthouse(base_y: float) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 3.0; cyl.top_radius = 2.0; cyl.height = 16.0; cyl.radial_segments = 8
	body.mesh = cyl
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.93, 0.92, 0.88)
	body.material_override = m
	body.position = Vector3(0, base_y + 8.0, 0)
	n.add_child(body)
	var band := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.bottom_radius = 2.62; bc.top_radius = 2.38; bc.height = 3.0; bc.radial_segments = 8
	band.mesh = bc
	var rm := StandardMaterial3D.new(); rm.albedo_color = Color(0.75, 0.12, 0.1)
	band.material_override = rm
	band.position = Vector3(0, base_y + 9.0, 0)
	n.add_child(band)
	var lamp := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.bottom_radius = 1.5; lc.top_radius = 1.5; lc.height = 2.2; lc.radial_segments = 8
	lamp.mesh = lc
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.9, 0.5); lm.emission_enabled = true
	lm.emission = Color(1.0, 0.8, 0.35); lm.emission_energy_multiplier = 3.0
	lamp.material_override = lm
	lamp.position = Vector3(0, base_y + 17.1, 0)
	n.add_child(lamp)
	var roof := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.bottom_radius = 2.0; rc.top_radius = 0.1; rc.height = 1.8; rc.radial_segments = 8
	roof.mesh = rc
	roof.material_override = rm
	roof.position = Vector3(0, base_y + 19.0, 0)
	n.add_child(roof)
	return n

func _build_palm_mesh() -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 4
	var pos := Vector3.ZERO
	var lean := Vector3(0.35, 1.0, 0.1).normalized()
	for i in segs:
		var cm := CylinderMesh.new()
		cm.bottom_radius = lerpf(0.24, 0.12, float(i) / segs)
		cm.top_radius = lerpf(0.24, 0.12, float(i + 1.0) / segs)
		cm.height = 1.4
		cm.radial_segments = 5
		cm.rings = 1
		cm.cap_top = false; cm.cap_bottom = false
		var bend := Vector3(lean.x * (1.0 + i * 0.25), 1.0, lean.z)
		var up := bend.normalized()
		var b := Basis(Quaternion(Vector3.UP, up))
		trunk.append_from(cm, 0, Transform3D(b, pos + up * 0.7))
		pos += up * 1.4
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var yaw := float(i) / 8.0 * TAU
		var dirv := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-dirv.z, 0, dirv.x)
		var o := pos
		var m1 := o + dirv * 1.1 + Vector3(0, 0.55, 0)
		var tip := o + dirv * 2.7 + Vector3(0, -0.2, 0)
		var l1 := m1 - side * 0.5; var r1 := m1 + side * 0.5
		for v in [o, r1, l1, l1, r1, tip, ]:
			leaves.set_normal(Vector3.UP)
			leaves.add_vertex(v)
	var mesh := ArrayMesh.new()
	trunk.commit(mesh)
	leaves.commit(mesh)
	mesh.surface_set_material(0, _trunk_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh

func _build_horizon() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_base
	noise.frequency = 0.6
	noise.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 360
	var layers := [
		{"r": horizon_radius * 1.0, "h": 520.0, "off": 0.0, "top": Color(0.55, 0.64, 0.74), "bot": Color(0.78, 0.82, 0.86)},
		{"r": horizon_radius * 0.82, "h": 330.0, "off": 40.0, "top": Color(0.42, 0.52, 0.62), "bot": Color(0.72, 0.77, 0.82)},
	]
	for L in layers:
		var r: float = L["r"]
		for i in segs:
			var a0 := float(i) / segs * TAU
			var a1 := float(i + 1) / segs * TAU
			var h0 := _ridge(noise, a0, float(L["off"])) * float(L["h"])
			var h1 := _ridge(noise, a1, float(L["off"])) * float(L["h"])
			var b0 := Vector3(cos(a0) * r, -60.0, sin(a0) * r)
			var b1 := Vector3(cos(a1) * r, -60.0, sin(a1) * r)
			var t0 := Vector3(cos(a0) * r, h0, sin(a0) * r)
			var t1 := Vector3(cos(a1) * r, h1, sin(a1) * r)
			var tc: Color = L["top"]
			var bc: Color = L["bot"]
			for v in [[b0, bc], [t0, tc], [b1, bc], [b1, bc], [t0, tc], [t1, tc]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	_ring = MeshInstance3D.new()
	_ring.mesh = st.commit()
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.extra_cull_margin = 10000.0
	add_child(_ring)

func _ridge(noise: FastNoiseLite, ang: float, off: float) -> float:
	var n := noise.get_noise_2d(cos(ang) * 2.0 + off, sin(ang) * 2.0 + off) # [-1, 1]
	var m := clampf((n + 0.1) * 1.8, 0.0, 1.0)
	return pow(m, 1.5) * (0.5 + 0.5 * noise.get_noise_2d(ang * 9.0, off))
