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
	# Canto: the camera is searched (camera_clearview.gd) so the sun god-face and the ship share the frame and no sail/rigging covers him.
	{"name": "Canto", "mode": "canto_frame", "solve": true, "fov": 62.0},
	{"name": "silhouette", "mode": "sun_behind", "dist": 34.0, "height": 2.6, "fov": 56.0},
	# Crew close-ups (not part of the auto cycle): offset is relative to the character, in the ship frame.
	{"name": "close Papi_Fuego", "mode": "crew", "solve": true, "slot": "Papi_Fuego", "off": Vector3(-2.6, 0.5, -2.6), "fov": 45.0},
	{"name": "close Papi_Diagnostica", "mode": "crew", "solve": true, "slot": "Papi_Diagnostica", "off": Vector3(3.4, 2.3, -1.2), "fov": 45.0},
	{"name": "close El_Salchipapa", "mode": "crew", "solve": true, "slot": "El_Salchipapa", "off": Vector3(-2.0, 1.4, -3.0), "fov": 45.0},
	{"name": "close Don_Omar", "mode": "crew", "solve": true, "slot": "Don_Omar", "off": Vector3(2.4, 0.15, 2.4), "fov": 40.0},
	# Ocean inspection shots (not part of the auto cycle).
	{"name": "water close", "pos": Vector3(-8.0, 1.5, -5.0), "look": Vector3(0.0, 0.8, -3.0), "fov": 55.0},
	{"name": "helm", "attached": true, "mode": "crew", "solve": true, "front_deg": 38.0, "slot": "Papi_Fuego", "off": Vector3(-1.9, 0.7, 1.9), "fov": 48.0},
	{"name": "violin", "attached": true, "mode": "crew", "solve": true, "slot": "Don_Omar", "off": Vector3(1.9, 0.5, -0.4), "fov": 42.0},
	{"name": "top down", "pos": Vector3(0.5, 30.0, 1.0), "look": Vector3(0.0, 0.0, 0.0), "fov": 45.0},
	{"name": "flag stern", "mode": "flag", "group": "flag_pavillion_mast", "dist": 7.0, "fov": 45.0},
	{"name": "flag main", "mode": "flag", "group": "flag_main_mast", "dist": 7.0, "fov": 45.0},
	{"name": "wake", "pos": Vector3(3.0, 13.0, 27.0), "look": Vector3(0.0, 0.0, 14.0), "fov": 60.0},
	# Storm hero (index 18): low on the weather bow quarter, looking up at the hull and the rig against the swell.
	{"name": "storm", "pos": Vector3(-10.0, 1.5, -13.0), "look": Vector3(0.0, 8.0, -2.0), "fov": 62.0},
	# Island portrait (index 19): from the deck toward the nearest island, framed by its size (evidence shot for island lighting).
	{"name": "island", "mode": "island", "solve": true, "pos": Vector3(3.0, 9.0, -4.0), "fov": 40.0},
	{"name": "island close", "mode": "island", "solve": true, "frame": 0.42, "pos": Vector3(3.0, 11.0, -4.0), "fov": 40.0},
	# Anti-sun (index 21, not in the cycle): looks away from the sun, where the rainbow forms after a storm.
	{"name": "anti-sun", "mode": "sun_away", "pos": Vector3(-13.0, 9.0, 6.0), "rise": 16.0, "fov": 72.0},
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
## Clear-view solver state (camera_clearview.gd): per shot index {off|pos, goal, cands, ci, age, best, best_f}.
const ClearView := preload("res://scripts/camera_clearview.gd")
var _cv := ClearView.new()
var _cv_ready := false
var _sol := {}
var _ship_len := 22.0
var _samples: Array = []
const SOLVE_BUDGET_US := 1500 ## microseconds per frame shared by all solver work (an instant jump still runs a full pass synchronously)
const BUILD_START_S := 2.5 ## the ship model is loaded by then (ship_ready fires in the first frames)
const BUILD_BUDGET_US := 1500 ## microseconds per frame for the incremental occluder build (at least one mesh per frame)
var _deadline_us := 0
var _cv_force_sync := false
const REVALIDATE_S := 1.5

func _ready() -> void:
	add_to_group("camera_director")
	add_to_group("rebase")
	process_priority = 10
	_ship = get_node(ship_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="): # debug: --cam=x,y,z,lx,ly,lz[,fov] in ship space, metres (index 22, mode raw)
			var v := a.get_slice("=", 1).split_floats(",")
			shots.append({"name": "debug", "mode": "raw", "pos": Vector3(v[0], v[1], v[2]), "look": Vector3(v[3], v[4], v[5]), "fov": v[6] if v.size() > 6 else 55.0})
	var ld := get_node_or_null("../Ship/Pivot/Model")
	if ld and ld.has_signal("ship_ready"):
		ld.ship_ready.connect(func(l: float, _b: float, _r: float) -> void:
			shot_scale = l / 22.0
			_ship_len = l
			_cv_ready = false
			_sol.clear())
	far = 60000.0
	near = 0.15
	_noise.frequency = 0.35
	_noise.fractal_octaves = 2
	_apply_pose(_time, true)

func _exit_tree() -> void:
	_cv.finish_pending() # never leave occluder-build tasks running while the tree is destroyed

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
	if instant:
		if not _cv_ready and shots[index].get("solve", false):
			_cv_force_sync = true # an instant jump (hotkey, capture) needs the answer now
		_update_solver(index, 0.0, true)

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

var _prof_us := 0
var _prof_on := OS.get_cmdline_user_args().has("--cam-prof")

func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_inner(delta)
	if _prof_on:
		var us := Time.get_ticks_usec() - _t0
		if us > 800:
			print("[camprof] t=", snappedf(_time, 0.01), " camera _process ", snappedf(us / 1000.0, 0.1), " ms (solver ", snappedf(_prof_us / 1000.0, 0.1), " ms)")
	_prof_us = 0

func _process_inner(delta: float) -> void:
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
	if not _cv_ready and _time > BUILD_START_S:
		_ensure_cv() # builds the occluders in slices during the start-up ramp, not at the first solved shot
	var solve_set: Array[int] = [_from]
	for k in [_to, (_to + 1) % cycle_count]: # the next cycle shot is pre-solved so it is ready when blended in
		if not solve_set.has(k):
			solve_set.append(k)
	var _s0 := Time.get_ticks_usec()
	_deadline_us = _s0 + SOLVE_BUDGET_US
	for i in solve_set:
		_update_solver(i, delta, false)
	_prof_us += Time.get_ticks_usec() - _s0
	_apply_pose(_time, false)

func _frame() -> Transform3D:
	# Use the interpolated ship transform (the body runs at the physics rate, the camera at the render rate).
	var st: Transform3D = _ship.get_global_transform_interpolated()
	var fwd := -st.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(st.origin.x, 0.0, st.origin.z))

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
		var c := _crew_center(s)
		var off: Vector3 = _sol[i]["off"] if _sol.has(i) else s["off"]
		return {"pos": c + off, "look": c, "fov": s["fov"], "att": true}
	if mode == "sun_away":
		var ha := Vector3(_sun_dir().x, 0.0, _sun_dir().z).normalized()
		var wpa: Vector3 = f * (s["pos"] as Vector3)
		var wla: Vector3 = wpa - ha * 100.0 + Vector3(0, float(s["rise"]), 0)
		return {"pos": s["pos"], "look": f.affine_inverse() * wla, "fov": s["fov"]}
	if mode == "island":
		var isl_pose := _island_pose(i, s, f)
		if not isl_pose.is_empty():
			return isl_pose
	if mode == "canto_frame":
		var pos: Vector3 = _sol[i]["pos"] if _sol.has(i) else _canto_default()
		var fr := _canto_frame(pos, _sun_local(f))
		return {"pos": pos, "look": pos + (fr["dir"] as Vector3) * 100.0, "fov": fr["fov"]}
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
	if shots[i].get("mode", "") == "flag":
		var fl := get_tree().get_first_node_in_group(String(shots[i]["group"]))
		if fl:
			var vp: Dictionary = fl.view_pose(float(shots[i]["dist"]))
			return {"pos": vp["pos"], "look": vp["look"], "fov": shots[i]["fov"], "att": false, "up": Vector3.UP}
	var p := _shot_pose(i, t)
	var att: bool = p.get("att", false)
	var f: Transform3D = _pivot().get_global_transform_interpolated() if att else _frame()
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
	return _ship.get_global_transform_interpolated().origin.y

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

# --- clear-view solver: shots whose subject must not be covered by sails, shrouds or lanterns ------------------------

func _crew_center(s: Dictionary) -> Vector3:
	var slot := get_node_or_null("../Ship/Pivot/CrewMarkers/" + str(s["slot"])) as Node3D
	return (slot.position if slot else Vector3.ZERO) + Vector3(0, 1.0, 0)

## Occluder set: built ONCE, incrementally (a few ms per frame, BVHs on worker threads), then cached for the whole run.
## The first call starts the build once the ship exists; solved shots wait until it is complete.
func _ensure_cv() -> bool:
	if _cv_ready:
		return true
	if not _cv.building:
		var model := get_node_or_null("../Ship/Pivot/Model")
		if model == null or _time < BUILD_START_S or model.get_child_count() == 0:
			return false
		_cv.begin_build([model, get_node_or_null("../Ship/Pivot/Helm"), get_node_or_null("../Ship/Pivot/Lights")].filter(func(n: Variant) -> bool: return n != null), _pivot())
	var immediate := _cv_force_sync
	if _cv.step_build(1 << 30 if immediate else BUILD_BUDGET_US):
		_cv_ready = true
		var rig := 0
		for it in _cv.items:
			if String(it["name"]).to_lower().contains("rigging"):
				rig += 1
		print("[cam] clear-view occluders: ", _cv.items.size(), " ship meshes (", rig, " rigging), ship length ", snappedf(_ship_len, 0.1), " m")
	return _cv_ready

func _canto_default() -> Vector3:
	return Vector3(-0.6, 0.12, 0.8) * _ship_len

func _sun_local(f: Transform3D) -> Vector3:
	var sd: Vector3 = f.basis.inverse() * _sun_dir()
	sd.y = maxf(sd.y, 0.06) # below the horizon (night) keep aiming just above it
	return sd.normalized()

## Look direction and vertical fov that keep the sun face and the ship centre in frame from `pos` (ship yaw frame). The look
## direction starts halfway between them and shifts toward the sun when both do not fit (high noon sun): Canto always stays
## fully framed, the ship is then allowed to crop at the bottom. `ok` = Canto fits; `need` = the vertical fov (deg) used.
func _canto_frame(pos: Vector3, sd: Vector3) -> Dictionary:
	var ctr := Vector3(0.0, 0.2 * _ship_len, 0.0)
	var dc := (ctr - pos).normalized()
	var hw := minf(atan(0.55 * _ship_len / maxf(pos.distance_to(ctr), 1.0)), deg_to_rad(32.0))
	var m := deg_to_rad(11.0)
	# Continuous in the sun angle (no stepping): the more the sun and the ship are apart, the more the view leans to the sun.
	var sep := sd.angle_to(dc)
	var t := maxf(0.5, 1.0 - deg_to_rad(30.0) / maxf(sep, 0.01)) # keeps the sun within ~30 deg of the view centre
	var dir := (sd * t + dc * (1.0 - t)).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir).normalized()
	var sx := absf(atan2(sd.dot(right), sd.dot(dir)))
	var sy := absf(atan2(sd.dot(up), sd.dot(dir)))
	var cx := absf(atan2(dc.dot(right), dc.dot(dir)))
	var cy := absf(atan2(dc.dot(up), dc.dot(dir)))
	var half_c := maxf(sy + m, atan(tan(minf(sx + m, 1.4)) / 1.7))
	var half_s := maxf(cy + deg_to_rad(24.0), atan(tan(minf(cx + hw, 1.4)) / 1.7))
	var fov_full := rad_to_deg(maxf(half_c, half_s)) * 2.1
	return {"dir": dir, "fov": clampf(fov_full, 48.0, 94.0), "need": minf(fov_full, 94.0), "sep": rad_to_deg(sep), "ok": rad_to_deg(half_c) * 2.1 <= 92.0}

func _sun_clear(pos: Vector3, sd: Vector3) -> bool:
	var right := sd.cross(Vector3.UP).normalized()
	var up := right.cross(sd).normalized()
	var dirs: Array[Vector3] = [sd]
	for k in 6: # cone covering the face (about 4 degrees) plus margin
		var a := float(k) / 6.0 * TAU
		dirs.append((sd + (right * cos(a) + up * sin(a)) * 0.09).normalized())
	for d in dirs:
		if _cv.blocked(pos, pos + d * 400.0):
			return false
	return true

## Subject sample grid (3 heights x 3 widths, camera-relative width added in clear_fraction): thin shrouds and ratlines need a dense
## cone of rays, a handful of them threads through the gaps.
## Azimuth (atan2(x, z) in the pivot frame) of the way the character faces, read from its live Visual node (the model's
## native front is -X once crew_slot.gd applies final_model_yaw_deg); NAN when the slot is not loaded.
func _crew_front_az(s: Dictionary) -> float:
	var slot := get_node_or_null("../Ship/Pivot/CrewMarkers/" + str(s["slot"]))
	var vis := slot.get_node_or_null("Visual") as Node3D if slot else null
	if vis == null:
		return NAN
	var d: Vector3 = _pivot().global_basis.inverse() * vis.global_basis * Vector3(-1, 0, 0)
	return atan2(d.x, d.z)

func _crew_samples() -> Array:
	if _samples.is_empty():
		for yi in 5:
			for xi in 7:
				_samples.append(Vector3(-0.45 + xi * 0.15, -0.1 + yi * 0.24, 0.0))
	return _samples

func _crew_ok(c: Vector3, off: Vector3) -> float:
	if c.y + off.y < 1.7:
		return 0.0
	var frac := _cv.clear_fraction(c + off, c, _crew_samples())
	if frac >= 0.5 and _cv.near_blocked(c + off, c):
		frac -= 0.25 # lens jammed against a lantern, rail or shroud
	return frac

func _update_solver(i: int, dt: float, immediate: bool) -> void:
	var s := shots[i]
	if not s.get("solve", false) or free_mode or not _ensure_cv():
		return
	var mode: String = s.get("mode", "")
	var is_crew := mode == "crew"
	var is_island := mode == "island"
	var key := "off" if is_crew else "pos"
	if not _sol.has(i):
		_sol[i] = {key: (s["off"] as Vector3) if is_crew else (_island_default() if is_island else _canto_default()), "goal": null, "cands": [], "ci": 0, "age": 99.0, "best": null, "best_f": -1.0}
	var st: Dictionary = _sol[i]
	st["age"] = float(st["age"]) + dt
	var c := _crew_center(s) if is_crew else Vector3.ZERO
	var f := _frame()
	var sd := _sun_local(f)
	var aim := _island_dir() if is_island else sd # what the lens must see unobstructed: the sun face, or the island
	if st.has("ref") and aim.angle_to(st["ref"]) > deg_to_rad(3.0):
		st["age"] = 99.0 # the sun / island moved relative to the ship: re-check now instead of at the next interval
	# 1. revalidate the current goal now and then; a blocked one starts a new search around it
	if (st["cands"] as Array).is_empty() and (st["goal"] == null or float(st["age"]) >= REVALIDATE_S) and (immediate or Time.get_ticks_usec() < _deadline_us):
		var ok := false
		if st["goal"] != null:
			var g: Vector3 = st["goal"]
			if is_crew:
				ok = _crew_ok(c, g) >= float(s.get("min_clear", 1.0))
			elif is_island:
				ok = _sun_clear(g, aim)
			else:
				ok = _canto_frame(g, sd)["ok"] and _sun_clear(g, sd)
		st["age"] = 0.0
		st["ref"] = aim
		if not ok:
			if is_crew:
				st["cands"] = _crew_candidates(s, c, st)
			elif is_island:
				st["cands"] = _island_candidates(st, aim)
			else:
				st["cands"] = _canto_candidates(st, sd)
			st["ci"] = 0
			st["best"] = null
			st["best_f"] = -1.0
	# 2. test candidates in cost order, a few per frame, until one is fully clear
	var cands: Array = st["cands"]
	while not cands.is_empty() and (immediate or Time.get_ticks_usec() < _deadline_us):
		var idx: int = st["ci"]
		if idx >= cands.size():
			# nothing fully clear: settle for the least-blocked candidate
			st["goal"] = st["best"] if st["best"] != null else (st[key] as Vector3)
			cands.clear()
			print("[cam] ", s["name"], ": no fully clear spot, best kept (", snappedf(maxf(float(st["best_f"]), 0.0), 0.01), " clear) blocker=", _cv.last_blocker)
			break
		st["ci"] = idx + 1
		var cand: Vector3 = cands[idx]
		var frac := _crew_ok(c, cand) if is_crew else (1.0 if _sun_clear(cand, aim) else 0.0)
		if frac > float(st["best_f"]):
			st["best_f"] = frac
			st["best"] = cand
		if frac >= float(s.get("min_clear", 1.0)):
			st["goal"] = cand
			cands.clear()
			print("[cam] ", s["name"], ": clear spot ", cand, " after ", idx + 1, " tries", (" front_az=%.0f" % rad_to_deg(_crew_front_az(s))) if is_crew else "")
			break
	# 3. glide toward the goal with a critically damped spring (continuous velocity: no kick when the goal hops)
	if st["goal"] != null:
		var goal: Vector3 = st["goal"]
		if immediate and dt == 0.0 and (st["cands"] as Array).is_empty():
			st[key] = goal
			st["vel"] = Vector3.ZERO
		elif dt > 0.0:
			var smooth_t := 1.6 if is_crew else 4.0
			var om := 2.0 / smooth_t
			var x := om * dt
			var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
			var cur: Vector3 = st[key]
			var vel: Vector3 = st.get("vel", Vector3.ZERO)
			var d := cur - goal
			var tmp := (vel + om * d) * dt
			st["vel"] = (vel - om * tmp) * e
			st[key] = goal + (d + tmp) * e

func _crew_candidates(s: Dictionary, c: Vector3, st: Dictionary) -> Array:
	var off0: Vector3 = s["off"]
	var a0 := atan2(off0.x, off0.z)
	var r0 := maxf(Vector2(off0.x, off0.z).length(), 1.2)
	var af := _crew_front_az(s)
	if not is_nan(af):
		# Aim for the character's front quarter, on the side the shot was authored for.
		var side_sign := 1.0 if angle_difference(af, a0) >= 0.0 else -1.0
		a0 = af + side_sign * deg_to_rad(float(s.get("front_deg", 38.0)))
	var cur: Vector3 = st["goal"] if st["goal"] != null else off0
	var ac := atan2(cur.x, cur.z)
	var out: Array = []
	for k in range(-12, 12):
		var a := a0 + float(k) * deg_to_rad(15.0)
		for rm: float in [1.0, 0.8, 1.3, 1.7, 2.2]:
			var r: float = r0 * rm
			for dy: float in [0.0, 0.5, 1.0, 1.7]:
				var o := Vector3(sin(a) * r, off0.y + dy, cos(a) * r)
				var cost: float = absf(float(k)) * 0.26 + absf(rm - 1.0) * 0.5 + dy * 0.5 + absf(angle_difference(ac, a)) * 0.4
				out.append([cost, o])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out.map(func(e: Array) -> Vector3: return e[1])

func _canto_candidates(st: Dictionary, sd: Vector3) -> Array:
	var cur: Vector3 = st["goal"] if st["goal"] != null else _canto_default()
	var ac := atan2(cur.x, cur.z)
	var cr := Vector2(cur.x, cur.z).length() / _ship_len
	var ch := cur.y / _ship_len
	var out: Array = []
	for k in 24:
		var a := float(k) / 24.0 * TAU
		for rm: float in [0.9, 1.15, 1.5, 2.0]:
			for hm: float in [0.12, 0.3, 0.6]:
				var p := Vector3(sin(a) * rm * _ship_len, hm * _ship_len, cos(a) * rm * _ship_len)
				var fr := _canto_frame(p, sd)
				if not fr["ok"]:
					continue
				var need: float = fr["need"]
				var cost: float = need * 0.02 + float(fr["sep"]) * 0.05 + rm * 0.25 + hm * 0.6 + absf(angle_difference(ac, a)) * 2.0 + absf(rm - cr) * 1.5 + absf(hm - ch) * 1.5
				out.append([cost, p])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out.map(func(e: Array) -> Vector3: return e[1])

## Nearest island (Islands.targets(), read-only): {pos: Vector2 world xz, radius}; empty when none.
func _nearest_island(f: Transform3D) -> Dictionary:
	var isl := get_node_or_null("../Islands")
	if isl == null or not isl.has_method("targets"):
		return {}
	var best := {}
	var bd := 1e9
	for t: Dictionary in isl.targets():
		var d := (t["pos"] as Vector2).distance_to(Vector2(f.origin.x, f.origin.z))
		if d < bd:
			bd = d
			best = t
	return best

## Direction (ship yaw frame) from the ship to the nearest island's body.
func _island_dir() -> Vector3:
	var f := _frame()
	var t := _nearest_island(f)
	if t.is_empty():
		return Vector3(0, 0.05, -1)
	var wl := Vector3((t["pos"] as Vector2).x, 0.22 * float(t["radius"]), (t["pos"] as Vector2).y)
	return (f.affine_inverse() * wl).normalized()

func _island_default() -> Vector3:
	var d := _island_dir()
	return Vector3(d.x, 0.0, d.z).normalized() * 0.9 * _ship_len + Vector3(0, 0.15 * _ship_len, 0)

func _island_candidates(st: Dictionary, aim: Vector3) -> Array:
	var ab := atan2(aim.x, aim.z)
	var cur: Vector3 = st["goal"] if st["goal"] != null else _island_default()
	var ac := atan2(cur.x, cur.z)
	var out: Array = []
	for k in range(-6, 7):
		var a := ab + float(k) * deg_to_rad(12.0)
		for rm: float in [0.8, 1.0, 1.4]:
			for hm: float in [0.1, 0.18, 0.28]:
				var p := Vector3(sin(a) * rm * _ship_len, hm * _ship_len, cos(a) * rm * _ship_len)
				var cost: float = absf(float(k)) * 0.12 + rm * 0.3 + absf(hm - 0.16) * 0.8 + absf(angle_difference(ac, a)) * 1.2
				out.append([cost, p])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out.map(func(e: Array) -> Vector3: return e[1])

## From a clear spot on the island's side of the ship, looking at the nearest island framed by its clearance radius.
func _island_pose(i: int, s: Dictionary, f: Transform3D) -> Dictionary:
	var best := _nearest_island(f)
	if best.is_empty():
		return {}
	var rad: float = best["radius"]
	var pos: Vector3 = _sol[i]["pos"] if _sol.has(i) else _island_default()
	var wl := Vector3((best["pos"] as Vector2).x, 0.22 * rad, (best["pos"] as Vector2).y)
	var dist := (f * pos).distance_to(wl)
	var fov_deg := clampf(rad_to_deg(2.0 * atan(rad * float(s.get("frame", 1.1)) / maxf(dist, 1.0))), 8.0, 55.0)
	return {"pos": pos, "look": f.affine_inverse() * wl, "fov": fov_deg}
