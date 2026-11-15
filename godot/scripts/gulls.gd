extends Node3D
## Seabird boids around the masts: gulls (flapping) and a couple of albatrosses (long gliding wings).
## Each bird orbits the ship's mast tops, with separation/alignment/cohesion between birds and banking from lateral acceleration.
## Rendering: three MultiMeshes (bodies, left wings, right wings) for the whole flock; the look of each bird is unchanged.
## Presence (M4a.2): how many birds are around follows the day, the storm and the wind regime. Birds never pop in or out: a new bird
## flies in from the horizon and a leaving bird flies off and is only released once it is far out of sight. Behaviour follows the wind:
## in a calm few birds, flapping all the time; in fresh wind they soar (gliding, faster); in a strong wind fewer; in a storm none.
## Test aids: `--no-birds`, `--birds-log` (prints presence changes), `--birds-now` (every bird active from the first frame).

@export var gull_count := 8
@export var albatross_count := 2
@export var ship_path := NodePath("../Ship")

const FAR := 460.0 ## m: birds this far from the ship are released (hidden); arrivals and departures happen out here
const ARRIVE_RANGE := 420.0

enum State { AWAY, ACTIVE, LEAVING }

var _ship: Node3D
var _birds: Array[Dictionary] = []
var _mm_body: MultiMesh
var _mm_l: MultiMesh
var _mm_r: MultiMesh
var _cool := 0.0
var _presence := 1.0
var _log := false
var _t := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-birds" in args:
		queue_free()
		return
	_log = "--birds-log" in args
	_ship = get_node(ship_path)
	add_to_group("rebase")
	add_to_group("ambient_system")
	gull_count = maxi(3, int(round(gull_count * Quality.ambient_scale)))
	albatross_count = maxi(1, int(round(albatross_count * Quality.ambient_scale)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.93)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 8
	body.rings = 4
	var n := gull_count + albatross_count
	_mm_body = _make_mm(body, mat, n)
	_mm_l = _make_mm(_wing_mesh(1.0), mat, n)
	_mm_r = _make_mm(_wing_mesh(1.0), mat, n)
	_presence = _target_presence()
	var start_active := n if "--birds-now" in args else int(round(_presence * n))
	if _log:
		print("[birds] start presence=", snappedf(_presence, 0.01), " wind=", snappedf(WorldState.wind_ms, 0.1), " active=", start_active, "/", n)
	for i in n:
		var alb := i >= gull_count
		var dir := 1.0 if i % 2 == 0 else -1.0
		var rad := randf_range(22.0, 48.0) * (1.4 if alb else 1.0)
		var hgt := randf_range(26.0, 44.0) * (1.3 if alb else 1.0)
		var b := {
			"alb": alb, "sc": 1.0 if alb else 0.5, "dir": dir, "radius": rad, "height": hgt,
			"p": Vector3.ZERO, "v": Vector3.ZERO, "state": State.AWAY,
			"speed": randf_range(8.0, 11.0) if not alb else randf_range(9.0, 12.0),
			"phase": randf() * TAU, "flap": randf_range(4.0, 6.0), "bank": 0.0, "glide": randf() * 4.0,
			"xf": Transform3D.IDENTITY, "flapv": 0.0,
		}
		_birds.append(b)
		if _birds_index_active(i, start_active):
			_place_in_orbit(b)
			b["state"] = State.ACTIVE
		else:
			_hide(i)

func _make_mm(mesh: Mesh, mat: Material, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.custom_aabb = AABB(Vector3(-1200, -200, -1200), Vector3(2400, 800, 2400)) # the flock roams far from the node's origin
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return mm

## Birds fill in order: with `k` birds present, the first k indices (gulls first, albatrosses last) are the active ones.
func _birds_index_active(i: int, k: int) -> bool:
	return i < k

func _place_in_orbit(b: Dictionary) -> void:
	var a := randf() * TAU
	var rad: float = b["radius"]
	var c := _ship.global_position
	b["p"] = c + Vector3(cos(a) * rad, float(b["height"]), sin(a) * rad)
	b["v"] = Vector3(-sin(a), 0, cos(a)) * float(b["dir"]) * 7.0

func _hide(i: int) -> void:
	var z := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0))
	_mm_body.set_instance_transform(i, z)
	_mm_l.set_instance_transform(i, z)
	_mm_r.set_instance_transform(i, z)

func _wing_mesh(span: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0, 0.3), Vector3(0, 0, -0.25), Vector3(1.6 * span, 0.05, -0.12)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	return st.commit()

## 0..1 share of the flock that wants to be around: diurnal, none in a storm, a few in a calm, fewer in a strong wind.
func _target_presence() -> float:
	var w := WorldState
	var day := 1.0 - smoothstep(0.35, 0.8, w.night)
	var storm := 1.0 - smoothstep(0.3, 0.75, w.storm)
	var wind := w.wind_ms
	# calm (0-2 m/s) ~40 %, light 80 %, moderate/fresh 100 %, strong (14-20) falling to 40 %
	var wf := lerpf(0.4, 1.0, smoothstep(1.0, 4.0, wind)) * (1.0 - 0.6 * smoothstep(13.0, 20.0, wind))
	return clampf(day * storm * wf, 0.0, 1.0)

## Soaring factor 0..1: 0 in a calm (flapping to stay up), 1 in fresh wind (long glides).
func _soar() -> float:
	return smoothstep(2.0, 9.0, WorldState.wind_ms) * (1.0 - 0.5 * smoothstep(16.0, 22.0, WorldState.wind_ms))

func _active_count() -> int:
	var k := 0
	for b in _birds:
		if int(b["state"]) == State.ACTIVE:
			k += 1
	return k

func _process(delta: float) -> void:
	_t += delta
	var sp := _ship.global_position
	var n := _birds.size()
	# --- presence: launch an arrival or send one bird off every few seconds, never all at once ---
	_presence = lerpf(_presence, _target_presence(), 1.0 - exp(-delta / 20.0))
	_cool -= delta
	if _cool <= 0.0:
		var want := int(round(_presence * float(n)))
		var have := _active_count()
		if have < want:
			for i in n:
				var b: Dictionary = _birds[i]
				if int(b["state"]) == State.AWAY:
					_launch_arrival(b, sp)
					_cool = randf_range(2.0, 5.0)
					if _log:
						print("[birds] t=", int(_t), " arrival ", i, " presence=", snappedf(_presence, 0.01), " wind=", snappedf(WorldState.wind_ms, 0.1), " active=", have + 1, "/", n)
					break
		elif have > want:
			for i in range(n - 1, -1, -1):
				var b: Dictionary = _birds[i]
				if int(b["state"]) == State.ACTIVE:
					b["state"] = State.LEAVING
					_cool = randf_range(3.0, 7.0)
					if _log:
						print("[birds] t=", int(_t), " leaving ", i, " presence=", snappedf(_presence, 0.01), " wind=", snappedf(WorldState.wind_ms, 0.1), " active=", have - 1, "/", n)
					break
	var soar := _soar()
	var t := _t
	for i in n:
		var b: Dictionary = _birds[i]
		var st: int = b["state"]
		if st == State.AWAY:
			continue
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		var rel := p - sp
		var flat := Vector3(rel.x, 0, rel.z)
		var dist := maxf(flat.length(), 0.01)
		var radial := flat / dist
		var tangent := Vector3(-radial.z, 0, radial.x) * float(b["dir"])
		var spd_k := lerpf(0.8, 1.12, soar) # soaring birds cruise faster
		var base_speed := float(b["speed"]) * spd_k
		var want: Vector3
		var acc: Vector3
		if st == State.LEAVING:
			# Head out to the horizon, climbing a little; released once far out of sight.
			want = radial * base_speed * 1.25 + tangent * base_speed * 0.2
			want.y = (sp.y + float(b["height"]) + 12.0 - p.y) * 0.3
			acc = (want - v) * 1.1
		else:
			want = tangent * base_speed + radial * (float(b["radius"]) - dist) * 0.45
			want.y = (sp.y + float(b["height"]) + sin(t * 0.35 + float(b["phase"])) * 3.0 - p.y) * 0.6
			acc = (want - v) * 1.4
			var sep := Vector3.ZERO
			var ali := Vector3.ZERO
			var coh := Vector3.ZERO
			var cnt := 0
			for j in n:
				if j == i or int((_birds[j] as Dictionary)["state"]) != State.ACTIVE:
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
		nv = nv.limit_length(base_speed * 1.3)
		if spd < 4.0:
			nv = nv.normalized() * 4.0
		b["v"] = nv
		p += nv * delta
		b["p"] = p
		if st == State.LEAVING and dist > FAR:
			b["state"] = State.AWAY
			_hide(i)
			continue
		var fwd := nv.normalized()
		var bank: float = b["bank"]
		var basis := Basis.IDENTITY
		if absf(fwd.y) < 0.99:
			var lat := acc.dot(Vector3(-fwd.z, 0, fwd.x))
			bank = lerpf(bank, clampf(-lat * 0.12, -0.7, 0.7), 1.0 - exp(-delta * 3.0))
			b["bank"] = bank
			basis = Basis.looking_at(fwd, Vector3.UP).rotated(fwd, bank)
		var flap: float
		if bool(b["alb"]):
			flap = sin(t * 0.8 + float(b["phase"])) * lerpf(0.2, 0.12, soar) + 0.05
		else:
			# Flap bursts alternating with glides: in a calm it flaps all the time, in fresh wind it mostly glides.
			var g := sin(t * 0.5 + float(b["glide"]))
			var thr := lerpf(-1.1, 0.55, soar) # g > thr -> flapping
			flap = (sin(t * float(b["flap"]) * TAU * 0.5 + float(b["phase"])) * 0.55 if g > thr else 0.08)
		var sc: float = b["sc"]
		var o := p
		_mm_body.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(0.18, 0.16, 0.6) * sc), o))
		_mm_l.set_instance_transform(i, Transform3D(basis * Basis(Vector3(0, 0, 1), flap) * Basis.from_scale(Vector3(sc, sc, sc)), o))
		_mm_r.set_instance_transform(i, Transform3D(basis * Basis(Vector3(0, 0, 1), -flap) * Basis.from_scale(Vector3(-sc, sc, sc)), o))

## A new bird appears far out (invisible at that distance), already heading in; it flies into its orbit.
func _launch_arrival(b: Dictionary, sp: Vector3) -> void:
	var a := randf() * TAU
	var c := sp + Vector3(cos(a) * ARRIVE_RANGE, 0.0, sin(a) * ARRIVE_RANGE)
	c.y = sp.y + float(b["height"])
	b["p"] = c
	b["v"] = (sp - c).normalized() * float(b["speed"])
	b["state"] = State.ACTIVE
	b["bank"] = 0.0

## World rebase: keep the flock with the ship.
func rebase(shift: Vector3) -> void:
	for b in _birds:
		b["p"] = (b["p"] as Vector3) - Vector3(shift.x, 0.0, shift.z)

func ambient_pools() -> Dictionary:
	return {"birds": _birds.size()}

func ambient_stats() -> Dictionary:
	var k := 0
	for b in _birds:
		if int(b["state"]) != State.AWAY:
			k += 1
	return {"birds": k}
