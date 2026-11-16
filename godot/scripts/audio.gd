extends Node
## Audio autoload (`Audio`): ambient beds plus a small positional API for every source that lives in the scene.
##
## Beds (not positional): sea, wind (five clips cross-faded by wind speed), rain, thunder. Everything with a place in the world is a
## 3D source with distance attenuation and a distance low-pass: gulls (on the birds), hull creaks and wave wash (on the hull), the
## night bell, the sail flap (on the mast), and whatever other systems add through the API:
##   Audio.play_at(&"hammer", node_or_pos)            one-shot, follows the node if it is a Node3D
##   Audio.loop_at(&"violin", node_or_pos) -> player  looped source; Audio.stop(player) fades it out and frees it
##   Audio.footstep(node, &"wood")                    surface footstep (wood | wet), volume and pitch jittered
##   Audio.register(&"fishing", [stream, ...], {...}) a new id (streams from anywhere), params: bus, max, unit, db, pitch=[lo, hi], filter_hz
## Options for play_at/loop_at: `db` (added), `pitch` (multiplied), `offset` (Vector3 local to the node), `bus`, `max`, `unit`.
## Ids shipped: gull, creak, wave, bell, footstep_wood, footstep_wet, hammer, hammer_loop, saw, violin.
## Flags: `--no-audio` (API calls do nothing), `--mute`, `--audio` (force on in capture/test modes, which are muted by default),
## `--audio-log` (levels every 5 s), `--audio-demo` (a source that flies past the camera: gull calls, footsteps and hammer, then violin).
## Buses (created here): Ambient (beds, gulls), SFX (everything positional else), Thunder (SFX + low-pass); Master has a limiter, -6 dB.

const DIR := "res://assets/audio/"
const MASTER_DB := -6.0
const MAX_3D := 40
## Wind speed (m/s) at which each wind clip is at full level; neighbours cross-fade between them.
const WIND_PEAKS := [3.5, 7.0, 11.0, 15.0, 19.5]

var enabled := true
var _lib := {} # id -> {files, streams (lazy), bus, max, unit, db, pitch, filter_hz}
var _live: Array[AudioStreamPlayer3D] = []
var _ship: Node3D
var _t := 0.0
var _smooth := {}
var _sea: AudioStreamPlayer
var _winds: Array[AudioStreamPlayer] = []
var _rain: Array[AudioStreamPlayer] = []
var _thunder_player: AudioStreamPlayer
var _rumble_player: AudioStreamPlayer
var _flap: AudioStreamPlayer3D
var _flap_pb: AudioStreamGeneratorPlayback
var _flap_lp := 0.0
var _flap_env := 0.0
var _flap_next := 0.5
var _next_wave := 3.0
var _next_gull := 6.0
var _next_creak := 4.0
var _next_bell := 120.0
var _last_wobble_wave := -10.0
var _last_wobble_creak := -10.0
var _log := false
var _log_t := 0.0
var _demo := false
var _demo_node: Node3D
var _demo_t := 0.0
var _demo_next := 0.0
var _demo_loop: AudioStreamPlayer3D
var _built := false
var _persist := {} # key -> {player, base_db}
var _next_island_gull := 12.0
var _next_far_bell := 40.0
var _next_rig := 5.0
var _last_bump := -10.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-audio" in args:
		enabled = false
		set_process(false)
		return
	var capture_mode := false
	for a in args:
		if a == "--capture" or a == "--jitter-test" or a == "--rebase-test" or a.begins_with("--sky-shots") or a.begins_with("--perf-log") or a.begins_with("--autopilot-log") or a.begins_with("--plan="):
			capture_mode = true
	_log = "--audio-log" in args
	_demo = "--audio-demo" in args
	_setup_buses()
	var mute := "--mute" in args or (capture_mode and not "--audio" in args)
	AudioServer.set_bus_mute(0, mute)
	process_priority = 130
	_define_library()
	print("[audio] ready: muted=", mute, " master=", MASTER_DB, " dB")

# ------------------------------------------------------------------------------------------------ public API
## Registers or replaces an id. `streams` may be AudioStream resources or "res://..." paths.
func register(id: StringName, streams: Array, params: Dictionary = {}) -> void:
	var d := {"files": streams, "streams": [], "bus": "SFX", "max": 60.0, "unit": 8.0, "db": 0.0, "pitch": [0.95, 1.05], "filter_hz": 5000.0}
	d.merge(params, true)
	_lib[id] = d

## One-shot positional sound. `target` is a Node3D (the sound follows it) or a world position. Returns the player or null.
func play_at(id: StringName, target: Variant, opts: Dictionary = {}) -> AudioStreamPlayer3D:
	return _spawn(id, target, opts, false)

## Looped positional source (violin, saw, hammering). Stop it with `stop(player)`.
func loop_at(id: StringName, target: Variant, opts: Dictionary = {}) -> AudioStreamPlayer3D:
	return _spawn(id, target, opts, true)

func stop(player: AudioStreamPlayer3D, fade := 0.4) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tw := player.create_tween()
	tw.tween_property(player, "volume_db", -60.0, fade)
	tw.tween_callback(player.queue_free)

## Footstep on a surface ("wood" or "wet"; anything else falls back to wood), a little quieter with a random offset in pitch.
func footstep(target: Variant, surface: StringName = &"wood", opts: Dictionary = {}) -> AudioStreamPlayer3D:
	var id := &"footstep_wet" if surface == &"wet" else &"footstep_wood"
	var o := opts.duplicate()
	o["db"] = float(o.get("db", 0.0)) + randf_range(-3.0, 0.0)
	return _spawn(id, target, o, false)

# ------------------------------------------------------------------------------------------------ internals
func _define_library() -> void:
	register(&"gull", _names("gull_", 8), {"bus": "Ambient", "max": 170.0, "unit": 28.0, "db": -3.0, "pitch": [0.9, 1.1], "filter_hz": 6000.0})
	register(&"creak", _names("creak_", 7), {"max": 60.0, "unit": 7.0, "db": -6.0, "pitch": [0.85, 1.1], "filter_hz": 3500.0})
	register(&"wave", _names("wave_", 4), {"max": 120.0, "unit": 14.0, "db": -8.0, "pitch": [0.95, 1.05], "filter_hz": 4500.0})
	register(&"bell", ["bell"], {"max": 220.0, "unit": 20.0, "db": -20.0, "pitch": [0.97, 1.03], "filter_hz": 4000.0})
	register(&"footstep_wood", _names("step_wood_", 4), {"max": 30.0, "unit": 4.0, "db": -4.0, "pitch": [0.92, 1.08], "filter_hz": 3500.0})
	register(&"footstep_wet", _names("step_wet_", 3), {"max": 30.0, "unit": 4.0, "db": -4.0, "pitch": [0.92, 1.08], "filter_hz": 3500.0})
	register(&"hammer", ["hammer_hit"], {"max": 60.0, "unit": 6.0, "db": -4.0, "pitch": [0.92, 1.08], "filter_hz": 4000.0})
	register(&"hammer_loop", ["hammer_loop"], {"max": 60.0, "unit": 6.0, "db": -6.0, "filter_hz": 4000.0})
	register(&"saw", ["saw_loop"], {"max": 50.0, "unit": 5.0, "db": -6.0, "filter_hz": 4000.0})
	register(&"splash", _names("splash_", 4), {"max": 150.0, "unit": 12.0, "db": -4.0, "pitch": [0.9, 1.1], "filter_hz": 4500.0})
	register(&"hit", _names("hit_", 3), {"max": 60.0, "unit": 5.0, "db": -8.0, "pitch": [0.85, 1.0], "filter_hz": 3500.0})
	register(&"crackle", [_synth("crackle")], {"max": 16.0, "unit": 1.5, "db": -24.0, "pitch": [0.95, 1.05], "filter_hz": 6000.0})
	register(&"patter", [_synth("patter")], {"max": 40.0, "unit": 5.0, "db": -14.0, "pitch": [1.0, 1.0], "filter_hz": 6000.0})
	register(&"flutter", [_synth("flutter")], {"max": 70.0, "unit": 6.0, "db": -14.0, "pitch": [0.95, 1.05], "filter_hz": 5000.0})
	register(&"hum", [_synth("hum")], {"max": 450.0, "unit": 25.0, "db": -34.0, "pitch": [1.0, 1.0], "filter_hz": 1500.0})
	register(&"violin", ["violin_loop"], {"max": 55.0, "unit": 6.0, "db": -4.0, "pitch": [1.0, 1.0], "filter_hz": 7000.0})

## Short procedural loops (no CC0 recording needed): fire crackle, rain on wood, flag flutter, a very low lighthouse hum.
func _synth(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var secs := 3.0 if kind != "hum" else 2.0
	var n := int(rate * secs)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var env := 0.0
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		match kind:
			"crackle": # quiet hiss plus sparse sharp clicks that decay in a few ms
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
				if rng.randf() < 0.0009:
					env = rng.randf_range(0.25, 1.0)
				env *= 0.9965
				v = lp * 0.05 + (rng.randf_range(-1.0, 1.0) * env * 0.7)
			"patter": # dense small drops on a hard surface
				if rng.randf() < 0.008:
					env = rng.randf_range(0.1, 1.0) * rng.randf()
				env *= 0.992
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.45
				v = lp * env * 1.1 + rng.randf_range(-1.0, 1.0) * 0.015
			"flutter": # cloth: noise cut by a ~9 Hz flap envelope
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
				var e := 0.5 + 0.5 * sin(TAU * 9.0 * t + 1.7 * sin(TAU * 1.0 * t))
				v = lp * e * e * 0.9
			"hum":
				v = 0.7 * sin(TAU * 58.0 * t) + 0.3 * sin(TAU * 116.0 * t + 0.6)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w

func _names(prefix: String, n: int) -> Array:
	var out := []
	for i in range(1, n + 1):
		out.append(prefix + str(i))
	return out

func _streams(id: StringName) -> Array:
	var d: Dictionary = _lib[id]
	if (d["streams"] as Array).is_empty():
		for f in d["files"]:
			var s: AudioStream = f if f is AudioStream else load(DIR + str(f) + ".ogg") as AudioStream
			if s != null:
				(d["streams"] as Array).append(s)
	return d["streams"]

func _spawn(id: StringName, target: Variant, opts: Dictionary, looped: bool) -> AudioStreamPlayer3D:
	if not enabled or not _lib.has(id):
		return null
	var streams := _streams(id)
	if streams.is_empty():
		return null
	_live = _live.filter(func(p): return is_instance_valid(p))
	if _live.size() >= MAX_3D:
		return null
	var d: Dictionary = _lib[id]
	var s: AudioStream = streams[randi() % streams.size()]
	if looped and "loop" in s:
		s = s.duplicate()
		s.set("loop", true)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = str(opts.get("bus", d["bus"]))
	p.max_distance = float(opts.get("max", d["max"]))
	p.unit_size = float(opts.get("unit", d["unit"]))
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.attenuation_filter_cutoff_hz = float(d["filter_hz"]) # distance low-pass: far sources are darker
	p.attenuation_filter_db = -18.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	var pr: Array = d["pitch"]
	p.pitch_scale = randf_range(float(pr[0]), float(pr[1])) * float(opts.get("pitch", 1.0))
	p.volume_db = float(d["db"]) + float(opts.get("db", 0.0))
	if target is Node3D and is_instance_valid(target):
		(target as Node3D).add_child(p)
		p.position = opts.get("offset", Vector3.ZERO)
	else:
		add_child(p)
		p.global_position = target if target is Vector3 else Vector3.ZERO
	if not looped:
		p.finished.connect(p.queue_free)
	_live.append(p)
	p.play()
	return p

func _setup_buses() -> void:
	AudioServer.set_bus_volume_db(0, MASTER_DB)
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -1.0
		lim.threshold_db = -6.0
		AudioServer.add_bus_effect(0, lim)
	for n in ["Ambient", "SFX", "Thunder"]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, &"Master")
	var ti := AudioServer.get_bus_index("Thunder")
	AudioServer.set_bus_send(ti, &"SFX")
	if AudioServer.get_bus_effect_count(ti) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 2600.0
		AudioServer.add_bus_effect(ti, lp)

func _loop_stream(n: String) -> AudioStream:
	var s := load(DIR + n + ".ogg") as AudioStream
	if s and "loop" in s:
		s = s.duplicate()
		s.set("loop", true)
	return s

func _bed(stream: AudioStream, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p

## Beds and the sail flap need the ship, which does not exist yet when the autoload starts.
func _build_with_ship() -> void:
	_built = true
	_sea = _bed(_loop_stream("sea_loop"), "Ambient")
	_sea.play()
	for i in range(1, 6):
		var w := _bed(_loop_stream("wind_" + str(i)), "Ambient")
		w.play(randf() * 20.0)
		_winds.append(w)
	for i in 2:
		var r := _bed(_loop_stream("rain"), "Ambient")
		r.pitch_scale = 0.95 + 0.1 * i
		r.play(2.0 * i)
		_rain.append(r)
	_thunder_player = _bed(load(DIR + "thunder.ogg") as AudioStream, "Thunder")
	_thunder_player.volume_db = 0.0
	_rumble_player = _bed(load(DIR + "rumble.ogg") as AudioStream, "Thunder")
	_rumble_player.volume_db = -12.0
	# Sail flap: a positional procedural source at the mainmast, low-passed noise bursts with a fast decay.
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_flap = AudioStreamPlayer3D.new()
	_flap.stream = gen
	_flap.bus = "SFX"
	_flap.max_distance = 90.0
	_flap.unit_size = 10.0
	_flap.attenuation_filter_cutoff_hz = 5000.0
	_flap.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_flap.volume_db = -80.0
	_ship.add_child(_flap)
	_flap.position = Vector3(0, 12.0, -2.0)
	_flap.play()
	_flap_pb = _flap.get_stream_playback() as AudioStreamGeneratorPlayback
	if _ship.has_signal("wobble"):
		_ship.connect("wobble", _on_wobble)
	WorldState.thunder.connect(_on_thunder)
	_setup_persistent()

func _db(g: float) -> float:
	return linear_to_db(maxf(g, 0.0001))

## Exponential smoothing of a layer gain, so nothing ever steps.
func _sm(layer: String, target: float, dt: float, tau := 1.5) -> float:
	var cur: float = _smooth.get(layer, target)
	cur = lerpf(cur, target, 1.0 - exp(-dt / tau))
	_smooth[layer] = cur
	return cur

func _process(delta: float) -> void:
	if not _built:
		_ship = get_tree().root.get_node_or_null("Main/Ship") as Node3D
		if _ship == null:
			return
		_build_with_ship()
	_t += delta
	var w := WorldState
	var dt := minf(delta, 0.1)
	var speed := 0.0
	if "current_speed" in _ship:
		speed = float(_ship.get("current_speed"))
	var night: float = w.night
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), lerpf(0.0, -3.0, night))
	var wind_ms: float = w.wind_speed_ms()
	var sea: float = w.sea_state
	var rain_amt := smoothstep(0.35, 0.8, w.storm)

	# Sea bed: about -20 dB (flat) to -8 dB (sea 0.9), a little louder when the ship moves, softer at night.
	var sea_g := _sm("sea", lerpf(0.14, 0.45, clampf(sea, 0.0, 1.0)) * (1.0 + 0.25 * clampf(speed / 8.0, 0.0, 1.0)) * lerpf(1.0, 0.7, night), dt)
	_sea.volume_db = _db(sea_g)

	# Wind: five clips cross-fade by wind speed; a calm is near silence; gusts breathe the level.
	var gust := 0.0
	var wf := get_node_or_null("/root/WindField")
	if wf and wf.has_method("gust_amp"):
		gust = float(wf.call("gust_amp"))
	var calm := smoothstep(1.5, 4.5, wind_ms)
	for i in _winds.size():
		var peak: float = WIND_PEAKS[i]
		var width := 4.2 if i < 4 else 6.0
		var wgt := clampf(1.0 - absf(wind_ms - peak) / width, 0.0, 1.0)
		if i == 0:
			wgt *= calm
		elif i == _winds.size() - 1 and wind_ms > peak:
			wgt = 1.0 # beyond the strongest clip's wind speed it stays at full level
		var g := _sm("wind" + str(i), wgt * 0.5 * (1.0 + 0.2 * sin(_t * 0.31 + float(i)) + 0.15 * gust), dt, 2.5)
		_winds[i].volume_db = _db(g)
		_winds[i].stream_paused = g < 0.002

	# Rain (two offset loops).
	var rg := _sm("rain", rain_amt * 0.45, dt, 2.0)
	for r in _rain:
		r.volume_db = _db(rg)
		r.stream_paused = rg < 0.003

	# Wave wash against the hull: more often and louder with speed and sea state; positional on the bow quarters.
	_next_wave -= dt
	if _next_wave <= 0.0:
		_next_wave = randf_range(5.0, 11.0) / (0.5 + clampf(speed / 6.0, 0.0, 1.5) + sea)
		_wave_wash(clampf(0.25 + sea * 0.6 + speed * 0.04, 0.2, 1.0))
	# Gulls: sporadic calls from the birds themselves.
	var gulls_node := get_tree().root.get_node_or_null("Main/Gulls")
	var birds_out: bool = gulls_node != null and gulls_node.visible and night < 0.7 and w.storm < 0.75
	_next_gull -= dt
	if _next_gull <= 0.0:
		_next_gull = randf_range(8.0, 25.0)
		if birds_out:
			_gull_call(gulls_node)
	# Creaks: rare at rest, more with the swell.
	_next_creak -= dt
	if _next_creak <= 0.0:
		_next_creak = randf_range(4.0, 11.0) / (0.4 + sea * 2.0)
		_creak(clampf(0.35 + sea * 0.6, 0.2, 1.0))
	# Bell: rare, at night, never in a storm; at the stern.
	_next_bell -= dt
	if _next_bell <= 0.0:
		_next_bell = randf_range(240.0, 480.0)
		if night > 0.7 and w.storm < 0.4:
			play_at(&"bell", _ship, {"offset": Vector3(0, 6.0, 12.0)})
	_tick_flap(dt, wind_ms)
	_tick_scene_sources(dt, w, wind_ms, rain_amt, night)
	if _demo:
		_tick_demo(dt)
	if _log:
		_log_t += dt
		if _log_t >= 5.0:
			_log_t = 0.0
			print("[audio] t=", int(_t), " sea=", snappedf(_sea.volume_db, 0.1), " dB wind_ms=", snappedf(wind_ms, 0.1), " winds=", _winds.map(func(p): return snappedf(p.volume_db, 1.0)),
				" rain=", snappedf(_db(rg), 0.1), " storm=", snappedf(w.storm, 0.01), " night=", snappedf(night, 0.01), " birds_out=", birds_out, " sources3d=", _live.size(), " persistent=", _persist.size())

func _wave_wash(level: float) -> void:
	var side := 1.0 if randf() < 0.5 else -1.0
	play_at(&"wave", _ship, {"offset": Vector3(side * 3.5, 0.3, randf_range(-9.0, 6.0)), "db": linear_to_db(level)})

func _creak(level: float) -> void:
	play_at(&"creak", _ship, {"offset": Vector3(randf_range(-3.0, 3.0), randf_range(2.0, 6.0), randf_range(-9.0, 9.0)), "db": linear_to_db(level)})

## A gull call from one of the birds: attached to the bird's node when the gull system exposes it, else at a random point of the flock area.
func _gull_call(gulls_node: Node) -> void:
	var target: Variant = null
	if gulls_node != null and gulls_node.has_method("audio_bird_node"):
		target = gulls_node.call("audio_bird_node")
	elif gulls_node != null and "_birds" in gulls_node:
		var birds: Array = gulls_node.get("_birds")
		if not birds.is_empty():
			var b: Dictionary = birds[randi() % birds.size()]
			target = b.get("node", null)
	if target == null:
		var a := randf() * TAU
		target = _ship.global_position + Vector3(cos(a) * randf_range(25.0, 70.0), randf_range(22.0, 45.0), sin(a) * randf_range(25.0, 70.0))
	play_at(&"gull", target, {"db": randf_range(-3.0, 1.0)})

func _on_wobble(intensity: float, kind: String) -> void:
	if kind == "slam" and _t - _last_wobble_wave > 1.5:
		_last_wobble_wave = _t
		_wave_wash(clampf(0.4 + intensity, 0.4, 1.0))
		play_at(&"splash", _ship, {"offset": Vector3(0, 1.0, -10.0), "db": linear_to_db(clampf(0.5 + intensity, 0.5, 1.0)), "pitch": 0.85}) # bow spray
	if kind != "slam" and intensity > 0.15 and _t - _last_bump > 2.0:
		_last_bump = _t
		var boat := get_tree().root.get_node_or_null("Main/Boat") as Node3D
		if boat != null:
			play_at(&"hit", boat, {"db": linear_to_db(clampf(intensity, 0.2, 1.0))}) # the lashed boat knocking in its cradle
		return
	elif _t - _last_wobble_creak > 1.5:
		_last_wobble_creak = _t
		_creak(clampf(0.3 + intensity * 0.7, 0.2, 1.0))

func _on_thunder(delay_s: float, intensity: float) -> void:
	await get_tree().create_timer(delay_s).timeout
	if _thunder_player == null or not is_inside_tree():
		return
	var loud := clampf(intensity, 0.2, 1.0)
	var farness := clampf(delay_s / 4.0, 0.0, 1.0) # distant strikes: quieter and darker
	var tb := AudioServer.get_bus_index("Thunder")
	if AudioServer.get_bus_effect_count(tb) > 0:
		(AudioServer.get_bus_effect(tb, 0) as AudioEffectLowPassFilter).cutoff_hz = lerpf(5000.0, 900.0, farness)
	_thunder_player.volume_db = _db(loud * lerpf(0.9, 0.5, farness))
	_thunder_player.pitch_scale = randf_range(0.9, 1.05)
	_thunder_player.play()
	_rumble_player.volume_db = _db(loud * 0.25)
	_rumble_player.play(randf() * 60.0)
	await get_tree().create_timer(6.0 + 4.0 * loud).timeout
	if _rumble_player:
		_rumble_player.stop()

## Sail flap: bursts of low-passed noise (a snap and a flutter); rate and brightness rise with the wind, nothing in a calm.
func _tick_flap(dt: float, wind_ms: float) -> void:
	if _flap_pb == null:
		return
	var level := smoothstep(5.0, 16.0, wind_ms)
	_flap.volume_db = _db(0.35 * level) if level > 0.01 else -80.0
	_flap_next -= dt
	if _flap_next <= 0.0 and level > 0.01:
		_flap_env = randf_range(0.6, 1.0)
		_flap_next = randf_range(0.25, 1.8) / (0.4 + level * 2.0)
	var n := _flap_pb.get_frames_available()
	var k := 0.18 + 0.5 * level
	var decay := exp(-1.0 / (22050.0 * 0.12))
	for i in n:
		_flap_lp += (randf_range(-1.0, 1.0) - _flap_lp) * k
		_flap_env *= decay
		var s := _flap_lp * _flap_env
		_flap_pb.push_frame(Vector2(s, s))

## `--audio-demo`: a source that flies past the camera on a 300 m line (15 m/s, 8 m off the camera's axis) so approach and recede are audible.
## Passes 1: gull calls, 2: footsteps and hammer blows, 3 (and on): a violin loop. 20 s per pass.
func _tick_demo(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _demo_node == null:
		_demo_node = Node3D.new()
		add_child(_demo_node)
	_demo_t += dt
	var pass_len := 20.0
	var k := int(_demo_t / pass_len)
	var u := fmod(_demo_t, pass_len) / pass_len
	var x := lerpf(-150.0, 150.0, u)
	var up := Vector3.UP * (28.0 if k % 3 == 0 else 1.2)
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	_demo_node.global_position = cam.global_position + right * x + fwd * 8.0 + up
	if k % 3 != 2 and _demo_loop != null:
		stop(_demo_loop)
		_demo_loop = null
	_demo_next -= dt
	match k % 3:
		0:
			if _demo_next <= 0.0:
				_demo_next = 1.6
				play_at(&"gull", _demo_node)
		1:
			if _demo_next <= 0.0:
				_demo_next = 0.55
				footstep(_demo_node, &"wood")
				if randf() < 0.3:
					play_at(&"hammer", _demo_node)
		2:
			if _demo_loop == null:
				_demo_loop = loop_at(&"violin", _demo_node)


# ------------------------------------------------------------------------------------------------ scene sources
## Looped sources that live on scene nodes (lantern crackle, flag flutter, lighthouse hum, rain on deck and sails): created once, volume per frame.
func _persistent(key: String, id: StringName, target: Node3D, base_db: float, opts: Dictionary = {}) -> void:
	if _persist.has(key) or target == null:
		return
	var p := loop_at(id, target, opts)
	if p == null:
		return
	p.volume_db = -60.0
	_persist[key] = {"player": p, "base": base_db}

func _set_persistent(key: String, gain: float) -> void:
	if not _persist.has(key):
		return
	var d: Dictionary = _persist[key]
	var p: AudioStreamPlayer3D = d["player"]
	if not is_instance_valid(p):
		_persist.erase(key)
		return
	p.volume_db = float(d["base"]) + _db(gain) if gain > 0.002 else -60.0
	p.stream_paused = gain <= 0.002

func _setup_persistent() -> void:
	_persistent("rain_deck", &"patter", _ship, -8.0, {"offset": Vector3(0, 3.0, 2.0)})
	_persistent("rain_sails", &"patter", _ship, -12.0, {"offset": Vector3(0, 11.0, -2.0), "pitch": 1.35})
	if ShipLights.has_signal("lantern_changed"):
		ShipLights.lantern_changed.connect(func(_id, _lit): _sync_lanterns())
	_sync_lanterns()
	for g in ["flag_pavillion_mast", "flag_main_mast"]:
		var f := get_tree().get_first_node_in_group(g) as Node3D
		_persistent("flag_" + g, &"flutter", f, -4.0)
	for i in get_tree().get_nodes_in_group("lighthouse_beam").size():
		var b := get_tree().get_nodes_in_group("lighthouse_beam")[i] as Node3D
		_persistent("hum_" + str(b.get_instance_id()), &"hum", b, 0.0)

func _sync_lanterns() -> void:
	for l in get_tree().get_nodes_in_group("ship_lantern"):
		var key := "fire_" + str(l.get_instance_id())
		if l.lit and not l.is_window:
			_persistent(key, &"crackle", l, 0.0)
			_set_persistent(key, 1.0)
		else:
			_set_persistent(key, 0.0)

func _tick_scene_sources(dt: float, w: Node, wind_ms: float, rain_amt: float, night: float) -> void:
	_set_persistent("rain_deck", rain_amt)
	_set_persistent("rain_sails", rain_amt * 0.8)
	var flap := smoothstep(2.0, 12.0, wind_ms)
	for g in ["flag_pavillion_mast", "flag_main_mast"]:
		_set_persistent("flag_" + g, flap)
	for k in _persist.keys():
		if str(k).begins_with("hum_"):
			_set_persistent(k, 1.0)
	# New lighthouses and lanterns appear as islands recycle: check them every few seconds.
	if int(_t) % 5 == 0 and int(_t * 10.0) % 10 == 0:
		for b in get_tree().get_nodes_in_group("lighthouse_beam"):
			_persistent("hum_" + str(b.get_instance_id()), &"hum", b as Node3D, 0.0)
	# Gulls resting on the islands: day only, from the island itself.
	_next_island_gull -= dt
	if _next_island_gull <= 0.0:
		_next_island_gull = randf_range(10.0, 28.0)
		if night < 0.5 and w.storm < 0.6:
			var isl := get_tree().root.get_node_or_null("Main/Islands")
			if isl != null and isl.has_method("targets"):
				var best: Vector3 = Vector3.INF
				var bd := 1100.0
				for t in isl.targets():
					var pos := Vector3((t["pos"] as Vector2).x, 25.0, (t["pos"] as Vector2).y)
					var d := pos.distance_to(_ship.global_position)
					if d < bd:
						bd = d
						best = pos
				if best.is_finite():
					play_at(&"gull", best, {"db": 4.0, "max": 1100.0, "unit": 70.0})
	# A very distant bell from a passing ship, now and then, much attenuated.
	_next_far_bell -= dt
	if _next_far_bell <= 0.0:
		_next_far_bell = randf_range(40.0, 110.0)
		var ps := get_tree().root.get_node_or_null("Main/PassingShips")
		if ps != null and "_slots" in ps:
			var act: Array = []
			for s in ps.get("_slots"):
				if s["active"]:
					act.append(s["node"])
			if not act.is_empty():
				var shp: Node3D = act[randi() % act.size()]
				play_at(&"bell", shp, {"db": 14.0, "max": 1800.0, "unit": 90.0, "pitch": 0.9})
	# Rigging and blocks groaning, more with the wind.
	if wind_ms > 5.0:
		_next_rig -= dt
		if _next_rig <= 0.0:
			_next_rig = randf_range(3.0, 9.0) / (0.3 + wind_ms / 12.0)
			play_at(&"creak", _ship, {"offset": Vector3(randf_range(-2.0, 2.0), randf_range(6.0, 16.0), randf_range(-8.0, 8.0)), "pitch": randf_range(1.35, 1.7), "db": -10.0 + 8.0 * smoothstep(5.0, 18.0, wind_ms)})
