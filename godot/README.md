# Pirate Ship Wallpaper (Godot 4.7)

Infinite, animated living wallpaper: a galleon sails forever through procedural Gerstner waves with
four crew members aboard and low-poly tropical islands drifting by. No gameplay.

## Run
```
godot --path /Users/rafael/Documents/workspace/autonomo/el-terraria-blender/godot
```
First time (or after dropping new GLBs): `godot --headless --path <project> --import`
(not strictly needed: GLBs without an import file are parsed at runtime as a fallback).

Screenshots + quit: `godot --path <project> -- --capture` writes `_shots/shot_01..07.png`.

## Controls
- `C` toggle free-fly debug camera (WASD, Q/E down/up, mouse look, Shift fast, Esc frees the mouse)
- `1`-`5` jump to camera shots (3/4 bow, side low, high wide, captain, deck crew)
- Auto camera blends to the next shot every 20 s with drift and handheld noise.

## Where to drop final assets
- Ship: `res://assets/ship/barco.glb`
- Crew: `res://assets/characters/{papi_fuego,papi_diagnostica,el_salchipapa,don_omar}.glb`
If the file exists it is used, otherwise `res://assets/placeholder/*.glb` (exported from the Blender blockout
by `../export_placeholders.py`).

Ship normalization (`scripts/ship_loader.gd`): AABB -> long axis -> bow detected as the narrower end -> rotated so the
bow points to -Z -> scaled to `target_length` (22 m) -> waterline at 35% of an estimated hull depth.
Fix a wrong guess with `ship_yaw_offset_deg`, `force_bow_sign`, `ship_scale_override`, `waterline_offset`, `hull_depth_ratio`.
Crew: height normalized per slot (`target_height`), first/"idle" animation looped with a random start.

## Tweaking (all exports, editable in the editor)
- Crew markers: `Ship/Pivot/CrewMarkers/<name>`: `norm_u` (0 stern .. 1 bow), `norm_v` (-1 port .. 1 starboard),
  `deck_height_frac`, `snap_to_deck` (raycast, tolerance `snap_tolerance`), `facing_deg`, `target_height`,
  `final_model_yaw_deg` (model's native front), `barrel_height`.
- Waves: ONE place, `scripts/waves.gd` (`wave_defs`, `sea_state`); pushed to the shader and mirrored on CPU (`height_at`).
- Ship motion: `Ship` -> `speed`, `heave/pitch/roll gains`, `wind_heel_deg`, `yaw_wander_deg`.
- Sky: `Sky` -> `sun_azimuth_deg`, `sun_elevation_deg`, `fog_density`, `day_cycle` (off by default).
- Islands: `Islands` -> `island_count`, lateral/ahead distances, `seed_base`.

## Infinite sailing
The ship moves along -Z; every 1024 m everything in group `rebase` is shifted back to the origin and the shift is folded into the
wave phase in double precision (`Waves.add_world_shift`), so there is no jitter after hours. Test: `-- --rebase-test=50`.

## Running automated captures / tests without stealing focus (macOS)
```
open -g -n -W -a /Applications/Godot.app --args --path <project> --position 20,40 --resolution 1280x720 \
     --log-file <project>/_shots/godot.log -- --capture
```
`-g` keeps the current app frontmost, `-W` waits for exit; output goes to the log file. In `--capture` and `--jitter-test`
modes `capture.gd` also sets `WINDOW_FLAG_NO_FOCUS`. Other flags: `--jitter-test [--jitter-shot=N]`, `--rebase-test=<m>`, `--debug-deck`.
Ocean: `Waves.sea_state` (0 calm .. 1 storm); FFT pipeline vendored in `addons/ocean_fft` (MIT, see its README).

## World state / autonomy (T4)
`WorldState` autoload runs day/night (720 s per day), weather (clear -> cloudy -> storm -> cloudy), wind drift and `sea_state`.
The autopilot (`Ship/Autopilot`) sails between islands, tacks when the waypoint is upwind and drives `Ship.rudder_cmd`; `Ship.rudder` (-1..1) is the shared steering signal.
Test args: `--timescale=N` (day/weather clocks only), `--start-phase=0..1` (0 midnight, .5 noon), `--weather=clear|cloudy|storm` (hold),
`--sea=0..1`, `--wind=<deg>` (fixed wind direction), `--no-day`, `--engine-scale=N`, `--lightning`, `--plan=world|sky`, `--autopilot-log=<secs>`.

## Integration API for NPCs (ship lights)
Autoload `ShipLights` (scripts/ship_lights.gd); lanterns are `ShipLantern` nodes created under `Ship/Pivot/Lights` (table in
`scripts/ship_lights_builder.gd`: stern_port, stern_starboard, helm, waist, forecastle, cabin). They are OFF by default.
- `ShipLights.get_lanterns()` -> `[{id, position (world), interaction_point (world deck point where the NPC stands), facing_deg (yaw of the stance, 0 = bow, +90 = port), lit, is_window}]`
- `ShipLights.light(id)` / `ShipLights.extinguish(id)` / `ShipLights.is_lit(id)`; ignition takes ~2.4 s (flame grows, light fades in), extinguish ~1.2 s.
- Signals: `lighting_needed(ids)` when `WorldState.daylight` drops below 0.30 (dusk), `extinguish_suggested(ids)` when it rises above 0.50 (dawn), `lantern_changed(id, lit)`.
- Test aid: `--auto-light[=delay_s]` lights every lantern (staggered) that long after dusk; use `--start-phase=0.0 --no-day` for a night capture.
Other hooks for NPC code: ship deck query = raycast against the ship meshes (see crew_manager.gd), `Ship.roll/pitch/roll_rate/pitch_rate/yaw/yaw_rate/rudder/forward/current_speed`, `Ship.linear_velocity` (RigidBody3D), `WorldState` (daylight, night, storm, cloud, wind_vector(), wind_speed_ms(), sun_elevation_deg).

## Wind + cloth (R4 / T9 / T9b)
One wind model for everything that reacts to air.
- `WindField` (autoload, `scripts/wind_field.gd`): `sample(pos, t) -> Vector3` true wind (world, m/s) = WorldState mean wind x
  boundary-layer profile x **travelling gusts** (noise field advected downwind at 0.8 x wind speed; survives world rebase) +
  turbulence; `apparent(pos, point_velocity)`; `gust_factor(pos)`. Test: `--wind-ms=N` forces the mean speed, `--gust-amp=X`.
- `ClothSolver` (`scripts/cloth_solver.gd`): XPBD cloth (stretch / shear / bending constraints, hard + soft pins, capsule colliders,
  real gravity, two-sided per-triangle aerodynamics from the apparent wind, 2 substeps x 8 iterations). All cloths are stepped in
  parallel on the WorkerThreadPool by `WindField` (priority 100, after the owners wrote their pin targets). `--no-cloth` skips it.
- Flags (`flag.gd`, 16x10): tied ONLY at the two hoist corners to the posed staff. Sails (`pinnace_rig.gd` + `sail_cloth.gd`,
  12x10 per sail, `sail_cloth.gdshader` displaces the real sail mesh by the simulated grid): head on the yard, clews = soft pins (sheets).
- **Integration API for the rigid-body ship** (all in ship/pivot space): `get_tree().get_first_node_in_group("sail_rig")`
  `.get_sail_forces()` -> per sail `{name, force (N), point (centre of effort, m), area, pressure (Pa), tension (N), gust, state, brace_deg}`;
  `.total_sail_force()` -> `{force, point}`. `flag.debug_info()` gives tension / pressure / gust for the flags.
- QA: `-- --cloth-demo=full|calm|moderate|storm|beam|gust|gusthead [--no-day --start-phase=0.6 --weather=clear]` drives calm -> 12 m/s ->
  26 m/s -> wind from the beam/bow (backed sails) -> travelling gust (following / head wind), saves `_shots/cloth_*.png` and prints `[cloth]`/`[gust]` logs.

## Quality presets (autoload `Quality`, scripts/quality.gd)
`-- --quality=dev|final` (DEFAULT `dev`, so any run without the flag is light; the shipped wallpaper launch passes `--quality=final`; unknown values warn and fall back to dev; ProjectSetting `game/quality` changes the default). Agents/tests use dev unless a step
validates final visuals. `--uncap` removes the fps cap and vsync for benchmarking.
| | dev | final |
|---|---|---|
| render scale / MSAA / fps cap | 0.6 FSR / off / 30 | 1.0 / 4x / vsync |
| directional shadows, glow | off | on |
| ocean rings / FFT / cascades | 6 / 128 / 2 | 11 / 512 / 3 |
| wake field | 256^2 at 20 Hz | 1024^2 every frame |
| cloth substeps+iterations | x0.5 | x1 |
| particles (rain, spray) | x0.25 | x1 |
Other systems read `Quality.<field>` (ocean_levels, fft_size, ocean_cascades, wake_resolution, cloth_scale, particle_scale, shadows, glow,
render_scale, msaa, max_fps, readback_hz); it loads before everything else, so `_ready()` code can use it directly. The environment and lights
are patched two frames after start (glow, SSR/SSAO off, shadows off in dev). New heavy features (SSR, volumetric clouds, higher FFT...) should hang
off a field here: off in dev, on in final.
## Sky / atmosphere (R5)
- Clouds: Sunshine Clouds 2 (`scripts/ambient/sc2_clouds.gd`, MIT addon in `addons/SunshineClouds2`). Quarter-res march, 100 steps, TAA replaces MSAA
  (Metal cannot write image2DMS). `--no-sc2` falls back to the sky shader fbm layer. Tests: `--sc2-res=N --sc2-steps=N --perf` (avg frame time).
- Global shader parameters (registered by WorldState, set every frame by sky.gd; ocean shaders may declare them as `global uniform`):
  `sky_horizon_color`, `sky_zenith_color`, `sky_fog_color` (vec3), `sky_sun_color` (vec3, colour x energy), `sky_sun_dir`, `sky_fog_density`,
  `sky_storminess`, `sky_night`, `sky_rain`, `sky_biolum` (float; night bioluminescence amount for the wake/ocean).
- WorldState additions: `rainbow`, `fog_bank`, `biolum`, `wetness`, signals `thunder(delay_s, intensity)` and `storm_cleared`. Test aids: `--rainbow-test`, `--no-autoexp`.
- Clouds are gated by the quality preset: SC2 runs with `--quality=final` (or `--sc2` in dev); dev uses the sky shader fbm layer.

## Ambient life (R8)
`scripts/ambient/ambient_life.gd` (node `AmbientLife`): dolphin pods at the bow (day, calm), distant whale spouts, a ship passing on the horizon (lanterns lit at night/storm),
flotsam and seaweed on the swell (height + slope from `Waves.height_at`). `scripts/gulls.gd`: gull + albatross boids around the masts (diurnal).
`scripts/ambient/lighthouse_beam.gd`: rotating beam on island lighthouses (night/storm). All world-space and rebase-safe (group `rebase`).
Test aids: `--ambient-now` (events every few seconds), `--no-ambient`, `--no-birds`. Bioluminescence hook for the ocean: `WorldState.biolum` and the global shader parameter `sky_biolum` (0..1, night only).
