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
const ISLAND_SHADER := preload("res://shaders/island.gdshader")
const HORIZON_SHADER := preload("res://shaders/island_horizon.gdshader")
## Ocean `shallow_color` default (shaders/ocean/common.gdshaderinc); read live from the ocean material when available so the
## underwater sand shelf fades into the same turquoise the water shader paints around the island.
const SHALLOW_DEFAULT := Color(0.05, 0.62, 0.58)

var _island_mat: ShaderMaterial
var _trunk_mat: ShaderMaterial
var _leaf_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _bush_mat: ShaderMaterial
var _palm_mesh: ArrayMesh
var _rock_mesh: ArrayMesh
var _bush_mesh: ArrayMesh
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _shallow := SHALLOW_DEFAULT

func _lit_mat(tint: Color, use_vertex_color := false, rough := 0.95) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ISLAND_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("use_vertex_color", use_vertex_color)
	m.set_shader_parameter("roughness", rough)
	return m

func _ready() -> void:
	add_to_group("rebase")
	_ship = get_node(ship_path)
	_rng.seed = seed_base
	_island_mat = _lit_mat(Color.WHITE, true)
	_trunk_mat = _lit_mat(Color(0.36, 0.25, 0.15), false, 1.0)
	_leaf_mat = _lit_mat(Color(0.13, 0.46, 0.15))
	_rock_mat = _lit_mat(Color(0.58, 0.55, 0.51), false, 0.9)
	_bush_mat = _lit_mat(Color(0.17, 0.44, 0.17))
	_palm_mesh = _build_palm_mesh()
	_rock_mesh = _build_blob_mesh(5, 3, 0.55)
	_bush_mesh = _build_blob_mesh(6, 3, 0.8)
	_build_horizon()
	for i in island_count:
		_spawn_ahead(-150.0 + (float(i) / island_count) * 2000.0 + _rng.randf() * 120.0)

func rebase(shift: Vector3) -> void:
	for isl in _islands:
		isl.global_position -= shift

func _push_to_ocean() -> void:
	if Waves.ocean == null:
		return
	var list := PackedVector4Array()
	for isl in _islands:
		var sh: Vector2 = isl.get_meta("shore")
		list.append(Vector4(isl.global_position.x, isl.global_position.z, maxf(sh.x, 8.0), maxf(sh.y, 8.0)))
	Waves.ocean.set_islands(list)

func _process(_delta: float) -> void:
	_push_to_ocean()
	# The far mountains take their colour from the sky globals in island_horizon.gdshader (no manual dimming).
	_ring.global_position = Vector3(_ship.global_position.x, 0.0, _ship.global_position.z)
	var sp := Vector2(_ship.global_position.x, _ship.global_position.z)
	var fwd: Vector2 = _ship.forward if "forward" in _ship else Vector2(0, -1)
	for isl in _islands.duplicate():
		var rel := Vector2(isl.global_position.x, isl.global_position.z) - sp
		var behind := rel.dot(fwd) < -(behind_recycle + float(isl.get_meta("radius")))
		if rel.length() > 2300.0 or (behind and rel.length() > 700.0):
			_islands.erase(isl)
			isl.queue_free()
			_spawn_ahead(_rng.randf_range(ahead_min + 300.0, ahead_max))

## Islands as autopilot targets: [{pos: Vector2 (world xz), radius: float (clearance radius)}].
func targets() -> Array:
	var out := []
	for isl in _islands:
		var sh: Vector2 = isl.get_meta("shore")
		out.append({"pos": Vector2(isl.global_position.x, isl.global_position.z), "radius": maxf(sh.x, sh.y) + 40.0})
	return out

## Spawns an island `ahead` metres in front of the ship (along its heading), offset sideways.
func _spawn_ahead(ahead: float) -> void:
	var fwd: Vector2 = _ship.forward if "forward" in _ship else Vector2(0, -1)
	var right := Vector2(-fwd.y, fwd.x) # perpendicular (starboard is (cos yaw, -sin yaw) = (-fwd.y, fwd.x))
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
	isl.set_meta("shore", isl.get_meta("shore_xz"))
	add_child(isl)
	var sp := Vector2(_ship.global_position.x, _ship.global_position.z)
	var p := sp + fwd * ahead + right * _side * lateral
	isl.global_position = Vector3(p.x, 0.0, p.y)
	_islands.append(isl)

func _make_island(seed_i: int, radius: float, peak: float) -> Node3D:
	_refresh_shallow()
	var noise := FastNoiseLite.new()
	noise.seed = seed_i
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = seed_i + 1
	shape_noise.frequency = 0.9
	var hill_noise := FastNoiseLite.new()
	hill_noise.seed = seed_i + 2
	hill_noise.frequency = 0.018
	var detail := FastNoiseLite.new() # colour breakup, not shape
	detail.seed = seed_i + 3
	detail.frequency = 0.07
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
		# A broad shoulder (second hill) breaks the single cone silhouette; the crest keeps its ridged character.
		var shoulder := maxf(hill_noise.get_noise_2d(x + 400.0, z - 300.0), 0.0) * peak * 0.34 * shape * shape
		return -7.0 + (peak + 7.0) * pow(shape, 1.25) * (0.7 + 0.45 * ridge) + shoulder + 3.0 * shape_noise.get_noise_2d(x * 0.05, z * 0.05) * shape
	var node := Node3D.new()
	var ext := radius * 1.45
	var cells := 56
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
			_tri(st, p00, p01, p10, peak, detail, step)
			_tri(st, p10, p01, p11, peak, detail, step)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _island_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	# Vegetation, rocks and bushes as one MultiMesh each (cheap, one draw call per kind per island).
	var palms: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	for i in int(radius / 6.0):
		var x := rng.randf_range(-radius * 1.15, radius * 1.15)
		var z := rng.randf_range(-radius * 1.15, radius * 1.15)
		var h: float = height_fn.call(x, z)
		var kind := rng.randf()
		if h > 1.1 and h < peak * 0.42 and kind < 0.55:
			var s := rng.randf_range(0.8, 1.5)
			palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.2, z)))
		elif h > 1.6 and h < peak * 0.55 and kind < 0.8:
			var sb := rng.randf_range(1.6, 3.4)
			bushes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sb, sb * rng.randf_range(0.55, 0.85), sb)), Vector3(x, h + 0.1, z)))
		elif h > -0.6 and h < 3.0:
			var sr := rng.randf_range(0.9, 3.2)
			rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sr, sr * rng.randf_range(0.6, 1.0), sr * rng.randf_range(0.8, 1.2))), Vector3(x, h - 0.15, z)))
	_add_multimesh(node, _palm_mesh, palms, [])
	_add_multimesh(node, _bush_mesh, bushes, [], _bush_mat)
	_add_multimesh(node, _rock_mesh, rocks, [], _rock_mat)
	if seed_i % 3 == 0:
		node.add_child(_make_lighthouse(height_fn.call(0.0, 0.0)))
	# Waterline ellipse radii (where the height crosses 0 along +-X and +-Z), used for the turquoise shallows.
	var shore := Vector2.ZERO
	for axis in 2:
		var acc := 0.0
		for sgn in [-1.0, 1.0]:
			var r := 0.0
			var found := radius * 0.4
			while r < ext:
				var hx: float = height_fn.call(sgn * r if axis == 0 else 0.0, sgn * r if axis == 1 else 0.0)
				if hx < 0.0:
					found = r
					break
				r += 2.0
			acc += found
		shore[axis] = acc * 0.5
	node.set_meta("shore_xz", shore)
	return node

## Instances `mesh` at `xfs` as one MultiMeshInstance3D under `parent` (per-instance colour when `cols` is given).
func _add_multimesh(parent: Node3D, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material = null) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if mat != null:
		inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)

## Reads the ocean's `shallow_color` uniform (read-only) so the underwater shelf matches the water around the island.
func _refresh_shallow() -> void:
	if Waves.ocean == null:
		return
	var m: Variant = (Waves.ocean as GeometryInstance3D).material_override
	if m is ShaderMaterial:
		var c: Variant = (m as ShaderMaterial).get_shader_parameter("shallow_color")
		if c is Color:
			_shallow = c
		elif c is Vector3:
			_shallow = Color(c.x, c.y, c.z)

## Smooth vertex colour by height, slope and noise: shelf -> wet sand -> beach -> dune grass -> jungle -> rock.
func _vcol(pos: Vector3, slope: float, peak: float, n: float) -> Color:
	var h := pos.y
	var sand_wet := Color(0.58, 0.52, 0.38)
	var sand := Color(0.90, 0.83, 0.62)
	var grass_dry := Color(0.50, 0.58, 0.26)
	var jungle_lo := Color(0.12, 0.40, 0.14)
	var jungle_hi := Color(0.30, 0.52, 0.19)
	var rock_lo := Color(0.40, 0.37, 0.35)
	var rock_hi := Color(0.62, 0.59, 0.55)
	# Underwater: sand shelf fading into the ocean's shallow colour (the water shader tints the same way near islands).
	var shelf := sand_wet.lerp(_shallow * Color(1.15, 1.0, 0.9), smoothstep(0.0, -3.5, h))
	var col := shelf
	if h > 0.0:
		var beach_top := 2.2 + 1.6 * n
		col = sand_wet.lerp(sand, smoothstep(0.0, 0.9, h))
		col = col.lerp(grass_dry, smoothstep(beach_top - 0.8, beach_top + 0.6, h))
		var jungle := jungle_lo.lerp(jungle_hi, clampf(n * 0.5 + 0.5 + h / peak * 0.5, 0.0, 1.0))
		col = col.lerp(jungle, smoothstep(beach_top, beach_top + 2.4, h))
		var tree_line := peak * (0.68 + 0.10 * n)
		var rock := rock_lo.lerp(rock_hi, clampf(h / peak + n * 0.2, 0.0, 1.0))
		col = col.lerp(rock, smoothstep(tree_line - peak * 0.06, tree_line + peak * 0.05, h))
		# Steep faces show bare stone at any height above the beach (cliffs, gullies).
		col = col.lerp(rock, smoothstep(1.5, 2.4, slope) * smoothstep(2.0, 6.0, h))
	return col

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, peak: float, detail: FastNoiseLite, step: float) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	var slope := sqrt(maxf(1.0 - nrm.y * nrm.y, 0.0)) / maxf(absf(nrm.y), 0.05) # |gradient| of the face
	for v in [a, b, c]:
		var n := detail.get_noise_2d(v.x, v.z)
		st.set_color(_vcol(v, slope, peak, n))
		st.add_vertex(v)

func _make_lighthouse(base_y: float) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 3.0; cyl.top_radius = 2.0; cyl.height = 16.0; cyl.radial_segments = 8
	body.mesh = cyl
	var m := _lit_mat(Color(0.93, 0.92, 0.88), false, 0.8)
	body.material_override = m
	body.position = Vector3(0, base_y + 8.0, 0)
	n.add_child(body)
	var band := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.bottom_radius = 2.62; bc.top_radius = 2.38; bc.height = 3.0; bc.radial_segments = 8
	band.mesh = bc
	var rm := _lit_mat(Color(0.75, 0.12, 0.1), false, 0.7)
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
	var beam := Node3D.new()
	beam.set_script(load("res://scripts/ambient/lighthouse_beam.gd"))
	beam.position = lamp.position
	n.add_child(beam)
	var roof := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.bottom_radius = 2.0; rc.top_radius = 0.1; rc.height = 1.8; rc.radial_segments = 8
	roof.mesh = rc
	roof.material_override = rm
	roof.position = Vector3(0, base_y + 19.0, 0)
	n.add_child(roof)
	return n

## Faceted rock / bush blob: a low-poly sphere with deterministic per-vertex jitter, unit-ish radius, flat shaded.
func _build_blob_mesh(radial: int, rings: int, jitter: float) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radial_segments = radial
	sm.rings = rings
	sm.radius = 1.0
	sm.height = 1.6
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var r := RandomNumberGenerator.new()
	r.seed = 4242 + radial
	var jit := {}
	for i in verts.size():
		var key := Vector3(snappedf(verts[i].x, 0.01), snappedf(verts[i].y, 0.01), snappedf(verts[i].z, 0.01))
		if not jit.has(key):
			jit[key] = 1.0 + r.randf_range(-jitter, jitter) * 0.5
		verts[i] *= float(jit[key])
	arr[Mesh.ARRAY_VERTEX] = verts
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3): # flip the winding so the regenerated flat normals point outward
		var tmp_i := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = tmp_i
	arr[Mesh.ARRAY_INDEX] = idx
	var flat := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	flat.create_from(tmp, 0)
	flat.deindex()
	flat.generate_normals()
	return flat.commit()

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
		{"r": horizon_radius * 1.0, "h": 520.0, "off": 0.0, "top": Color(1.0, 0.0, 0.0), "bot": Color(0.0, 0.0, 0.0)},
		{"r": horizon_radius * 0.82, "h": 330.0, "off": 40.0, "top": Color(1.0, 1.0, 0.0), "bot": Color(0.0, 1.0, 0.0)},
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
	var mat := ShaderMaterial.new()
	mat.shader = HORIZON_SHADER
	_ring = MeshInstance3D.new()
	_ring.mesh = st.commit()
	_ring.material_override = mat
	_ring_mat = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.extra_cull_margin = 10000.0
	add_child(_ring)

func _ridge(noise: FastNoiseLite, ang: float, off: float) -> float:
	var n := noise.get_noise_2d(cos(ang) * 2.0 + off, sin(ang) * 2.0 + off) # [-1, 1]
	var m := clampf((n + 0.1) * 1.8, 0.0, 1.0)
	return pow(m, 1.5) * (0.5 + 0.5 * noise.get_noise_2d(ang * 9.0, off))
