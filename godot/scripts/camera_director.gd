extends Camera3D
## Cinematic auto camera: preset shots (defined in the ship's yaw-only frame) blended every
## `shot_duration` seconds, with slow orbit drift and handheld-like noise.
## C toggles a free-fly debug camera, 1-4 jump to shots.

@export var ship_path := NodePath("../Ship")
@export var shot_duration := 20.0
@export var blend_time := 5.0
@export var handheld_deg := 0.35
## Noise sampling speed for the handheld sway (noise frequency 0.35 -> ~0.5 Hz at 1.5).
@export var handheld_rate := 1.5
@export var free_speed := 25.0

# Positions are in the ship frame (+X starboard, -Z bow) for a ~22 m ship.
var shots: Array[Dictionary] = [
	{"name": "3/4 bow", "pos": Vector3(-13.0, 4.6, -19.0), "look": Vector3(0.0, 4.2, -1.5), "fov": 58.0},
	{"name": "side low", "pos": Vector3(-25.0, 1.8, 3.0), "look": Vector3(0.0, 4.5, -1.0), "fov": 52.0},
	{"name": "high wide", "pos": Vector3(15.0, 21.0, 30.0), "look": Vector3(0.0, 2.0, -50.0), "fov": 64.0},
	{"name": "captain", "attached": true, "pos": Vector3(-1.3, 7.3, 13.4), "look": Vector3(0.0, 4.0, -14.0), "fov": 60.0},
	{"name": "deck crew", "attached": true, "pos": Vector3(-9.0, 7.0, 4.0), "look": Vector3(0.0, 3.0, 0.0), "fov": 55.0},
	# Sun-relative shots (computed from the DirectionalLight3D direction at runtime).
	{"name": "Canto", "mode": "sun_look", "pos": Vector3(-2.5, 4.9, 2.0), "fov": 62.0},
	{"name": "silhouette", "mode": "sun_behind", "dist": 34.0, "height": 2.6, "fov": 56.0},
	# Crew close-ups (not part of the auto cycle): offset is relative to the character, in the ship frame.
	{"name": "close Papi_Fuego", "mode": "crew", "slot": "Papi_Fuego", "off": Vector3(-2.6, 0.5, -2.6), "fov": 45.0},
	{"name": "close Papi_Diagnostica", "mode": "crew", "slot": "Papi_Diagnostica", "off": Vector3(3.4, 2.3, -1.2), "fov": 45.0},
	{"name": "close El_Salchipapa", "mode": "crew", "slot": "El_Salchipapa", "off": Vector3(-2.0, 1.4, -3.0), "fov": 45.0},
	{"name": "close Don_Omar", "mode": "crew", "slot": "Don_Omar", "off": Vector3(2.4, 0.15, 2.4), "fov": 40.0},
	# Ocean inspection shots (not part of the auto cycle).
	{"name": "water close", "pos": Vector3(-8.0, 1.5, -5.0), "look": Vector3(0.0, 0.8, -3.0), "fov": 55.0},
	{"name": "helm", "attached": true, "mode": "crew", "slot": "Papi_Fuego", "off": Vector3(-1.9, 0.7, 1.9), "fov": 48.0},
	{"name": "violin", "attached": true, "mode": "crew", "slot": "Don_Omar", "off": Vector3(1.9, 0.5, -0.4), "fov": 42.0},
	{"name": "top down", "pos": Vector3(0.5, 30.0, 1.0), "look": Vector3(0.0, 0.0, 0.0), "fov": 45.0},
	{"name": "wake", "pos": Vector3(3.0, 13.0, 27.0), "look": Vector3(0.0, 0.0, 14.0), "fov": 60.0},
]
## Ocean inspection shots (not part of the auto cycle).
## (appended below in _ready)
## Only the first N shots take part in the automatic cycle.
var cycle_count := 7

var free_mode := false
## Shots are authored for a 22 m ship; this scales them to the real ship length (set from ship_ready).
var shot_scale := 1.0
var _lift := 0.0
var _env := -1000.0
var _dt := 0.016
var _ship: Node3D
var _from := 0
var _to := 0
var _blend := 1.0
var _blend_len := 5.0
var _timer := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _free_yaw := 0.0
var _free_pitch := 0.0

func _ready() -> void:
	add_to_group("camera_director")
	add_to_group("rebase")
	process_priority = 10
	_ship = get_node(ship_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="): # debug: --cam=x,y,z,lx,ly,lz[,fov] in ship space, metres (index 16, mode raw)
			var v := a.get_slice("=", 1).split_floats(",")
			shots.append({"name": "debug", "mode": "raw", "pos": Vector3(v[0], v[1], v[2]), "look": Vector3(v[3], v[4], v[5]), "fov": v[6] if v.size() > 6 else 55.0})
	var ld := get_node_or_null("../Ship/Pivot/Model")
	if ld and ld.has_signal("ship_ready"):
		ld.ship_ready.connect(func(l: float, _b: float, _r: float) -> void: shot_scale = l / 22.0)
	far = 25000.0
	near = 0.15
	_noise.frequency = 0.35
	_noise.fractal_octaves = 2
	_apply_pose(_time, true)

func rebase(shift: Vector3) -> void:
	if free_mode:
		global_position -= shift

func jump_to(index: int, instant := false) -> void:
	index = clampi(index, 0, shots.size() - 1)
	_from = _to if _blend >= 1.0 else _from
	_to = index
	_blend = 1.0 if instant else 0.0
	if instant:
		_from = index
	_blend_len = 1.6
	_timer = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_C:
			free_mode = not free_mode
			if free_mode:
				var e := global_transform.basis.get_euler()
				_free_yaw = e.y
				_free_pitch = e.x
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if free_mode else Input.MOUSE_MODE_VISIBLE
		elif k >= KEY_1 and k <= KEY_7:
			free_mode = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			jump_to(k - KEY_1)
		elif k == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif free_mode and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_free_yaw -= mm.relative.x * 0.0028
		_free_pitch = clampf(_free_pitch - mm.relative.y * 0.0028, -1.5, 1.5)

func _process(delta: float) -> void:
	_time += delta
	_dt = delta
	if free_mode:
		_free_fly(delta)
		return
	_timer += delta
	if _blend >= 1.0 and _timer >= shot_duration:
		_timer = 0.0
		_from = _to
		_to = (_to + 1) % cycle_count
		_blend = 0.0
		_blend_len = blend_time
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / _blend_len)
		if _blend >= 1.0:
			_from = _to
	_apply_pose(_time, false)

func _frame() -> Transform3D:
	var yaw := _ship.rotation.y
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(_ship.global_position.x, 0.0, _ship.global_position.z))

func _sun_dir() -> Vector3:
	var sun := get_node_or_null("../Sun") as Node3D
	return sun.global_transform.basis.z.normalized() if sun else Vector3(0, 0.34, -0.9)

func _shot_pose(i: int, t: float) -> Dictionary:
	var s := shots[i]
	if shot_scale != 1.0 and s.get("mode", "") in ["", "sun_look"]:
		s = s.duplicate()
		if s.has("pos"): s["pos"] = (s["pos"] as Vector3) * shot_scale
		if s.has("look"): s["look"] = (s["look"] as Vector3) * shot_scale
	var f := _frame()
	var mode: String = s.get("mode", "")
	if mode == "crew":
		var slot := get_node_or_null("../Ship/Pivot/CrewMarkers/" + str(s["slot"])) as Node3D
		var c := (slot.position if slot else Vector3.ZERO) + Vector3(0, 1.0, 0)
		return {"pos": c + (s["off"] as Vector3), "look": c, "fov": s["fov"], "att": true}
	if mode == "sun_look":
		# Stand on deck and look up toward the sun, keeping it in the upper third of the frame.
		var wp: Vector3 = f * (s["pos"] as Vector3)
		var wl: Vector3 = wp + _sun_dir() * 100.0 - Vector3(0, 13.0, 0)
		return {"pos": s["pos"], "look": f.affine_inverse() * wl, "fov": s["fov"]}
	if mode == "sun_behind":
		# Camera on the far side of the ship from the sun: the ship is silhouetted against it.
		var h := Vector3(_sun_dir().x, 0.0, _sun_dir().z).normalized()
		var wp2: Vector3 = Vector3(f.origin.x, float(s["height"]), f.origin.z) - h * float(s["dist"])
		wp2 = wp2.rotated(Vector3.UP, 0.0)
		var sway := sin(t * 0.05) * 0.18
		var rel := (wp2 - f.origin).rotated(Vector3.UP, sway)
		var wpos2 := f.origin + rel
		wpos2.y = float(s["height"])
		return {"pos": f.affine_inverse() * wpos2, "look": Vector3(0, 6.0, 0), "fov": s["fov"]}
	var ss := maxf(shot_scale, 1.0)
	var drift := sin(t * 0.045 / ss + float(i) * 1.7) * 0.22 # slow orbit; angular rate shrinks with ship size so m/s stays small
	var look: Vector3 = s["look"]
	var off: Vector3 = (s["pos"] as Vector3) - look
	off = Basis(Vector3.UP, drift) * off
	off.y += sin(t * 0.07 / ss + float(i)) * 0.5 * ss
	return {"pos": look + off, "look": look, "fov": s["fov"], "att": s.get("attached", false)}

func _pivot() -> Node3D:
	return _ship.get_node("Pivot") as Node3D

## World-space pose of one shot. Attached shots live in the ship's full frame (yaw, pitch, roll, heave), so the horizon
## tilts with the roll; the others use the yaw-only frame and watch the ship rock.
func _world_pose(i: int, t: float) -> Dictionary:
	var p := _shot_pose(i, t)
	var att: bool = p.get("att", false)
	var f: Transform3D = _pivot().global_transform if att else _frame()
	var wl: Vector3 = f * (p["look"] as Vector3)
	if not att:
		wl.y += _ship_heave() * 0.5
	return {"pos": f * (p["pos"] as Vector3), "look": wl, "fov": p["fov"], "att": att, "up": (f.basis.y if att else Vector3.UP)}

func _apply_pose(t: float, _first: bool) -> void:
	var a := _world_pose(_from, t)
	var b := _world_pose(_to, t)
	var w := smoothstep(0.0, 1.0, _blend)
	var wpos: Vector3 = (a["pos"] as Vector3).lerp(b["pos"], w)
	var wlook: Vector3 = (a["look"] as Vector3).lerp(b["look"], w)
	var up: Vector3 = (a["up"] as Vector3).lerp(b["up"], w).normalized()
	var fv: float = lerpf(a["fov"], b["fov"], w)
	var att_w: float = lerpf(1.0 if a["att"] else 0.0, 1.0 if b["att"] else 0.0, w)
	# Soft water clearance against the wave ENVELOPE: highest surface among the camera column, a ring around it and
	# points ahead along the view direction (so it never ends up inside a crest), raised with sea_state.
	var fwd_xz := Vector2(wlook.x - wpos.x, wlook.z - wpos.z).normalized()
	var side := Vector2(-fwd_xz.y, fwd_xz.x)
	var env := Waves.height_at(wpos.x, wpos.z)
	for off in [Vector2(0, 0), fwd_xz * 5.0, fwd_xz * 11.0, side * 5.0, -side * 5.0, -fwd_xz * 4.0]:
		env = maxf(env, Waves.height_at(wpos.x + off.x, wpos.z + off.y))
	# The envelope itself is low-passed (0.45 s) so single crests do not jerk the camera; the margin covers the lag.
	_env = lerpf(_env, env, 1.0 - exp(-_dt / 0.45)) if _env > -900.0 else env
	env = maxf(_env, env - 1.2)
	var margin := 1.0 + 2.2 * Waves.sea_state
	var deficit := env + margin - wpos.y
	var lift := 0.5 * (deficit + sqrt(deficit * deficit + 0.35))
	# Asymmetric low-pass: rises quickly (the envelope look-ahead + margin anticipate crests), falls slowly.
	_lift = lerpf(_lift, lift, 1.0 - exp(-(1.3 if lift > _lift else 0.6) * _dt))
	wpos.y += _lift * (1.0 - att_w) # cameras mounted on the ship ride with it, no water clearance needed
	global_position = wpos
	look_at(wlook, up)
	# Handheld sway must be slow (<1 Hz); sampling the noise fast reads as vibration.
	var hh := deg_to_rad(handheld_deg)
	var ht := t * handheld_rate
	var rot := Vector3(_noise.get_noise_1d(ht) * hh, _noise.get_noise_1d(ht + 100.0) * hh,
		_noise.get_noise_1d(ht + 200.0) * hh * 0.6)
	basis = basis * Basis.from_euler(rot)
	fov = fv

func _ship_heave() -> float:
	var h = _ship.get("heave")
	return float(h) if h != null else 0.0

func _free_fly(delta: float) -> void:
	basis = Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0.0))
	var v := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): v.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): v.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_E): v.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q): v.y -= 1.0
	var sp := free_speed * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position += basis * v * sp * delta
