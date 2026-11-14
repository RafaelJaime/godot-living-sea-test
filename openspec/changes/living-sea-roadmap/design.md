# Design: Living Sea Roadmap (finish the infinite realistic living wallpaper)

## Technical Approach

The roadmap follows proposal Approach A. Each milestone or slice is its own SDD change and single PR on `main`, merged in
dependency order, so `main` stays runnable after every merge. The architecture keeps the conventions the project already
uses: autoload-based shared state (`Waves`, `WorldState`, `WindField`, `ShipLights`, `Capture`), one script per concern
under `godot/scripts/`, one wave source (`scripts/waves.gd` facade over `ocean.gd`), and world rebase through the
`rebase` group plus `Waves.add_world_shift`. This design adds one autoload (`Quality`), one include split of the ocean
shader, one ambient-life subtree, and a measurement and regression harness in `capture.gd`.

New milestone **MQ (quality presets)** lands right after M0 and before every rendering milestone. It is the
"quality-preset system first" requirement: every later milestone reads its knobs from `Quality` rather than hard-coding
cost.

### Ground truth on `main` (read 2026-11-14; differs from exploration.md)

The code on `main` is further along than the exploration recorded. M0 must record this, and the scopes below use it:

| Area | Exploration said | Code on `main` actually does |
|------|------------------|------------------------------|
| Ship propulsion | own `sail_force_local` + WorldState wind | `buoyancy.gd::_apply_sails` applies `PinnaceRig.get_sail_forces()` at each centre of effort with heel depower and a 0.35 g cap per sail. The analytic flat-plate path is only a fallback (`--analytic-sails` or no rig) and still reads `WorldState.wind_vector()` rather than `WindField`. |
| Wake | stern ribbons, cleared on rebase | `Main/Wake` runs `wake_field.gd`, a 1024² RGBA16F ping-pong `SubViewport` pair over a 320 m window tracked in absolute world coordinates (local + `Waves.offset_*`). It is rebase-safe by construction. `wake_update.gdshader` already has Kelvin arm drift (`arm_slope = tan 19.5°`) and bow/side/stern/arm stamps. `wake_ribbon.gd` is still loaded as an `ext_resource` in `main.tscn`, but no node uses it. |
| Hull foam | ignores heel | Foam uses `ship_a` (yaw only) and the 2D `hull_w` outline, so it does ignore heel. `hull_inv` (full pose) and `hull_tex` (cross-section volume) are already uploaded and used for the no-water-in-hull discard. |
| Far-field normals | speckle | The FFT normal arrays have no mips (the addon creates no mip chain). Toksvig slope variance plus a distance fade on cascade 2 is the only filtering. |
| Sky | — | `sky.gd` builds the `Environment` in code: AgX, glow, SSAO off, no SSR, `REFLECTION_SOURCE_SKY`, radiance 128, incremental. Clouds are inside `sky_night.gdshader`. |

The remaining work in M1 and M2b is therefore hardening and completing these paths, not building them from scratch.
Other worktrees (`ocean`, `cloth-wind`, `sky-ambient`) may hold further unmerged work. M0 reconciles them before any
milestone starts.

## Architecture Decisions

### Decision 1: `Quality` autoload with two named presets, applied at start-up

**Choice**: Add a new autoload `Quality` (`scripts/quality.gd`), registered FIRST in `[autoload]` so that `Waves`,
`WorldState`, `WindField` and every scene node can read it in `_ready`. It holds two const preset dictionaries, `dev`
and `final`, and exposes `Quality.preset: StringName`, `Quality.v(key: StringName)`, and `Quality.is_final()`. `Quality`
applies the global render settings itself (viewport scaling, FPS cap, vsync, AA, shadow atlas sizes). Every system
reads its own keys once in `_ready`. The preset is resolved in this order:
1. `--quality=dev|final` user argument.
2. If any test or measurement argument is present (`--capture`, `--jitter-test`, `--autopilot-log=`, `--perf-log=`,
   `--rebase-test=`, `--cloth-demo`) and no explicit `--quality=` is given, use `dev`. Agents cannot accidentally run
   heavy.
3. Otherwise use `dev` (ORCHESTRATOR CORRECTION 2026-11-14: per the quality-presets spec and the user's request to keep
   visuals low while testing, the default is `dev`; implemented on main in 839e7a9). `final` is selected only with
   `--quality=final` or project setting `game/quality=final`; the shipped wallpaper launch config must pass it.
   MQ itself is already implemented (a789aff + 839e7a9); remaining MQ work is the `--plan=regression` batch and the
   `--perf-log` percentiles.

**Alternatives considered**: (a) `Resource` `.tres` presets: editor-friendly, but they add files and a load-order
problem for autoloads, and the values are few. (b) Live switching through a `changed` signal: every system would need
rebuild paths (clipmap meshes, FFT `init_gpu`, `SubViewport` sizes). That is a lot of code for a feature nobody uses
while the wallpaper runs. (c) Godot project-setting overrides (`.godot` feature tags): they cannot switch per launch
from the command line in a way agents control reliably.

**Rationale**: This is the smallest central mechanism that satisfies confirmed decision 1 ("centralised in a
`quality.gd` autoload read by every system"). Restart-to-switch keeps every consumer change to one line in `_ready`.
The test-argument default protects the machine (two testsem slots, user working in parallel).

**Physics-invariant rule**: these values are NOT preset keys, so dev and final sail the same ship: `readback_hz`,
`CPU_CASCADES`, the physics tick, the cascade tile sizes, the rebase distance, and the WindField model. Halved cloth
iterations in `dev` are the one accepted exception, because confirmed decision 1 requires them. Every acceptance that
depends on sail forces (M1 autopilot logs, M5 keel logs) therefore runs at `final`.

### Decision 2: Preset contents (scale features in `final`, drop them in `dev`)

| Key | `dev` | `final` | Consumer |
|-----|-------|---------|----------|
| `render_scale` / `scaling_mode` | 0.6 / bilinear | 1.0 / native (fallback 0.77 / FSR2 if over budget) | `quality.gd` → root `Viewport` |
| `max_fps` / `vsync` | 30 / on | 0 (uncapped for measurement) / on for the wallpaper | `quality.gd` |
| `aa` | none | TAA (+ FXAA off) | `quality.gd` |
| `shadow_size` / `shadow_splits` / `soft_shadow_quality` / `shadow_distance` | 2048 / 2 / low / 100 m | 4096 / 4 / high / 160 m | `quality.gd`, `sky.gd` |
| `ssr` (+ `ssr_steps`) | off | on (64 steps, fade-in 0.15, fade-out 2.0) | `sky.gd` |
| `ssao` / `ssil` | off / off | on / on (half-res) | `sky.gd` |
| `sky_radiance` | 64 | 256 | `sky.gd` |
| `volumetric_fog` | off | on (storm only, low density) | `sky.gd` |
| `clouds` | `sky_layer` (existing 2D) | `sunshine` or `layered` (Decision 9) | `sky.gd` / `clouds.gd` |
| `fft_map_size` | 256 | 512 (1024 only if the M2a spike passes) | `ocean.gd` |
| `ocean_levels` / `cells_per_level` | 9 / 64 | 11 / 96 | `ocean.gd` |
| `fft_updates_per_second` | 30 | 60 | `ocean.gd` |
| `normal_mips` | 3 | 5 | `ocean.gd` (M2a) |
| `wake_res` / `wake_size` | 512 / 320 m | 1024 / 320 m (2048 / 480 m if budget allows) | `wake_field.gd` |
| `cloth_substeps` / `cloth_iterations` | ½ of the code defaults (min 1 / 4) | code defaults | `cloth_solver.gd` |
| `particles_scale` | 0.4 | 1.0 | `ship_fx.gd`, `weather_fx.gd`, ambient |
| `ambient_scale` | 0.5 (counts) | 1.0 | `scripts/ambient/*` |

**Alternatives considered**: three tiers (low/med/high). Rejected because the user confirmed exactly two presets.
A third tier can be added later as a third dictionary without API change.

**Rationale**: `dev` removes every screen-space and volumetric pass and halves the geometry and simulation that scale
with resolution. `final` keeps every feature on and, if the frame budget is exceeded, lowers resolution (FSR2) before it
removes a feature. The proposal requires this order: "scaling features rather than dropping them".

### Decision 3: Split `ocean_fft.gdshader` into includes in MQ (behaviour-neutral)

**Choice**: In MQ, without changing any pixel, move the fragment code into `.gdshaderinc` files:
`shaders/ocean/surface.gdshaderinc` (normals, Toksvig, mips), `shaders/ocean/foam.gdshaderinc` (hull, wake, whitecap,
shore foam), `shaders/ocean/shading.gdshaderinc` (body colour, SSS, `light()` terms) and
`shaders/ocean/common.gdshaderinc` (uniform declarations, helpers). The `.gdshader` file becomes a thin shell of
`#include` lines and the `vertex()` / `fragment()` / `light()` call order. Verification: MQ captures at `final` versus M0
baseline captures at the same presets, visually identical. Pixel-exact identity is not required because of TAA/FFT
timing; M0 and MQ captures use `--engine-scale` and fixed timing.

**Alternatives considered**: (a) Keep one file and serialise every milestone that touches the ocean shader. That would
block the proposal's safe pairs: M1 (heel foam) and M2a (shading) both edit it. (b) Separate materials or passes per
feature: they double vertex work and add draw calls over 11 clipmap rings.

**Rationale**: Godot 4 supports `#include` of `.gdshaderinc`. After the split, M1 owns `foam`, M2a owns `surface` and
`shading`, M2d adds `caustics.gdshaderinc` plus one include line, and M4b adds a bioluminescence term in `foam`.
Ownership becomes per file, which is how the max-2-agents rule is enforced.

### Decision 4: M1: one wind model for both paths, settled start-up, heel-aware foam from the 3D hull volume

**Choice**:
- Keep `get_sail_forces()` as the primary path (already on `main`). Change the analytic fallback to read
  `WindField.sample(pos_w)` at each sail's centre of effort instead of `WorldState.wind_vector() * wind_speed_ms()`.
  Both paths then see the same gusts. The existing `--analytic-sails` flag is documented as the proposal's "legacy force
  path behind a flag until M6". Its name stays unchanged.
- **Settled start-up** (no exposed underside), in `buoyancy.gd::_start_physics`: (1) solve the hydrostatic equilibrium
  heave before unfreezing: bisection on `y` until the displaced column volume equals `mass / water_density`, using the
  existing `_cols`. (2) Start with `linear_velocity` at the expected cruise speed instead of 4 m/s. (3) Ramp the sail
  force with `sail_ramp = smoothstep(0, 6 s, t_since_start)` multiplied into `heel_d`. (4) Pre-roll: run 2.0 s of
  simulation with the camera director held on a wide shot and `Capture` not saving. No fade-to-black is needed if
  (1)–(3) suffice; the fade is a fallback only.
- **Heel-aware hull foam**: in `foam.gdshaderinc`, replace the yaw-only `ship_a` / `hull_w` outline distance with a
  pivot-space distance: `hp = hull_inv * world_pos`, `hw = texture(hull_tex, huv(hp.z, hp.y)).r`, `d = |hp.x| - hw`.
  Because `hull_inv` contains roll and pitch, the foam band follows the heeled waterline. Keep `hull_w` as the fallback
  when `hull_volume_on` is false.
- New read-only hooks: `PinnaceRig.sail_state()` and the `Ship.wobble` signal (see Interfaces).

**Alternatives considered**: (a) Remove the analytic path now. Rejected: the proposal keeps it until M6 for rollback.
(b) Hide start-up with a fade only. Rejected as the primary fix because it hides the cause rather than fixing it, and
`--jitter-test` and captures would still see the transient. (c) Compute the heeled waterline on the CPU and upload a new
outline every frame: 48 raycasts or bisections per frame for something the shader can read from the already-uploaded
volume.

**Rationale**: This is the minimal change that unifies wind, removes the start transient at its source, and reuses
data already on the GPU. Budget: ≤ 0.3 ms (the bisection runs once; the shader adds one texture fetch).

### Decision 5: M2a: compute-generated normal mips, built-in SSR with sky fallback, SSS validation

**Choice**:
- **Normal mips**: add a compute downsample pass (`addons/ocean_fft/shaders/compute/normal_mips.glsl`). It runs after
  `fft_unpack` on each FFT update and writes `Quality.v(&"normal_mips")` levels into the normal texture array. The
  array is created with mipmaps in `render_context.gd` / `wave_generator.gd`. This is a vendored-addon edit, recorded in
  `addons/ocean_fft/README.md` and allowed by its MIT licence. `surface.gdshaderinc` samples with hardware trilinear
  filtering and keeps Toksvig on top for the residual variance.
- **Reflection**: `final` enables `Environment.ssr_enabled` (Forward+ SSR works on this opaque, `depth_draw_opaque`
  material). Where rays miss, Godot falls back to the sky radiance map (`REFLECTION_SOURCE_SKY`), so off-screen and
  horizon reflections stay sky-correct. `dev` is sky-only reflection. The radiance size comes from the preset
  (64 / 256), so dusk reflections match the sky colour at `final`.
- **Crest SSS**: no new model. Validate the existing `sss_height` term with a dedicated capture preset (sun behind the
  waves, low elevation, `--start-phase` near 0.27 / 0.73) against `ref_12s`. Tune `sss_modifier` and the crest weight
  only.
- Spike: test `fft_map_size = 1024` in `final`. `fft_compute` dispatches `[1, map_size, 4]` with a workgroup sized by
  `map_size`, which may exceed device limits at 1024. If it fails, `final` stays at 512 and the extra detail comes from
  mips plus cascade 2.

**Alternatives considered**: (a) A custom in-shader sky reflection (re-evaluating sky gradient and clouds in the water
shader). Rejected: it duplicates `sky_night.gdshader` logic and drifts out of sync; the radiance map already is the sky.
(b) Planar reflection camera. Rejected: it doubles scene render cost and handles a wavy surface badly. (c) LEAN/CLEAN
mapping without mips. Rejected: it needs per-cascade second moments (an extra texture channel and FFT outputs), which is
a larger change than a mip pass.

**Rationale**: Mips remove far-field speckle at the source. Built-in SSR plus the sky fallback is the cheapest correct
reflection and is gated purely by preset. Budget: ≤ 1.5 ms at `final` (SSR about 1.0–1.2 ms, mips about 0.1 ms).

### Decision 6: M2b: harden the existing advected wake rather than replace it

**Choice**: Keep `wake_field.gd` and `wake_update.gdshader` as the architecture. Complete the following:
1. **Precision**: store the window origin as two GDScript `float` (64-bit) fields instead of a `Vector2` (32-bit in
   standard builds). After hours of sailing the absolute coordinates exceed 10⁵ m, where float32 snapping drifts.
2. **Fixed-step update**: run the ping-pong at a fixed 30 Hz with an accumulator, independent of frame rate. `dev`
   (30 fps cap) and `final` (60 fps) then produce the same wake, and the diffusion term
   (`0.12 * clamp(dt * 30, 0, 1)`) stops depending on fps. This also halves the cost at 60 fps.
3. **Real footprint**: take `half_len` / `half_beam` from `Ship` (`set_ship_footprint` values from `ship_ready`) instead
   of the hard-coded `0.46 * 39.8` and `4.4`.
4. **Relative speed and heel**: stamp with the surge component of the hull velocity relative to the water (no currents
   exist, so this is `linear_velocity · forward`). Use leeway (lateral component) to skew the stamps. Shift the side
   stamp toward leeward by `roll`. Bow wave amplitude ∝ Froude number `U / sqrt(g·L)`, not just `speed / 5`.
5. **Channels**: R = foam (existing). G = turbulence or freshness: stamped at the stern and bow, decays faster, used by
   `foam.gdshaderinc` for normal roughening in the turbulent centre and by M4b for bioluminescence. B = signed wave
   ridge height for the Kelvin arms, turned into a normal perturbation by central differences in `surface.gdshaderinc`.
6. **Rebase**: no special handling is needed. The origin is absolute, and window steps are whole multiples of 8 texels,
   so `delta_uv` is exact and there is no resampling blur. Acceptance stays `--rebase-test=150` continuity.
7. Delete `wake_ribbon.gd`, `wake_ribbon.gdshader` and their `ext_resource` in `main.tscn` (the "scales" artefact
   source).

**Alternatives considered**: (a) A wave-particle or height-field simulation of the actual Kelvin pattern (for example a
2D wave equation in the texture). It is more physical, but it costs more at 1024², is unstable with variable dt, and
the reference frames are read as foam pattern rather than wave height. (b) Re-centring the texture on the ship each
frame (ship-anchored). Rejected: foam would smear when the ship turns; world anchoring is what makes the trail stay put.
(c) Clearing on rebase. Rejected: it is already solved better.

**Rationale**: The hard part (world anchoring, ping-pong, rebase) already works. The remaining defects are precision,
fps dependence, hard-coded geometry and the missing wave-normal channel. Budget: ≤ 1.0 ms at `final`.

### Decision 7: M2c spray and M2d caustics stay inside existing owners

**Choice**: M2c reworks `ship_fx.gd` emission to `rate ∝ clamp(U², …) * immersion_rate + slam_impulse`, where
`slam_impulse` is the stem's downward relative velocity crossing the surface (`Waves.height_at` at the stem, already
sampled). Particle `amount` is multiplied by `Quality.v(&"particles_scale")`. M2d adds `caustics.gdshaderinc`: two
scrolling procedural cell patterns modulate `shallow_tint` brightness by `pow(shallow, 1.4)` and sun elevation, so there
is no extra pass and no seabed mesh.

**Alternatives considered**: projected caustics on a seabed mesh or decals. Rejected: there is no seabed geometry, and
the shallows are a colour band of an opaque surface.

**Rationale**: Each costs one owner file plus its budget (0.5 ms and 0.3 ms).

### Decision 8: M3: deterministic exposure; sky owns all environment knobs

**Choice**: `sky.gd` remains the single owner of `Environment`, the sun and the moon. Exposure is computed from
WorldState (sun elevation, cloud, storm; lightning excluded) and written to `CameraAttributesPractical.exposure_multiplier`.
Physical auto-exposure is not used. SSAO and SSIL come from `Quality`. Rain stays in `weather_fx.gd` with
`particles_scale`. Ship shadows use `final` with 4 splits and a 160 m distance, plus `shadow_blur` for the soft look.
T6 camera polish lives in `camera_director.gd` (shot definitions only).

**Alternatives considered**: auto-exposure (`auto_exposure_enabled`). Rejected because it pumps on camera cuts and
lightning, and it makes captures non-reproducible. Captures are the regression suite.

**Rationale**: A curve driven by WorldState reproduces exactly at every capture preset and satisfies "no exposure
pumping in a `--timescale` day run" by construction.

### Decision 9: M3 clouds: gated Sunshine Clouds 2, otherwise layered sky clouds; sky-shader clouds always feed reflections

**Choice**: M3 starts with a time-boxed spike on a throwaway branch. Pass criteria: Sunshine Clouds 2 loads on Godot
4.7.2 with no script errors, AND costs ≤ 2.5 ms GPU at 1920×1080 `final` (measured with `--perf-log`). If it passes,
vendor it under `addons/sunshine_clouds2/` (MIT, `ATTRIBUTION.md`). A new adapter `scripts/clouds.gd` maps
`WorldState.cloud`, `storm`, `wind_vector()` and `cloud_scroll` to the addon parameters. If it fails, implement
`layered`: two to three 2.5D noise layers in `sky_night.gdshader` with sun-lit edges, lit from `sun_dir`.
In both cases the existing sky-shader cloud layer keeps rendering in the radiance (`AT_CUBEMAP_PASS`) pass. A
compositor effect is not part of the sky radiance, so without this the water would reflect a cloudless sky.
`dev` uses only the existing 2D layer.

**Alternatives considered**: (a) TCA_Weather_System. Rejected: it replaces WorldState and the sky (out of scope:
"weather cycle logic rewrite"). (b) Built-in volumetric fog as clouds. Rejected: wrong look and costly at range.

**Rationale**: This implements confirmed decision 2 exactly and closes the reflection gap that addon clouds create.

### Decision 10: M4: one `AmbientDirector` with fixed pools and ship-relative recycling

**Choice**: Add a node `Main/Ambient` running `scripts/ambient/ambient_director.gd`. It owns child systems, each a
script in `scripts/ambient/`. Every system has a fixed pool sized as `base_count * Quality.v(&"ambient_scale")`,
created in `_ready` (never instantiated at runtime). Systems recycle members that leave a ship-relative ring, join the
`rebase` group, and read only autoload state plus the Ship's public fields. The director exposes
`stats() -> {system: active_count}` for the 10-minute node-count check.
- M4a: `birds.gd` (boids on a `MultiMeshInstance3D`; replaces `gulls.gd` and takes over its node), `dolphins.gd`
  (pods that pace the bow wave and breach on arcs, with heights from `Waves.height_at`), `whales.gd` (distant spout
  particles; optional).
- M4b: `passing_ships.gd` (impostor or low-poly silhouettes on far lanes 800–3000 m, emissive night lights, a real
  `OmniLight3D` only within 300 m and in `final`), `lighthouse.gd` (placed on an island from `islands.gd::targets()`,
  with an additive beam cone plus a `SpotLight3D` in `final`), bioluminescence (night × wake G channel emission in
  `foam.gdshaderinc`).
- M4c: cat's paws (Decision 11), and optionally flotsam, wet deck (ship material wetness from `WorldState.deck_wetness`),
  rainbow (sky shader term after a storm), morning fog (sky.gd fog curve).

**Alternatives considered**: (a) Independent nodes in `main.tscn` per element: each would need its own budget, and
`main.tscn` would become a conflict hotspot. (b) Spawning on demand with `queue_free`: node count can grow unbounded,
which violates the acceptance criteria.

**Rationale**: Fixed pools make "no unbounded node count" true by construction. One director gives a single
measurement point for the 1.5 ms M4 budget.

### Decision 11: Cat's paws from the real WindField gust field, rasterised natively

**Choice**: `WindField` gains `gust_texture() -> ImageTexture` and `gust_window() -> Vector4` (origin xz, size, stretch).
Every 0.25 s it refreshes a 128×232 image of the same `_gust` FastNoiseLite, offset by (window origin − `_advect`) and
using the native `Noise.get_image()`. Native generation avoids per-texel GDScript calls. The z stretch of 1.8 is
handled by the image aspect ratio. `surface.gdshaderinc` and `foam.gdshaderinc` lower roughness and raise the
fine-cascade normal contrast where the gust factor exceeds 1. Visible dark patches then move across the water with the
same field that hits the sails.

**Alternatives considered**: (a) An independent shader noise. Rejected: the gusts on the water would not match the
gusts in the sails, and this coherence is the point of the effect. (b) Sampling `gust_factor` per texel in GDScript.
Rejected: about 30k noise calls per refresh on the main thread.

**Rationale**: It reuses the one wind model. Cost is bounded (a native image of under 30k pixels, four times per
second). Gust pulses are omitted; they are a test aid.

### Decision 12: M5: keel-end mitigation without hull edits

**Choice**: In `buoyancy.gd`, apply per-column wave coupling that falls with distance from midship
(`coupling(z) = lerp(wave_coupling, wave_coupling * 0.6, |z - z_mid| / half_len)`). A long hull does not follow short
waves at its ends; this is the physical low-pass, applied where the keel shows. Add slam damping on end columns that
emerge (vertical damping ∝ emergence velocity, capped like `keel_suction`). Retune `keel_free_lift` and `keel_suction`
for end columns only. Report the `[keel]` summary at sea 0.5 / 0.9 against the interim targets (1.1 / 2.3 m) and the
stretch targets (0.5 / 1.5 m). Stop at the interim if the stretch would degrade roll and pitch ranges below T8.
Boat to ship: `lashed_boat.gd` applies the equal and opposite lashing force and torque to `_ship`
(`apply_force(-F, attach_w - ship_origin)`), using the spring force it already computes. Rope sag: each rope renders as a
catenary approximation with segments, where `sag = k * max(rest_len - chord, 0)`.

**Alternatives considered**: (a) Stronger global `keel_suction`. Rejected: it makes the hull "sticky" and visibly
unphysical in heave. (b) Shader-side water raising near the hull ends (visual cheat). Rejected: it masks the defect
checklist item and conflicts with the no-water-in-hull discard. (c) Hull or draft edits. Out of scope (confirmed
decision 3).

**Rationale**: These are physically motivated levers inside the existing column model, behind exports, and they can be
reverted per value. Budget: ≤ 0.2 ms (no new columns).

### Decision 13: Measurement and regression harness lives in `capture.gd`

**Choice**: In M0, add `--perf-log=<secs>` to `capture.gd`. It enables `viewport_set_measure_render_time` on the root
viewport and samples CPU (`Performance.TIME_PROCESS`, `TIME_PHYSICS_PROCESS`) and GPU
(`RenderingServer.viewport_get_measured_render_time_gpu`) frame times each frame after a 5 s warm-up. It prints one
`[perf] preset=<capture preset> quality=<q> res=<WxH> p50 p95 p99 1%low fps` line. In MQ, add
`--plan=regression`, which walks four fixed capture presets in one process: it sets `WorldState.day_phase` and
`set_weather(..., true)`, `override_sea`, and a fixed `--wind`. It settles for 8 s per preset, then saves the shots,
named `reg_<preset>_<shot>.png`. One testsem slot covers the whole suite.

| Capture preset | day_phase | weather | sea | Shots |
|----------------|-----------|---------|-----|-------|
| `day_calm` | 0.45 | clear | 0.2 | 3/4 bow, top-down wake, horizon |
| `dusk_moderate` | 0.73 | cloudy | 0.5 | sun-behind-waves, side low, horizon |
| `storm` | 0.55 | storm | 0.9 | 3/4 bow, deck, wide |
| `night` | 0.02 | clear | 0.35 | wake top-down (bioluminescence), lanterns (`--auto-light`), wide |

**Alternatives considered**: (a) An external benchmark script or `--print-fps` only: no GPU time, no percentiles.
(b) One launch per preset: four times the testsem usage.

**Rationale**: It extends the existing capture conventions (`PLAN` arrays, `[tag]` log lines). Each PR reports the same
numbers.

## Data Flow

```
  Quality (autoload, first) ──read once in _ready──▶ every system below (render knobs only, never physics)

  WorldState (-90) ── day_phase, sun_dir, daylight, night, cloud, storm, wind_angle/strength, sea_state, flash
     │                 (+ deck_wetness from M4c)
     ├──▶ Waves.sea_state ──▶ Ocean (FFT compute, clipmap, readback 20 Hz) ──▶ Waves.height_at ──▶ Ship columns,
     │                                                                                    ShipFX, dolphins, boat
     ├──▶ WindField (-1000: ClothSolver.sync; mean wind, gusts advected, rebase-safe via Waves.offset_*)
     │        ├──▶ ClothSolver (worker threads, launched at priority 100) ──▶ PinnaceRig.get_sail_forces()
     │        │                                                                   │
     │        └──▶ gust_texture() (M4c) ──▶ ocean surface/foam (cat's paws)      ▼
     ├──▶ Sky (sky.gd: env, sun, moon, exposure, clouds adapter) ──radiance──▶ ocean reflections (+ SSR in final)
     └──▶ ShipLights (dusk/dawn signals) ──▶ NPC session (external)

  Ship (RigidBody3D, _physics_process, Jolt) ◀── sail forces, rudder (Autopilot), hydrostatics (Waves)
     │  public state: roll, pitch, rates, yaw, yaw_rate, rudder, forward, current_speed, linear_velocity
     │  + signal wobble (M1)
     ├──▶ Ocean._push_dynamic: hull_inv (full pose), ship_a, ship_speed  ──▶ foam.gdshaderinc (heel-aware foam)
     ├──▶ WakeField (150, fixed 30 Hz): stamps R/G/B ──▶ Ocean.set_wake ──▶ foam / surface / bioluminescence
     ├──▶ ShipFX spray, Boat lashing (◀── reaction load back to Ship, M5), Camera, AmbientDirector
     └──▶ Capture (1000): logs, perf, regression shots

  Main (rebase at 1600 m) ──▶ group "rebase".rebase(shift) + Waves.add_world_shift(shift)
        └─ Ocean cascade_shift, WakeField origin (absolute), WindField _off: all continuous by construction
```

Process order stays: WindField −1000 → WorldState −90 → default (0: Sky, Autopilot, Ambient) → Ocean 100 / cloth
launcher 100 → WakeField 150 → Capture 1000. Ambient systems read Ship state after physics by running at priority 120
or higher (after Ocean, before WakeField).

## File Changes

### Ownership per milestone (one owner at a time; the second agent waits for the merge)

| Milestone | Owns (modify/create) | Must NOT touch |
|-----------|----------------------|----------------|
| M0 | `godot/README.md`, `odd/tasks/living-sea-wallpaper.md`, `odd/evidence/m0/*`, `scripts/capture.gd` (`--perf-log` only) | any runtime script or shader |
| MQ | `scripts/quality.gd` (new), `project.godot` (autoload line), `shaders/ocean_fft.gdshader` → `shaders/ocean/*.gdshaderinc` (split), one-line `Quality.v` reads in `ocean.gd`, `wake_field.gd`, `cloth_solver.gd`, `ship_fx.gd`, `weather_fx.gd`, `sky.gd`; `capture.gd` (`--plan=regression`) | shader logic (split only) |
| M1 | `scripts/buoyancy.gd`, `scripts/pinnace_rig.gd` (`sail_state`), `shaders/ocean/foam.gdshaderinc`, `scripts/ocean.gd` (push only, if needed) | `surface`/`shading` incs, wake files, sky |
| M2a | `shaders/ocean/surface.gdshaderinc`, `shaders/ocean/shading.gdshaderinc`, `addons/ocean_fft/*` (mips), `scripts/ocean.gd`, `scripts/sky.gd` (SSR/radiance keys only) | `foam.gdshaderinc`, wake, buoyancy |
| M2b | `scripts/wake_field.gd`, `shaders/wake_update.gdshader`, `shaders/ocean/foam.gdshaderinc` (wake block), `surface.gdshaderinc` (B-channel normal, after M2a merges), delete `wake_ribbon.*`, `main.tscn` (remove ext_resource) | buoyancy, sky |
| M2c | `scripts/ship_fx.gd` | everything else |
| M2d | `shaders/ocean/caustics.gdshaderinc` (new) + one include line in the shell `ocean_fft.gdshader` | other incs |
| M3 | `scripts/sky.gd`, `shaders/sky_night.gdshader`, `scripts/clouds.gd` (new), `addons/sunshine_clouds2/*` (if gated in), `scripts/weather_fx.gd`, `scripts/camera_director.gd` (T6 shots), `scripts/islands.gd` (T6 island polish), `ATTRIBUTION.md` | ocean incs, world_state logic |
| M4a | `scripts/ambient/ambient_director.gd`, `ambient/birds.gd`, `ambient/dolphins.gd`, `ambient/whales.gd`, `main.tscn` (Ambient node, Gulls node swap), delete `gulls.gd` | ocean, wake |
| M4b | `ambient/passing_ships.gd`, `ambient/lighthouse.gd`, `foam.gdshaderinc` (bioluminescence term), `islands.gd` (read-only use of `targets()`; edit only if a placement hook is missing) | wake_update (consumes G only) |
| M4c | `scripts/wind_field.gd` (`gust_texture`), `surface.gdshaderinc` (cat's paws), `scripts/world_state.gd` (`deck_wetness`), optional `ambient/flotsam.gd`, sky rainbow/fog terms | buoyancy |
| M5 | `scripts/buoyancy.gd` (columns), `scripts/lashed_boat.gd` | shaders |
| M6 | fixes found by QA in the owning files, `godot/README.md`, ODD doc, `odd/evidence/m6/*` | — |
| any | NEVER: `scripts/crew_*.gd`, character assets, the `stable` worktree | — |

### Concurrency (max 2 agents, worktree each under `el-terraria-blender-worktrees/`)

Safe pairs given the ownership table: M1 ∥ M2a (foam vs surface/shading incs, after MQ); M1 ∥ M2d; M3 ∥ M5;
M4a ∥ M2b; M2c ∥ M3. Forbidden pairs: any two milestones that own the same inc; M2b ∥ M4b (foam); M2a ∥ M4c
(surface); M1 ∥ M5 (buoyancy). Sequence: M0 → MQ → {M1 ∥ M2a} → M2b → {M2c ∥ M3} → {M2d, M4a ∥ M5} → M4b → M4c → M6.

### Per-file summary

| File | Action | Description |
|------|--------|-------------|
| `godot/scripts/quality.gd` | Create | `Quality` autoload: presets, resolution order, global render apply |
| `godot/project.godot` | Modify | Register `Quality` first in `[autoload]` |
| `godot/shaders/ocean_fft.gdshader` | Modify | Becomes an include shell (MQ) |
| `godot/shaders/ocean/{common,surface,foam,shading,caustics}.gdshaderinc` | Create | Split ownership units |
| `godot/addons/ocean_fft/{render_context.gd,wave_generator.gd,shaders/compute/normal_mips.glsl,README.md}` | Modify/Create | Normal mip chain (M2a) |
| `godot/scripts/ocean.gd` | Modify | Preset reads, mip dispatch hookup |
| `godot/scripts/buoyancy.gd` | Modify | WindField fallback, settled start, sail ramp, wobble signal, keel-end coupling (M5) |
| `godot/scripts/pinnace_rig.gd` | Modify | `sail_state()` read-only summary |
| `godot/scripts/wake_field.gd`, `godot/shaders/wake_update.gdshader` | Modify | Precision, fixed step, footprint, G/B channels |
| `godot/scripts/wake_ribbon.gd`, `godot/shaders/wake_ribbon.gdshader` (+ `.uid`) | Delete | Unused ribbon wake |
| `godot/scripts/ship_fx.gd` | Modify | Spray ∝ U² and slam; particles_scale |
| `godot/scripts/sky.gd`, `godot/shaders/sky_night.gdshader` | Modify | Presets, exposure curve, clouds layers, radiance pass |
| `godot/scripts/clouds.gd`, `godot/addons/sunshine_clouds2/*` | Create (gated) | Clouds adapter or addon |
| `godot/scripts/weather_fx.gd` | Modify | Rain scale, storm darkness coupling |
| `godot/scripts/ambient/*.gd` | Create | Director and pooled systems |
| `godot/scripts/gulls.gd` | Delete (M4a) | Superseded by `ambient/birds.gd` |
| `godot/scripts/wind_field.gd` | Modify | `gust_texture()`, `gust_window()` |
| `godot/scripts/world_state.gd` | Modify | `deck_wetness` (M4c) |
| `godot/scripts/lashed_boat.gd` | Modify | Reaction load, rope sag, `state()` |
| `godot/scripts/capture.gd` | Modify | `--perf-log`, `--plan=regression`, `--quality` passthrough to logs |
| `godot/main.tscn` | Modify | Remove ribbon ext_resource (M2b), Ambient node (M4a) |
| `godot/README.md`, `odd/tasks/living-sea-wallpaper.md`, `ATTRIBUTION.md` | Modify | Docs, NPC API, licences |

## Interfaces / Contracts

```gdscript
# scripts/quality.gd (autoload "Quality", first in [autoload])
extends Node
const PRESETS := {
	&"dev":   { &"render_scale": 0.6, &"max_fps": 30, &"ssr": false, &"ssao": false, &"ssil": false, &"fft_map_size": 256, ... },
	&"final": { &"render_scale": 1.0, &"max_fps": 0,  &"ssr": true,  &"ssao": true,  &"ssil": true,  &"fft_map_size": 512, ... },
}
var preset: StringName            # resolved in _init from --quality / test args / default "dev"
func v(key: StringName) -> Variant # push_error + return null on an unknown key (fails loudly in the log = 0-errors check)
func is_final() -> bool
```

NPC integration API (read-only additions; documented in `godot/README.md` with a changelog line per milestone):

```gdscript
# Ship (buoyancy.gd), M1
signal wobble(intensity: float, kind: StringName)  # kind: &"roll" | &"pitch" | &"slam"; rate-limited to ≤ 2 Hz,
                                                   # intensity 0..1 from roll_acc / pitch_acc / slam impulse
var settled: bool                                  # false during the start-up ramp

# PinnaceRig (group "sail_rig"), M1
func sail_state() -> Dictionary  # {furl: float 0..1 (sail_power), brace_deg: float, mean_pressure_pa: float,
                                 #  luffing: bool, backed: bool, gust: float}

# Boat (lashed_boat.gd), M5
func state() -> Dictionary       # {offset_m: float, tilt_deg: float, lashing_load_n: float, in_cradle: bool}

# WorldState, M4c
var deck_wetness: float          # 0 dry .. 1 soaked; rises with storm rain, dries with daylight and wind

# WindField, M4c (render consumers; NPCs may read gust_factor as today)
func gust_texture() -> ImageTexture
func gust_window() -> Vector4    # origin x, origin z (local coords), size m, z-stretch
```

Unchanged and kept stable: `ShipLights.*` (get_lanterns, light, extinguish, is_lit, lighting_needed,
extinguish_suggested, lantern_changed); `Ship.roll/pitch/roll_rate/pitch_rate/yaw/yaw_rate/rudder/forward/current_speed/
linear_velocity`; `WorldState.daylight/night/storm/cloud/wind_vector()/wind_speed_ms()/sun_elevation_deg`; the deck
raycast. Rule: any change that breaks a hook needs a README changelog entry and a user announcement before merge.

Wake texture contract (M2b, consumed by `foam`/`surface` incs and M4b):
`R` foam 0..1 (decay 0.26/s), `G` turbulence/freshness 0..1 (decay ~1/s), `B` signed Kelvin ridge height (m,
±0.5 clamp). Format RGBA16F, window `wake_size` m, origin snapped to 8 texels in absolute world coordinates.

## Performance Budget (per preset)

Measured with `--perf-log` at 1920×1080, Forward+, Apple Silicon, `--plan=regression` presets; the reported number is
the worst preset's p50 GPU and CPU frame time, plus the 1% low.

| Milestone | `final` increment (GPU ms) | `dev` increment | Notes |
|-----------|---------------------------|-----------------|-------|
| M0 baseline | measured B_final (current look) | — | Unknown at 1080p; 720p soak was 12.9 ms |
| MQ | ≤ 0 (split is neutral) | defines B_dev | `dev` target: ≤ 12 ms GPU at 0.6 scale, a steady 30 fps cap, machine responsive with one other testsem run |
| M1 | ≤ 0.3 | ≤ 0.2 | One-off bisection; one extra texture fetch |
| M2a | ≤ 1.5 | ≤ 0.2 | SSR `final` only; mips both |
| M2b | ≤ 1.0 | ≤ 0.4 | 30 Hz fixed step; 512² in `dev` |
| M2c | ≤ 0.5 | ≤ 0.2 | particles_scale |
| M2d | ≤ 0.3 | ≤ 0.3 | Shader only |
| M3 | ≤ 3.5 (clouds ≤ 2.5, SSAO/SSIL + shadows ≤ 1.0) | ≤ 0.3 | `dev` keeps the 2D cloud layer |
| M4 | ≤ 1.5 total | ≤ 0.8 | ambient_scale 0.5 |
| M5 | ≤ 0.2 CPU | ≤ 0.2 CPU | No new columns |

Rule: if B_final plus the increments exceeds 16.7 ms, `final` first switches to FSR2 at 0.77 render scale, which buys
back about 35–40% of the pixel-bound cost. Only after that may it lower feature quality (SSR steps, cloud steps, SSIL
half-res), never remove a feature. A PR that exceeds its increment documents the fallback it used or asks the user. CPU
budget: the main thread stays ≤ 8 ms at `final`, because GDScript hydrostatics and cloth sync are the CPU-bound parts.

## Testing Strategy

There is no unit runner (`strict_tdd: false`, `test_command: null`). Verification is functional and always runs through
`~/.claude/bin/testsem -- open -g -n -W -a /Applications/Godot.app --args --path godot --log-file godot/_shots/godot.log -- …`.

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Regression (every PR) | Visual state at the 4 capture presets | `--plan=regression --quality=dev` during iteration; one `--quality=final` batch at PR close, saved under `odd/evidence/<milestone>/`, compared side by side with the M0/MQ baseline and the matching `refs/reference_krautdev` frames |
| Performance (every PR) | Frame time vs budget | `--perf-log=30 --quality=final --resolution 1920x1080` at the worst preset; p50/p95/p99/1% low in the PR body |
| Physics (M1, M5) | Speed, roll, pitch, gust-correlated thrust, keel, boat | `--autopilot-log=120 --sea=0.2/0.5/0.9 --quality=final`; `[keel]` summary; `--log-boat`; compared with T8 ranges |
| Motion quality | Camera and ship jitter | `--jitter-test` not worse than baseline |
| Rebase (M2a, M2b, M2d, M4) | Continuity across world shift | `--rebase-test=150` with top-down wake shots before and after a shift |
| Start-up (M1) | No exposed underside | Captures at t = 1, 3, 5, 8, 10 s (`--shots=` at fixed times) |
| Endurance (M4, M6) | Node count, errors | 10-minute `--timescale` run logging `AmbientDirector.stats()` every 30 s; flat counts; 0 `SCRIPT ERROR` lines in `godot.log` |
| Final QA (M6) | R7 checklist | 360° horizon sweep × sea 0.2/0.5/0.9 and a 10-minute day → storm → night run at `final` 1920×1080 |

Every log is checked for zero `SCRIPT ERROR` / `ERROR:` lines. `Quality.v()` on an unknown key raises `push_error`, so
a typo fails this check rather than silently using a default.

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration
boundary. This change only adds in-engine GDScript and shaders, plus CLI flags parsed by the game itself. Godot launches
keep using the existing testsem wrapper unchanged.

## Migration / Rollout

- No data migration. Every milestone is one PR on `main`; rollback means reverting its merge commit.
- Feature flags: render features are gated by `Quality` keys, so a single key can turn them off without a revert.
  `--analytic-sails` remains the legacy force path until M6. Clouds are gated by the Decision 9 spike.
- M0 order: (1) commit the `sky-ambient` WIP to its own branch before anything else; (2) reconcile the other worktrees
  against the ground-truth table above; (3) sync docs; (4) baseline captures and `--perf-log`; (5) prune merged
  branches or worktrees only with explicit, recorded user OK; never touch `stable`.
- The MQ default makes plain launches `dev` (corrected; see decision 1). The user's `stable` worktree is unaffected until a merge reaches it
  through ordinary policy.

## Open Questions

- [ ] Does `fft_map_size = 1024` work with the vendored `fft_compute` dispatch on Apple Silicon? This is an M2a spike;
      it does not block, and `final` falls back to 512.
- [ ] Does Sunshine Clouds 2 run on Godot 4.7.2 within 2.5 ms at 1080p? This is the M3 spike defined in Decision 9; it
      does not block.
- [ ] Do unmerged commits in the `ocean`, `cloth-wind` or `sky-ambient` worktrees overlap the ground-truth table? M0
      must answer this before M1 or M2b tasks are written. It may shrink or grow their scope.
- [ ] Is an image-diff metric (for example ImageMagick `compare -metric RMSE`) acceptable as an advisory regression
      signal next to human side-by-side review? It is optional and not a gate.
