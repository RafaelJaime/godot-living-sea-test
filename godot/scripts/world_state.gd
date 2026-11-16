extends Node
## Autonomous world clocks: day/night cycle, weather cycle (clear -> cloudy -> storm -> cloudy -> clear),
## slowly drifting wind. Everything else (sky, fog, lights, rain, ocean sea_state, autopilot) reads from here.
## Capture/test args: --timescale=N (speeds up the internal clocks only), --start-phase=0..1 (0 midnight, .5 noon),
## --weather=clear|cloudy|storm (start there and hold), --sea=0..1 (force sea_state).

const WEATHER_PLAN := [ # [name, duration s at timescale 1]: one storm (~7 % of the time) every 30 minutes
	["clear", 600.0], ["cloudy", 240.0], ["storm", 120.0], ["cloudy", 120.0], ["clear", 480.0], ["cloudy", 240.0],
]

## Wind regimes (true wind m/s at 10 m): [name, lo, hi, min hold s, max hold s, share of the time]. Calm leaves the flags hanging,
## light drops them half way, fresh is the ~11 m/s the sail calibration was done at. The storm is NOT a regime: it comes from
## the weather plan and pulls the wind up while `storm` rises (see _update_wind).
const WIND_REGIMES := [
	["calm", 0.3, 1.8, 120.0, 300.0, 0.12],
	["light", 2.3, 4.8, 180.0, 480.0, 0.28],
	["moderate", 5.5, 8.5, 240.0, 600.0, 0.30],
	["fresh", 9.5, 12.5, 180.0, 420.0, 0.16],
	["strong", 14.5, 19.0, 60.0, 120.0, 0.06],
]
const STORM_WIND_MS := 25.0
const WEATHER_TARGET := {
	"clear": Vector2(0.12, 0.0), # (cloud cover, storminess)
	"cloudy": Vector2(0.72, 0.08),
	"storm": Vector2(1.0, 1.0),
}

@export var day_length := 720.0 ## seconds per full day/night cycle
@export var day_enabled := true
@export var blend_time := 40.0 ## seconds for weather values to settle

var time_scale := 1.0
var day_phase := 0.70 ## 0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset (0.70 ~ 20 deg late afternoon)
var cloud := 0.12
var storm := 0.0
var wind_angle := -2.0 ## direction the wind blows TOWARD, radians in the (x, z) plane
var wind_strength := 0.3 ## 0..1, derived: wind_ms / 28
var wind_ms := 11.0 ## true mean wind speed (m/s), follows the regime machine, the storm pulls it up
var wind_regime := 3 ## index into WIND_REGIMES (fresh at start: the look the project was tuned at)
var wind_regime_name := "fresh"
var _wind_from := 11.0
var _wind_to := 11.0
var _wind_ramp_t := 1.0e9
var _wind_ramp_dur := 90.0
var _wind_hold := 240.0
var _wind_timer := 0.0
var _wind_frozen := false ## --wind=<regime> / --wind-hold: no transitions
var _wind_rng := RandomNumberGenerator.new()
var _wind_log := false
var _wind_seeded := false
var _force_regime_name := ""
var _storm_cooldown := 0.0
var _force_ms := -1.0
var _was_stormy_wind := false
var sea_state := 0.25
var override_sea := -1.0
var override_wind_deg := 9999.0 ## test aid (--wind=deg): fixed wind direction
var flash := 0.0 ## lightning flash 0..1 (written by weather_fx.gd)
var cloud_scroll := Vector2.ZERO
var rainbow := 0.0 ## 0..1, after a storm while the sun is low-ish and the rain has stopped
var fog_bank := 0.0 ## 0..1, morning fog bank around sunrise on calm mornings
var biolum := 0.0 ## 0..1, night bioluminescence amount (ocean agent hook; also the global shader parameter `sky_biolum`)
var deck_wetness := 0.0 ## 0..1, ship deck: soaks within ~25 s of heavy rain, dries slowly (faster in daylight and wind). Drives deck_wet.gd.
var wetness := 0.0 ## 0..1, decays ~2 min after the rain stops (wet decks, glossy sea)

## Emitted with every lightning strike: `delay_s` = seconds until the thunder should be heard (distance / 343), `intensity` 0..1.
signal thunder(delay_s: float, intensity: float)
## Emitted once when a storm clears and a rainbow can form.
signal storm_cleared

# derived
var sun_elevation_deg := 20.0
var sun_dir := Vector3.UP
var moon_dir := Vector3.DOWN
var daylight := 1.0 ## 0 night .. 1 day
var night := 0.0

var _plan_index := 0
var _plan_elapsed := 0.0
var _hold := false
var _noise := FastNoiseLite.new()
var _clock := 0.0

## Names of the global shader parameters the sky publishes every frame (see sky.gd). Registered here, at autoload time,
## so any shader (ocean, wake, ...) can declare `global uniform ...;` without touching project.godot.
const GLOBALS := {
	"sky_horizon_color": Vector3(0.8, 0.8, 0.8), "sky_zenith_color": Vector3(0.22, 0.42, 0.75),
	"sky_fog_color": Vector3(0.8, 0.8, 0.8), "sky_sun_color": Vector3(1, 1, 1), "sky_sun_dir": Vector3(0, 1, 0),
	"sky_fog_density": 0.0003, "sky_storminess": 0.0, "sky_night": 0.0, "sky_rain": 0.0, "sky_biolum": 0.0,
}
var _was_stormy := false

func _ready() -> void:
	process_priority = -90
	for g in GLOBALS:
		var v: Variant = GLOBALS[g]
		var t := RenderingServer.GLOBAL_VAR_TYPE_VEC3 if v is Vector3 else RenderingServer.GLOBAL_VAR_TYPE_FLOAT
		if not ProjectSettings.has_setting("shader_globals/" + g):
			RenderingServer.global_shader_parameter_add(g, t, v)
	_noise.seed = 77
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--timescale="):
			time_scale = float(a.get_slice("=", 1))
		elif a.begins_with("--start-phase="):
			day_phase = float(a.get_slice("=", 1))
		elif a.begins_with("--sea="):
			override_sea = float(a.get_slice("=", 1))
		elif a.begins_with("--weather="):
			var w := a.get_slice("=", 1)
			_hold = true
			var t: Vector2 = WEATHER_TARGET.get(w, WEATHER_TARGET["clear"])
			cloud = t.x
			storm = t.y
			for i in WEATHER_PLAN.size():
				if WEATHER_PLAN[i][0] == w:
					_plan_index = i
					break
		elif a.begins_with("--wind="):
			var wv := a.get_slice("=", 1)
			if wv.is_valid_float():
				override_wind_deg = float(wv) # direction, degrees
			else:
				_force_regime_name = wv # calm|light|moderate|fresh|strong|storm
		elif a.begins_with("--wind-ms="): # exact mean wind (also read by WindField); regime machine held
			_force_ms = float(a.get_slice("=", 1))
			_wind_frozen = true
		elif a.begins_with("--wind-seed="):
			_wind_rng.seed = int(a.get_slice("=", 1))
			_wind_seeded = true
		elif a == "--wind-hold":
			_wind_frozen = true
		elif a == "--wind-log":
			_wind_log = true
		elif a.begins_with("--engine-scale="):
			Engine.time_scale = float(a.get_slice("=", 1))
		elif a == "--no-day":
			day_enabled = false
	if not _wind_seeded:
		_wind_rng.randomize()
	_init_wind()
	_derive()

func set_weather(name: String, instant := false) -> void:
	for i in WEATHER_PLAN.size():
		if WEATHER_PLAN[i][0] == name:
			_plan_index = i
			_plan_elapsed = 0.0
	if instant:
		var t: Vector2 = WEATHER_TARGET[name]
		cloud = t.x
		storm = t.y

func _process(delta: float) -> void:
	var dt := delta * time_scale
	_clock += dt
	if day_enabled:
		day_phase = fposmod(day_phase + dt / day_length, 1.0)
	# Weather schedule.
	if not _hold:
		_plan_elapsed += dt
		if _plan_elapsed >= WEATHER_PLAN[_plan_index][1]:
			_plan_elapsed = 0.0
			_plan_index = (_plan_index + 1) % WEATHER_PLAN.size()
	var tgt: Vector2 = WEATHER_TARGET[WEATHER_PLAN[_plan_index][0]]
	var k := 1.0 - exp(-dt / maxf(blend_time, 0.01) * 2.0)
	cloud = lerpf(cloud, tgt.x, k)
	storm = lerpf(storm, tgt.y, k)
	# Wind drifts slowly around a base direction; strength follows the weather plus gusts.
	var n1 := _noise.get_noise_1d(_clock * 0.006)
	var n2 := _noise.get_noise_1d(_clock * 0.03 + 50.0)
	wind_angle = -2.0 + n1 * 1.4 if override_wind_deg > 9000.0 else deg_to_rad(override_wind_deg)
	_update_wind(dt, n2)
	cloud_scroll += Vector2(cos(wind_angle), sin(wind_angle)) * (0.004 + 0.012 * wind_strength) * dt
	# Sea follows the wind (~0.07 flat calm, ~0.22 at 11 m/s, ~1 in the storm) plus a little from the cloud cover.
	sea_state = override_sea if override_sea >= 0.0 else clampf(0.05 + 0.5 * pow(wind_ms / 28.0, 1.2) + 0.12 * cloud + 0.3 * storm, 0.0, 1.0)
	Waves.sea_state = sea_state
	flash = maxf(flash - delta * 5.0, 0.0)
	_derive()
	_derive_atmosphere(dt)

func _derive() -> void:
	sun_elevation_deg = 65.0 * -cos(day_phase * TAU)
	var az := deg_to_rad(-30.0 + (day_phase - 0.7) * 260.0)
	var el := deg_to_rad(sun_elevation_deg)
	sun_dir = Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	moon_dir = Vector3(-sun_dir.x, -sun_dir.y, -sun_dir.z).normalized()
	daylight = smoothstep(-7.0, 12.0, sun_elevation_deg)
	night = 1.0 - smoothstep(-14.0, -3.0, sun_elevation_deg)

## Wind as a unit vector in world (x, z): where the wind blows toward.
func wind_vector() -> Vector2:
	return Vector2(cos(wind_angle), sin(wind_angle))

func wind_speed_ms() -> float:
	return wind_ms

func _regime_center(i: int) -> float:
	return 0.5 * (float(WIND_REGIMES[i][1]) + float(WIND_REGIMES[i][2]))

func _init_wind() -> void:
	if _force_regime_name != "":
		_wind_frozen = true
		if _force_regime_name == "storm":
			_wind_from = STORM_WIND_MS
			set_weather("storm", true)
			_hold = true
		else:
			for i in WIND_REGIMES.size():
				if WIND_REGIMES[i][0] == _force_regime_name:
					wind_regime = i
			_wind_from = _regime_center(wind_regime)
	else:
		wind_regime = 3
		_wind_from = _regime_center(wind_regime) # 11 m/s, as before
	if _force_ms >= 0.0:
		_wind_from = _force_ms
		for i in WIND_REGIMES.size():
			if _force_ms >= float(WIND_REGIMES[i][1]) - 0.4:
				wind_regime = i
	wind_regime_name = WIND_REGIMES[wind_regime][0] if _force_regime_name != "storm" else "storm"
	_wind_to = _wind_from
	wind_ms = _wind_from
	wind_strength = clampf(wind_ms / 28.0, 0.02, 1.0)
	_wind_ramp_t = 1.0e9
	_wind_timer = 0.0
	_wind_hold = _wind_rng.randf_range(float(WIND_REGIMES[wind_regime][3]), float(WIND_REGIMES[wind_regime][4]))

## Visit probability of each regime: share of the time / mean hold, so the TIME shares come out as WIND_REGIMES says.
func _regime_weight(i: int) -> float:
	var r: Array = WIND_REGIMES[i]
	return float(r[5]) / (90.0 + 0.5 * (float(r[3]) + float(r[4]))) # 90 s = mean ramp

## Metropolis-Hastings walk over the neighbouring regimes (proposals are always valid ones: an edge regime has one neighbour),
## stationary in visit rate so the TIME shares come out as WIND_REGIMES says.
func _next_regime(cur: int, after_storm := false) -> int:
	if after_storm and _wind_rng.randf() < 0.4:
		return _wind_rng.randi_range(0, 1) # the lull behind a front
	var last := WIND_REGIMES.size() - 1
	var j := cur + (1 if (cur == 0 or (cur < last and _wind_rng.randf() < 0.5)) else -1)
	var n_cur := 1 if (cur == 0 or cur == last) else 2
	var n_j := 1 if (j == 0 or j == last) else 2
	var accept := (_regime_weight(j) * (1.0 / float(n_j))) / (_regime_weight(cur) * (1.0 / float(n_cur)))
	return j if _wind_rng.randf() < minf(1.0, accept) else cur

func _begin_ramp(to_regime: int, after_storm := false) -> void:
	var r: Array = WIND_REGIMES[to_regime]
	wind_regime = to_regime
	wind_regime_name = r[0]
	_wind_from = wind_ms
	_wind_to = _wind_rng.randf_range(float(r[1]), float(r[2]))
	_wind_ramp_t = 0.0
	_wind_ramp_dur = _wind_rng.randf_range(60.0, 120.0) # smooth: wind never jumps
	_wind_hold = _wind_ramp_dur + _wind_rng.randf_range(float(r[3]), float(r[4]))
	_wind_timer = 0.0
	if _wind_log:
		print("[wind] regime ", wind_regime_name, " target ", snappedf(_wind_to, 0.1), " m/s ramp ", int(_wind_ramp_dur), " s hold ", int(_wind_hold), " s")

func _update_wind(dt: float, n2: float) -> void:
	var base := _wind_to
	if not _wind_frozen:
		_wind_timer += dt
		if _wind_timer >= _wind_hold:
			_begin_ramp(_next_regime(wind_regime, _storm_cooldown > 0.0))
			_storm_cooldown = 0.0
	if _wind_ramp_t < _wind_ramp_dur:
		_wind_ramp_t += dt
		base = lerpf(_wind_from, _wind_to, smoothstep(0.0, 1.0, clampf(_wind_ramp_t / _wind_ramp_dur, 0.0, 1.0)))
	else:
		base = _wind_to
	# Slow +-8 % drift inside the regime (not for forced/held regimes: tests want the exact number).
	var drift := 1.0 if _wind_frozen else 1.0 + 0.08 * n2 * 2.0
	var calm_ms := base * drift
	# Storm: the weather plan raises storm 0..1; the wind follows it up and falls back to the regime afterwards.
	var sk := smoothstep(0.05, 0.7, storm)
	wind_ms = lerpf(calm_ms, maxf(calm_ms, STORM_WIND_MS), sk)
	if _was_stormy_wind and storm < 0.05:
		_storm_cooldown = 1.0
	_was_stormy_wind = storm >= 0.05
	if _wind_frozen and _force_regime_name == "storm":
		wind_ms = STORM_WIND_MS
	wind_strength = clampf(wind_ms / 28.0, 0.02, 1.0)

## Rainbow / fog bank / wetness / bioluminescence: slow envelopes derived from the clocks above.
func _derive_atmosphere(dt: float) -> void:
	var rain := smoothstep(0.35, 0.8, storm)
	wetness = maxf(wetness - dt / 120.0, rain)
	if rain > deck_wetness:
		deck_wetness = minf(rain, deck_wetness + dt / 25.0)
	else:
		deck_wetness = maxf(0.0, deck_wetness - dt / 150.0 * (0.4 + 1.2 * daylight * (1.0 - 0.6 * cloud) + 0.8 * wind_strength))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--deck-wet="):
			deck_wetness = float(a.get_slice("=", 1))
	var stormy := storm > 0.6
	if _was_stormy and storm < 0.45:
		storm_cleared.emit()
	_was_stormy = stormy or (_was_stormy and storm >= 0.45)
	var sun_ok := smoothstep(4.0, 12.0, sun_elevation_deg) * (1.0 - smoothstep(38.0, 46.0, sun_elevation_deg))
	var after := clampf((wetness - rain) * 1.6, 0.0, 1.0) * (1.0 - smoothstep(0.55, 0.9, cloud))
	rainbow = lerpf(rainbow, after * sun_ok * smoothstep(0.55, 0.3, storm), 1.0 - exp(-dt / 8.0))
	if "--rainbow-test" in OS.get_cmdline_user_args():
		rainbow = sun_ok
	var dawn := exp(-pow((day_phase - 0.27) / 0.045, 2.0))
	fog_bank = dawn * (1.0 - 0.7 * cloud) * (1.0 - storm)
	biolum = night * (1.0 - 0.8 * cloud) * (1.0 - storm) * (0.35 + 0.65 * (1.0 - sea_state))
