extends Node
## Volumetric clouds (Sunshine Clouds 2, MIT) attached to the Sky WorldEnvironment as a CompositorEffect.
## Driven by WorldState: coverage, density, layer height and colours follow weather and time of day; the sun AND the moon
## light the clouds (so night clouds are only moonlit) and lightning lights them from inside.
## Enabled by `--quality=final` (or `--sc2` in dev); `--no-sc2` disables it (the sky shader's fbm layer then draws the clouds).
##
## Metal note: SC2's MSAA post pass writes an image2DMS, which the Metal driver rejects, so this node switches the viewport
## from MSAA to TAA while the clouds are on. Cost (Apple M5, 1920x1080, scene ~14.5 ms): see odd/tasks/living-sea-wallpaper.md R5.
## Test aids: `--sc2-res=0..3` (0 native, 1 half, 2 quarter), `--sc2-steps=N`, `--sc2-light-steps=N`.

var effect: Resource
var driver: Node
var _sky: WorldEnvironment

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Heavy feature: off in the dev quality preset (the sky shader's fbm layer draws the clouds), on in final or with `--sc2`.
	if "--no-sc2" in args or (Quality.level != Quality.Level.FINAL and not "--sc2" in args):
		queue_free()
		return
	_sky = get_node("../Sky") as WorldEnvironment
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.use_taa = true
	effect = (load("res://assets/sky/sc2_clouds.tres") as Resource).duplicate()
	# Budget defaults: quarter-resolution march + TAA, 100 steps, short light march.
	effect.set("resolution_scale", 2)
	effect.set("max_step_count", 100.0)
	effect.set("max_lighting_steps", 12.0)
	effect.set("cloud_floor", 1200.0)
	effect.set("cloud_ceiling", 6500.0)
	var light_steps := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sc2-res="):
			effect.set("resolution_scale", int(a.get_slice("=", 1)))
		elif a.begins_with("--sc2-steps="):
			effect.set("max_step_count", float(a.get_slice("=", 1)))
		elif a.begins_with("--sc2-light-steps="):
			light_steps = int(a.get_slice("=", 1))
			effect.set("max_lighting_steps", float(light_steps))
	var comp := Compositor.new()
	comp.compositor_effects = [effect]
	_sky.compositor = comp
	driver = (load("res://addons/SunshineClouds2/SunshineCloudsDriver.gd") as GDScript).new()
	driver.set("clouds_resource", effect)
	var lights: Array[DirectionalLight3D] = [get_node("../Sun") as DirectionalLight3D]
	var steps: Array[int] = [light_steps]
	var moon := get_node_or_null("../Moon") as DirectionalLight3D
	if moon:
		lights.append(moon)
		steps.append(maxi(light_steps / 2, 4))
	driver.set("tracked_directional_lights", lights)
	driver.set("tracked_directional_light_shadow_steps", steps)
	driver.set("update_continuously", true)
	add_child(driver)

func _process(_delta: float) -> void:
	if effect == null:
		return
	var w := WorldState
	var sky := _sky as Node
	var k: float = w.daylight
	var storm: float = w.storm
	# A failed shader compile disables the effect: fall back to the sky shader's own cloud layer.
	var on: bool = effect.get("enabled")
	sky.set("volumetric_clouds", on)
	# Coverage: sparse cumulus when clear, solid deck in storms. Storm decks sit lower and thicker.
	effect.set("clouds_coverage", clampf(lerpf(0.6, 0.9, w.cloud) + 0.08 * storm, 0.0, 1.0))
	effect.set("clouds_density", lerpf(0.9, 3.2, storm))
	effect.set("cloud_floor", lerpf(1200.0, 600.0, storm))
	effect.set("cloud_ceiling", lerpf(6500.0, 5200.0, storm))
	# Colours: white-blue ambient by day, near-black at night, grey in storms, plus an inner glow while lightning flashes.
	var amb := Color(0.02, 0.03, 0.06).lerp(Color(1, 1, 1), k).lerp(Color(0.45, 0.48, 0.55), storm * 0.6)
	amb = amb * (1.0 - 0.35 * storm) + Color(1.0, 1.05, 1.4) * (w.flash * 7.0)
	amb.a = 1.0
	effect.set("cloud_ambient_color", amb)
	var hor: Color = sky.get("horizon_color")
	effect.set("atmosphere_color", hor)
	var ao := Color(0.55, 0.38, 0.32, 0.4).lerp(Color(0.18, 0.2, 0.26, 0.6), storm) * (0.15 + 0.85 * k)
	ao.a = 0.45 + 0.15 * storm
	effect.set("ambient_occlusion_color", ao)
	var sc := w.cloud_scroll
	driver.set("wind_direction", Vector3(w.wind_vector().x, 0.0, w.wind_vector().y) * (0.4 + 0.6 * w.wind_strength))
	driver.set("origin_offset", Vector3(sc.x, 0.0, sc.y) * 0.0)
