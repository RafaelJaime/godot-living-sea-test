# Pirate Ship Wallpaper (Godot 4.7)

Infinite, animated living wallpaper: a pinnace (Poly Haven / Sketchfab "Pirate ship (Rigged)", see `../ATTRIBUTION.md`) sails forever through an FFT ocean
(GodotOceanWaves, vendored in `addons/ocean_fft`) with four crew members aboard and low-poly tropical islands drifting by. No gameplay.
The shipped wallpaper launch passes `--quality=final`; every run without the flag is the light `dev` preset (see Quality presets).

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
- Ship: `res://assets/ship/pinnace/barco_pinnace.glb` (`ShipLoader.model_path`; modelled in real metres, `ship_scale_override = 1`; `res://assets/ship/barco.glb` is the placeholder fallback)
- Crew: `res://assets/characters/{papi_fuego,papi_diagnostica,el_salchipapa,don_omar}.glb`
If the file exists it is used, otherwise `res://assets/placeholder/*.glb` (exported from the Blender blockout
by `../export_placeholders.py`).

Ship normalization (`scripts/ship_loader.gd`): AABB -> long axis -> bow detected as the narrower end -> rotated so the
bow points to -Z -> scaled by `ship_scale_override` (1 = real metres; `target_length` 22 m is used only when it is 0) -> waterline at 35% of an estimated hull depth.
Fix a wrong guess with `ship_yaw_offset_deg`, `force_bow_sign`, `ship_scale_override`, `waterline_offset`, `hull_depth_ratio`.
Crew: height normalized per slot (`target_height`), first/"idle" animation looped with a random start.

## Tweaking (all exports, editable in the editor)
- Crew markers: `Ship/Pivot/CrewMarkers/<name>`: `norm_u` (0 stern .. 1 bow), `norm_v` (-1 port .. 1 starboard),
  `deck_height_frac`, `snap_to_deck` (raycast, tolerance `snap_tolerance`), `facing_deg`, `target_height`,
  `final_model_yaw_deg` (model's native front), `barrel_height`.
- Waves: the ocean is an FFT simulation (`scripts/ocean.gd` + `addons/ocean_fft`, three cascades, `Waves.sea_state` 0..1 sets wind/fetch/swell); `scripts/waves.gd` (autoload `Waves`) reads the displacement maps back so the CPU mirrors the surface (`Waves.height_at`).
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
`--sea=0..1`, `--wind=<deg>` (fixed wind direction) or `--wind=calm|light|moderate|fresh|strong|storm` (hold that wind regime), `--wind-ms=N` (exact mean speed, held), `--wind-seed=N`, `--wind-hold` (no regime changes), `--wind-log` (print regime changes), `--no-day`, `--engine-scale=N`, `--lightning`, `--plan=world|sky`, `--autopilot-log=<secs>`.

## Integration API for NPCs (ship lights)
Autoload `ShipLights` (scripts/ship_lights.gd). Lights are anchored on the model's REAL parts, nothing is added to the hull but light and
additive glow (`scripts/ship_lights_builder.gd` under `Ship/Pivot/Lights`, `ShipLantern` nodes). They are OFF by default. Three ids only:
- `stern_port`, `stern_starboard`: the two caged lanterns on the stern posts (mesh `geo_ship_pinnace_details`). Anchor = centroid of the cage vertices
  (baked, pivot space); warm OmniLight with ignition + flicker, glow = additive shell over the dark panes + soft halo (no glb change).
- `cabin_windows` (`is_window`): the eight glazed stern windows (mesh `geo_ship_pinnace_aft`); additive glow panes over the glass + a light behind the transom.
- `ShipLights.get_lanterns()` -> `[{id, position (world), interaction_point (world deck point where the NPC stands), facing_deg (yaw of the stance, 0 = bow, +90 = port), lit, is_window, local_position (pivot), stand_local (pivot)}]`.
  Lamp stance = deck point ~0.8 m inboard/forward of the lantern (downward ray against temporary deck colliders, ~7.46 m); cabin stance = stern-rail side of the poop deck (no cabin door in the model).
- `ShipLights.light(id)` / `ShipLights.extinguish(id)` / `ShipLights.is_lit(id)`; ignition takes ~2.4 s (glow + light fade in), extinguish ~1.2 s.
- Signals: `lighting_needed(ids)` when `WorldState.daylight` drops below 0.30 (dusk), `extinguish_suggested(ids)` when it rises above 0.50 (dawn), `lantern_changed(id, lit)`.
- Test aids: `--auto-light[=delay_s]` lights every light (staggered) that long after dusk; use `--start-phase=0.0 --no-day` for a night capture. `--debug-lights` logs stances, `lighting_needed`, `lantern_changed`. `--check-lamps` re-measures the posed cage centroid every second (`[lights] lamp-drift`); the hull is skinned to one bone that never moves relative to the pivot, so anchors are plain children of the pivot (max deviation 0.0 cm over a 125 s storm, anchor-to-centroid 0 cm after baking; evidence in `odd/evidence/lights/`). Retune the tables in the builder if the model changes.
Other hooks for NPC code: ship deck query = raycast against the ship meshes (see crew_manager.gd), `Ship.roll/pitch/roll_rate/pitch_rate/yaw/yaw_rate/rudder/forward/current_speed`, `Ship.linear_velocity` (RigidBody3D), `WorldState` (daylight, night, storm, cloud, wind_vector(), wind_speed_ms(), sun_elevation_deg).

## Wind + cloth (R4 / T9 / T9b)
One wind model for everything that reacts to air.
- `WindField` (autoload, `scripts/wind_field.gd`): `sample(pos, t) -> Vector3` true wind (world, m/s) = WorldState mean wind x
  boundary-layer profile x **travelling gusts** (noise field advected downwind at 0.8 x wind speed; survives world rebase) +
  turbulence; `apparent(pos, point_velocity)`; `gust_factor(pos)`; `gust_texture()` / `gust_window()` / `gust_amp()` feed the ocean's cat's paws (global shader params `gust_tex`, `gust_win` = origin x, origin z, size x, size z in metres, `gust_amp`; 64x116 texels over ~1 km refreshed every 0.25 s, window slides with the advection; `--no-gust-tex` stops the refresh, `--gust-tex-test` checks texels against the noise and dumps PNGs). Cat's paws on the water: `--catpaw=<gain>` (default 1.5, 0 = off), `--water-debug=7` shows the mask. Mean speed comes from `WorldState.wind_ms`: a regime machine (calm 0-2 m/s ~12 %, light 2-5 ~28 %, moderate 5-9 ~30 %, fresh 9-14 ~16 %, strong 14-20 ~6 %, storm from the weather plan ~7 %) with 60-120 s smooth transitions; it starts in fresh (~11 m/s, the sail calibration). Compare runs with `--wind-hold` or `--wind=fresh`. Test: `--wind-ms=N` forces the mean speed, `--gust-amp=X`.
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
| wake field | 256^2 at 30 Hz | 1024^2 at 30 Hz |
| cloth substeps+iterations | x0.5 | x1 |
| ocean normal mips | 3 | 5 |
| sky reflection cube (`sky_radiance`) | 64 | 256 |
| SSAO / SSIL / SSR | off / off / off | on (q0) / off / off |
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
- WorldState additions: `rainbow`, `fog_bank`, `biolum`, `wetness`, signals `thunder(delay_s, intensity)` and `storm_cleared`. Test aids: `--rainbow-test`.
- Clouds are gated by the quality preset: SC2 runs with `--quality=final` (or `--sc2` in dev); dev uses the sky shader fbm layer.
- Exposure is deterministic (no auto-exposure): `Sky.exposure` = `Sky._exposure_for(sun_elevation, cloud, storm)` written to `CameraAttributesPractical.exposure_multiplier`
  (0.82 at a clear noon, 1.0 at dusk/night, x0.86 in storms; lightning never feeds it), so captures reproduce and a `--timescale` run cannot pump.
- SSAO (half-res) is applied by `sky.gd` from `Quality` in `final` only (`Quality.ssao`, `ssao_quality`, `ssil`; final: SSAO q0 only, SSIL opt-in with `--ao=both`; dev: off; logged as `[sky] <preset>: ssao=.. ssil=..`); ship shadows are 4 cascades over 160 m with blur 1.3
  (dev has no shadows). A/B aids: `--no-ao`, `--no-shadows`.
- Storms: fog density x7, saturation 1.08 -> 0.78, exposure x0.86, rain streaks dim with daylight; rain particles = 7000 x `Quality.particle_scale` (logged as `[weather] rain particles cap=`).
- Probe (`scripts/sky_probe.gd`, created by `sky.gd` only with the flags): `--sky-log=<wall s> --timescale=N` logs exposure/ambient/fog/horizon and reports max rate of change, its ratio to the
  99th percentile (a tint step shows as a large ratio) and exposure direction reversals; `--storm-end-test` (storm -> clear, state 60 game seconds later vs a clear reference);
  `--sky-shots=name,phase,weather,shot[,wait[,ox,oy,oz]]+...` preset captures to `_shots/sky_<name>.png` (weather `storm_end` = storm then clear; shot `-1` = camera by the nearest island).
  Ambient: `--far-ship-test [--far-ship-angle=rad]` places the horizon ship 1.1 km ahead (its lanterns grow with distance so they read as lights).

## Ambient life (R8)
`scripts/ambient/ambient_life.gd` (node `AmbientLife`): dolphin pods at the bow (day, calm), distant whale spouts, a ship passing on the horizon (lanterns lit at night/storm),
flotsam and seaweed on the swell (height + slope from `Waves.height_at`). `scripts/gulls.gd`: gull + albatross boids around the masts (diurnal).
`scripts/ambient/lighthouse_beam.gd`: rotating beam on island lighthouses (night/storm). All world-space and rebase-safe (group `rebase`).
Test aids: `--ambient-now` (events every few seconds), `--no-ambient`, `--no-birds`. Bioluminescence hook for the ocean: `WorldState.biolum` and the global shader parameter `sky_biolum` (0..1, night only).

## Command-line flags (after `--`, e.g. `godot --path godot -- --quality=final --capture`)
Presets: `--quality=dev|final`, `--uncap`, `--ssr` / `--no-ssr`, `--msaa=N`, `--fft-size=N`, `--normal-mips=N`, `--no-ao`.
Captures and measurement: `--capture` (writes `_shots/shot_NN.png`), `--shots=i,j,k` (camera shot indices, one every 2.5 s), `--cam=x,y,z,lx,ly,lz[,fov]` (debug camera in ship space, appended as the LAST shot),
`--cam-island[=height]` (debug camera at the nearest island shore), `--cam-sweep=N[,height]` (N shots turning through 360 degrees), `--plan=regression` (4 fixed presets x 3 shots -> `_shots/reg_*.png`),
`--perf-log=<s>` (frame-time percentiles after a 5 s warm-up; `gpu_ms` reads 0.00 on the Apple GPU), `--autopilot-log=<s>` (motion summary, `[keel]` line), `--jitter-test`, `--rebase-test=<m>`, `--poll-sail-state`, `--spike-probe[=ms]` (per-priority-band frame split for CPU spikes), `--spike-log`, `--spike-ms=<ms>`, `--sync-readback` (old synchronous CPU-surface readback, for A/B).
World: `--start-phase=0..1`, `--no-day`, `--timescale=N`, `--weather=clear|cloudy|storm`, `--sea=0..1`, `--wind=<deg>|calm|light|moderate|fresh|strong|storm`, `--wind-ms=N`, `--wind-hold`, `--wind-seed=N`, `--wind-log`.
Ocean and wake: `--water-debug=1..6`, `--horizon-mix=<0..1>`, `--hull-foam=<gain>`, `--caustics=`, `--caustics-emit=`, `--caustics-scale=`, `--caustics-wide=`, `--caustics-sharp=`, `--wake-log`, `--wake-far=<m>`,
`--wake-test-speed=<k>`, `--wake-turb=<g>`, `--wake-ridge=<g>`, `--fx-log`, `--no-spray`, `--fx-test-speed=<k>`.
Ship, rig and lights: `--hold-heading=<deg>`, `--tack-test`, `--rudder-test`, `--analytic-sails`, `--settle-log`, `--log-wobble`, `--furl-log`, `--request-furl=idx:t@sec`, `--maneuver-log`, `--log-boat`, `--no-lash-load`,
`--auto-light[=s]`, `--debug-lights`, `--check-lamps`, `--debug-deck`, `--ambient-now`. Test aids that scale an input (`--wake-test-speed`, `--fx-test-speed`) do not change the real ship speed.

## Integration API (names, with kind)
| Name | Kind | Notes |
|---|---|---|
| `Ship.roll`, `Ship.pitch`, `Ship.yaw` | property (rad) | roll is starboard-up positive |
| `Ship.roll_rate`, `Ship.pitch_rate`, `Ship.yaw_rate` | property (rad/s) | |
| `Ship.rudder`, `Ship.brace` | property | rudder -1..1 (+ starboard); yard brace angle |
| `Ship.forward`, `Ship.current_speed` | property | heading as world (x, z) unit vector; speed in m/s |
| `Ship.linear_velocity` | property | RigidBody3D velocity |
| `Ship.settled` | property (bool) | false during the ~6 s start-up ramp |
| `Ship.settled_changed(is_settled)`, `Ship.wobble(intensity, kind)` | signal | |
| `WorldState.daylight`, `.night`, `.storm`, `.cloud`, `.sea_state`, `.wind_strength`, `.deck_wetness`, `.sun_elevation_deg` | property | |
| `WorldState.wind_vector()`, `.wind_speed_ms()` | getter | |
| `WorldState.thunder(delay_s, intensity)`, `.storm_cleared` | signal | |
| `Waves.height_at(x, z)` | getter | CPU mirror of the FFT surface |
| `PinnaceRig.sail_state()`, `.get_sail_forces()`, `.total_sail_force()`, `.sail_count()`, `.get_furl(idx)` | getter | |
| `PinnaceRig.request_furl(idx, t)` | method | optional crew request |
| `PinnaceRig.furl_changed(idx, value)`, `Autopilot.maneuver_started(kind, side)`, `Autopilot.maneuver_ended(kind)` | signal | |
| `LashedBoat.state()` | getter | |
| `ShipLights.get_lanterns()`, `.is_lit(id)` | getter | see the ship lights section |
| `ShipLights.light(id)`, `.extinguish(id)` | method | |
| `ShipLights.lighting_needed(ids)`, `.extinguish_suggested(ids)`, `.lantern_changed(id, lit)` | signal | |
| Deck raycast | pattern | no API: `scripts/crew_manager.gd` builds temporary trimesh colliders of the deck/aft meshes and ray-casts downward (`--debug-deck` prints the heights) |

## Changelog (ocean / ship track, newest first)
- 2026-11-15: horizon blend of far water into the sky colour (`horizon_mix`), SSS 1.8, island caustics (soft additive pattern), sky radiance and SSR keys in Quality (SSR off in both presets: no visible effect on the opaque ocean shader, +1.5 ms), spray following relative speed squared, lashing reaction on the ship and a stiffer lashing, per-sail furl and maneuver signals, wake field hardening (64-bit origin, fixed 30 Hz, Froude/heel stamps, turbulence and ridge channels, ribbon wake removed), normal mip chain, real stern lamps and windows for `ShipLights`.
- Earlier (see the sections above): FFT ocean on 11 clipmap rings with non-integer cascade tiles, physics ship with column hydrostatics and cloth sail forces, quality presets, regression/perf/jitter tooling, ocean shader split into includes.

### Ship hooks added by the roadmap (OS track)
- `Ship.settled: bool` and signal `Ship.settled_changed(is_settled)`: false during the ~6 s start-up ramp, then true (log `[ship] settled`).
- signal `Ship.wobble(intensity: float, kind: String)`, kind `roll` | `pitch` | `slam`, at most every 0.5 s, only when settled and the hull moves noticeably (calm sea: none; sea_state 0.9: several per minute). `--log-wobble` prints each emission.
- `--analytic-sails` uses the analytic flat-plate model fed by `WindField.sample` at each sail's centre; the log prints `[ship] sail path: analytic (WindField per sail)` or `cloth forces` once.
- `--settle-log` prints roll, pitch, heave and keel lift each second for the first 12 s.
- `PinnaceRig.sail_state()` -> `{furl, brace_deg, mean_pressure_pa, luffing, backed, gust}` per sail group (read-only, M1.7); `--poll-sail-state` logs it each `--autopilot-log` period.
- Changelog (M1): `settled`/`settled_changed`, `wobble`, `sail_state()` and the heel-aware hull foam were added on top of the physics ship without changing any existing Ship property or signal.

### Crew hooks on the rig and autopilot (H2)
- `PinnaceRig.sail_count()`, `get_furl(idx)`, `request_furl(idx, t)` (t clamped to 0..1, invalid index = one warning), signal `furl_changed(idx, value)`; one furl value per sail,
  `sail_power` uses the mean. A requested sail is never overridden; `request_furl(idx, 0.0)` sets it again. Storm fallback: when `storm > furl_storm` (0.86) and a sail got no request
  for `furl_grace_s` (20 s) it is furled automatically (`[rig] auto-furl fallback sail <i> furl_source=auto`); auto-furl releases when the storm subsides. Test aids: `--furl-log`, `--request-furl=idx:t@sec`.
  `sail_state()` gains `furl_per_sail`. Furled-bundle meshes still show only when the mean furl is above 0.9 (per-sail bundles are not mapped).
- `Autopilot` signals `maneuver_started(kind, side)` (`&"tack"` when the tack side flips, `&"beat"` when beating starts; side = +1/-1) and `maneuver_ended(kind)` (rudder settled, `|rudder| < 0.1` for 3 s, or 90 s timeout).
  Never nested; `maneuver_lead_s` (default 0) delays the flip to give consumers lead time. Logged with `--autopilot-log` or `--maneuver-log`.
- Changelog (H2): per-sail furl and maneuver signals are additive; existing Ship/Autopilot properties and logs are unchanged.

### Wake texture contract (M2b)
`scripts/wake_field.gd` renders a `Quality.wake_resolution`^2 (`wake_res`: 256 dev, 1024 final) RGBA16F field over a `size` = 320 m (`wake_size`) world window with a ping-pong
pair of SubViewports (`shaders/wake_update.gdshader`), at a fixed `Quality.wake_updates_per_second` (30 Hz) step. The window origin is kept as two 64-bit floats and moves in whole 8-texel steps;
`Waves.ocean.set_wake(texture, origin_local, size)` hands it to the water shader (`wake_tex`, `wake_origin`, `wake_size`). Channels: R = foam 0..1, G = centre-line turbulence 0..1 (decay ~1/s),
B = signed Kelvin ridge height in metres (clamped +-0.5, decay ~0.6/s). `foam.gdshaderinc` reads R (foam) and, through `wake_normal_terms`, G (roughness, fine normal noise, gain `wake_turb_gain`) and
B (ridge slope by central differences, gain `wake_ridge_gain`); both gains default to 1.0. Stamps scale with the Froude number of the surge speed relative to the water, the leeward side stamps stronger,
stern turbulence and arm origins follow the track. Test aids: `--wake-log`, `--wake-far=<m>`, `--wake-test-speed=<k>`, `--wake-turb=<g>`, `--wake-ridge=<g>`, `--water-debug=3..6` (channel views).
The old ribbon wake (`wake_ribbon.gd`) is gone.

### Lashed boat hooks (M5)
`LashedBoat.state()` -> `{offset_m, tilt_deg, lashing_load_n, in_cradle, left_cradle}` (read-only). The lashing spring force and torque now also act on the ship with opposite sign
(dynamic part only); test aids `--log-boat` (prints play, tilt and load every 10 s) and `--no-lash-load` (ship ignores the boat, for A/B). Changelog (M5): reaction on the ship added; the rope sag (M5.5) is not implemented.

### Ocean shader layout (godot/shaders/ocean/)
`ocean_fft.gdshader` is a shell: header, four includes and `fragment()`. Owners: `common.gdshaderinc` = all (defines, uniforms, varyings, island_distance);
`surface.gdshaderinc` = M2a/M2b (vertex displacement, bicubic normal sampling); `foam.gdshaderinc` = M2b/M1.9 (`hull_foam_term` heel-aware via `hull_inv`
and the hull cross-section table, `whitecap_term`, `wake_term`); `shading.gdshaderinc` = M2a (GGX, SSS, `light()`).
Other hooks: `PinnaceRig.sail_state()` -> furl, brace_deg, mean_pressure_pa, luffing, backed, gust (read-only; `--poll-sail-state` logs it each `--autopilot-log` period).

## Camera shots and island polish (M3.10 / M3.11)
Shot indices (hotkeys 1-7 and the 20 s cycle are unchanged; new shots are appended): 5 Canto, 7-10 crew close-ups, 12 helm, 13 violin, 17 wake,
**18 storm** (low on the bow quarter), **19 island**, **20 island close**, **21 anti-sun** (looks away from the sun: rainbow) (from the island side of the ship toward the nearest island, via `Islands.targets()`, read-only).
- `scripts/camera_clearview.gd` (`CameraClearView`): line-of-sight queries against the ship's own meshes (skeleton pose baked once, triangle BVHs) plus the helm
  wheel and the lanterns. `camera_director.gd` uses it for every shot with `"solve": true`: Canto, crew close-ups, helm, violin, island.
  Crew shots search a ring around the character (front quarter taken from the live `Visual` node, `front_deg`) with a dense ray grid over head and torso (thin
  shrouds slip through a few rays), and reject lenses jammed against a lantern or rail (`near_blocked`). Optional per shot: `front_deg`, `min_clear`.
  Canto: candidates around the ship, the sun face (+-5 deg cone) must be clear of sails, rigging and hull, and the view leans between the sun and the ship
  (continuous in the sun angle; with a near-zenith sun Canto stays fully framed and the ship crops at the bottom). Re-solved every 1.5 s or when the sun
  moves 3 deg relative to the ship, and the camera glides with a critically damped spring (no velocity kick, `--jitter-test` accel stays < 3 m/s2).
  Solutions are logged as `[cam] <shot>: clear spot ...`; the occluder set is built once at 2-6 s after start (one short hitch during the start-up ramp).
- Islands (`islands.gd`): `shaders/island.gdshader` replaces the StandardMaterials (terrain, palms, rocks, bushes, lighthouse bodies) with the same PBR plus a fill
  from the published sky globals (`sky_horizon_color`, `sky_zenith_color`, `sky_night`, `sky_storminess`): hemispheric sky fill by day and dusk, moonlit blue fill at night,
  so no face ever goes black. `shaders/island_horizon.gdshader` colours the far mountain ring from `sky_fog_color` / `sky_zenith_color`, so it matches the horizon at every
  hour. Terrain colour is a smooth vertex blend (shelf, wet sand, beach, dune grass, jungle, treeline rock, steep-face cliffs), a second shoulder hill breaks the cone, palms /
  bushes / rocks are one MultiMesh each. The underwater shelf fades into the ocean's `shallow_color` (read from the ocean material, default `vec3(0.05, 0.62, 0.58)`; ocean files untouched).
  Lighthouse beams (`ambient/lighthouse_beam.gd`) are unchanged.
