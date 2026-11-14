# Living sea wallpaper (El Terraria crew ship)

## Objective
Turn the Godot ship scene into an infinite "living wallpaper" with realistic sea and ship physics
in the spirit of KrautDev's age-of-sail Godot game (https://www.youtube.com/watch?v=ClBGteyLn2c):
realistic ocean with foam/wake/spray, cloth sails and flag reacting to wind, a better-looking ship,
character animations, and autonomous mechanics (no user input).

## Problem / why
Current scene (Gerstner ocean, single-mesh Meshy galleon, idle-only crew) works but the water looks
flat, sails/flag are rigid, and the ship model is lower quality than the characters.

## Scope (authorized 2026-11-14)
- Ocean: FFT-based waves (evaluate GodotOceanWaves / godot4-oceanfft on Godot 4.7.2), foam, ship wake,
  bow spray, turquoise shallows near islands; CPU-consistent buoyancy.
- Ship: regenerate HULL ONLY (masts/yards, no sails) at higher quality from multi-view refs; sails, flag
  and ropes built in Godot as cloth reacting to wind.
- Autonomous mechanics: slowly shifting wind, autopilot steering/tacking between islands, day/night
  cycle, weather cycle (clear -> cloudy -> storm -> clear) driving waves, fog, light, rain.
- Animations: Don Omar seated playing violin (Meshy sit idle 33 + procedural violin arm pose + prop),
  Papi Fuego hands on the wheel (IK, wheel turns with autopilot), Papi Diagnostica look-around (336),
  El Salchipapa alert (2).
- Camera fixes: Canto shot not occluded by sails, per-character close-ups unobstructed.
- Better procedural islands (beach, vegetation, shallows).

## Constraints
- Godot 4.7.2 Forward+, Apple Silicon, target 60 fps.
- Higgsfield credits: hull regen ~30-50, re-rig animations 3 x 8 = 24. No other paid generation.
- No user interaction mechanics yet (autonomous only).
- ~400 authored changed lines per task is a planning heuristic only.

## Verification / TDD
- TDD mode: global strict TDD is configured, but this Godot project has no test runner; verification
  is functional: `godot --path godot -- --capture` screenshots + `--jitter-test` metrics + zero script
  errors in the Godot log. (Disclosed: no unit test framework present.)

## Tasks (ordered plan, revised 2026-11-14 after user feedback)
- [x] T1 Ocean upgrade: FFT + foam + wake + spray + shallows, `sea_state` 0..1, buoyancy in sync — delegated (godot-ship) — done in the `feat(ocean)` commit (see git log --grep "feat(ocean)")
- [ ] T2 Realistic hull asset: hull-only multi-view 3D (job 43aef847). Quality gate: compare against the
      characters in a close-up capture; if still uglier, iterate (higher polycount / better refs / texture_prompt)
      before T3. — inline (Higgsfield)
- [ ] T3 Ship rebuild on the new hull: cloth sails + flag (wind-driven), ropes/rigging, extra props
      (barrels/crates for Don Omar's seat). — delegated
- [ ] T3b No water through the hull: water must never render inside the hull/deck (hull interior mask:
      depth/stencil "hull cutout" volume that discards ocean fragments inside the hull), plus correct
      buoyancy depth so the waterline matches the hull shape in heave/pitch/roll and in storms. — delegated
- [ ] T4 Autonomous mechanics: wind direction/strength drift, autopilot that steers/tacks between islands
      (rudder angle as a shared signal), day/night cycle, weather cycle clear->cloudy->storm->clear driving
      sea_state, fog, light, rain; Canto dims at night/storm. — delegated
- [ ] T5 Animations:
      - re-rig Don Omar (sit), Papi Diagnostica (look around), El Salchipapa (alert) — DONE assets (inline)
      - Papi Fuego helmsman reacts to steering: hands on the wheel via IK; wheel rotates with the autopilot
        rudder; body leans/turns into the turn, looks toward the heading, braces when the ship pitches/rolls
        hard (procedural layer over idle). — delegated
      - Don Omar violin: arm pose layered over sit + violin prop + bow motion. — delegated
      - Crew balance: all crew sway/brace with ship roll (procedural hip/spine counter-lean). — delegated
- [ ] T6 Camera fixes (Canto shot unoccluded, close-ups unobstructed, shots that show helmsman steering
      and storm) + nicer islands (beach, vegetation, shallows). — delegated

## Acceptance criteria
- Water reads as realistic ocean (foam, wake behind ship, spray at bow) in captures; no seams.
- Water NEVER visible inside the hull or over the deck (except spray/rain), in calm and storm.
- Ship hull quality comparable to the characters (side-by-side capture review).
- Sails and flag visibly deform and flutter with the wind; change with wind strength.
- Wind/weather/day cycle run unattended; storm visibly changes sea state; runs for hours.
- Papi Fuego turns the wheel and leans into turns in sync with the ship's heading changes.
- Don Omar seated playing violin; other two animated; crew brace with roll.
- No script errors; >= 60 fps.

## Credits budget (Higgsfield)
- Spent this feature: re-rig 24 + hull views 1 + hull 3D 30 = 55.
- Reserve: up to ~60 for hull iterations if the quality gate fails; nothing else planned.

## Progress / evidence
- Baseline (before this feature): Gerstner ocean, Canto sun, 4 final crew GLBs placed, jitter fixed.
- T5 assets (2026-11-14): re-rigged via Higgsfield 3d_rigging (8 cr each): don_omar.glb -> Chair_Sit_Idle_M, papi_diagnostica.glb -> Long_Breathe_and_Look_Around, el_salchipapa.glb -> Alert. Idle versions backed up in refs/glb_idle_backup/. Godot-side IK/violin still pending.
- T2 in progress: hull-only refs refs/hull_{side,34front,34rear,front}.png (4 x 0.25 cr); multi_image_to_3d job 43aef847 (30 cr, 150k tris, PBR, symmetry on).
- T1 (2026-11-14): vendored 2Retr0/GodotOceanWaves (MIT) FFT compute pipeline under godot/addons/ocean_fft (godot4-oceanfft not needed). Fixed for Godot 4.7.2: exact push-constant sizes, separate read-only descriptor set for the modulate pass. Own clipmap + shader (godot/shaders/ocean_fft.gdshader), 3 cascades (tiles 200/80/20 m; rebase step 1600 m is a common multiple so waves never jump). `Waves.sea_state` / `ocean.sea_state` (0..1) drives wind speed, whitecap threshold and foam amount. CPU buoyancy = synchronous readback of the 2 displacement cascades at 20 Hz, blended prev->current, same fixed-point inversion as the shader (async readback crashes 4.7.2 intermittently with texture-array layers). Foam wake (22 s world-space particles snapped to the FFT surface), bow-wave foam, bow spray driven by stem immersion rate + sea_state, hull-contact foam, turquoise island shallows with shore surf (waterline ellipses pushed from islands.gd). Evidence: captures in godot/_shots (sea_state 0.2 and 0.9: close water, wake from above, wide with islands), 3 consecutive `--capture` runs with 0 script/engine errors, 125-155 fps in capture (avg frame 7.5 ms), jitter test shot 0: 0.27 m/s, 2.8 m/s2; rebase test OK (`-- --rebase-test=40`). Limits: low shot jitter 1.9 m/s peak speed (camera rides waves, by design); wake is cleared on world rebase (every 1600 m) and regrows within ~20 s; foam is not shadowed.

## Next step
T2 + T5 asset generation (inline); then T3 / T4.
