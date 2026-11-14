extends MeshInstance3D
## Camera-following geometry-clipmap ocean. Each level is a square grid with doubled cell size;
## levels snap to their own cell size so vertices never swim against the world-space waves.

@export var base_cell := 0.8
@export var cells_per_level := 96  ## must be a multiple of 4
@export var levels := 9

var _mat: ShaderMaterial
var _level_nodes: Array[MeshInstance3D] = []
var _level_cell: Array[float] = []

func _ready() -> void:
	process_priority = 100 # after camera
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ocean.gdshader")
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.width = 512
	tex.height = 512
	_mat.set_shader_parameter("detail_normal", tex)
	Waves.push_to(_mat)
	mesh = null
	for l in levels:
		var cell := base_cell * pow(2.0, l)
		var mi := MeshInstance3D.new()
		mi.mesh = _build_level(cell, l > 0)
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 200.0
		add_child(mi)
		_level_nodes.append(mi)
		_level_cell.append(cell)
	_snap(Vector3.ZERO)

func _build_level(cell: float, with_hole: bool) -> ArrayMesh:
	var n := cells_per_level
	var half := n * cell * 0.5
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	# Vertices of the full (n+1)^2 grid; cells inside the hole are skipped (one cell of overlap).
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
		var p := Vector3(snappedf(cam_pos.x, c), 0.0, snappedf(cam_pos.z, c))
		_level_nodes[l].global_position = p
		if l == 0:
			_level_nodes[l].set_instance_shader_parameter("inner_rect", Vector4(1.0, 1.0, -1.0, -1.0))
		else:
			var prev_half := cells_per_level * _level_cell[l - 1] * 0.5
			var pp := _level_nodes[l - 1].global_position
			_level_nodes[l].set_instance_shader_parameter("inner_rect",
				Vector4(pp.x - prev_half, pp.z - prev_half, pp.x + prev_half, pp.z + prev_half))

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_snap(cam.global_position)
	Waves.push_to(_mat)
