# Exploration: living-sea-roadmap

Main at b259196. Worktrees: stable (user tests), cloth-wind, ocean, sky-ambient (uncommitted R5 work in progress).

## Done
R0 seams/streaks; R1 horizon (11 rings, 211/79/23 m cascades, exact rebase); T8 rigid-body ship (column hydrostatics,
hydrofoil rudder, sail forces, yard bracing); keel fix (midship never visible; ends 1.1 m @0.5, 2.3 m @0.9 vs targets
0.5/1.5); R9 NPC-gated lanterns (ShipLights API); lashed boat (RigidBody3D, 5 cm max play); R4/T9/T9b XPBD cloth +
WindField + get_sail_forces() (cloth 0.2 ms; soak 78–97 fps); T1/T1b/T3/T3b/T4/T5/T6b.

## Partial
- R2: missing SSR, crest SSS validation (sun behind waves), island caustics, far-field speckle (normal mips).
- R3: missing advected ping-pong wake texture, bow wave by relative speed, stern ribbon "scales", spray rework,
  wake cleared on each 1600 m rebase.

## Pending
Ship still uses its own sail_force_local + WorldState wind (not get_sail_forces/WindField); start-up heel transient
shows the underside; hull foam footprint ignores heel; R5 sky/clouds/light; R8 ambient life (only gulls.gd);
R6 leftovers (keel ends, boat→ship load); R7 final QA. Docs stale: ODD checkboxes (T8, T8b, R9, R6, R2, R3) and
godot/README.md ("galleon, Gerstner"; Integration API lacks physics-ship/boat hooks).

## NPC integration points (README)
ShipLights get_lanterns/light/extinguish/is_lit + lighting_needed/extinguish_suggested/lantern_changed;
Ship roll/pitch/rates/yaw/yaw_rate/rudder/forward/current_speed/linear_velocity; WorldState daylight/night/storm/
cloud/wind_vector/wind_speed_ms/sun_elevation_deg; deck raycast. To add: sail state summary, boat state,
ship-wobble signal, deck wetness.

## Approaches
A (recommended): one SDD change per milestone, single PR each ≤400 lines, runnable main.
B: one mega-change (breaks budget, agent conflicts). C: per ODD task (ignores shared dependencies).

## Milestones (dependency order, effort)
M0 Housekeeping (S): sync ODD checkboxes + README, prune merged branches/worktrees (needs user OK), commit sky state.
M1 Ship uses WindField + get_sail_forces, settled start-up, heel-aware hull foam (M).
M2 Water/wake finish (L, 2–3 slices): a) far-field normal mips + SSR w/ sky fallback + crest SSS; b) advected wake
   texture + bow wave + Kelvin arms, rebase-safe (largest risk); c) spray rework; d) island caustics.
M3 Sky/light/weather R5 (L): clouds, sun/sky/fog consistency, exposure, SSAO/SSIL, shadows, rain (perf risk;
   addon only if 4.7 + cost verified). Fold T6 camera/island polish here.
M4 Ambient life R8 (L, 3+ slices): boids/dolphins/whale; passing ships + lighthouse + bioluminescence;
   cat's paws/flotsam/wet deck/rainbow/fog.
M5 Physics leftovers R6 (S–M): keel ends, boat rope sag, boat→ship load, optional dynamic draft.
M6 Final QA R7 (M): 360° sweep × 3 sea states, 60 fps, 10-min unattended day→storm→night, defect checklist.
M0/M1 can run parallel to M2a/M2d (not M2b).

## Risks
Perf headroom (78 fps soak before SSR/clouds/SSAO; give each milestone a 2–3 ms budget); shared-file conflicts
(ocean/wake/sky/world_state); wake rework + rebase; flag/sail edge cases; keel targets may need draft/hull change;
uncommitted sky work; no automated tests (fixed-camera capture presets are the regression suite).

## Open questions
1. Hard 60 fps floor with quality tiers allowed to drop SSR/clouds?
2. R5 clouds: custom layered shader vs vetted addon (Sunshine Clouds 2)?
3. Keel ends: accept 1.1/2.3 m or require 0.5/1.5 m (may need draft/hull edits)?
4. R8 must-haves for "done" (suggested: boids, dolphins, passing ships w/ lights, lighthouse, bioluminescence, cat's paws)?
5. May M0 delete merged branches/worktrees?
6. Include T6 camera/island polish (assumed yes, in M3/M6)?
