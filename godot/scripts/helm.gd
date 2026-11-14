extends Node3D
## Helm: removes the wheel baked into the hull mesh, builds a procedural wheel that turns with `Ship.rudder`, and
## exposes two hand targets (left/right) that grab the handles hand-over-hand as the wheel turns.
## All positions are in the ship Pivot's local frame (+X starboard, -Z bow, y up from the waterline).

@export var ship_path := NodePath("../..")
@export var loader_path := NodePath("../Model")
## Wheel hub position and radius for the current hull (retune when the hull changes).
@export var wheel_pos := Vector3(0.0, 5.3, 8.5)
@export var wheel_radius := 0.62
## Triangles of the hull fully inside this box (Pivot space) are removed (the baked wheel).
@export var cut_box := AABB(Vector3(-1.25, 4.45, 8.0), Vector3(2.5, 2.0, 0.62))
## Wheel angle (rad) per unit of rudder.
@export var turn_per_rudder := 3.6
@export var wheel_smooth := 6.0
## Total wheel diameter incl. handles, in units of the grip diameter (asset only).
@export var wheel_asset_diameter_scale := 1.2

const WHEEL_ASSET := "res://assets/ship/ship_wheel.glb"
var wheel: Node3D
var hand_l: Node3D
var hand_r: Node3D
var _ship: Node
var _angle := 0.0
var _handle_l := 0
var _handle_r := 0
var _tgt_l := Vector3.ZERO
var _tgt_r := Vector3.ZERO
const HANDLES := 8

func _ready() -> void:
	_ship = get_node(ship_path)
	var loader := get_node(loader_path)
	loader.ship_ready.connect(_on_ship_ready)
	hand_l = Node3D.new(); hand_l.name = "HandL"; add_child(hand_l)
	hand_r = Node3D.new(); hand_r.name = "HandR"; add_child(hand_r)

func _on_ship_ready(_l: float, _b: float, _r: float) -> void:
	_cut_baked_wheel()
	_build_wheel()
	_tgt_l = _grip(-1.0, 0)
	_tgt_r = _grip(1.0, 0)
	hand_l.position = _tgt_l
	hand_r.position = _tgt_r

func _cut_baked_wheel() -> void:
	var loader := get_node(loader_path)
	var pivot_inv := get_parent().global_transform.affine_inverse() as Transform3D
	var removed := 0
	for n in loader.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_pivot: Transform3D = pivot_inv * mi.global_transform
		var box_in_mesh: AABB = to_pivot.affine_inverse() * cut_box
		if not mi.get_aabb().intersects(box_in_mesh):
			continue
		var old := mi.mesh
		var new_mesh := ArrayMesh.new()
		var changed := false
		for s in old.get_surface_count():
			var arrays := old.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				new_mesh.surface_set_material(s, old.surface_get_material(s))
				continue
			var inside := PackedByteArray()
			inside.resize(verts.size())
			for i in verts.size():
				inside[i] = 1 if cut_box.has_point(to_pivot * verts[i]) else 0
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				if inside[idx[t]] == 1 and inside[idx[t + 1]] == 1 and inside[idx[t + 2]] == 1:
					removed += 1
					changed = true
				else:
					keep.append(idx[t]); keep.append(idx[t + 1]); keep.append(idx[t + 2])
			arrays[Mesh.ARRAY_INDEX] = keep
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			new_mesh.surface_set_material(s, old.surface_get_material(s))
		if changed:
			mi.mesh = new_mesh
	print("[helm] removed ", removed, " baked wheel triangles")

func _build_wheel() -> void:
	wheel = Node3D.new()
	wheel.name = "Wheel"
	wheel.position = wheel_pos
	add_child(wheel)
	if ModelUtil.file_present(WHEEL_ASSET) and _mount_wheel_asset():
		return
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.20, 0.10)
	wood.roughness = 0.75
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.82, 0.62, 0.22)
	brass.metallic = 0.85
	brass.roughness = 0.35
	var r := wheel_radius
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.86
	tm.outer_radius = r
	tm.rings = 28
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = wood
	ring.rotation.x = PI * 0.5 # torus axis Y -> Z (wheel faces fore/aft)
	wheel.add_child(ring)
	for k in 4:
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, r * 2.0, 0.07)
		spoke.mesh = bm
		spoke.material_override = wood
		spoke.rotation.z = k * PI / 4.0
		wheel.add_child(spoke)
	for k in HANDLES:
		var a := k * TAU / HANDLES
		var h := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.032
		cm.bottom_radius = 0.045
		cm.height = r * 0.36
		cm.radial_segments = 8
		h.mesh = cm
		h.material_override = wood
		h.position = Vector3(sin(a), cos(a), 0.0) * (r + cm.height * 0.45)
		h.rotation.z = -a
		wheel.add_child(h)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.17
	hm.bottom_radius = 0.17
	hm.height = 0.3
	hub.mesh = hm
	hub.material_override = brass
	hub.rotation.x = PI * 0.5
	wheel.add_child(hub)

## Rim position (Pivot space) of handle `k` at the current wheel angle.
func _handle_pos(k: int) -> Vector3:
	var a := float(k) * TAU / HANDLES - _angle
	return wheel_pos + Vector3(sin(a), cos(a), 0.0) * (wheel_radius * 0.95) + Vector3(0, 0, 0.1)

func _grip(side: float, k: int) -> Vector3:
	var a := float(k) * TAU / HANDLES - _angle
	return wheel_pos + Vector3(sin(a), cos(a), 0.0) * (wheel_radius * 0.95) + Vector3(0, 0, 0.1)

func _process(delta: float) -> void:
	if wheel == null:
		return
	var rud: float = _ship.get("rudder") if _ship.get("rudder") != null else 0.0
	# Wheel angle follows the (already smoothed) rudder; positive rudder = starboard = wheel turns clockwise from behind.
	var target := -rud * turn_per_rudder
	_angle = lerpf(_angle, target, 1.0 - exp(-wheel_smooth * delta))
	wheel.rotation.z = _angle
	# Hand-over-hand: each hand keeps its handle until it drifts > 32 deg from its resting grip angle, then regrabs.
	var grip_l := deg_to_rad(-70.0)
	var grip_r := deg_to_rad(70.0)
	_handle_l = _pick_handle(_handle_l, grip_l)
	_handle_r = _pick_handle(_handle_r, grip_r)
	var dl := _handle_pos(_handle_l)
	var dr := _handle_pos(_handle_r)
	# Hands glide to their handle with a speed limit (no snapping), so the arms never whip on a regrab.
	_tgt_l = _glide(_tgt_l, dl, delta)
	_tgt_r = _glide(_tgt_r, dr, delta)
	hand_l.position = _tgt_l
	hand_r.position = _tgt_r

func _pick_handle(current: int, grip_angle: float) -> int:
	var step := TAU / HANDLES
	var err := wrapf(float(current) * step - _angle - grip_angle, -PI, PI)
	if absf(err) <= deg_to_rad(32.0):
		return current
	# Choose the handle closest to the resting grip angle.
	var best := current
	var best_err := 1.0e9
	for k in HANDLES:
		var e := absf(wrapf(float(k) * step - _angle - grip_angle, -PI, PI))
		if e < best_err:
			best_err = e
			best = k
	return best

## Mounts res://assets/ship/ship_wheel.glb: finds the axle (smallest AABB axis), turns it to the ship's fore/aft axis,
## scales it to the wheel size and centres the hub on the helm pivot. Returns false if the asset cannot be loaded.
func _mount_wheel_asset() -> bool:
	var inst := ModelUtil.load_glb(WHEEL_ASSET) as Node3D
	if inst == null:
		return false
	var holder := Node3D.new()
	wheel.add_child(holder)
	holder.add_child(inst)
	var box := ModelUtil.local_aabb(holder)
	var sz := box.size
	var axle := 0
	if sz.y < sz[axle]: axle = 1
	if sz.z < sz[axle]: axle = 2
	var b := Basis.IDENTITY
	if axle == 0:
		b = Basis(Vector3.UP, PI * 0.5)
	elif axle == 1:
		b = Basis(Vector3.RIGHT, PI * 0.5)
	var disc := maxf(maxf(sz.x, sz.y), sz.z)
	var s := (wheel_radius * 2.0 * wheel_asset_diameter_scale) / maxf(disc, 0.0001)
	holder.transform = Transform3D(b * Basis.from_scale(Vector3(s, s, s)), -(b * (box.get_center() * s)))
	print("[helm] mounted ship_wheel.glb axle_axis=", axle, " scale=", s)
	return true

const HAND_MAX_SPEED := 0.9 # m/s
func _glide(cur: Vector3, goal: Vector3, delta: float) -> Vector3:
	var k := 1.0 - exp(-10.0 * delta)
	var step := (goal - cur) * k
	return cur + step.limit_length(HAND_MAX_SPEED * delta)
