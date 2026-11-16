extends Node
## Test aid, created by sky.gd only with `--sky-log=<wall seconds>`: logs the sky/exposure/fog/ambient values and reports
## how smooth they are. Run it with `--timescale=N` to sweep a day (720 s at x1) and the weather plan quickly.
##   --sky-log=30 --timescale=30                full run, prints a sample every 2 s and a summary, then quits
##   --storm-end-test                           starts in a held storm, switches to clear after 3 s and reports the state 60
##                                              game-seconds later against a clear reference at the same sun position
##   --sky-shots=name,phase,weather,shot[,wait]+name2,...   preset captures into res://_shots/sky_<name>.png, then quits.
##                                              weather: clear|cloudy|storm|storm_end (storm, then clear after wait/2 s);
##                                              shot: camera_director index (-1 = camera by the nearest island); wait: wall seconds to settle (default 6);
##                                              optional ox,oy,oz (after wait) override a crew shot's offset (candidate sweeps).
## Summary lines: per metric, the largest per-game-second rate of change, its 99th percentile, the ratio of the two (a
## tint step shows as a ratio far above ~3) and, for exposure, how many times the direction of change reversed.

var sky: WorldEnvironment

var _secs := 30.0
var _wall := 0.0
var _next_print := 0.0
var _storm_test := false
var _storm_t := -1.0 # game seconds since the weather switched to clear
var _metrics := {}
var _prev := {}
var _prev_dir := {}
var _reversals := 0
var _frames := 0
var _shots: Array = []
var _shot_i := 0
var _shot_t := -1.0
var _shot_flipped := false
var _follow := false
var _game_t := 0.0
var _last_rev := -1.0
var _min_rev_gap := INF

func _ready() -> void:
	process_priority = 20 # after the camera director (10), so shot -2 can take over the camera
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sky-log="):
			_secs = float(a.get_slice("=", 1))
		elif a == "--storm-end-test":
			_storm_test = true
		elif a.begins_with("--sky-shots="):
			for item in a.get_slice("=", 1).split("+"):
				var f := item.split(",")
				_shots.append({"name": f[0], "phase": float(f[1]), "weather": f[2], "shot": int(f[3]), "wait": float(f[4]) if f.size() > 4 else 6.0,
					"off": Vector3(float(f[5]), float(f[6]), float(f[7])) if f.size() > 7 else Vector3.INF})
	if _storm_test:
		WorldState.day_enabled = false
		WorldState.set_weather("storm", true)
	print("[sky-log] start: run=", _secs, "s timescale=", WorldState.time_scale, " quality=", Quality.name_)

func _sample() -> Dictionary:
	var env: Environment = sky.environment
	var fc: Color = sky.fog_color
	var hc: Color = sky.horizon_color
	return {
		"exposure": sky.exposure,
		"ambient": env.ambient_light_energy,
		"fog_density": env.fog_density,
		"fog_lum": fc.get_luminance(),
		"fog_warm": fc.r - fc.b,
		"horizon_lum": hc.get_luminance(),
		"horizon_warm": hc.r - hc.b,
		"sun_energy": sky.sun_energy_now,
	}

func _shots_step(delta: float) -> void:
	if _wall < 2.0:
		return
	if _shot_i >= _shots.size():
		print("[sky-shots] done: ", _shots.size(), " captures")
		get_tree().quit()
		return
	var it: Dictionary = _shots[_shot_i]
	if _shot_t < 0.0:
		_shot_t = 0.0
		_shot_flipped = false
		WorldState.day_enabled = false
		WorldState.day_phase = float(it["phase"])
		var wx := String(it["weather"])
		WorldState.set_weather("storm" if wx == "storm_end" else wx, true)
		var d := get_tree().get_first_node_in_group("camera_director")
		if d and int(it["shot"]) == -1:
			it["shot"] = _island_shot(d)
		elif d and (int(it["shot"]) == -5 or int(it["shot"]) == -6): # nearest barrel (-5) / plank (-6)
			d.shots.append({"name": "flot", "pos": Vector3(0, 6, 0), "look": Vector3(0, 6, -50), "fov": 50.0})
			it["follow"] = 4 if int(it["shot"]) == -5 else 5
			it["shot"] = d.shots.size() - 1
		elif d and int(it["shot"]) == -4: # camera 5 m from the nearest seaweed patch
			d.shots.append({"name": "weed", "pos": Vector3(0, 6, 0), "look": Vector3(0, 6, -50), "fov": 50.0})
			it["shot"] = d.shots.size() - 1
			it["follow"] = 3
		elif d and int(it["shot"]) == -3: # camera on deck looking at the whale spout (follow handled per frame)
			d.shots.append({"name": "whale", "pos": Vector3(0, 6, 0), "look": Vector3(0, 6, -50), "fov": 30.0})
			it["shot"] = d.shots.size() - 1
			it["follow"] = 2
		elif d and int(it["shot"]) == -2: # camera off the starboard bow, looking at the dolphin pod's zone (ship frame)
			d.shots.append({"name": "pod", "pos": Vector3(11.0, 1.8, -12.0), "look": Vector3(4.0, 0.2, -21.0), "fov": 65.0})
			it["shot"] = d.shots.size() - 1
			it["follow"] = 1
		if d:
			if (it["off"] as Vector3).is_finite(): # candidate sweep: override a crew shot's offset
				d.shots[int(it["shot"])]["off"] = it["off"]
			d.jump_to(int(it["shot"]), true)
		print("[sky-shots] ", it["name"], ": phase=", it["phase"], " weather=", wx, " shot=", it["shot"])
	_shot_t += delta
	if String(it["name"]).begins_with("strike") and not it.get("struck", false) and _shot_t >= 0.4:
		it["struck"] = true # test aid: force one lightning strike, captured 0.15 s later (items named strike_*, wait 0.55)
		var wx := get_node_or_null("../../Weather")
		if wx != null:
			var dist: float = wx.call("_spawn_bolt")
			if wx.get("_zap_on"):
				wx.call("_zap", dist)
			WorldState.flash = 1.0
	_follow = int(_shots[_shot_i].get("follow", 0)) == 1
	_follow_dolphin()
	if int(_shots[_shot_i].get("follow", 0)) == 2:
		_follow_whale()
	elif int(_shots[_shot_i].get("follow", 0)) >= 3:
		_follow_weed(int(_shots[_shot_i].get("follow", 0)))
	if String(it["weather"]) == "storm_end" and not _shot_flipped and _shot_t >= 2.0:
		_shot_flipped = true
		WorldState.set_weather("clear")
	if WorldState.night > 0.5 and _shot_t > 1.0 and _shot_t < 1.2:
		for l in ShipLights.get_lanterns():
			ShipLights.light(l["id"])
	if _shot_t >= float(it["wait"]):
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://_shots/sky_%s.png" % it["name"])
		img.save_png(path)
		print("[sky-shots] saved ", path, " ", img.get_size(), " sun_elev=", snappedf(WorldState.sun_elevation_deg, 0.1), " cloud=", snappedf(WorldState.cloud, 0.01),
			" storm=", snappedf(WorldState.storm, 0.01), " rainbow=", snappedf(WorldState.rainbow, 0.01), " deck_wetness=", snappedf(WorldState.deck_wetness, 0.01), " biolum=", snappedf(WorldState.biolum, 0.01), " exposure=", snappedf(sky.exposure, 0.001))
		_shot_i += 1
		_shot_t = -1.0

## Shot -4: the camera sits 5 m from the seaweed patch nearest to the ship, 2 m up, looking at it.
func _follow_weed(mode: int = 3) -> void:
	var life := get_node_or_null("../../AmbientLife")
	var cam := get_viewport().get_camera_3d()
	var ship := get_node_or_null("../../Ship") as Node3D
	if life == null or cam == null or ship == null:
		return
	var best: Dictionary = {}
	var bd := INF
	for f in life.get("_flot"):
		var k := int(f["kind"])
		if (mode == 3 and k >= 2) or (mode == 4 and k == 1) or (mode == 5 and k == 0):
			var d: float = (f["pos"] as Vector3).distance_to(ship.global_position)
			if d < bd and d > 8.0:
				bd = d
				best = f
	if best.is_empty():
		return
	var p: Vector3 = (best["node"] as Node3D).global_position
	cam.global_position = p + (Vector3(3.5, 2.0, 3.5) if mode == 3 else Vector3(2.4, 1.3, 2.4))
	cam.look_at(p, Vector3.UP)
	cam.fov = 50.0

## Shot -3: the camera stays at the ship and looks at the whale (or its last position), narrow fov.
func _follow_whale() -> void:
	var life := get_node_or_null("../../AmbientLife")
	var cam := get_viewport().get_camera_3d()
	var ship := get_node_or_null("../../Ship") as Node3D
	if life == null or cam == null or ship == null:
		return
	var wp: Vector3 = life.get("_whale_pos")
	cam.global_position = ship.global_position + Vector3(0, 8, 0)
	cam.look_at(wp + Vector3(0, 2.5, 0), Vector3.UP)
	cam.fov = 18.0

## Shot -2: the camera itself follows the highest visible dolphin (7 m abeam, 3 m aft, 1.5 m up) and looks at it. Runs after the director.
func _follow_dolphin() -> void:
	var life := get_node_or_null("../../AmbientLife")
	var cam := get_viewport().get_camera_3d()
	if life == null or cam == null or not _follow:
		return
	var best: Dictionary = {}
	for dd in life.get("_dolphins"):
		if (dd["node"] as Node3D).visible and (best.is_empty() or float(dd["pos"].y) > float(best["pos"].y)):
			best = dd
	if best.is_empty():
		return
	var dp: Vector3 = best["pos"]
	var vel: Vector3 = best["vel"]
	var fwd := Vector3(vel.x, 0.0, vel.z).normalized() if vel.length() > 0.5 else Vector3(0, 0, -1)
	var right := fwd.cross(Vector3.UP)
	cam.global_position = dp + right * 7.0 - fwd * 2.0 + Vector3(0, 1.2, 0)
	cam.look_at(dp + Vector3(0, 0.2, 0), Vector3.UP)
	cam.fov = 50.0

## shot -1: a camera 220 m off the nearest island's shore, 14 m up, looking at the island (adds a shot to the director).
func _island_shot(d: Node) -> int:
	var isl := get_node_or_null("../../Islands")
	var ship := get_node("../../Ship") as Node3D
	if isl == null:
		return 0
	var best := {}
	var bd := INF
	for t in isl.targets():
		var dd: float = (t["pos"] as Vector2).distance_to(Vector2(ship.global_position.x, ship.global_position.z))
		if dd < bd:
			bd = dd
			best = t
	var c := Vector3((best["pos"] as Vector2).x, 0.0, (best["pos"] as Vector2).y)
	var dir := (c - Vector3(ship.global_position.x, 0.0, ship.global_position.z)).normalized()
	var cam_w := c - dir * (float(best["radius"]) + 220.0) + Vector3(0, 14.0, 0)
	var f: Transform3D = d.call("_frame")
	d.shots.append({"name": "island", "pos": f.affine_inverse() * cam_w, "look": f.affine_inverse() * (c + Vector3(0, 18.0, 0)), "fov": 55.0})
	print("[sky-shots] island camera: island at ", snappedf(bd, 1.0), " m from the ship, radius ", snappedf(float(best["radius"]), 1.0))
	return d.shots.size() - 1

func _process(delta: float) -> void:
	_wall += delta
	if not _shots.is_empty():
		_shots_step(delta)
		return
	var gdt: float = maxf(delta * WorldState.time_scale, 1e-6)
	var cur := _sample()
	if _frames > 0:
		for k in cur:
			var rate: float = absf(float(cur[k]) - float(_prev[k])) / gdt
			if not _metrics.has(k):
				_metrics[k] = []
			(_metrics[k] as Array).append(rate)
		var d: float = float(cur["exposure"]) - float(_prev["exposure"])
		if absf(d) > 1e-5:
			var dir := signf(d)
			if _prev_dir.has("exposure") and dir != _prev_dir["exposure"]:
				_reversals += 1
				if _last_rev >= 0.0:
					_min_rev_gap = minf(_min_rev_gap, _game_t - _last_rev)
				_last_rev = _game_t
			_prev_dir["exposure"] = dir
	_prev = cur
	_game_t += gdt
	_frames += 1
	if _storm_test:
		_storm_step(delta)
		return
	if _wall >= _next_print:
		_next_print = _wall + 2.0
		print("[sky-log] t=%.0f phase=%.3f elev=%.1f cloud=%.2f storm=%.2f exposure=%.3f ambient=%.3f fog=%.5f sun_e=%.2f ao=%s" % [
			_wall, WorldState.day_phase, WorldState.sun_elevation_deg, WorldState.cloud, WorldState.storm,
			sky.exposure, (cur["ambient"] as float), (cur["fog_density"] as float), sky.sun_energy_now, sky.ao_state])
	if _wall >= _secs:
		_report()
		get_tree().quit()

func _storm_step(delta: float) -> void:
	if _wall < 3.0:
		return
	if _storm_t < 0.0:
		_storm_t = 0.0
		WorldState.set_weather("clear")
		print("[storm-end] storm=%.2f rain_ratio=%.2f exposure=%.3f at switch" % [WorldState.storm, _rain_ratio(), sky.exposure])
	_storm_t += delta * WorldState.time_scale
	if int(_storm_t) % 15 == 0 and int(_storm_t) != int(_storm_t - delta * WorldState.time_scale):
		print("[storm-end] +%ds storm=%.3f cloud=%.3f rain_ratio=%.3f exposure=%.3f" % [int(_storm_t), WorldState.storm, WorldState.cloud, _rain_ratio(), sky.exposure])
	if _storm_t >= 60.0:
		var cloud := WorldState.WEATHER_TARGET["clear"].x as float
		var ref_exp: float = sky.call("_exposure_for", WorldState.sun_elevation_deg, cloud, 0.0)
		print("[storm-end] +60s storm=%.3f cloud=%.3f rain_ratio=%.3f exposure=%.3f (clear reference %.3f, diff %.1f%%) fog_density=%.5f" % [
			WorldState.storm, WorldState.cloud, _rain_ratio(), sky.exposure, ref_exp, 100.0 * absf(sky.exposure - ref_exp) / ref_exp,
			(sky.environment as Environment).fog_density])
		get_tree().quit()

func _rain_ratio() -> float:
	var wx := get_node_or_null("../../Weather")
	if wx and wx.get("_rain"):
		return (wx.get("_rain") as GPUParticles3D).amount_ratio
	return -1.0

func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(ceil(q * float(b.size()))) - 1, 0, b.size() - 1)]

func _report() -> void:
	for k in _metrics:
		var a: Array = _metrics[k]
		var mx := 0.0
		for v in a:
			mx = maxf(mx, v)
		var p99 := _pct(a, 0.99)
		print("[sky-log] summary %-12s max_rate=%.5f/game_s p99=%.5f ratio=%.1f" % [k, mx, p99, mx / maxf(p99, 1e-9)])
	print("[sky-log] summary exposure direction reversals=", _reversals, " over ", _frames, " frames, game time ", snappedf(_game_t, 1.0),
		" s, shortest gap between reversals ", snappedf(_min_rev_gap, 1.0), " game s (oscillation would show gaps of a few frames)")
