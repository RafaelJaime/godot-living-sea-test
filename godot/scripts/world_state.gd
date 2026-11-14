extends Node
## Autonomous world clocks: day/night cycle, weather cycle (clear -> cloudy -> storm -> cloudy -> clear),
## slowly drifting wind. Everything else (sky, fog, lights, rain, ocean sea_state, Canto, autopilot) reads from here.
## Capture/test args: --timescale=N (speeds up the internal clocks only), --start-phase=0..1 (0 midnight, .5 noon),
## --weather=clear|cloudy|storm (start there and hold), --sea=0..1 (force sea_state).

const WEATHER_PLAN := [ # [name, duration s at timescale 1]
	["clear", 150.0], ["cloudy", 70.0], ["storm", 110.0], ["cloudy", 60.0],
]
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
var wind_strength := 0.3 ## 0..1
var sea_state := 0.25
var override_sea := -1.0
var override_wind_deg := 9999.0 ## test aid (--wind=deg): fixed wind direction
var flash := 0.0 ## lightning flash 0..1 (written by weather_fx.gd)
var cloud_scroll := Vector2.ZERO

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

func _ready() -> void:
	process_priority = -90
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
			override_wind_deg = float(a.get_slice("=", 1))
		elif a.begins_with("--engine-scale="):
			Engine.time_scale = float(a.get_slice("=", 1))
		elif a == "--no-day":
			day_enabled = false
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
	wind_strength = clampf(0.18 + 0.5 * cloud + 0.3 * storm + 0.1 * n2, 0.05, 1.0)
	cloud_scroll += Vector2(cos(wind_angle), sin(wind_angle)) * (0.004 + 0.012 * wind_strength) * dt
	sea_state = override_sea if override_sea >= 0.0 else clampf(0.16 + 0.22 * cloud + 0.52 * storm + 0.06 * wind_strength, 0.0, 1.0)
	Waves.sea_state = sea_state
	flash = maxf(flash - delta * 5.0, 0.0)
	_derive()

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
	return 3.0 + 17.0 * wind_strength
