# Proposal: Living Sea Roadmap (finish the infinite realistic living wallpaper)

## Intent

The Godot scene (`godot/`) is close to a realistic, infinite, unattended "living wallpaper": FFT ocean with seamless
horizon (R0/R1), rigid-body physics ship (T8), XPBD cloth sails and flags on one WindField (R4/T9/T9b), NPC-gated
lanterns (R9) and a lashed boat are done. What remains is partial or pending and spread across several worktrees:
water shading (R2), wake/spray (R3), sky/light/weather (R5), ambient life (R8), physics leftovers (R6), final QA (R7),
plus stale docs and an uncommitted sky work-in-progress. Without one ordered plan, parallel agents collide on shared
files (`ocean`, `wake`, `sky`, `world_state`), the frame budget erodes (78 fps soak before SSR/clouds/SSAO), and
"done" stays undefined.

This roadmap defines milestones M0–M6, each delivered as its own SDD change and single PR, so the scene reaches the
feature acceptance criteria in `odd/tasks/living-sea-wallpaper.md` (realistic sea, wake, spray, no water in the hull,
unattended day/weather cycle for hours, zero script errors, >= 60 fps) while main stays runnable at every step.

Success: an unattended 10-minute day -> storm -> night run at 1920x1080 on Apple Silicon holds >= 60 fps, shows no
defect from the R7 checklist at fixed capture presets, and logs zero Godot script errors.

## Scope

### In Scope
- Milestones M0–M6 (below), each one SDD change -> one PR <= 400 authored changed lines (M2 and M4 split into slices,
  each slice its own change/PR).
- A frame-time budget per milestone and quality tiers (pending decision 1).
- Documented NPC integration points (hooks only) in `godot/README.md`.
- Rollout and parallelisation rules (max 2 concurrent agents, worktree per agent, testsem for every Godot run).

### Out of Scope
- NPC / crew behaviour and assets: T7 sandbox crew, T10 foot IK / stumbles, helm/violin/crew poses, `crew_*.gd`
  (owned by the user's separate session). This roadmap only exposes or documents hooks.
- Hair/clothing physics; user-interaction gameplay; new paid Higgsfield generation (beyond the existing reserve).
- Hull or draft remodelling for keel targets (see decision 3).
- Any change to the `stable` worktree, which the user tests from.

## Capabilities

`openspec/specs/` is empty, so all capabilities are new. Each milestone change writes only the specs it touches.

### New Capabilities
- `ocean-water-shading`: Fresnel sky reflection (SSR + sky fallback), crest SSS, far-field normal filtering, island caustics (M2a, M2d).
- `ship-wake-spray`: advected rebase-safe wake texture, bow wave by relative speed, Kelvin arms, spray (M2b, M2c).
- `physics-ship-wind-coupling`: ship propulsion from `SailRig.get_sail_forces()` / WindField, settled start-up, heel-aware hull foam (M1).
- `sky-light-weather`: clouds, sun/sky/fog consistency, exposure, SSAO/SSIL, shadows, rain, camera/island polish (M3).
- `ambient-life`: boids, dolphins, whale, passing ships, lighthouse, bioluminescence, cat's paws, optional extras (M4).
- `ship-physics-refinements`: keel-end lift, boat rope sag, boat -> ship load, optional dynamic draft (M5).
- `living-wallpaper-qa`: capture presets, fps budget, unattended run and defect checklist as the regression suite (M0 baseline, M6 final).
- `npc-integration-api`: documented hooks the NPC session consumes (cross-cutting).

### Modified Capabilities
- None (no existing specs).

## Approach

Approach A from the exploration: one SDD change per milestone (or slice), single PR each <= 400 authored lines,
merged to main in dependency order; main always runnable. Rejected: B (one mega-change: breaks the review budget
and causes agent conflicts) and C (per ODD task: ignores shared dependencies such as the wake/ocean shaders).

Conventions for every milestone:
- One worktree per agent under `el-terraria-blender-worktrees/`; never edit `stable`.
- Every Godot run through `~/.claude/bin/testsem` with `open -g` (focus-free), batched captures.
- Verification is functional (no unit runner): `--capture` at fixed presets vs the matching `refs/reference_krautdev`
  frame, `--jitter-test`, `--autopilot-log`, `--rebase-test=N` where water/wake is touched, zero script errors in
  `godot/_shots/godot.log`, frame time against the milestone budget. Evidence under `odd/evidence/<milestone>/`.
- Every milestone updates `odd/tasks/living-sea-wallpaper.md` checkboxes/evidence and `godot/README.md` where APIs change.

### Milestones

#### M0 Housekeeping and baseline (effort S)
- Intent: start from a clean, truthful state and a measured baseline.
- In: sync ODD checkboxes (T8, T8b, R9, R6, R2, R3) and `godot/README.md` (FFT not Gerstner, pinnace not galleon,
  physics-ship/boat hooks in the Integration API); commit or park the uncommitted `sky-ambient` R5 work on its branch;
  define fixed capture presets (day calm, dusk moderate, storm, night) and a frame-time measurement at 1920x1080;
  prune merged branches/worktrees only with explicit user OK (decision 5).
- Out: any behaviour change.
- Depends on: nothing.
- Acceptance: README and ODD doc match the code; baseline frame time at 1920x1080 recorded per preset; captures of
  all presets; 0 script errors; no branch/worktree removed without recorded user OK; `stable` untouched.
- Risks: losing uncommitted sky work (mitigation: commit to its own branch before anything else).

#### M1 Ship on WindField + settled start-up (effort M)
- Intent: one wind model for cloth AND propulsion; no start-up glitch.
- In: replace `sail_force_local` + WorldState wind with `SailRig.get_sail_forces()` / `WindField.sample`; settled
  start-up (pre-roll/initial equilibrium so the underside never shows); hull foam footprint follows heel.
- Out: sail/flag solver changes; autopilot strategy changes beyond retuning.
- Depends on: M0.
- Budget: <= 0.3 ms.
- Acceptance: `--autopilot-log=120` at sea 0.2/0.5/0.9 shows speed/roll/pitch in the same ranges as the T8 log and
  gust-correlated thrust; first 10 s captures show no exposed underside; heeled top-down capture shows foam on the
  hull outline; `--jitter-test` not worse than baseline; 0 script errors.
- Risks: force scale mismatch between cloth pressure and the old model (retune, keep a fallback flag);
  backed-sail edge cases.

#### M2 Water and wake finish (effort L, 4 slices)
- M2a (M): far-field normal mips (speckle), SSR with sky fallback, crest SSS validated with the sun behind waves.
  Budget <= 1.5 ms (SSR is tier-gated). Acceptance: horizon captures without speckle; sun-behind-waves capture shows
  teal crest glow vs ref_12s; dusk reflection matches sky.
- M2b (L, largest risk): advected ping-pong wake texture following the ship, bow wave by hull/water relative speed,
  Kelvin arms (~19.5 deg), turbulent centre, replaces stern ribbon "scales", survives the 1600 m rebase.
  Budget <= 1.0 ms. Acceptance: top-down capture vs ref_12s; `--rebase-test=150` wake continuous across rebase;
  no ribbon artifacts. Depends on M1 (relative speed, heel).
- M2c (S–M): spray rework (emission ~ speed^2 and slamming). Budget <= 0.5 ms. Depends on M2b.
- M2d (S): island shallows caustics. Budget <= 0.3 ms. Independent.
- Out: new ocean simulation; clipmap topology.
- Risks: shared `ocean_fft.gdshader`/wake files; SSR cost; rebase continuity.

#### M3 Sky, light and weather R5 + T6 polish (effort L, may split)
- Intent: sky that matches ref_15s/ref_18s across the day and weather cycle.
- In: clouds (decision 2), sun/sky/fog/ambient consistency per time of day and weather, auto-exposure, SSAO/SSIL where
  affordable, crisp ship shadows, storm darkness and rain; T6 camera (Canto unoccluded, close-ups, helm/storm shots)
  and island polish (decision 6).
- Out: weather cycle logic rewrite.
- Depends on: M0 (sky WIP committed); can follow M2a (reflection uses sky).
- Budget: clouds <= 2.5 ms, SSAO/SSIL + shadows <= 1.0 ms.
- Acceptance: preset captures at dawn/day/dusk/night × clear/storm vs references; no exposure pumping in a
  `--timescale` day run; 0 script errors.
- Risks: biggest perf risk; addon compatibility with 4.7.2.

#### M4 Ambient life R8 (effort L, 3+ slices)
- M4a: gull/albatross boids, dolphins at the bow, distant whale spouts.
- M4b: passing ships with night lights, lighthouse with rotating beam, wake bioluminescence at night (needs M2b).
- M4c: cat's paws on the water (WindField gusts), flotsam/seaweed, wet deck in rain, rainbow after storms, morning fog.
- Must-have set per decision 4; the rest optional.
- Budget: <= 1.5 ms total across M4.
- Acceptance: each element visible in its preset capture; spawn/recycle stable over a 10-min run (no unbounded node
  count); 0 script errors.
- Risks: scope creep; node-count growth; overlap with NPC session (none expected: no crew code).

#### M5 Physics leftovers R6 (effort S–M)
- In: keel-end lift tuning (decision 3), boat rope sag, boat -> ship reaction load, optional dynamic draft.
- Out: hull/draft geometry edits.
- Budget: <= 0.2 ms.
- Acceptance: `[keel]` summary at sea 0.5/0.9 reported vs interim and stretch targets; `--log-boat` play <= 5 cm,
  never leaves the cradle; roll/pitch ranges not worse than T8.
- Risks: keel targets unreachable without hull changes.

#### M6 Final QA R7 (effort M)
- In: 360° horizon sweep × 3 sea states, 10-minute unattended day -> storm -> night at fixed presets, defect checklist
  (cracks, popping, floating crew, clipping, keel visible, water in hull), fps report, final T6 polish fixes found
  by QA, docs final.
- Depends on: M1–M5.
- Acceptance: >= 60 fps (1% low reported) at 1920x1080 at the agreed tier; checklist all clear or each residual
  recorded and accepted by the user; 0 script errors over the run.

### Performance budget

- Target: >= 60 fps (<= 16.7 ms frame) on Apple Silicon at 1920x1080, Forward+, vsync off for measurement.
- Known baseline: 78 fps soak (12.9 ms) at 1280x720 with cloth; M0 must re-measure at 1920x1080 because headroom
  there is unknown and may already be tight.
- Per-milestone increments over the M0 baseline: M1 0.3, M2a 1.5, M2b 1.0, M2c 0.5, M2d 0.3, M3 3.5, M4 1.5,
  M5 0.2 ms (sum ~8.8 ms). If the M0 baseline plus this sum exceeds 16.7 ms, quality tiers apply (decision 1): the
  tier may drop SSR to sky-only reflection, lower cloud resolution/steps or disable clouds, and reduce SSAO/SSIL.
- Each PR reports measured frame time per preset; a PR exceeding its increment needs a tier fallback or user OK.

### NPC integration points (cross-cutting)

NPC behaviour is out of scope; this roadmap only keeps these hooks stable and documented in `godot/README.md`:
- Existing: `ShipLights` (get_lanterns, light, extinguish, is_lit; signals lighting_needed, extinguish_suggested,
  lantern_changed); Ship (roll, pitch, rates, yaw, yaw_rate, rudder, forward, current_speed, linear_velocity);
  WorldState (daylight, night, storm, cloud, wind_vector, wind_speed_ms, sun_elevation_deg); deck raycast.
- To add (read-only, signal/getter only): sail state summary (M1), boat state (M5), ship-wobble signal (M1),
  deck wetness (M4c).
- Rule: no edits to `crew_*.gd` or character assets; any breaking hook change is announced in the README changelog.

### Rollout and parallelisation

- Max 2 concurrent agents (testsem has 2 slots machine-wide); each in its own worktree and branch, one SDD change each.
- Merge order follows dependencies: M0 -> M1 -> M2b -> M2c; M2a/M2d after M0; M3 after M0 (preferably after M2a);
  M4a/M4c after M0; M4b after M2b; M5 after M1; M6 last.
- Safe pairs: M0/M1 with M2a or M2d (not M2b); M3 with M5; M4a with M2b. Never two agents on the same shared file
  set (`ocean_fft.gdshader`, wake, sky, `world_state.gd`) at once; the second rebases after the first merges.
- Delivery: single-pr per change; the 400-line budget is a planning heuristic; a slice that naturally exceeds it is
  explained in its PR.

## Decisions

### Confirmed by the user (2026-11-14)
1. QUALITY PRESETS replace the single 60 fps floor: a low `dev` preset used for all development and agent
   tests/captures (reduced render scale, 30 fps cap, no SSR/SSAO/SSIL/volumetrics, fewer ocean rings/FFT res,
   halved cloth iterations, fewer particles) to keep the machine responsive, and a `final` preset for the
   shipped wallpaper with graphics "much better" than today (full quality and room for SSR, volumetric clouds,
   higher FFT resolution, soft shadows, TAA/FSR2). Centralised in a `quality.gd` autoload read by every system.
   Performance budgets apply per preset (dev: smooth on the dev Mac under load; final: target 60 fps at
   1920x1080 on Apple Silicon, scaling features rather than dropping them).

### Pending user confirmation (defaults proposed, not assumed accepted)
1. (superseded by the confirmed quality-preset decision above)
2. R5 clouds: custom layered shader vs Sunshine Clouds 2 addon. Proposed default: try the addon behind a gate
   (works on Godot 4.7.2 and costs <= 2.5 ms at 1920x1080), otherwise fall back to a custom layered shader.
3. Keel ends target. Proposed default: accept the current 1.1 m (sea 0.5) / 2.3 m (sea 0.9) as interim; keep
   0.5 / 1.5 m as an M5 stretch goal without hull/draft edits.
4. R8 must-haves for "done". Proposed default: boids, dolphins, passing ships with lights, lighthouse beam,
   bioluminescence, cat's paws; whale, flotsam, wet deck, rainbow, morning fog optional.
5. Deleting merged branches/worktrees in M0. Proposed default: require explicit user OK at M0 time; never delete
   `stable`.
6. T6 camera/island polish included. Proposed default: yes, in M3 with leftovers in M6.

Dependent work: decision 1 gates the M2a/M3 tier design; 2 gates M3 cloud tasks; 3 gates M5 acceptance; 4 gates
M4 slice scope; 5 gates the M0 pruning step only; 6 gates the T6 part of M3. All other work can proceed.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `godot/scripts/buoyancy.gd`, sail rig / `wind_field.gd` consumers | Modified | M1 propulsion from cloth forces, start-up, M5 keel/boat load |
| `godot/shaders/ocean_fft.gdshader`, ocean scripts | Modified | M2a shading, M2d caustics, hull foam under heel (M1) |
| `godot/scripts/wake_ribbon.gd`, wake/spray shaders | Modified/Replaced | M2b advected wake, M2c spray |
| sky shader, `world_state.gd` consumers, environment | Modified | M3 clouds, light, exposure, rain |
| new ambient scripts (`godot/scripts/ambient/*`), `gulls.gd` | New/Modified | M4 ambient life |
| `godot/scripts/lashed_boat.gd` | Modified | M5 rope sag, reaction load |
| camera shots, `islands.gd` | Modified | T6 polish (M3/M6) |
| `godot/README.md`, `odd/tasks/living-sea-wallpaper.md`, `odd/evidence/*` | Modified/New | docs, NPC hooks, evidence |
| `crew_*.gd`, character assets | Not touched | owned by the NPC session |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Frame budget exhausted at 1920x1080 (baseline measured only at 720p) | High | M0 re-measures; per-milestone ms budget; quality tiers (decision 1) |
| Shared-file conflicts between parallel agents | Med | Max 2 agents, never same shared file set, merge order by dependency |
| Advected wake breaks across the 1600 m rebase | Med | Shift the wake window with `cascade_shift`; `--rebase-test` in M2b acceptance |
| Clouds addon incompatible with 4.7.2 or too costly | Med | Gate + custom shader fallback (decision 2) |
| Keel targets unreachable without hull/draft edits | Med | Interim targets (decision 3) |
| Uncommitted sky WIP lost | Med | Commit to its own branch first in M0 |
| No automated tests; regressions slip | Med | Fixed capture presets + logs as regression suite, every PR |
| Cloth/force scale mismatch in M1 | Med | Retune with logs; keep legacy force path behind a flag until M6 |
| Scope creep in M4 | Med | Must-have list (decision 4), the rest optional |

## Rollback Plan

Each milestone/slice is a single PR merged to main; rollback = revert that merge commit, which leaves main runnable
because every PR is self-contained and verified. New render features (SSR, clouds, SSAO/SSIL, ambient elements) sit
behind quality-tier or feature flags so they can be disabled without a revert. M1 keeps the legacy sail-force path
behind a flag until M6. The `stable` worktree is never modified, so the user always has a known-good scene.

## Dependencies

- Godot 4.7.2 Forward+ with Jolt; `~/.claude/bin/testsem` (2 slots).
- Reference frames in `refs/reference_krautdev/`; research in `odd/research/realism-techniques.md`.
- Optional: Sunshine Clouds 2 (MIT) if decision 2 accepts the gate; license recorded in `ATTRIBUTION.md`.
- User answers to the six pending decisions for the dependent parts.

## Success Criteria

- [ ] M0–M6 merged to main in dependency order, each PR with capture/log evidence and 0 script errors.
- [ ] 10-minute unattended day -> storm -> night run at 1920x1080: >= 60 fps (at the agreed tier), 0 script errors.
- [ ] R7 defect checklist clear (or residuals accepted by the user) across a 360° sweep at 3 sea states.
- [ ] Wake continuous across rebase; no water inside the hull; keel ends within the agreed target.
- [ ] Agreed R8 must-haves visible in their presets.
- [ ] `godot/README.md` NPC integration API and `odd/tasks/living-sea-wallpaper.md` match the code.
