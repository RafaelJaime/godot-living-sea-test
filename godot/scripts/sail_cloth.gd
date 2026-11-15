class_name SailCloth
extends RefCounted
## One deployed sail of the pinnace as XPBD cloth (ClothSolver + WindField, same model as the flags).
##  - Grid COLSxROWS fitted to the sail's real (posed) outline: per-row left/right extents, so trapezoids work.
##  - Head row = hard pins on the yard; clews (lower corners) = soft pins (sheets); two soft ties per side edge
##    (bowlines / leech lines); foot and leeches otherwise free -> slack in calm, luffing when the angle of attack is
##    small, backed when the wind comes from ahead, violent in a storm.
##  - The visible mesh keeps its geometry and is displaced in the vertex shader (sail_cloth.gdshader) by the simulated
##    grid (Catmull-Rom over a COLSxROWS float texture updated every frame): "skinned to the simulated grid".
##  - Exports force / centre of effort / pressure / tension in SHIP (pivot) space for the future rigid-body ship.

const COLS := 12
const ROWS := 10

var sail_name := ""
var mi: MeshInstance3D
var cloth: ClothSolver
var mats: Array[ShaderMaterial] = []
var pivot: Node3D
var tex: ImageTexture
var img: Image
var rest_local := PackedVector3Array() ## ship (pivot) space rest grid, row-major
var bz := PackedFloat32Array() ## baked mesh z per node (ship space), removed from the displacement
var ytop := 0.0
var hgt := 1.0
var z0 := 0.0
var area := 1.0
var visible_sim := true
var mast_z := 0.0
var brace := 0.0 ## current yard brace (rad), written by the rig from Ship.brace; the yard bones are rotated by the rig, here the pins follow
var mast_pos := Vector3.ZERO ## brace axis (vertical through x = 0, z), ship space, same pivot the rig uses for the bones
var _brace_sim := 0.0

# per-frame results (ship space)
var force_ship := Vector3.ZERO
var point_ship := Vector3.ZERO
var pressure := 0.0
var tension := 0.0
var gust := 1.0
var state := "slack"
var _dbuf := PackedFloat32Array()

## Builds the cloth. `shader` is sail_cloth.gdshader; `mast_zs` are the ship-space z of the three masts.
func setup(p_mi: MeshInstance3D, shader: Shader, p_pivot: Node3D, mast_zs: PackedFloat32Array, density: float, p_mast_pos: Vector3) -> bool:
	mi = p_mi
	pivot = p_pivot
	mast_pos = p_mast_pos
	sail_name = String(mi.name)
	# 1) outline of the sail surface(s) (material "ship_pinnace_sails"), posed, in ship space
	var pts := PackedVector3Array()
	for si in mi.mesh.get_surface_count():
		var mt := mi.get_active_material(si)
		if mt != null and String(mt.resource_name).contains("sails"):
			pts.append_array(posed_surface(mi, si, pivot))
	if pts.size() < 40:
		return false
	var ys := PackedFloat32Array()
	for p in pts:
		ys.append(p.y)
	ys.sort()
	var ybot := ys[int(ys.size() * 0.01)]
	ytop = ys[int(ys.size() * 0.99)]
	hgt = maxf(ytop - ybot, 0.5)
	# 2) row extents
	var xl := PackedFloat32Array()
	var xr := PackedFloat32Array()
	var band := hgt / float(ROWS - 1)
	var gxl := 1.0e9
	var gxr := -1.0e9
	for p in pts:
		gxl = minf(gxl, p.x); gxr = maxf(gxr, p.x)
	for j in ROWS:
		var yj := ytop - band * j
		var lo := 1.0e9
		var hi := -1.0e9
		for p in pts:
			if absf(p.y - yj) <= band * 0.7:
				lo = minf(lo, p.x); hi = maxf(hi, p.x)
		if hi - lo < 0.5:
			lo = gxl; hi = gxr
		xl.append(lo); xr.append(hi)
	var sl := xl.duplicate()
	var sr := xr.duplicate()
	for j in range(1, ROWS - 1):
		sl[j] = (xl[j - 1] + xl[j] * 2.0 + xl[j + 1]) * 0.25
		sr[j] = (xr[j - 1] + xr[j] * 2.0 + xr[j + 1]) * 0.25
	xl = sl; xr = sr
	# 3) rest plane z (near the yard) and baked z per node
	var zs := 0.0
	var zc := 0
	for p in pts:
		if (ytop - p.y) / hgt < 0.25:
			zs += p.z; zc += 1
	z0 = zs / maxf(float(zc), 1.0)
	var acc := PackedFloat32Array(); acc.resize(COLS * ROWS)
	var wgt := PackedFloat32Array(); wgt.resize(COLS * ROWS)
	for p in pts:
		var v := clampf((ytop - p.y) / hgt, 0.0, 1.0) * float(ROWS - 1)
		var j := mini(int(v), ROWS - 2)
		var fy := v - float(j)
		var xlv := lerpf(xl[j], xl[j + 1], fy)
		var xrv := lerpf(xr[j], xr[j + 1], fy)
		var u := clampf((p.x - xlv) / maxf(xrv - xlv, 0.1), 0.0, 1.0) * float(COLS - 1)
		var i := mini(int(u), COLS - 2)
		var fx := u - float(i)
		for dj in 2:
			for di in 2:
				var w := (fx if di == 1 else 1.0 - fx) * (fy if dj == 1 else 1.0 - fy)
				var k := (j + dj) * COLS + i + di
				acc[k] += p.z * w
				wgt[k] += w
	bz.resize(COLS * ROWS)
	var known := PackedByteArray(); known.resize(COLS * ROWS)
	for k in COLS * ROWS:
		if wgt[k] > 0.15:
			bz[k] = acc[k] / wgt[k]
			known[k] = 1
		else:
			bz[k] = z0
	for _pass in 24: # diffuse into unsupported nodes
		for j in ROWS:
			for i in COLS:
				var k := j * COLS + i
				if known[k] == 0:
					var s := 0.0
					var c := 0
					for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var ii: int = i + o.x
						var jj: int = j + o.y
						if ii >= 0 and ii < COLS and jj >= 0 and jj < ROWS and known[jj * COLS + ii] == 1:
							s += bz[jj * COLS + ii]; c += 1
					if c > 0:
						bz[k] = s / float(c)
						known[k] = 2
		for k in COLS * ROWS:
			if known[k] == 2:
				known[k] = 1
	# 4) rest grid and cloth
	rest_local.resize(COLS * ROWS)
	for j in ROWS:
		for i in COLS:
			rest_local[j * COLS + i] = Vector3(lerpf(xl[j], xr[j], float(i) / float(COLS - 1)), ytop - band * float(j), z0)
	var gt := pivot.get_global_transform_interpolated()
	var rest_w := PackedVector3Array()
	for p in rest_local:
		rest_w.append(gt * p)
	cloth = ClothSolver.new()
	cloth.density = density
	cloth.tag = sail_name
	cloth.cN = 1.2
	cloth.cT = 0.05
	cloth.substeps = 2
	cloth.iterations = 10
	cloth.use_bending = false
	cloth.max_extra_substeps = 0
	cloth.min_quality = 1.0 # dev's half-rate solve limit-cycles the sails at 30 fps
	cloth.flutter = 0.35
	cloth.build(COLS, ROWS, rest_w)
	area = cloth.area
	for i in COLS: # head on the yard
		cloth.add_anchor(i, 0.0, rest_w[i])
	var last := (ROWS - 1) * COLS
	cloth.add_anchor(last, 2.0e-3, rest_w[last]) # clews (sheets)
	cloth.add_anchor(last + COLS - 1, 2.0e-3, rest_w[last + COLS - 1])
	for jr in [ROWS / 3, 2 * ROWS / 3]: # bowlines / leech lines, elastic
		cloth.add_anchor(jr * COLS, 0.05, rest_w[jr * COLS])
		cloth.add_anchor(jr * COLS + COLS - 1, 0.05, rest_w[jr * COLS + COLS - 1])
	# mast collider (vertical capsule), clear of the rest plane
	mast_z = mast_zs[0]
	for mz in mast_zs:
		if absf(mz - z0) < absf(mast_z - z0):
			mast_z = mz
	print("[sail] ", sail_name, " z0=", snappedf(z0, 0.01), " mast_z=", snappedf(mast_z, 0.01), " y=", snappedf(ytop - hgt, 0.1), "..", snappedf(ytop, 0.1), " w=", snappedf(xr[0] - xl[0], 0.1), "/", snappedf(xr[ROWS - 1] - xl[ROWS - 1], 0.1))
	cloth.post_step = _post_step
	cloth.reset_provider = _rest_world
	cloth.pivot_inv = pivot.get_global_transform_interpolated().affine_inverse()
	cloth._launch_xf = cloth.pivot_inv
	# 5) displacement texture + materials
	_dbuf.resize(COLS * ROWS * 4)
	img = Image.create(COLS, ROWS, false, Image.FORMAT_RGBAF)
	tex = ImageTexture.create_from_image(img)
	var to_ship: Transform3D = pivot.global_transform.affine_inverse() * mi.global_transform
	for si in mi.mesh.get_surface_count():
		var src := mi.get_active_material(si)
		var m := ShaderMaterial.new()
		m.shader = shader
		if src is BaseMaterial3D:
			var b := src as BaseMaterial3D
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			m.set_shader_parameter("normal_tex", b.normal_texture)
		m.set_shader_parameter("dtex", tex)
		m.set_shader_parameter("to_ship", to_ship)
		m.set_shader_parameter("from_ship", to_ship.affine_inverse())
		m.set_shader_parameter("ytop", ytop)
		m.set_shader_parameter("hgt", hgt)
		m.set_shader_parameter("z0", z0)
		m.set_shader_parameter("mast_pos", mast_pos)
		m.set_shader_parameter("brace", 0.0)
		mi.set_surface_override_material(si, m)
		mats.append(m)
	mi.extra_cull_margin = 30.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_post_step()
	return true

## Posed (CPU-skinned) vertices of one surface in `root` space.
static func posed_surface(m: MeshInstance3D, si: int, root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var root_inv := root.global_transform.affine_inverse()
	var arr := m.mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var skel: Skeleton3D = null
	if not m.get_skeleton_path().is_empty():
		skel = m.get_node_or_null(m.get_skeleton_path()) as Skeleton3D
	if skel == null or m.skin == null:
		var t := root_inv * m.global_transform
		for v in verts:
			out.append(t * v)
		return out
	var to_root := root_inv * skel.global_transform
	var poses: Array[Transform3D] = []
	for i in m.skin.get_bind_count():
		var bone := m.skin.get_bind_bone(i)
		if bone < 0:
			bone = skel.find_bone(m.skin.get_bind_name(i))
		var pose := skel.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
		poses.append(pose * m.skin.get_bind_pose(i))
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var stride := (bones.size() / verts.size()) if (verts.size() > 0 and bones.size() > 0) else 0
	for vi in verts.size():
		var p := verts[vi]
		if stride > 0:
			var a := Vector3.ZERO
			var ws := 0.0
			for k in stride:
				var w := weights[vi * stride + k]
				if w > 0.0:
					a += (poses[bones[vi * stride + k]] * verts[vi]) * w
					ws += w
			if ws > 0.0:
				p = a / ws
		out.append(to_root * p)
	return out

## Main thread, BEFORE the parallel step: pin targets follow the ship.
func _rest_world() -> PackedVector3Array:
	var gt := pivot.get_global_transform_interpolated()
	var out := PackedVector3Array()
	for i in rest_local.size():
		out.append(gt * _braced(i))
	return out

func update_anchors(furl: float, p_brace: float) -> void:
	brace = p_brace
	_brace_sim = p_brace
	var gt := pivot.get_global_transform_interpolated()
	cloth.pivot_inv = gt.affine_inverse()
	var last := (ROWS - 1) * COLS
	var k := 0
	for i in COLS:
		cloth.set_anchor(k, gt * _braced(i)); k += 1
	cloth.set_anchor(k, gt * _braced(last)); k += 1
	cloth.set_anchor(k, gt * _braced(last + COLS - 1)); k += 1
	for jr in [ROWS / 3, 2 * ROWS / 3]:
		cloth.set_anchor(k, gt * _braced(jr * COLS)); k += 1
		cloth.set_anchor(k, gt * _braced(jr * COLS + COLS - 1)); k += 1
	# masts taper: ~0.45 m at the course yards, ~0.18 m at the topgallants
	var ymid := ytop - hgt * 0.5
	var rad := clampf(minf(lerpf(0.45, 0.18, clampf((ymid - 8.0) / 14.0, 0.0, 1.0)), absf(mast_z - z0) - 0.12), 0.1, 0.45)
	cloth.set_capsules(PackedVector3Array([gt * Vector3(0.0, 1.0, mast_z)]), PackedVector3Array([gt * Vector3(0.0, 32.0, mast_z)]), PackedFloat32Array([rad]))
	cloth.enabled = furl < 0.985
	for m in mats:
		m.set_shader_parameter("brace", brace)

## Rest node in ship space after the yard brace (rotation about the vertical axis through mast_pos).
func _braced(idx: int) -> Vector3:
	var r := rest_local[idx]
	return mast_pos + Basis(Vector3.UP, brace) * (r - mast_pos)

## Main thread, AFTER the step: displacement texture + exported forces.
func _post_step() -> void:
	var inv := cloth._launch_xf # world -> ship frame the step was computed in
	for j in ROWS:
		for i in COLS:
			var k := j * COLS + i
			var p := inv * cloth.pos[k]
			if _brace_sim != 0.0: # simulated grid back into the sail's unbraced frame (the shader rotates it forward again)
				p = mast_pos + Basis(Vector3.UP, -_brace_sim) * (p - mast_pos)
			var r := rest_local[k]
			var o := k * 4
			_dbuf[o] = p.x - r.x
			_dbuf[o + 1] = p.y - r.y
			_dbuf[o + 2] = p.z - bz[k]
			_dbuf[o + 3] = r.x
	img.set_data(COLS, ROWS, false, Image.FORMAT_RGBAF, _dbuf.to_byte_array())
	tex.update(img)
	force_ship = inv.basis * cloth.aero_force
	point_ship = inv * cloth.aero_point
	pressure = cloth.pressure
	tension = cloth.constraint_force.length()
	gust = cloth.gust_seen
	# state from the thrust direction (-z = forward) and how much of the dynamic pressure the cloth catches
	var thrust := -force_ship.z
	var mean_w := Vector3.ZERO
	for k in range(0, COLS * ROWS, 5):
		mean_w += cloth.wind[k]
	mean_w /= float(COLS * ROWS / 5)
	var q := 0.5 * ClothSolver.RHO * mean_w.length_squared()
	var rel := force_ship.length() / maxf(q * area, 1.0)
	if thrust < -0.05 * q * area:
		state = "backed"
	elif rel < 0.12:
		state = "slack"
	elif cloth.max_stretch > 0.0 and _is_luffing():
		state = "luffing"
	else:
		state = "filling"

func _is_luffing() -> bool:
	# Luffing = the cloth flaps: large vertex speeds with little net drive.
	var s := 0.0
	for k in range(COLS * 3, COLS * ROWS, 7):
		s += cloth.vel[k].length()
	s /= float(COLS * ROWS / 7)
	return s > 1.5 and absf(force_ship.z) < 0.5 * cloth.pressure * area

## Mean belly of the sim grid in the sail's own frame (z of the nodes minus the yard plane): < 0 = bulges toward the bow.
func bulge() -> float:
	var acc := 0.0
	for k in COLS * ROWS:
		acc += _dbuf[k * 4 + 2] + bz[k] - z0
	return acc / float(COLS * ROWS)

func set_furl(f: float, time: float) -> void:
	for m in mats:
		m.set_shader_parameter("furl", f)
	mi.visible = f < 0.985

func info() -> Dictionary:
	return {"name": sail_name.trim_prefix("geo_ship_pinnace_").trim_prefix("GEO_ship_pinnace_"), "force": force_ship, "point": point_ship,
		"area": area, "pressure": pressure, "tension": tension, "gust": gust, "state": state, "brace_deg": rad_to_deg(brace), "stretch": cloth.max_stretch, "bulge": bulge()}
