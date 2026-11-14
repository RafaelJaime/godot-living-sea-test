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

## Tasks
- [ ] T1 Ocean upgrade (FFT + foam + wake + spray + shallows, buoyancy in sync) — route: delegated (godot-ship)
- [ ] T2 Hull-only ship asset (refs + multi-view 3D) — route: inline (Higgsfield generation)
- [ ] T3 Cloth sails, flag and ropes on new hull, wind-driven — route: delegated (godot-ship)
- [ ] T4 Autonomous mechanics: wind, autopilot/tacking, day-night, weather — route: delegated (godot-ship)
- [ ] T5 Animations: re-rig 3 characters (inline, Higgsfield) + wheel IK & violin pose (delegated)
- [ ] T6 Camera fixes + nicer islands — route: delegated (godot-ship)

## Acceptance criteria
- Water reads as realistic ocean (foam, wake behind ship, spray at bow) in captures; no seams.
- Sails and flag visibly deform and flutter with the wind; change with wind strength.
- Ship hull quality comparable to the characters.
- Wind/weather/day cycle run unattended; storm visibly changes sea state; runs for hours.
- Fuego's hands on the wheel; Don Omar seated playing violin; other two animated.
- No script errors; >= 60 fps.

## Progress / evidence
- Baseline (before this feature): Gerstner ocean, Canto sun, 4 final crew GLBs placed, jitter fixed.
- T5 assets (2026-11-14): re-rigged via Higgsfield 3d_rigging (8 cr each): don_omar.glb -> Chair_Sit_Idle_M, papi_diagnostica.glb -> Long_Breathe_and_Look_Around, el_salchipapa.glb -> Alert. Idle versions backed up in refs/glb_idle_backup/. Godot-side IK/violin still pending.
- T2 in progress: hull-only refs refs/hull_{side,34front,34rear,front}.png (4 x 0.25 cr); multi_image_to_3d job 43aef847 (30 cr, 150k tris, PBR, symmetry on).

## Next step
T2 + T5 asset generation (inline) in parallel with T1 (delegated).
