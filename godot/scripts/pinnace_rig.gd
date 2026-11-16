extends Node
## Rig of the Poly Haven pinnace: shows the deployed sails (*_down) instead of the furled ones (*_top), turns each one into
## XPBD cloth (SailCloth + ClothSolver, driven by the shared WindField, rendered by sail_cloth.gdshader), furls them in the
## worst storm and moves the rudder with Ship.rudder.
## Integration API for the (future) rigid-body ship: get_sail_forces() / total_sail_force().

@export var ship_path := NodePath("../..")
@export var loader_path := NodePath("../Model")
@export var pivot_path := NodePath("..")
@export var furl_storm := 0.86 ## storminess above which the sails are furled
@export var furl_speed := 0.07 ## 1/s
@export var furl_grace_s := 20.0 ## storm fallback: a sail nobody asked to furl is furled automatically this long after the storm crosses furl_storm

signal furl_changed(idx: int, value: float)
@export var sail_density := 0.45 ## kg/m2 (canvas)

var _sails: Array[SailCloth] = []
var _furled: Array[MeshInstance3D] = []
var _ship: Node
var _pivot: Node3D
var _skel: Skeleton3D
var _sail_bones: Array = []  # per sail: Array[int] bone indices (the bones that carry its yard, sail and running rigging)
var _mast_ship: Array = []   # per sail: brace axis position (ship/pivot space)
var _last_brace := 0.0
var _rudder_bone := -1
var _rudder_rest := Quaternion.IDENTITY
var _furl := 0.0 ## mean furl of all sails (what sail_power and the furled bundles use)
var _furls := PackedFloat32Array()      ## furl 0..1 per sail
var _req_t := PackedFloat32Array()      ## crew-requested target per sail
var _req_on: Array[bool] = []           ## a crew request is active for this sail (never overridden by the storm fallback)
var _req_time := PackedFloat32Array()   ## time of the last request per sail (-1e9 = never)
var _auto_on: Array[bool] = []          ## storm fallback is furling this sail
var _emitted := PackedFloat32Array()    ## last furl value signalled per sail
var _done_logged: Array[bool] = []
var _storm_since := -1.0                ## time storm went above furl_storm (-1 = below)
var _time := 0.0
var _furl_log := false
var _mast_zs := PackedFloat32Array()
var _hull_ready := false
var _no_collide := false
var _collide_log := false
var _collide_scale := 1.0
var _collide_t := 0.0
var _pen_sum := 0
var _pen_frames := 0
var _log_t := 0.0
var _test_req: Array = []               ## --request-furl=idx:t@sec test aid

func _ready() -> void:
	add_to_group("rebase")
	add_to_group("sail_rig")
	_ship = get_node(ship_path)
	_pivot = get_node(pivot_path)
	get_node(loader_path).ship_ready.connect(_on_ship_ready)
	for a in OS.get_cmdline_user_args():
		if a == "--furl-log":
			_furl_log = true
		elif a.begins_with("--request-furl="): # idx:t@sec, e.g. --request-furl=0:1.0@10
			var parts := a.get_slice("=", 1).split("@")
			var it := parts[0].split(":")
			_test_req.append({"idx": int(it[0]), "t": float(it[1]), "at": float(parts[1]) if parts.size() > 1 else 0.0, "done": false})

func _on_ship_ready(_l: float, _b: float, _r: float) -> void:
	var model := get_node(loader_path)
	var shader := load("res://shaders/sail_cloth.gdshader") as Shader
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0]
		_rudder_bone = _skel.find_bone("def_rudder")
		if _rudder_bone >= 0:
			_rudder_rest = _skel.get_bone_rest(_rudder_bone).basis.get_rotation_quaternion()
	var mast_zs := PackedFloat32Array()
	_mast_zs = mast_zs
	var pinv := _pivot.global_transform.affine_inverse()
	if _skel:
		for bn in ["def_forecourse", "def_main_sail", "def_mizzen_course"]:
			var bi := _skel.find_bone(bn)
			if bi >= 0:
				mast_zs.append((pinv * _skel.global_transform * _skel.get_bone_global_pose(bi)).origin.z)
	if mast_zs.is_empty():
		mast_zs = PackedFloat32Array([-8.5, 2.4, 12.3])
	var hidden := 0
	var cloth := 0
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := mi.name.to_lower()
		var is_sail := nm.contains("_sails_") or nm.contains("sailsmain")
		if is_sail and nm.ends_with("_top") or nm.ends_with("_course_top") or nm.contains("spritsail_top"):
			mi.visible = false
			hidden += 1
			_furled.append(mi)
			continue
		if nm.contains("rigging_") and not nm.contains("_down") and _has_down(model, nm):
			mi.visible = false
			hidden += 1
			continue
		if is_sail and nm.contains("_down"):
			if _make_cloth(mi, shader, mast_zs):
				cloth += 1
	var tot := 0.0
	if "sail_defs" in _ship:
		for d in _ship.sail_defs: tot += float(d["area"])
	_init_furl_state()
	_init_colliders(model)
	print("[sails] total area m2=", snappedf(tot, 1.0), " cloth=", cloth, " hidden furled/duplicate=", hidden, " rudder_bone=", _rudder_bone)

## Key shared by a sail mesh and its furled/yard meshes: "geo_ship_pinnace_sails_fore_topsail_down" and "..._sails_fore_topsail_top"
## and "..._rigging_foretopsail" all give "foretop".
static func _sail_key(mesh_name: String) -> String:
	var k := mesh_name.to_lower().trim_prefix("geo_ship_pinnace_").trim_prefix("rigging_")
	if k.begins_with("sailsmain"): # the one mesh named "sailsmain_course_top"
		k = "main" + k.substr(9)
	k = k.trim_prefix("sails_")
	for suf in ["_down", "_top"]:
		k = k.trim_suffix(suf)
	k = k.replace("_", "")
	for suf in ["sails", "sail"]:
		k = k.trim_suffix(suf)
	return k

## The yard of each sail is NOT a separate mesh: it lives in the (hidden or visible) rigging mesh, skinned to the yard bone `def_<sail>`,
## whose vertices also dominate the furled `_top` sail mesh. The brace list only held the canvas bones (`.L` / `.R`), so the yards
## stayed square to the ship while their sails turned. Add the yard bone and the yard's own suspension lines (they run from the mast
## top, which is on the brace axis, so they turn rigidly with the yard).
func _add_yard_bones(mi: MeshInstance3D, bl: Array) -> void:
	if _skel == null:
		return
	var key := _sail_key(String(mi.name))
	var root_idx := _skel.find_bone("def_root")
	var yard := -1
	for n in mi.get_parent().find_children("*", "MeshInstance3D", true, false):
		var o := n as MeshInstance3D
		var on := o.name.to_lower()
		if o.skin == null or not (on.ends_with("_top")) or not on.contains("sail") or _sail_key(on) != key:
			continue
		var cnt := {}
		for si in o.mesh.get_surface_count():
			var arr := o.mesh.surface_get_arrays(si)
			if arr[Mesh.ARRAY_BONES] == null:
				continue
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / maxi(arr[Mesh.ARRAY_VERTEX].size(), 1)
			for v in arr[Mesh.ARRAY_VERTEX].size():
				if wts[v * stride] > 0.5:
					var b := _skel.find_bone(o.skin.get_bind_name(bones[v * stride]))
					if b >= 0 and b != root_idx:
						cnt[b] = int(cnt.get(b, 0)) + 1
		var best := 0
		for b in cnt:
			if int(cnt[b]) > best:
				best = int(cnt[b])
				yard = int(b)
	if yard < 0:
		return
	if not bl.has(yard):
		bl.append(yard)
	if not "--no-yard-restore" in OS.get_cmdline_user_args():
		_restore_yard_mesh(mi.get_parent(), key, yard)
	var yname := _skel.get_bone_name(yard)
	var prefixes := [yname + "_susp"]
	if yname.ends_with("_sail"):
		prefixes.append(yname.trim_suffix("_sail") + "_susp") # def_main_sail -> def_main_suspension
	var added := [yname]
	for b in _skel.get_bone_count():
		var bn := _skel.get_bone_name(b)
		var mine := false
		for pf in prefixes:
			mine = mine or bn.begins_with(pf)
		if b != yard and b != root_idx and mine and not bl.has(b):
			bl.append(b)
			added.append(bn)
	if "--rig-log" in OS.get_cmdline_user_args():
		print("[rig] yard of ", mi.name, ": ", ", ".join(added))

## The rigging mesh of 7 sails is hidden as a "duplicate" of its `_down` variant (see _on_ship_ready), and with it went the yard, so
## those sails hung from nothing. Rebuild just the yard from that hidden mesh: the triangles whose three vertices are weighted
## (>= 50 %) to the yard bone. Same material, skin and skeleton as the original, so it turns with the brace like the other yards.
func _restore_yard_mesh(model: Node, key: String, yard: int) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var o := n as MeshInstance3D
		var on := o.name.to_lower()
		if o.skin == null or not on.contains("rigging_") or on.ends_with("_down") or _sail_key(on) != key or not _has_down(model, on):
			continue
		var yname := _skel.get_bone_name(yard)
		var mesh := ArrayMesh.new()
		var kept := 0
		for si in o.mesh.get_surface_count():
			var arr := o.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null or verts.is_empty():
				continue
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / verts.size()
			var is_yard := PackedByteArray()
			is_yard.resize(verts.size())
			for v in verts.size():
				var w := 0.0
				for q in stride:
					if o.skin.get_bind_name(bones[v * stride + q]) == yname:
						w += wts[v * stride + q]
				is_yard[v] = 1 if w >= 0.5 else 0
			var idx_src: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx_src.is_empty():
				idx_src.resize(verts.size())
				for v in verts.size():
					idx_src[v] = v
			var idx := PackedInt32Array()
			for t in range(0, idx_src.size() - 2, 3):
				if is_yard[idx_src[t]] == 1 and is_yard[idx_src[t + 1]] == 1 and is_yard[idx_src[t + 2]] == 1:
					idx.append(idx_src[t]); idx.append(idx_src[t + 1]); idx.append(idx_src[t + 2])
			if idx.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = idx
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var si_new := mesh.get_surface_count() - 1
			mesh.surface_set_material(si_new, o.mesh.surface_get_material(si))
			kept += idx.size() / 3
		if kept == 0:
			return
		var ni := MeshInstance3D.new()
		ni.name = "yard_" + key
		ni.mesh = mesh
		ni.skin = o.skin
		ni.skeleton = o.skeleton
		ni.transform = o.transform
		ni.extra_cull_margin = 4.0
		o.get_parent().add_child(ni)
		if "--rig-log" in OS.get_cmdline_user_args():
			print("[rig] restored yard ", yname, " from ", o.name, ": ", kept, " triangles")
		return

## --- Cloth colliders (masts, yards of the other sails, hull box), see ClothSolver.sh_*: built in ship space once, moved to world every frame.
func _init_colliders(model: Node) -> void:
	_no_collide = "--no-cloth-collide" in OS.get_cmdline_user_args()
	ClothSolver.collide_push = not "--no-cloth-push" in OS.get_cmdline_user_args() # measure only
	_collide_log = "--collide-log" in OS.get_cmdline_user_args()
	ClothSolver.count_pen = _collide_log
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--collide-scale="): # stress/sanity: multiplies the shared capsule radii
			_collide_scale = float(a.get_slice("=", 1))
	if _no_collide or _mast_zs.is_empty():
		return
	var inv := _pivot.global_transform.affine_inverse()
	var deck := model.find_child("geo_ship_pinnace_deck_001", true, false) as MeshInstance3D
	if deck != null:
		# Deck profile along z (the ship has a forecastle, a waist and a quarterdeck): per 1 m bin, the deck top (85th percentile of the
		# vertex heights near the centreline) and the half-beam, in ship space.
		var xf := inv * deck.global_transform
		var zmin := 1.0e9
		var zmax := -1.0e9
		var pts := PackedVector3Array()
		for si in deck.mesh.get_surface_count():
			for v in deck.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var q := xf * (v as Vector3)
				pts.append(q)
				zmin = minf(zmin, q.z)
				zmax = maxf(zmax, q.z)
		var nb := maxi(int(ceil(zmax - zmin)), 1)
		var ys: Array = []
		var hws := PackedFloat32Array()
		for i in nb:
			ys.append([])
			hws.append(0.0)
		for q in pts:
			var bi := clampi(int(q.z - zmin), 0, nb - 1)
			hws[bi] = maxf(hws[bi], absf(q.x))
			if absf(q.x) < 3.0:
				(ys[bi] as Array).append(q.y)
		var deck_y := PackedFloat32Array()
		var ymax := -1.0e9
		for i in nb:
			var a: Array = ys[i]
			a.sort()
			var y := (a[int(a.size() * 0.85)] if not a.is_empty() else (deck_y[i - 1] if i > 0 else 0.0)) as float
			deck_y.append(y)
			ymax = maxf(ymax, y)
		ClothSolver.hull_z0 = zmin
		ClothSolver.hull_dz = 1.0
		ClothSolver.hull_deck = deck_y
		ClothSolver.hull_hw = hws
		var hwmax := 0.0
		for h_ in hws:
			hwmax = maxf(hwmax, h_)
		ClothSolver.hull_box = Vector4(hwmax, ymax, zmin, zmax)
		ClothSolver.hull_rail = ymax + 1.0
		_hull_ready = true
		var prof := []
		for i in range(0, nb, 4):
			prof.append("%d:%.1f/%.1f" % [int(zmin) + i, deck_y[i], hws[i]])
		print("[cloth] collide deck profile z:deck_y/half_beam ", " ".join(prof))
	_build_shroud_walls(model, inv)
	for si in _sails.size():
		var sail := _sails[si]
		var k := 0
		var best := 1.0e9
		for mi_ in _mast_zs.size():
			if absf(_mast_zs[mi_] - sail.mast_z) < best:
				best = absf(_mast_zs[mi_] - sail.mast_z)
				k = mi_
		sail.cloth.use_shared = true
		sail.cloth.skip_shared = PackedInt32Array([2 * k, 2 * k + 1, 2 * _mast_zs.size() + si])

## Shroud ladders are sloping sheets from the rails to the mast top, a little aft of each mast: sails braced hard or billowing aft pressed
## through them. Fitted from the mast meshes: per mast and side, |x| against y of the ladder vertices (ship space), and its z range.
func _build_shroud_walls(model: Node, inv: Transform3D) -> void:
	var walls := PackedFloat32Array() # per wall: x0 (at y0), y0, x1 (at y1), y1, zlo, zhi, side (+1 / -1)
	var verts := PackedVector3Array()
	for n in model.find_children("*mast*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.name.to_lower().contains("pavillion"):
			continue
		var xf := inv * m.global_transform
		for si in m.mesh.get_surface_count():
			for v in m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				verts.append(xf * (v as Vector3))
	for zk in _mast_zs:
		var bins := {} # y bin (0.5 m) -> [max |x|, count]
		var zlo := 1.0e9
		var zhi := -1.0e9
		for q in verts:
			if q.z > zk + 0.25 and q.z < zk + 3.6 and absf(q.x) > 1.2 and absf(q.x) < 4.6:
				var kb := int(floor(q.y * 2.0))
				var e: Array = bins.get(kb, [0.0, 0])
				e[0] = maxf(e[0], absf(q.x))
				e[1] += 1
				bins[kb] = e
				zlo = minf(zlo, q.z)
				zhi = maxf(zhi, q.z)
		var ks := []
		for kb in bins:
			if int((bins[kb] as Array)[1]) >= 8:
				ks.append(kb)
		if ks.size() < 6:
			continue
		# least squares |x| = a + b y
		var n_ := float(ks.size())
		var sy := 0.0
		var sx := 0.0
		var syy := 0.0
		var sxy := 0.0
		for kb in ks:
			var y := (float(kb) + 0.5) * 0.5
			var x: float = (bins[kb] as Array)[0]
			sy += y; sx += x; syy += y * y; sxy += y * x
		var den := n_ * syy - sy * sy
		if absf(den) < 1.0e-6:
			continue
		var b := (n_ * sxy - sy * sx) / den
		var a := (sx - b * sy) / n_
		ks.sort()
		var y0 := (float(ks[0]) + 0.5) * 0.5
		var y1 := (float(ks[ks.size() - 1]) + 0.5) * 0.5
		for side in [1.0, -1.0]:
			walls.append_array(PackedFloat32Array([a + b * y0, y0, a + b * y1, y1, zlo, zhi, side]))
		print("[cloth] shroud wall mast z=", snappedf(zk, 0.1), ": |x| ", snappedf(a + b * y0, 0.01), " at y ", snappedf(y0, 0.1), " -> ", snappedf(a + b * y1, 0.01), " at y ", snappedf(y1, 0.1), ", z ", snappedf(zlo, 0.1), "..", snappedf(zhi, 0.1))
	ClothSolver.wall_data = walls

func _update_colliders(br: float) -> void:
	if _no_collide and _collide_log:
		_collide_t += get_process_delta_time()
		if _collide_t >= 10.0:
			_collide_t = 0.0
			print("[collide] 10 s: collisions OFF cloth step ms ", snappedf(ClothSolver.step_ms, 0.01))
	if _no_collide or _mast_zs.is_empty() or _sails.is_empty():
		return
	var gt := _pivot.get_global_transform_interpolated()
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var r := PackedFloat32Array()
	for z in _mast_zs:
		a.append(gt * Vector3(0.0, 1.0, z)); b.append(gt * Vector3(0.0, 13.0, z)); r.append(0.42 * _collide_scale)
		a.append(gt * Vector3(0.0, 13.0, z)); b.append(gt * Vector3(0.0, 28.0, z)); r.append(0.2 * _collide_scale)
	var rot := Basis(Vector3.UP, br)
	for sail in _sails:
		var mp := sail.mast_pos
		var y := sail.ytop + 0.05
		var p0 := mp + rot * (Vector3(sail.yard_x.x - 0.4, y, sail.z0) - mp)
		var p1 := mp + rot * (Vector3(sail.yard_x.y + 0.4, y, sail.z0) - mp)
		a.append(gt * p0); b.append(gt * p1); r.append(0.17 * _collide_scale)
	if _collide_log:
		var tot := 0
		for sail in _sails:
			tot += sail.cloth.pen_last
		_pen_sum += tot
		_pen_frames += 1
		_collide_t += get_process_delta_time()
		if _collide_t >= 10.0:
			var pm := []
			for sail in _sails:
				pm.append("%s:%d" % [String(sail.sail_name).trim_prefix("geo_ship_pinnace_sails_").trim_prefix("GEO_ship_pinnace_sails_").trim_suffix("_down"), sail.cloth.pen_max])
			print("[collide] 10 s: mean penetrating particles/frame ", snappedf(float(_pen_sum) / maxf(float(_pen_frames), 1.0), 0.01), " cloth step ms ", snappedf(ClothSolver.step_ms, 0.01), " max per sail ", " ".join(pm))
			_collide_t = 0.0
			_pen_sum = 0
			_pen_frames = 0
			for sail in _sails:
				sail.cloth.pen_max = 0
	ClothSolver.sh_a = a
	ClothSolver.sh_b = b
	ClothSolver.sh_r = r
	if _hull_ready:
		ClothSolver.hull_fwd = gt
		ClothSolver.hull_inv = gt.affine_inverse()
		ClothSolver.hull_on = true

func _has_down(model: Node, nm: String) -> bool:
	return model.find_child(nm + "_down", true, false) != null or model.find_child(nm.replace("geo_", "geo_") + "_down", true, false) != null

func _make_cloth(mi: MeshInstance3D, shader: Shader, mast_zs: PackedFloat32Array) -> bool:
	var box: AABB = (_pivot.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
	# Brace axis = the mast the sail hangs from (vertical line through x = 0); the bowsprit sail pivots about itself.
	var zc := box.get_center().z
	var zm := zc
	for mz in mast_zs:
		if absf(mz - zc) < 4.0:
			zm = mz
	var axis := Vector3(0.0, box.get_center().y, zm)
	var sail := SailCloth.new()
	if not sail.setup(mi, shader, _pivot, mast_zs, sail_density, axis):
		return false
	_sails.append(sail)
	# Bones to brace = only the bones that actually carry this sail's vertices (yard, sail, clews, its running rigging).
	# Never def_root: the masts, the stern staff and the hull are 100 % weighted to it and must stay attached to the ship.
	var bl: Array = []
	if _skel != null and mi.skin != null:
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			if arr[Mesh.ARRAY_BONES] == null:
				continue
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for q in bones.size():
				if wts[q] > 0.02:
					var bidx := _skel.find_bone(mi.skin.get_bind_name(bones[q]))
					if bidx < 0:
						bidx = mi.skin.get_bind_bone(bones[q])
					if bidx >= 0 and bidx != _skel.find_bone("def_root") and not bl.has(bidx):
						bl.append(bidx)
	if not "--no-yard-brace" in OS.get_cmdline_user_args(): # test aid: the old behaviour (yards stay square to the ship)
		_add_yard_bones(mi, bl)
	_sail_bones.append(bl)
	_mast_ship.append(axis)
	if "sail_defs" in _ship:
		_ship.sail_defs.append({"pos": box.get_center(), "area": box.size.x * box.size.y * 0.85, "name": String(mi.name)})
	return true

func rebase(shift: Vector3) -> void:
	for s in _sails:
		s.cloth.rebase(shift)

func _exit_tree() -> void:
	for s in _sails:
		s.cloth.destroy()

## Per-sail aerodynamic result of the last frame, SHIP (pivot) space: name, force (N), point (centre of effort, m), area,
## pressure (Pa), tension (N at the pins), gust (gust factor seen), state (filling/luffing/backed/slack), brace_deg.
func get_sail_forces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _sails:
		out.append(s.info())
	return out

## Read-only summary for gameplay/NPC code (does not touch any simulation state):
## furl 0..1, brace_deg, mean_pressure_pa (area-weighted), luffing/backed (any sail in that state), gust (max gust factor).
func sail_state() -> Dictionary:
	var area := 0.0
	var psum := 0.0
	var luff := false
	var backed := false
	var gust := 1.0
	var br := 0.0
	for s in _sails:
		var i: Dictionary = s.info()
		var a: float = float(i["area"])
		area += a
		psum += float(i["pressure"]) * a
		luff = luff or str(i["state"]) == "luffing"
		backed = backed or str(i["state"]) == "backed"
		gust = maxf(gust, float(i["gust"]))
		br = float(i["brace_deg"])
	return {"furl": _furl, "furl_per_sail": _furls, "brace_deg": br, "mean_pressure_pa": psum / area if area > 0.0 else 0.0, "luffing": luff, "backed": backed, "gust": gust}

## Sum of all sail forces (ship space, N) and the force-weighted centre of effort (ship space, m).
func total_sail_force() -> Dictionary:
	var f := Vector3.ZERO
	var pw := Vector3.ZERO
	var w := 0.0
	for s in _sails:
		if not s.cloth.enabled:
			continue
		f += s.force_ship
		var m := s.force_ship.length()
		pw += s.point_ship * m
		w += m
	return {"force": f, "point": (pw / w) if w > 1.0 else Vector3.ZERO}

func _init_furl_state() -> void:
	var n := _sails.size()
	_furls.resize(n)
	_req_t.resize(n)
	_req_time.resize(n)
	_emitted.resize(n)
	_req_on.resize(n)
	_auto_on.resize(n)
	_done_logged.resize(n)
	for i in n:
		_furls[i] = 0.0
		_req_t[i] = 0.0
		_req_time[i] = -1e9
		_emitted[i] = 0.0
		_req_on[i] = false
		_auto_on[i] = false
		_done_logged[i] = true

func sail_count() -> int:
	return _sails.size()

func get_furl(idx: int) -> float:
	return _furls[idx] if idx >= 0 and idx < _furls.size() else 0.0

## Ask for sail `idx` to be furled to t (0 = fully set, 1 = fully furled; clamped). Optional: the ship works without any caller.
## A requested sail is never overridden by the storm fallback; request_furl(idx, 0.0) sets it again.
func request_furl(idx: int, t: float) -> void:
	if idx < 0 or idx >= _sails.size():
		push_warning("[rig] request_furl: invalid sail index %d (sail_count=%d)" % [idx, _sails.size()])
		return
	t = clampf(t, 0.0, 1.0)
	_req_t[idx] = t
	_req_on[idx] = true
	_req_time[idx] = _time
	_auto_on[idx] = false
	_done_logged[idx] = false
	print("[rig] furl_request idx=", idx, " t=", snappedf(t, 0.01), " furl_source=crew")

func _update_furls(delta: float, furl_t: float) -> void:
	var storm: float = WorldState.storm
	if storm > furl_storm:
		if _storm_since < 0.0:
			_storm_since = _time
	elif storm < furl_storm - 0.1:
		_storm_since = -1.0
	for i in _furls.size():
		var target := 0.0
		if _req_on[i]:
			target = _req_t[i]
		else:
			if _storm_since >= 0.0 and not _auto_on[i] and _time - maxf(_storm_since, _req_time[i]) >= furl_grace_s:
				_auto_on[i] = true
				_done_logged[i] = false
				print("[rig] auto-furl fallback sail ", i, " furl_source=auto")
			if _auto_on[i]:
				target = furl_t
				if furl_t < 0.01 and storm < furl_storm - 0.1:
					_auto_on[i] = false # storm over: auto-furl released
		_furls[i] = move_toward(_furls[i], target, furl_speed * delta)
		if not _done_logged[i] and absf(_furls[i] - target) < 0.005:
			_done_logged[i] = true
			print("[rig] furl_done idx=", i, " furl=", snappedf(_furls[i], 0.01))
		if absf(_furls[i] - _emitted[i]) >= 0.02 or (absf(_furls[i] - target) < 0.005 and _furls[i] != _emitted[i]):
			_emitted[i] = _furls[i]
			furl_changed.emit(i, _furls[i])
	var m := 0.0
	for v in _furls:
		m += v
	_furl = m / float(maxi(_furls.size(), 1))

func _process(delta: float) -> void:
	_time += delta
	var w := WorldState
	var furl_t := smoothstep(furl_storm - 0.06, furl_storm + 0.06, w.storm)
	for r in _test_req:
		if not r["done"] and _time >= r["at"]:
			r["done"] = true
			request_furl(int(r["idx"]), float(r["t"]))
	_update_furls(delta, furl_t)
	_log_t += delta
	if _furl_log and _log_t >= 5.0:
		_log_t = 0.0
		var row := "[rig] furls t=%d sail_count=%d storm=%.2f power=%.2f :" % [int(_time), _sails.size(), w.storm, _ship.sail_power if "sail_power" in _ship else -1.0]
		for v in _furls:
			row += " %.2f" % v
		print(row)
	if "sail_power" in _ship:
		_ship.sail_power = 1.0 - 0.75 * _furl # storm canvas: furled sails keep a little drive
	# Yard bracing (physical ship): the yard bones are rotated about the mast; the cloth pins follow (sail_cloth.gd).
	var br: float = _ship.get("brace") if _ship.get("brace") != null else 0.0
	if _skel != null and absf(br - _last_brace) > 0.003:
		_last_brace = br
		_apply_brace(br)
	for si in _sails.size():
		var fv: float = _furls[si] if si < _furls.size() else 0.0
		_sails[si].set_furl(fv, _time)
		_sails[si].update_anchors(fv, br) # pin targets for this frame; the parallel cloth step is launched last in the frame
	_update_colliders(br)
	# Furled bundles appear only once the sails are mostly up.
	for f in _furled:
		f.visible = _furl > 0.9
	# Rudder follows the helm (rudder > 0 = starboard).
	if _skel and _rudder_bone >= 0:
		var rud: float = _ship.get("rudder") if _ship.get("rudder") != null else 0.0
		var q := Quaternion(Vector3.UP, -rud * deg_to_rad(28.0))
		_skel.set_bone_pose_rotation(_rudder_bone, _rudder_rest * q)

func _apply_brace(beta: float) -> void:
	var rot := Basis(Vector3.UP, beta)
	var seen := {}
	for si in _sails.size():
		var pv_local: Vector3 = _mast_ship[si]
		var ps: Vector3 = _skel.global_transform.affine_inverse() * (_pivot.global_transform * pv_local)
		var t := Transform3D(rot, ps - rot * ps)
		var bl: Array = _sail_bones[si]
		bl.sort() # parents come before children in Godot's bone order
		for bidx in bl:
			if seen.has(bidx):
				continue # a bone shared between sails keeps the first mast's pivot
			seen[bidx] = true
			var rest_g := _skel.get_bone_global_rest(bidx)
			var parent := _skel.get_bone_parent(bidx)
			var pg := _skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
			var local := pg.affine_inverse() * (t * rest_g)
			_skel.set_bone_pose_position(bidx, local.origin)
			_skel.set_bone_pose_rotation(bidx, local.basis.orthonormalized().get_rotation_quaternion())
