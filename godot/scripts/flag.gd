extends Node3D
## XPBD cloth flag (ClothSolver, same solver and same WindField as the sails), simulated in WORLD space.
## Tied ONLY at the two hoist corners (halyard ties) to the real posed staff (axis derived from the CPU-skinned vertices of
## the staff mesh, re-evaluated every frame from the ship pivot transform so it follows yaw/roll/pitch/heave); the hoist
## edge between the ties and the fly edge are free. Two instances: stern staff ("pavillion_mast") and main masthead ("main_mast").

@export var ship_path := NodePath("../..")
@export var loader_path := NodePath("../Model")
@export var mesh_suffix := "pavillion_mast"
@export var cols := 16 ## particles along the flag, hoist -> fly
@export var rows := 10 ## particles down the hoist
@export var flag_length := 3.7 ## m, hoist -> fly
@export var flag_height := 2.3 ## m, down the hoist
@export var hoist_drop := 0.25 ## top tie sits this far below the pole tip (m)
@export var pole_clearance := 0.07 ## ties sit this far from the pole axis (m)
@export var pole_radius := 0.05 ## collision capsule of the staff (m)
@export var tie_slack := 0.97 ## tie distance / flag height: the hoist edge bows a little between the ties
@export var density := 0.30 ## kg/m2 (ensign bunting)
@export var texture_path := "res://assets/ship/flag_pirat.png"

var _ship: Node
var _pivot: Node3D
var _cloth: ClothSolver
var _tie_local: PackedVector3Array # [top, bottom] hoist ties, ship-pivot space
var _pole_a := Vector3.ZERO # staff axis, ship-pivot space (tip, foot)
var _pole_b := Vector3.ZERO
var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _ready_flag := false
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()
var _dbg: Array[MeshInstance3D] = []
var _log_t := 0.0
var _fly_ema := Vector3.ZERO
var _anch := PackedInt32Array()
# Bone-posed staff tracking: the staff mesh is skinned (other tracks rotate yard bones that also carry the mast truck),
# so the ties are re-derived EVERY frame from the CPU-skinned top slice of the staff mesh (a few dozen vertices).
var _skel: Skeleton3D
var _to_root := Transform3D.IDENTITY # skeleton space -> pivot space
var _sub_v := PackedVector3Array()
var _sub_b := PackedInt32Array()
var _sub_w := PackedFloat32Array()
var _sub_stride := 0
var _sub_bind := PackedInt32Array() # skin bind index -> skeleton bone
var _sub_bindpose: Array[Transform3D] = []
var _top_sel := PackedInt32Array() # subset indices of the finial cluster / the lower cluster
var _mid_sel := PackedInt32Array()
var _c_top0 := Vector3.ZERO
var _ax0 := Vector3.UP
var _tie_rest := PackedVector3Array() # ties at the ready pose (pivot space)
var _pole_a0 := Vector3.ZERO
var _pole_b0 := Vector3.ZERO

func _ready() -> void:
	add_to_group("rebase")
	add_to_group("flag_" + mesh_suffix)
	_ship = get_node(ship_path)
	_pivot = get_parent() as Node3D
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.top_level = true
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_mi.extra_cull_margin = 20.0
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(texture_path):
		m.albedo_texture = load(texture_path)
		m.uv1_scale = Vector3(0.975, 0.97, 1.0) # crop the thin white margin of the supplied image
		m.uv1_offset = Vector3(0.0125, 0.015, 0.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.9
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.35, 0.35)
	_mi.material_override = m
	add_child(_mi)
	get_node(loader_path).ship_ready.connect(_on_ship_ready.unbind(3))

func rebase(shift: Vector3) -> void:
	if _cloth:
		_cloth.rebase(shift)

func _exit_tree() -> void:
	if _cloth:
		_cloth.destroy()

func _on_ship_ready() -> void:
	var model := get_node(loader_path)
	var pole: MeshInstance3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).to_lower().ends_with(mesh_suffix):
			pole = n
	if pole == null:
		push_warning("[flag] pole mesh not found: " + mesh_suffix)
		return
	var pts := ModelUtil.posed_points(pole, _pivot)
	# Pole axis = principal axis of the posed vertices; top = the higher end.
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	var ax := Vector3(0, 1, 0)
	for _i in 12: # power iteration on the covariance
		var nv := Vector3.ZERO
		for p in pts:
			var d := p - c
			nv += d * d.dot(ax)
		ax = nv.normalized()
	if ax.y < 0.0:
		ax = -ax
	var lo := 1.0e9
	var hi := -1.0e9
	for p in pts:
		var t := (p - c).dot(ax)
		lo = minf(lo, t); hi = maxf(hi, t)
	var tip := c + ax * hi
	_pole_a = tip
	_pole_b = c + ax * lo
	# Ties sit beside the pole on the ship's starboard side (+x made orthogonal to the pole).
	var off := (Vector3.RIGHT - ax * ax.dot(Vector3.RIGHT)).normalized() * pole_clearance
	var top := tip - ax * hoist_drop + off
	_tie_local = PackedVector3Array([top, top - ax * (flag_height * tie_slack)])
	_tie_rest = _tie_local.duplicate()
	_pole_a0 = _pole_a
	_pole_b0 = _pole_b
	_ax0 = ax
	_setup_tracking(pole, tip, hi - lo)
	_build_cloth(ax)
	_ready_flag = true
	print("[flag] ", mesh_suffix, " axis ", ax.snapped(Vector3.ONE * 0.01), " tip ", tip.snapped(Vector3.ONE * 0.01), " length ", snappedf(hi - lo, 0.01), " cloth ", cols, "x", rows, " mass ", snappedf(flag_length * flag_height * density, 0.01), " kg")
	if OS.get_cmdline_user_args().has("--debug-pins"):
		for r in 2:
			var sp := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.09; sm.height = 0.18
			sp.mesh = sm
			var mat := StandardMaterial3D.new(); mat.albedo_color = Color(1, 0.1, 0.9); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sp.material_override = mat
			sp.top_level = true
			add_child(sp)
			_dbg.append(sp)

## Flat rectangle hanging from the top tie, streaming toward the apparent wind (also the self-heal layout).
func _rest_layout(ax: Vector3) -> PackedVector3Array:
	var dir := _apparent_wind(_tie_world(0))
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, 1)
	var top := _tie_world(0)
	var down := -(_pivot.get_global_transform_interpolated().basis * ax).normalized()
	var rest := PackedVector3Array()
	for r in rows:
		for c in cols:
			rest.append(top + down * (flag_height * float(r) / float(rows - 1)) + dir * (flag_length * float(c) / float(cols - 1)))
	return rest

## Keeps the skinning data of the top part of the staff mesh so its pose can be re-evaluated every frame.
func _setup_tracking(pole: MeshInstance3D, tip: Vector3, length: float) -> void:
	if pole.skin == null or pole.get_skeleton_path().is_empty():
		push_warning("[flag] %s: staff mesh not skinned" % mesh_suffix)
		return
	_skel = pole.get_node_or_null(pole.get_skeleton_path()) as Skeleton3D
	if _skel == null:
		return
	_to_root = _pivot.global_transform.affine_inverse() * _skel.global_transform
	var arr := pole.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var stride := (bones.size() / verts.size()) if (verts.size() > 0 and bones.size() > 0) else 0
	var posed := SailCloth.posed_surface(pole, 0, _pivot)
	var ytip := tip.y
	var depth := 3.3 if length > 10.0 else length + 0.1 # long mast: top slice only; short staff: all of it
	var ys := PackedFloat32Array()
	for vi in verts.size():
		var y := posed[vi].y
		if y < ytip - depth:
			continue
		_sub_v.append(verts[vi])
		ys.append(y)
		for q in stride:
			_sub_b.append(bones[vi * stride + q])
			_sub_w.append(weights[vi * stride + q])
	# finial cluster = top 0.6 m; lower cluster = the lowest quarter of the slice (a low-poly staff may have no vertex 2.5 m down)
	var sorted_y := ys.duplicate()
	sorted_y.sort()
	if sorted_y.size() >= 8:
		var y_low: float = sorted_y[sorted_y.size() / 4]
		for k in ys.size():
			if ys[k] > ytip - 0.6:
				_top_sel.append(k)
			elif ys[k] <= y_low and ytip - ys[k] > 0.8:
				_mid_sel.append(k)
	_sub_stride = stride
	for i in pole.skin.get_bind_count():
		var bone := pole.skin.get_bind_bone(i)
		if bone < 0:
			bone = _skel.find_bone(pole.skin.get_bind_name(i))
		_sub_bind.append(bone)
		_sub_bindpose.append(pole.skin.get_bind_pose(i))
	if _top_sel.is_empty() or _mid_sel.is_empty():
		push_warning("[flag] %s: staff slice empty (top %d, mid %d, subset %d, tip.y %.2f)" % [mesh_suffix, _top_sel.size(), _mid_sel.size(), _sub_v.size(), tip.y])
		_skel = null
		return
	_c_top0 = _cluster(_top_sel)
	_ax0 = (_c_top0 - _cluster(_mid_sel)).normalized() # rotation reference = the cluster axis itself

## Centroid (pivot space) of a vertex subset, skinned with the CURRENT bone pose.
func _cluster(sel: PackedInt32Array) -> Vector3:
	var poses: Array[Transform3D] = []
	for i in _sub_bind.size():
		var b := _sub_bind[i]
		poses.append((_skel.get_bone_global_pose(b) if b >= 0 else Transform3D.IDENTITY) * _sub_bindpose[i])
	var acc := Vector3.ZERO
	for k in sel:
		var p := Vector3.ZERO
		if _sub_stride == 0:
			p = _sub_v[k]
		else:
			var ws := 0.0
			for q in _sub_stride:
				var w := _sub_w[k * _sub_stride + q]
				if w > 0.0:
					p += (poses[_sub_b[k * _sub_stride + q]] * _sub_v[k]) * w
					ws += w
			p = p / ws if ws > 0.0 else _sub_v[k]
		acc += _to_root * p
	return acc / float(sel.size())

## Per frame: where the staff is NOW (ties + collision capsule), from the posed top slice of its mesh.
func _track_staff() -> void:
	if _skel == null:
		return
	var c_top := _cluster(_top_sel)
	var c_mid := _cluster(_mid_sel)
	var ax_now := (c_top - c_mid).normalized()
	var rot := Basis(Quaternion(_ax0, ax_now))
	for i in 2:
		_tie_local[i] = c_top + rot * (_tie_rest[i] - _c_top0)
	_pole_a = c_top + rot * (_pole_a0 - _c_top0)
	_pole_b = c_top + rot * (_pole_b0 - _c_top0)

func _build_cloth(ax: Vector3) -> void:
	var rest := _rest_layout(ax)
	_cloth = ClothSolver.new()
	_cloth.density = density
	_cloth.tag = "flag_" + mesh_suffix
	_cloth.cN = 1.25
	_cloth.cT = 0.07
	_cloth.substeps = 2
	_cloth.iterations = 8
	_cloth.boost_iters = 3
	_cloth.max_aero_accel = 160.0
	_cloth.max_extra_substeps = 1
	_cloth.alpha_bend = 4.0e-2
	_cloth.flutter = 1.0
	_cloth.build(cols, rows, rest)
	# The whole hoist edge is laced to the staff (interpolated between the two ties): with only the corners tied the cloth was a
	# plank hinged on the pole's axis and could never hang limp in a calm.
	for r in rows:
		_anch.append(_cloth.add_anchor(r * cols, 0.0, _hoist_world(r)))
	_cloth.post_step = _after_step
	_cloth.reset_provider = _rest_layout.bind(ax)
	_uvs.clear(); _idx.clear()
	for r in rows:
		for c in cols:
			_uvs.append(Vector2(float(c) / (cols - 1), float(r) / (rows - 1)))
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			_idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
	# Warm-up so the first frame is not a flat sheet snapping into shape.
	_update_anchors()
	_cloth._launch_xf = _cloth.pivot_inv
	for _w in 70:
		_cloth._step(1.0 / 60.0)
		_cloth.anchor_prev = _cloth.anchor_t.duplicate()
	_update_mesh()

func _hoist_world(r: int) -> Vector3:
	return _tie_world(0).lerp(_tie_world(1), float(r) / float(maxi(rows - 1, 1)))

func _tie_world(i: int) -> Vector3:
	return _pivot.get_global_transform_interpolated() * _tie_local[i]

## Apparent wind at a world point for a point that moves with the ship's pivot (for orientation / logs only).
func _apparent_wind(p: Vector3) -> Vector3:
	var fwd: Vector2 = _ship.get("forward") if _ship.get("forward") != null else Vector2(0, -1)
	var spd: float = _ship.get("current_speed") if _ship.get("current_speed") != null else 6.0
	return WindField.sample(p) - Vector3(fwd.x * spd, 0.0, fwd.y * spd)

func _update_anchors() -> void:
	_track_staff()
	_cloth.pivot_inv = _pivot.get_global_transform_interpolated().affine_inverse()
	for r in rows:
		_cloth.set_anchor(_anch[r], _hoist_world(r))
	var gt := _pivot.get_global_transform_interpolated()
	_cloth.set_capsules(PackedVector3Array([gt * _pole_a]), PackedVector3Array([gt * _pole_b]), PackedFloat32Array([pole_radius]))

func _process(delta: float) -> void:
	if not _ready_flag:
		return
	_update_anchors() # before WindField (priority 100) steps the cloth
	for r in _dbg.size():
		_dbg[r].global_position = _tie_world(r)
	if OS.get_cmdline_user_args().has("--log-wind"):
		_log_t += delta
		if _log_t > 2.0:
			_log_t = 0.0
			var d := debug_info()
			print("[wind] ", mesh_suffix, " ", d)

## How far the staff has moved from its ready pose relative to the hull (m): ~0 means it stays attached to the ship.
func staff_shift() -> float:
	return (_tie_local[0] - _tie_rest[0]).length()

## Numbers for logs: tension (N, reaction at the ties), aero pressure (Pa), gust factor seen, fly vector, stretch.
func debug_info() -> Dictionary:
	var hoist := _tie_world(0)
	var fly := _cloth.particle(rows / 2, cols - 1) - _cloth.particle(rows / 2, 0)
	return {"tension": snappedf(_cloth.constraint_force.length(), 0.01), "pressure": snappedf(_cloth.pressure, 0.01),
		"gust": snappedf(_cloth.gust_seen, 0.01), "fly": fly.snapped(Vector3.ONE * 0.01), "stretch": snappedf(_cloth.max_stretch, 0.001),
		"droop": snappedf(_cloth.particle(rows / 2, cols - 1).y - hoist.y, 0.01)}

func _after_step() -> void:
	_update_mesh()
	var fly := _cloth.particle(rows / 2, cols - 1) - _cloth.particle(rows / 2, 0)
	_fly_ema = _fly_ema.lerp(fly, 1.0 - exp(-_cloth._frame_dt / 3.0))

func _update_mesh() -> void:
	# The step is one frame old: express it in the ship frame it was computed in and re-apply the CURRENT ship transform.
	var xf := _pivot.get_global_transform_interpolated() * _cloth._launch_xf
	var pos := PackedVector3Array()
	pos.resize(_cloth.n)
	for i in _cloth.n:
		pos[i] = xf * _cloth.pos[i]
	var norms := PackedVector3Array()
	norms.resize(pos.size())
	for r in rows:
		for c in cols:
			var left := pos[r * cols + maxi(c - 1, 0)]
			var right := pos[r * cols + mini(c + 1, cols - 1)]
			var up := pos[maxi(r - 1, 0) * cols + c]
			var dn := pos[mini(r + 1, rows - 1) * cols + c]
			var n := (right - left).cross(dn - up)
			norms[r * cols + c] = n.normalized() if n.length_squared() > 1e-9 else Vector3.UP
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = _uvs
	arr[Mesh.ARRAY_INDEX] = _idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mi.global_transform = Transform3D.IDENTITY

## Camera pose that looks at the flag from the side (perpendicular to its streaming direction).
func view_pose(dist: float) -> Dictionary:
	var center := _tie_world(0)
	var fly := _fly_ema
	fly.y = 0.0
	fly = fly.normalized() if fly.length() > 0.2 else Vector3(0, 0, 1)
	var perp := fly.cross(Vector3.UP).normalized()
	var target := center + fly * flag_length * 0.45 + Vector3(0, -flag_height * 0.45, 0)
	return {"pos": target + perp * dist + Vector3(0, 0.6, 0), "look": target}
