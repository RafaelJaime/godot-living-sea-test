extends Node
## Autoload "Quality": the ONE place that decides how heavy the scene is. Other systems read the numbers below
## (ocean rings / FFT size / cascades, wake resolution, cloth work, particle counts) and the global render settings
## (render scale, MSAA, fps cap, shadows, glow) are applied here.
##   godot --path godot -- --quality=dev     (agents / tests: fast, ugly)
##   godot --path godot                      (final: everything on; ProjectSettings "game/quality" can override the default)
## Systems that create their resources in _ready() simply read `Quality.<field>` (this autoload loads first); things that
## live in the scene tree (environment, lights) are patched once after the scene is up (see _apply_scene).

enum Level { DEV, FINAL }

var level: Level = Level.DEV
var name_: String = "dev"

# --- read by other scripts ---
var ocean_levels := 11
var fft_size := 512
var ocean_cascades := 3
var normal_mips := 5                   ## mip levels of the ocean normal/foam map (3 at dev: the 128 px map has only 3 useful levels)
var wake_resolution := 1024
var wake_updates_per_second := 0.0     ## 0 = every frame
var cloth_scale := 1.0                 ## multiplies cloth substeps / iterations
var particle_scale := 1.0              ## multiplies rain / spray / mist particle counts
var shadows := true
var ssao := false                      ## screen-space AO (applied by sky.gd, which owns the Environment)
var ssao_quality := 0                  ## RenderingServer SSAO quality 0 (very low) .. 3 (high)
var ssil := false                      ## screen-space indirect light (about +1.1 ms at 1080p on M5: opt-in)
var ssr := false                       ## screen-space reflections (applied by sky.gd, which owns the Environment)
var ssr_steps := 64                    ## SSR max steps
var sky_radiance := 64                 ## sky reflection cube size: 64 (dev) or 256 (final)
var glow := true
var render_scale := 1.0
var msaa := 2                          ## 0 off, 1 = 2x, 2 = 4x, 3 = 8x
var taa := false                       ## dev: no MSAA at 0.6 render scale breaks sub-pixel rigging into dots; TAA keeps it continuous
var max_fps := 0                       ## 0 = uncapped (vsync decides)
var fft_updates_per_second := 40.0
var readback_hz := 20.0

func _init() -> void:
	var want := str(ProjectSettings.get_setting("game/quality", "dev"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			want = a.get_slice("=", 1)
	set_level(want)
	for a in OS.get_cmdline_user_args():
		if a == "--no-ssr": # test aid: SSR off at any preset (A/B for the cost)
			ssr = false
		elif a == "--ssr":
			ssr = true
		elif a.begins_with("--msaa="): # test aid: override the MSAA level (0 off .. 3 = 8x)
			msaa = int(a.get_slice("=", 1))
		elif a.begins_with("--normal-mips="): # test aid: 1 = no mips (A/B), otherwise the level count
			normal_mips = maxi(1, int(a.get_slice("=", 1)))

func set_level(n: String) -> void:
	if n != "dev" and n != "final":
		push_warning("[quality] unknown preset '" + n + "', falling back to dev")
		n = "dev"
	name_ = n
	if n == "dev":
		level = Level.DEV
		ocean_levels = 6
		fft_size = 128
		ocean_cascades = 2
		normal_mips = 3
		wake_resolution = 256
		wake_updates_per_second = 20.0
		cloth_scale = 0.5
		particle_scale = 0.25
		shadows = false
		ssao = false
		ssil = false
		ssr = false
		sky_radiance = 64
		glow = false
		render_scale = 0.6
		msaa = 0
		taa = true
		max_fps = 30
		fft_updates_per_second = 20.0
		readback_hz = 10.0
	else:
		level = Level.FINAL
		ocean_levels = 11
		fft_size = 512
		ocean_cascades = 3
		normal_mips = 5
		wake_resolution = 1024
		wake_updates_per_second = 0.0
		cloth_scale = 1.0
		particle_scale = 1.0
		shadows = true
		ssao = true
		ssao_quality = 0
		ssil = false
		ssr = true
		ssr_steps = 64
		sky_radiance = 256
		glow = true
		render_scale = 1.0
		msaa = 2
		max_fps = 0
		fft_updates_per_second = 40.0
		readback_hz = 20.0

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--uncap"): # benchmarking: no fps cap, no vsync
		max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	var vp := get_viewport()
	vp.msaa_3d = msaa as Viewport.MSAA
	vp.use_taa = taa
	if render_scale < 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = render_scale
	print("[quality] ", name_, ": rings=", ocean_levels, " fft=", fft_size, " cascades=", ocean_cascades, " scale=", render_scale,
		" msaa=", msaa, " fps_cap=", max_fps, " shadows=", shadows, " glow=", glow)
	print("[quality] ", name_, ": SSR=", ssr, " (", ssr_steps, " steps) sky_radiance=", sky_radiance, "; SSAO=", ssao, " (quality ", ssao_quality, ") SSIL=", ssil, " (applied by sky.gd)")
	_apply_scene.call_deferred()

func _apply_scene() -> void:
	# The sky creates its Environment in _ready(); patch it (and the lights) after a couple of frames.
	await get_tree().process_frame
	await get_tree().process_frame
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env := (n as WorldEnvironment).environment
		if env:
			env.glow_enabled = glow and env.glow_enabled
	if not shadows:
		for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).shadow_enabled = false
