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
- [x] T1b Ocean FX polish: wake as streaky foam ribbon meshes (replaces blob billboards), spray as sharp velocity-aligned droplets + faint mist, camera clearance against the wave envelope (look-ahead, raised with sea_state) — delegated (godot-ship)
- [x] T2 Realistic hull asset — SUPERSEDED: two Meshy hulls rejected (duplicated wheel/lanterns, missing yard);
      user chose Sketchfab "Pirate ship (Rigged)" by TIG (CC BY 4.0, = Poly Haven Ship Pinnace CC0) — see ATTRIBUTION.md.
- [x] T3 Ship rebuild on the new hull: cloth sails + flag (wind-driven), ropes/rigging, extra props — done in the `feat(ship)` commit
      (barrels/crates for Don Omar's seat). — delegated
- [x] T3b No water through the hull: water must never render inside the hull/deck (hull interior mask: — done in the `feat(ocean)` hull-mask commit
      depth/stencil "hull cutout" volume that discards ocean fragments inside the hull), plus correct
      buoyancy depth so the waterline matches the hull shape in heave/pitch/roll and in storms. — delegated
- [x] T4 Autonomous mechanics: wind direction/strength drift, autopilot that steers/tacks between islands — done in the `feat(world)` commit
      (rudder angle as a shared signal), day/night cycle, weather cycle clear->cloudy->storm->clear driving
      sea_state, fog, light, rain; Canto dims at night/storm. — delegated
- [x] T5 Animations (Godot side done in the `feat(crew)` commit):
      - re-rig Don Omar (sit), Papi Diagnostica (look around), El Salchipapa (alert) — DONE assets (inline)
      - Papi Fuego helmsman reacts to steering: hands on the wheel via IK; wheel rotates with the autopilot
        rudder; body leans/turns into the turn, looks toward the heading, braces when the ship pitches/rolls
        hard (procedural layer over idle). — delegated
      - Don Omar violin: arm pose layered over sit + violin prop + bow motion. — delegated
      - Crew balance: all crew sway/brace with ship roll (procedural hip/spine counter-lean). — delegated
- [ ] T6 Camera fixes (Canto shot unoccluded, close-ups unobstructed, shots that show helmsman steering
      and storm) + nicer islands (beach, vegetation, shallows). — delegated
- [x] T6b Polish from user review: hull-hugging foam (cdab617), animation crossfades/ramps (700ee14), arm IK
      stabilised (acdbe66), Omar seated on barrels via deck raycast (1242bc9), Pirat flag + camera smoothing (55da2dc).
- [ ] T7 Sandbox crew: Papi Diagnostica and El Salchipapa roam the ship autonomously (deck waypoint graph,
      cabin door in/out, stairs up to the helm to talk to Papi Fuego, gather to listen to Don Omar's violin,
      idle chores), AnimationTree state machine with walk / climb_stairs / talk / listen clips (Meshy
      re-rig clips: Casual_Walk 30, Climb_Stairs 441, Talk_with_Hands_Open 313, + idle/look; shared
      AnimationLibrary across same-rig characters if retarget works, else per character). Helmsman and
      violinist react (turn head toward visitor). Depends on final ship choice (door/stairs). — delegated
- [x] T3 note: flag cloth physics confirmed in scope (user asked 2026-11-14). — done in the `feat(ship)` commit
- [ ] T8 Physics-driven ship (user 2026-11-14: realism instead of scripted roll): RigidBody3D with per-sample
      hydrostatic buoyancy on the FFT surface, keel-effect drag, sail aerodynamic forces (thrust + heel from apparent
      wind at each sail's centre of effort), rudder hydrodynamic lift, yards braced to the wind, sails luff/back;
      stable for hours, never capsizes, keel hidden except extreme storm moments. — delegated
- [ ] T8b Realistic ship's boat: lashed to the deck with ropes, slight physical play (spring/rope constraints),
      never falls off. — delegated
- [ ] T9 Flags: stern flag pinned to the real (bone-posed) staff; second Pirat flag at the main masthead. — delegated
- [ ] T9b Unified wind: one WindField (travelling gusts) + identical cloth aerodynamics for sails AND flags
      (apparent wind per point incl. ship/mast motion); sail forces on the ship come from the same cloth pressure,
      so visible filling/luffing = propulsion. — delegated
- [ ] T10 Hybrid character physics (APPROVED 2026-11-14): foot IK on the tilting deck + stumbles/balance recovery
      in storms over keyframed base clips. Hair/clothing physics explicitly OUT of scope. — delegated

## Ownership split (user 2026-11-14)
- NPCs/crew behaviour (sandbox T7, foot IK/stumbles T10, helm/violin/crew poses, character assets) are owned by the
  USER in a separate session. This feature's agents must not modify crew/NPC code or assets; they expose an
  "Integration API for NPCs" (deck query, ship motion signals, WorldState, rudder/heading) documented in README.
- This feature owns: ocean, horizon, water shading, wake/spray, cloth sails+flags+wind, sky/light, physics ship,
  lashed boat, ambient "living wallpaper" mechanics, QA.

## Phase 2 — Realism pass (user 2026-11-14: "lo más realista posible")
Research: odd/research/realism-techniques.md (sources + top 10). Reference frames: refs/reference_krautdev/ref_*.jpg (from the KrautDev video). Every task closes with a
side-by-side capture at fixed camera presets vs. the matching reference frame + an objective check.
Order is priority; runnable main at all times (agent works on a branch/worktree, user runs the stable worktree).

- [ ] R0 Ocean defects (BLOCKER): no black cracks/slits (clipmap seams: stitching/skirts + displacement
      geomorph across rings; hull mask strictly inside the hull) and no sparkly white crest streaks (FFT texture
      mipmaps/anisotropic filtering, distance/variance-based roughness, specular clamp). Check: 0 holes in a
      360° horizon sweep at 3 sea states.
- [ ] R1 Infinite horizon: ocean reaches the horizon seamlessly (far ring/skirt to the horizon line, distance
      fog/aerial perspective matching the sky colour, no visible tiling — non-integer cascade ratios + detail
      noise). Check: horizon sweep captures, no repeat pattern visible at 3 heights.
- [ ] R2 Physically based water shading: sky/environment reflection with Fresnel (SSR + sky fallback),
      subsurface scattering through wave crests (sun behind waves glows teal), depth/absorption colour,
      calibrated sun glitter, realistic foam (patchy whitecaps from accumulated Jacobian with decay, lacy
      textured foam, no artificial white lines), turquoise shallows like ref_3s. Check vs ref_3s/ref_12s.
- [ ] R3 Wake & spray realism: wake from the same foam accumulation (Kelvin wake ~19.5° arms, turbulent
      centre), bow wave and spray tied to hull/water relative speed; no ribbon artifacts. Check vs ref_12s.
- [ ] R4 Cloth realism (sails + flags, one WindField): flags tied at the 2 hoist corners only, correct mass
      and gravity (hang fully in calm, droop in light wind, stream in strong wind), drag/lift aero, enough
      substeps; sails as the same cloth pinned to yards with sheets; forces feed T8 propulsion. Check: calm /
      moderate / storm captures + gust timeline log.
- [ ] R5 Sky, light & atmosphere: volumetric or high-quality layered clouds, sun/sky/fog consistent per
      time of day and weather, auto-exposure, SSAO/SSIL where affordable, crisp ship shadows, storm darkness
      and rain like ref_15s/ref_18s.
- [ ] R6 Physics ship (T8/T8b) and crew physics (T10) as already specified.
- [ ] R8 Ambient life (watchability): gull/albatross boids, dolphins at the bow, distant whale spouts, passing
      ships on the horizon (lights at night), lighthouse with rotating beam on islands, night bioluminescence in the
      wake, visible wind gusts on the water (cat's paws), flotsam/seaweed, wet deck in rain, rainbow after storms,
      morning fog. See odd/research/realism-techniques.md.
- [ ] R7 Final QA: 10-minute unattended run (day→storm→night) recorded at fixed presets, fps >= 60,
      no visual defects checklist (cracks, popping, floating crew, clipping, keel visible).

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
- T1b (2026-11-14): wake_ribbon.gd builds 3 ribbons (stern wake 26 s, two bow lines 9 s) from the ship's path history; wake_ribbon.gdshader snaps them to the FFT surface and draws stretched-noise streaks/lace that break up with age. Spray = capsule droplets aligned to velocity (1400) + 120 faint mist sprites. Camera clearance uses max surface over the camera column, a ring and points ahead along the view, margin 1.0+1.6*sea_state, asymmetric low-pass. Evidence: captures shot_02 (wake from above), shot_04 (storm bow spray, low shot above crest), 0 errors, jitter shot 1: 2.0 m/s peak speed.
- T4 (2026-11-14): `WorldState` autoload (day 720 s, weather clear->cloudy->storm->cloudy, noise-drifting wind, sea_state 0.16..~0.95); `Ship.rudder_cmd -> rudder` (smoothed, rate 0.45/s) -> yaw rate (5.5 deg/s at full rudder, turn heel); `Autopilot` picks island waypoints, passes them with 150 m clearance, avoids islands, tacks at +-48 deg from the wind with a 140 m corridor, speed follows point of sail and wind. Islands now spawn along the ship's heading and recycle by distance. Sky shader: gradient, dusk, stars, moon, fbm clouds, overcast, lightning; sun/moon lights, fog and ambient follow WorldState; rain curtain + lightning in storms; Canto dims at the horizon, vanishes at night, veiled by clouds/storm. Evidence (godot/_shots/proof_*.png and scratch captures): night with stars, storm with rain, lightning flash, `--timescale=45` day->night storm and day storm; `--autopilot-log` runs: island legs (rudder -0.5..0.3, speed 5.1..7.8 with wind), beating with `tacking=true` and rudder -1.0 on tack; 0 script errors. Limits: lightning sound/shadows none; the moon only appears when in view; tack timing is simple (corridor-based).
- T5 Godot side (2026-11-14): `helm.gd` removes the baked wheel triangles from the hull mesh (box cut) and builds a procedural wheel (radius 0.62, hub y 5.3) that turns with `Ship.rudder` (2.3 rad per unit); two hand targets grab handles hand-over-hand. `crew_rig.gd` adds a `CrewPoseModifier` (SkeletonModifier3D) to every character: world-axis counter-lean against roll/pitch, lean into turns, head look toward the turn (Fuego), brace crouch on hard motion; Fuego gets two TwoBoneIK3D arms (hands on the handles, elbow poles); Don Omar (seated on the procedural barrel) gets `violin.gd`: violin held under the chin in a skeleton-derived character frame, left hand on the neck, right hand bowing back and forth (TwoBoneIK3D), bow prop on the right grip. Evidence: godot/_shots/proof_helm.png, proof_helm_storm.png (hands on wheel while turning, `--rudder-test`), proof_violin.png; IK hand error 0.0-0.05 m in normal use (up to ~0.3 m only under the exaggerated +-1 rudder test); 0 script errors, jitter test unchanged. Limits: hull-specific constants (wheel_pos, cut_box, grip) must be retuned for the new hull (T2/T3); Diagnostica and Salchipapa only get the counter-lean layer; wheel handles are not shown rotating the hand orientation (hands are position-IK only).
- T5 stabilisation (2026-11-14): arms went wild because IK targets could be at/over full arm reach (undefined elbow plane), hand targets snapped on regrab, and the idle clip drove arm/head bones. Fixes: IK targets go through reach-clamped proxies (93% of arm length), hand targets glide with a 0.9 m/s speed limit, `CrewPoseModifier` resets spine/neck/head/shoulders/arms to rest every frame (no accumulation, idle cannot make Fuego look back), head yaw clamped to +-25 deg, wheel turns 3.6 rad per unit rudder. Measured max arm-bone angular speed (`--debug-rig`, 21 s with `--plan=crew`): Fuego 284-706 deg/s peak (was 4000-11000), Omar 71-264 deg/s. Night mountains were already dark in captures (proof_night.png); lightning is now a jagged branching bolt ribbon (proof_lightning.png). `ship_wheel.glb` is auto-mounted by helm.gd when it exists (axle auto-detected).
- Polish (2026-11-14): hull foam now uses a baked waterline half-width profile (48 bins bow->stern, vertices within y -0.7..0.9 of the waterline) and a distance-to-outline band (thin, lace-broken, wider only at the bow when fast; bow ribbons thinner with fade-in). Animation smoothness: modifiers/IK fade in over 1.2 s, `CrewSlot.change_clip()` crossfades 0.35 s (default blend time set), skinned meshes get a large cull margin. Retarget feasibility probe on the 4 GLBs: identical 24-bone names, identical track path scheme (`Armature/Skeleton3D:<bone>`), similar A-pose rest rotations, proportions differ (hips-head 38-54 cm) so rotation tracks can be shared; only Hips position tracks need scaling by hip-height ratio; Godot 4.7 `RetargetModifier3D` exists as a fallback.
- T3 (2026-11-14): `export_pinnace.py` (Blender CLI) converts the Poly Haven pinnace FBX to `godot/assets/ship/pinnace/barco_pinnace.glb` (76 MB, 985-bone armature kept). Finding: the FBX stores the deployed sails (`*_down`, hidden objects) with mesh data local to the object origin and a parent-inverse that collapses them at the world origin; the export bakes `matrix_basis` into those meshes so they land on their yards. Loader: real scale (39.8 m incl. bowsprit, `ship_scale_override=1`), bow auto-detected -> -Z, waterline 33% of hull depth. `pinnace_rig.gd`: shows `*_down` sails (12 cloth meshes) and hides the furled `*_top` bundles and duplicate rigging; `sail_cloth.gdshader` is a wind-driven cloth (pinned at the yard and lower corners, billow along ship-z, ripple, luff, furl) driven by the apparent wind (true wind minus ship velocity) and WorldState (gusts, storm); sails furl when storm > 0.86. Rudder bone `def_rudder` follows `Ship.rudder` (+-28 deg). `flag.gd`: verlet cloth flag (17x10) pinned to the stern staff tip, driven by the apparent wind, procedural black pirate flag with shield and crown. The ship's boat IS present (on the waist booms, amidships near the main mast). Crew re-placed with exact ship-local positions (`use_fixed_position`): Fuego on the poop deck behind the mounted `ship_wheel.glb` (hub (0,7.6,16.6)), Diagnostica on the forecastle near the foremast, Salchipapa at the bow, Omar seated on barrels in the waist; deck map from `--debug-deck`. Camera shots scale with ship length. Old barco/barco_hull stay in assets (not loaded). Attribution in ATTRIBUTION.md. Limits: yard bracing (bones) not implemented (sails billow in ship space instead); rope sway not implemented; helm/crew constants are for this hull.
- T3b (2026-11-14): hull volume baked from hull/deck/aft/interior meshes as a W(z, height) = max |x| table in the ship pivot frame; the ocean shader transforms each fragment into pivot space with the full pose (yaw, pitch, roll, heave) and discards fragments inside the cross-section, so no water renders inside the hull or on the waist deck, even at sea_state 0.9 (captures). Heave/rotate smoothing slowed for the 40 m ship.
- Crew grounding (2026-11-14): every slot now snaps to the real deck with a downward raycast against deck/aft meshes (ray from ref+2.5 m to ref-6 m, tolerance 1.2 m), not hard-coded heights. Don Omar: the seat is measured from the sit clip itself (Hips vs soles/toes sampled at clip start): soles on the snapped deck, pelvis centred on a barrel stack whose top is the measured seat height (0.56 m at his scale), re-done on every `ship_ready`, so it follows ship changes (the earlier float came from placing the feet-origin on top of the barrels). Capture: godot/_shots/omar_calm.png (contact, no gap). Shared clips: `assets/anim/crew_shared.res` (walk, climb_stairs, talk, loop-linear) built from `assets/anim_src/*.glb` (24 tracks each, Hips position + 23 rotations, identical paths on all 4 characters); `CrewAnim.install()` copies it into each character's AnimationPlayer as library `shared` with the Hips position scaled by the hip-height ratio; `CrewSlot.play_shared("walk")` crossfades 0.35 s. Verified: Diagnostica plays shared/walk with correct proportions (`--test-clip=walk`, `diagnostica_walk_retarget.png`). anim_src GLB meshes are not instanced in the scene.
- Flag + camera (2026-11-14): flag uses `assets/ship/flag_pirat.png` (UV crop removes the thin margin; cloth 4.0 x 2.7 m = the image aspect), procedural flag kept as fallback. Jitter test now measures camera motion in the ship's yaw frame (a turning ship legitimately swings the camera around it in world space; the old metric reported 4 m/s of that). With the 40 m ship: calm shots 0.4-0.9 m/s (was 3.9-4.2 in world-frame terms); drift rate scales down with ship size, wave-envelope clearance is low-passed (0.45 s) with a sea-state margin. Storm low shot still 3.1 m/s: it follows 4 m swells by design. Omar re-seated with the no-violin GLB (pelvis 0.68 m above soles, 0.59 m seat, no gap).
- Ship motion (2026-11-14): roll and pitch are now damped harmonic oscillators in `buoyancy.gd` (natural periods `roll_period` 10 s / `pitch_period` 6 s, damping ratios 0.1 / 0.12, mild cubic stiffening, clamps 25 / 12 deg) driven by wave slope from the FFT samples (gain 0.12), a swell forcing near-resonant whose amplitude grows with sea_state, wind heel with gusts, turn heel and low-frequency noise. 70 s logs (`--autopilot-log=70 --log-period=0.25`, `[motion]` summary): sea 0.2: roll +-3.9 deg, T 9.4 s, pitch +-2.7 deg, T 6.5 s; sea 0.5: roll +-8.7 deg, T 11.6 s, pitch +-5.0, T 5.9; sea 0.9: roll +-18.3 deg (peak 19.2), T 9.0 s, pitch +-8.4, T 6.0. Camera shots captain/deck crew/helm/violin/close-ups are attached to the full pivot frame (horizon tilts with the roll), all others use the yaw frame and watch the ship rock. Sails and flag add the mast/staff velocity from roll/pitch rate to the apparent wind (flutter grows with motion); crew lean uses roll rate (inertia) and brace uses it too. Captures: roll_extreme_worldframe.png, roll_extreme_attached_captain.png (`--roll-extreme=13`).
- T9 flags (2026-11-14): `flag.gd` rewritten. Hoist line derived from the POSED pole: `ModelUtil.posed_points()` CPU-skins the staff/mast mesh with the rig, principal axis by power iteration, tip = higher end; every hoist row is pinned ON that line (7 cm off the axis), re-evaluated each frame from the pivot transform (stays attached under yaw/roll/heave). Cloth simulated in world space (12x7 verlet, 4 substeps x 8 iterations, rebase-aware), forced by TRUE wind minus particle velocity (equivalent to apparent wind because the pinned hoist moves with the ship), same WorldState wind field the sails use, travelling hoist->fly ripples, gusts, gravity droop only in calm, double-sided with per-frame normals. Second flag (same texture, 3.1 x 1.8 m) at the main-mast truck. Wind scale raised (6 + 22*strength m/s) so apparent wind is meaningful. Debug: `--debug-pins` (magenta spheres), `--log-wind` ([wind] true/apparent/fly vector), camera shots 15/16 (side views of each flag). Evidence: _shots/flag_stern_calm.png, flag_main_storm.png (+ calm/storm pairs); log at wind -60 deg: true (5.6,-9.7) m/s, ship fwd (-0.93,-0.37), apparent (9.9,-8.2) |12.9| m/s, flag EMA fly (3.6,-0.7,-0.2), ~30 deg from the apparent direction (hoist and gravity bias it). Known: flags flutter strongly during fast turns.

## Next step
T2 + T5 asset generation (inline); then T3 / T4.
