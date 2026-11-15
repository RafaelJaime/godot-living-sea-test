extends Node3D
## Creates the pinnace's lights under the ship pivot from the REAL model parts (ship-pivot space: +x starboard, -z bow,
## y up from the waterline). Nothing is added to the hull but light and additive glow:
##  - stern_port / stern_starboard: the two caged lanterns on the stern posts (mesh geo_ship_pinnace_details). The anchor is the
##    centroid of each cage's vertices; the baked values below were measured on the posed mesh by scripts/debug_lamp_probe.gd.
##  - cabin_windows: the eight glazed stern windows (mesh geo_ship_pinnace_aft); additive glow panes laid over the glass.
## The hull is skinned to ONE bone that never moves relative to the pivot, so a plain child of the pivot stays glued to the model;
## `--check-lamps` re-measures the posed cage centroid every second and prints the worst drift (see README).
## Retune the tables when the model changes.

const LAMPS := [
	# id, cage centroid (pivot space)
	{"id": "stern_port", "pos": Vector3(-1.751, 8.640, 18.401)},
	{"id": "stern_starboard", "pos": Vector3(1.774, 8.640, 18.401)},
]
const RAY_LAYER := 1 << 19 ## private physics layer of the temporary stance-ray colliders
const WINDOW_RAKE_DEG := 17.9 ## the transom leans aft towards the top: window plane normal points aft and down
const WINDOWS := [
	# centre of the window opening (pivot space), glass size (m)
	{"pos": Vector3(-2.23, 3.86, 17.95), "size": Vector2(0.56, 0.8)},
	{"pos": Vector3(-0.82, 3.87, 17.95), "size": Vector2(0.56, 0.8)},
	{"pos": Vector3(0.83, 3.88, 17.95), "size": Vector2(0.56, 0.8)},
	{"pos": Vector3(2.24, 3.86, 17.95), "size": Vector2(0.56, 0.8)},
	{"pos": Vector3(-1.74, 5.41, 18.40), "size": Vector2(0.44, 0.7)},
	{"pos": Vector3(-0.68, 5.43, 18.40), "size": Vector2(0.44, 0.7)},
	{"pos": Vector3(0.70, 5.43, 18.40), "size": Vector2(0.44, 0.7)},
	{"pos": Vector3(1.76, 5.41, 18.40), "size": Vector2(0.44, 0.7)},
]
const CABIN_STAND := Vector3(0.0, 7.5, 17.2) ## cabin stance (stern rail side of the poop deck): xz, and the height the ray starts from
const CABIN_LIGHT_OFFSET := Vector3(0.0, 0.6, 1.4) ## the cabin light sits outside, behind the glass line

var _lamps: Array[ShipLantern] = []
var _cage_idx: Dictionary = {} ## lamp id -> PackedInt32Array of details-mesh vertex indices (for --check-lamps)
var _details: MeshInstance3D
var _check := false
var _check_t := 0.0
var _worst := {}

func _ready() -> void:
	_check = OS.get_cmdline_user_args().has("--check-lamps")
	var loader := get_node_or_null("../Model")
	if loader and loader.has_signal("ship_ready"):
		loader.ship_ready.connect(_build.unbind(3), CONNECT_DEFERRED)
	else:
		_build()

func _build() -> void:
	for d in LAMPS:
		var l := ShipLantern.new()
		l.name = "Lantern_" + String(d["id"])
		l.id = d["id"]
		l.position = d["pos"]
		l.light_energy = 1.6
		add_child(l)
		_lamps.append(l)
	var cabin := ShipLantern.new()
	cabin.name = "Lantern_cabin_windows"
	cabin.id = "cabin_windows"
	cabin.is_window = true
	var centre := Vector3.ZERO
	for w in WINDOWS:
		centre += w["pos"] as Vector3
	centre /= float(WINDOWS.size())
	cabin.position = centre
	cabin.light_color = Color(1.0, 0.55, 0.2)
	cabin.light_energy = 1.0
	cabin.light_range = 8.0
	cabin.light_offset = CABIN_LIGHT_OFFSET
	var rot := Basis(Vector3.RIGHT, deg_to_rad(WINDOW_RAKE_DEG))
	for w in WINDOWS:
		cabin.add_pane(Transform3D(rot, (w["pos"] as Vector3) - centre), w["size"])
	add_child(cabin)
	_lamps.append(cabin)
	await _place_stances()
	if _check:
		_details = _find_mesh("details")
		if _details:
			var pts := ModelUtil.posed_points(_details, get_parent() as Node3D, 100000000)
			for d in LAMPS:
				var c := d["pos"] as Vector3
				var idx := PackedInt32Array()
				for i in pts.size():
					var p := pts[i]
					if absf(p.x - c.x) < 0.4 and absf(p.z - c.z) < 0.4 and p.y > c.y - 0.55 and p.y < c.y + 0.6:
						idx.append(i)
				_cage_idx[d["id"]] = idx
				print("[lights] check-lamps ", d["id"], " cage verts=", idx.size())

func _find_mesh(suffix: String) -> MeshInstance3D:
	for n in get_node("../Model").find_children("*", "MeshInstance3D", true, false):
		if String(n.name).to_lower().ends_with("_" + suffix):
			return n as MeshInstance3D
	return null

## Stance points: a short step inboard + forward of each lantern, height from a downward ray against temporary trimesh
## colliders of the deck/aft meshes (private layer, freed right after); falls back to a fixed height if nothing is hit.
func _place_stances() -> void:
	var bodies: Array[StaticBody3D] = []
	for n in get_node("../Model").find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var low := String(mi.name).to_lower()
		if mi.mesh == null or not ("deck" in low or "aft" in low):
			continue
		var b := StaticBody3D.new()
		b.name = "LampRayBody"
		b.collision_layer = RAY_LAYER
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		b.add_child(cs)
		add_child(b) # not under the model: the crew manager frees every StaticBody3D it finds there
		b.global_transform = mi.global_transform
		bodies.append(b)
	for i in 3:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var pivot := get_parent() as Node3D
	for l in _lamps:
		var at: Vector3
		if l.is_window:
			at = CABIN_STAND
		else:
			var sx := -signf(l.position.x)
			at = l.position + Vector3(sx * 0.55, 0.0, -0.58) # ~0.8 m away, inboard and forward
		var hy := _ground(space, pivot, at)
		var stand := Vector3(at.x, hy if not is_nan(hy) else 6.6, at.z)
		l.stand_local = stand
		var target := l.position if not l.is_window else Vector3(0.0, 0.0, 19.0)
		l.stand_facing_deg = rad_to_deg(atan2(-(target.x - stand.x), -(target.z - stand.z)))
		if OS.get_cmdline_user_args().has("--debug-lights"):
			print("[lights] ", l.id, " pos=", l.position, " stand=", stand, " facing=", snappedf(l.stand_facing_deg, 0.1), " ray_hit=", not is_nan(hy))
	for b in bodies:
		if is_instance_valid(b):
			b.queue_free()

func _ground(space: PhysicsDirectSpaceState3D, pivot: Node3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(pivot.to_global(p + Vector3(0, 1.0, 0)), pivot.to_global(p + Vector3(0, -5.0, 0)))
	q.collision_mask = RAY_LAYER
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return pivot.to_local(hit["position"]).y

func _process(delta: float) -> void:
	if not _check or _details == null:
		return
	_check_t += delta
	if _check_t < 1.0:
		return
	_check_t = 0.0
	var pts := ModelUtil.posed_points(_details, get_parent() as Node3D, 100000000)
	for l in _lamps:
		if not _cage_idx.has(l.id):
			continue
		var idx: PackedInt32Array = _cage_idx[l.id]
		var c := Vector3.ZERO
		for i in idx:
			c += pts[i]
		c /= float(maxi(idx.size(), 1))
		# the lamp node's pivot-space offset from its baked anchor vs. the live cage centroid
		var node_p := (get_parent() as Node3D).to_local(l.global_position)
		var drift := node_p.distance_to(c) # absolute (includes the baked-centroid vs verts-in-box difference)
		if not _worst.has(l.id):
			_worst[l.id] = {"base": drift, "max_dev": 0.0}
		var w: Dictionary = _worst[l.id]
		w["max_dev"] = maxf(w["max_dev"], absf(drift - w["base"]))
		print("[lights] lamp-drift ", l.id, " dist=", snappedf(drift * 100.0, 0.1), " cm  base=", snappedf(float(w["base"]) * 100.0, 0.1), " cm  centroid=", c.snapped(Vector3.ONE * 0.001), " max_dev=", snappedf(float(w["max_dev"]) * 100.0, 0.1), " cm")
