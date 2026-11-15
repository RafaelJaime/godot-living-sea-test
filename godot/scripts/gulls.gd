extends Node3D
## Seabird boids around the masts: gulls (flapping) and a couple of albatrosses (long gliding wings).
## Each bird orbits the ship's mast tops, with separation/alignment/cohesion between birds and banking from lateral acceleration.
## Birds are diurnal: they fade out at night and in heavy storms. Test aid: `--no-birds`.

@export var gull_count := 8
@export var albatross_count := 2
@export var ship_path := NodePath("../Ship")

var _ship: Node3D
var _birds: Array[Dictionary] = []

func _ready() -> void:
	if "--no-birds" in OS.get_cmdline_user_args():
		queue_free()
		return
	_ship = get_node(ship_path)
	add_to_group("rebase")
	add_to_group("ambient_system")
	gull_count = maxi(3, int(round(gull_count * Quality.ambient_scale)))
	albatross_count = maxi(1, int(round(albatross_count * Quality.ambient_scale)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.93)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 8
	body.rings = 4
	for i in gull_count + albatross_count:
		var alb := i >= gull_count
		var sc := 1.0 if alb else 0.5
		var bird := Node3D.new()
		var b := MeshInstance3D.new()
		b.mesh = body
		b.material_override = mat
		b.scale = Vector3(0.18, 0.16, 0.6) * sc
		bird.add_child(b)
		var wing := _wing_mesh(1.0)
		var l := MeshInstance3D.new(); l.mesh = wing; l.material_override = mat
		var r := MeshInstance3D.new(); r.mesh = wing; r.material_override = mat
		r.scale.x = -1.0
		l.scale *= sc; r.scale *= sc
		r.scale.x = -sc
		bird.add_child(l); bird.add_child(r)
		add_child(bird)
		var dir := 1.0 if i % 2 == 0 else -1.0
		var a := randf() * TAU
		var rad := randf_range(22.0, 48.0) * (1.4 if alb else 1.0)
		var hgt := randf_range(26.0, 44.0) * (1.3 if alb else 1.0)
		_birds.append({
			"node": bird, "l": l, "r": r, "alb": alb, "dir": dir, "radius": rad, "height": hgt,
			"p": _ship.global_position + Vector3(cos(a) * rad, hgt, sin(a) * rad),
			"v": Vector3(-sin(a), 0, cos(a)) * dir * 7.0,
			"speed": randf_range(8.0, 11.0) if not alb else randf_range(9.0, 12.0),
			"phase": randf() * TAU, "flap": randf_range(4.0, 6.0), "bank": 0.0, "glide": randf() * 4.0,
		})

func _wing_mesh(span: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0, 0.3), Vector3(0, 0, -0.25), Vector3(1.6 * span, 0.05, -0.12)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	return st.commit()

func _process(delta: float) -> void:
	var w := WorldState
	var show := w.night < 0.7 and w.storm < 0.75
	visible = show
	if not show:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var sp := _ship.global_position
	var centre := sp
	var n := _birds.size()
	for i in n:
		var b: Dictionary = _birds[i]
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		var rel := p - centre
		var flat := Vector3(rel.x, 0, rel.z)
		var dist := maxf(flat.length(), 0.01)
		var radial := flat / dist
		var tangent := Vector3(-radial.z, 0, radial.x) * float(b["dir"])
		var want := tangent * float(b["speed"]) + radial * (float(b["radius"]) - dist) * 0.45
		want.y = (centre.y + float(b["height"]) + sin(t * 0.35 + float(b["phase"])) * 3.0 - p.y) * 0.6
		var acc := (want - v) * 1.4
		var sep := Vector3.ZERO
		var ali := Vector3.ZERO
		var coh := Vector3.ZERO
		var cnt := 0
		for j in n:
			if j == i:
				continue
			var o: Dictionary = _birds[j]
			var d := p - (o["p"] as Vector3)
			var dl := d.length()
			if dl < 28.0:
				cnt += 1
				ali += o["v"] as Vector3
				coh += o["p"] as Vector3
				if dl < 7.0:
					sep += d / maxf(dl * dl, 0.5) * 6.0
		if cnt > 0:
			acc += sep * 3.0 + (ali / cnt - v) * 0.3 + (coh / cnt - p) * 0.02
		var nv := v + acc * delta
		var spd := nv.length()
		nv = nv.limit_length(float(b["speed"]) * 1.3)
		if spd < 4.0:
			nv = nv.normalized() * 4.0
		b["v"] = nv
		p += nv * delta
		b["p"] = p
		var node: Node3D = b["node"]
		node.global_position = p
		var fwd := nv.normalized()
		if absf(fwd.y) < 0.99:
			var lat := acc.dot(Vector3(-fwd.z, 0, fwd.x))
			b["bank"] = lerpf(float(b["bank"]), clampf(-lat * 0.12, -0.7, 0.7), 1.0 - exp(-delta * 3.0))
			node.look_at(p + fwd, Vector3.UP)
			node.rotate_object_local(Vector3.FORWARD, float(b["bank"]))
		var flap: float
		if bool(b["alb"]):
			flap = sin(t * 0.8 + float(b["phase"])) * 0.12 + 0.05
		else:
			# Flap bursts alternating with glides.
			var g := sin(t * 0.5 + float(b["glide"]))
			flap = (sin(t * float(b["flap"]) * TAU * 0.5 + float(b["phase"])) * 0.55 if g > -0.2 else 0.08)
		(b["l"] as Node3D).rotation.z = flap
		(b["r"] as Node3D).rotation.z = -flap

## World rebase: keep the flock with the ship.
func rebase(shift: Vector3) -> void:
	for b in _birds:
		b["p"] = (b["p"] as Vector3) - Vector3(shift.x, 0.0, shift.z)

func ambient_pools() -> Dictionary:
	return {"birds": _birds.size()}

func ambient_stats() -> Dictionary:
	return {"birds": _birds.size() if visible else 0}
