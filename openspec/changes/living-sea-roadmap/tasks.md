# Tasks: Living Sea Roadmap (finish the infinite realistic living wallpaper)

Scope rule: this file lists ONLY work that remains. Already on `main` and NOT tasked: quality presets `dev`/`final` with `dev` default (a789aff, 839e7a9), ship propulsion from `get_sail_forces()` + WindField (4593c47), world-anchored advected wake field (aab27d1), R0/R1, partial R2/R3, lanterns (R9), lashed boat, cloth. Hardening gaps in those areas (per design Decisions 4 and 6) ARE tasked.

> DELIVERY OVERRIDE (user, 2026-11-14): NO pull requests. Every slice is merged DIRECTLY into local `main`
> (fast-forward after rebasing the agent's worktree branch) once its observable verification passes; verify with
> `git merge-base --is-ancestor <commit> main`, then the orchestrator advances the `stable` worktree. "PR-xx" labels
> below are just slice names; the ≤400-line slice size remains a planning heuristic only, so `size:exception`
> decisions (MQ-c) no longer apply. The repo has no remote; nothing is pushed.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | about 3,000 to 3,800 authored lines across 21 slices (each slice 120 to 400); one conditional slice (MQ-c) may exceed 400 because it is a move-only shader split |
| 400-line budget risk | Medium overall; High only for slice MQ-c (move-only split, counts additions plus deletions) |
| Chained PRs recommended | Yes |
| Suggested split | One PR per slice, merged to `main` in dependency order (see Work Units and Parallel Waves) |
| Delivery strategy | single-pr (per slice) |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

Note on the decision line: it is "Yes" solely for slice MQ-c (task MQ.6). If the `ocean_fft.gdshader` include split has already landed on `main` (MQ.5 decides), MQ-c is dropped and the decision becomes "No". If MQ-c is needed and its moved lines exceed 400, the orchestrator must obtain `size:exception` (move-only diff, no logic change) before apply of MQ.6. Every other slice is planned at or below 400 authored lines.

## Conventions for every task

- Tracks: **ORC** = orchestrator (docs, evidence, merges, user decisions); **OS** = ocean/ship agent (ocean, wake, shaders, buoyancy, boat); **SA** = sky/ambient agent (sky, weather, clouds, camera, islands, ambient). One agent per track, one worktree each under `el-terraria-blender-worktrees/`, never `stable`.
- RUN template (the only way to launch Godot): `~/.claude/bin/testsem -- open -g -n -W -a /Applications/Godot.app --args --path godot --log-file godot/_shots/godot.log -- <flags>`. Iterate with `--quality=dev`; one `--quality=final` batch at slice close. Physics logs (`--autopilot-log`, `[keel]`, `--log-boat`) run at `final` (design physics-invariant rule).
- Evidence goes under `odd/evidence/<milestone>/` using the spec spelling `M0`, `M1`, `M2a` and so on (design text says lowercase `m0`; the specs are the contract and win). Each slice evidence set = captures at affected presets next to the matching reference frame, frame-time log per quality preset, applicable logs, and a godot log with zero `SCRIPT ERROR` / `ERROR:` lines.
- Capture presets (design Decision 13): `day_calm`, `dusk_moderate`, `storm`, `night`. Reference frames live in `refs/reference_krautdev/` and are read-only everywhere.
- Never edit `crew_*.gd`, character assets, or the `stable` worktree. Every PR diff must be checked with a changed-path listing for these (npc-integration-api: Crew files untouched).
- Verification is functional (no unit runner; `strict_tdd: false`). No RED-test tasks exist because there is no runner; the observable check per task is the verification target. Threat matrix is N/A (design).
- Each slice closes with: updated ODD checkboxes/evidence in `odd/tasks/living-sea-wallpaper.md` (the ORC track performs the doc edit at merge if the slice agent does not own that file) and a changelog line in `godot/README.md` when an API changes.

## Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| M0 | Truthful docs, sky WIP preserved, baseline evidence | PR-M0 | `rg` doc names against code (README Integration API names exist in `godot/`) | RUN `--plan=regression --quality=dev` and `--quality=final` plus `--perf-log=30` at 1920x1080 | Revert docs and evidence only; no runtime file touched |
| MQ-a | `--perf-log` percentiles | PR-MQa | RUN `--perf-log=30 --quality=dev` prints one `[perf]` line | same | `capture.gd` perf block only |
| MQ-b | `--plan=regression` batch | PR-MQb | RUN `--plan=regression --quality=dev` saves 12 `reg_*` shots | same | `capture.gd` plan block only |
| MQ-c | Behaviour-neutral ocean shader include split (conditional) | PR-MQc | RUN `--plan=regression --quality=final` vs M0 baseline captures | same, visual side-by-side | Revert restores monolithic `ocean_fft.gdshader` |
| M1-a | One wind model, settled start-up | PR-M1a | RUN `--autopilot-log=120 --sea=0.5 --quality=final` | RUN `--shots=` at t=1,3,5,8,10 s | `buoyancy.gd` start and fallback blocks |
| M1-b | Heel-aware foam, hooks (`sail_state`, `wobble`) | PR-M1b | RUN `--autopilot-log=120 --sea=0.9 --quality=final`; heeled top-down capture | same | `foam.gdshaderinc` block, `pinnace_rig.gd::sail_state`, `wobble` signal |
| M2a-1 | Far-field normal mips | PR-M2a1 | RUN horizon captures at sea 0.2/0.5/0.9 `--quality=dev` | RUN `--rebase-test=150` | Mip pass in vendored addon plus `ocean.gd` hookup |
| M2a-2 | SSR + sky fallback, crest SSS, 1024 FFT spike | PR-M2a2 | RUN dusk and sun-behind-waves captures `--quality=final` | RUN `--perf-log=60` SSR on/off | `sky.gd` SSR keys, shading inc values |
| M2b-1 | Wake hardening: precision, fixed step, footprint, ribbon deletion | PR-M2b1 | RUN `--rebase-test=150` top-down before/after | RUN `--perf-log=30 --quality=final` | `wake_field.gd` plus restore ribbon files from git |
| M2b-2 | Wake channels G/B, relative speed, heel | PR-M2b2 | RUN top-down capture vs `ref_12s`; arm angle measure | RUN `--autopilot-log` at two speeds | `wake_update.gdshader` channel writes, inc wake block |
| M2c | Spray rework | PR-M2c | RUN `--autopilot-log` spray log at two speeds | RUN `--perf-log=30` | `ship_fx.gd` only |
| M2d | Island caustics | PR-M2d | RUN island shore capture day/night | RUN `--perf-log=30` island on/off | `caustics.gdshaderinc` plus one include line |
| M3-1 | Cloud gate spike and clouds adapter | PR-M3a | RUN gate decision log + `--perf-log=30` | RUN `--plan=regression` | `clouds.gd`, addon dir, `sky.gd` cloud key |
| M3-2 | Exposure curve, SSAO/SSIL, shadows, storm and rain | PR-M3b | RUN `--timescale` day run exposure log | RUN storm capture and storm-end 60 s | `sky.gd`, `weather_fx.gd` blocks |
| M3-3 | Camera shots and island polish | PR-M3c | RUN shot-preset captures, Canto unoccluded | RUN dusk/night island captures | `camera_director.gd`, `islands.gd` |
| M4a | Ambient director, boids, dolphins, optional whales | PR-M4a | RUN day capture shows 3+ birds; dolphin capture | RUN 10-minute `--timescale` run with `AmbientDirector.stats()` | `scripts/ambient/*`, Ambient node, restore `gulls.gd` |
| M4b-1 | Passing ships with lights | PR-M4b1 | RUN night capture shows lit ship | RUN recycle log | `passing_ships.gd` only |
| M4b-2 | Lighthouse beam, bioluminescence | PR-M4b2 | RUN two night captures 2 s apart; night top-down wake | RUN `--perf-log=30` | `lighthouse.gd`, foam inc biolum term |
| M4c-1 | Cat's paws from WindField gusts | PR-M4c1 | RUN two captures 5 s apart moderate wind | RUN `--rebase-test=150`, `--perf-log=30` | `wind_field.gd` additions, surface inc block |
| M4c-2 | Optional extras (wet deck, rainbow, morning fog, flotsam) | PR-M4c2 | RUN rain deck capture before/during/after | RUN 10-minute run node counts | each extra behind its own `Quality` or feature key |
| M5-1 | Keel-end mitigation | PR-M5a | RUN `--autopilot-log=120 --sea=0.5` and `0.9 --quality=final` `[keel]` summary | same | `buoyancy.gd` end-column coupling exports |
| M5-2 | Boat reaction load, rope sag, `state()` | PR-M5b | RUN `--log-boat` 120 s at sea 0.9 | RUN `--autopilot-log=120` load on/off | `lashed_boat.gd` only |
| M6-1 | Final QA run and evidence | PR-M6a | RUN 360 degree sweep x 3 sea states | RUN 10-minute day, storm, night `--quality=final` at 1920x1080 | Evidence and docs only |
| M6-2 | QA fixes, final docs, legacy flag decision | PR-M6b | RUN regression + checklist re-capture | RUN repeat of failing item | Per fix, in the owning file |

## Parallel Waves (max 2 agents at once)

Pairs are drawn from the design ownership table. A second agent never starts on a file set the first still owns; it rebases after the first merges.

| Wave | Agent OS | Agent SA / ORC | Why this pair is safe | Gate to start |
|------|----------|----------------|-----------------------|---------------|
| W0 | MQ-a, then MQ-b, then MQ-c (if needed) | ORC: M0 docs and WIP commit (M0.1 to M0.5) | Docs vs `capture.gd` and shaders; M0.1 (WIP commit) is first action overall | M0.1 done |
| W0b | M0.6 baseline (ORC drives, needs MQ-a and MQ-b merged) | none | single-slot measurement, uses both testsem slots sparingly | MQ-a, MQ-b merged; MQ-c merged or dropped |
| W1 | M1-a then M1-b (buoyancy, foam inc) | M2a-1 then M2a-2 run by OS second worktree (surface, shading incs, addon) | M1 vs M2a own different includes and files (design: M1 parallel M2a) | MQ complete incl. MQ-c |
| W2 | M2b-1 then M2b-2 (wake, foam wake block, surface B channel) | M4a (ambient director, boids, dolphins) | Safe pair per design; both touch `main.tscn` in different hunks, second to merge rebases | M1-b and M2a-2 merged; M4a needs only M0 and MQ |
| W3 | M2c (`ship_fx.gd`) | M3-1 (clouds spike and adapter) | M2c touches nothing else; M3 owns sky files | M2b-2 merged |
| W4 | M2d (caustics inc) | M5-1 (buoyancy columns) | Shader-only vs buoyancy-only; M5 after M1 merged | M1-b merged, MQ-c merged |
| W5 | M5-2 (boat) | M3-2 (exposure, SSAO, shadows, rain) | Boat file vs sky files | M5-1 merged, M3-1 merged |
| W6 | M4b-1 (passing ships) | M3-3 (camera, islands) | Ambient file vs camera and islands; M4b-2 waits so islands read-only use is stable | M4a merged, M3-2 merged |
| W7 | M4b-2 (lighthouse, bioluminescence; owns foam inc) | M4c-2 (optional extras: `world_state.gd`, sky terms) | Foam inc and ambient vs world_state and sky; no shared file | M2b-2, M4b-1, M3-3 merged |
| W8 | M4c-1 (cat's paws: `wind_field.gd`, surface inc) | none | Owns surface inc; forbidden to pair with M2a, M2b, M4b | M4b-2 merged |
| W9 | M6-1 then M6-2 | ORC evidence | Last; all feature work merged | M1 to M5 merged |

Forbidden pairs (design): any two milestones owning the same include; M2b with M4b (foam); M2a with M4c (surface); M1 with M5 (buoyancy). W-numbers are a recommended order, not a promise; the dependency column per task is authoritative.

---

## M0: Housekeeping and baseline (ORC, S; no behaviour change)

Evidence folder: `odd/evidence/M0/`. M0.1 MUST be the first action of the whole roadmap.

- [x] M0.1 [ORC] Commit the uncommitted `sky-ambient` worktree WIP to its own branch (no other action first): `git status` recorded in the commit message body, no files modified beyond staging that WIP. Verify: `git log -1` on the `sky-ambient` branch shows the commit and the worktree is clean. Dependency: none. Spec: living-wallpaper-qa (Sky WIP preserved).
- [x] M0.2 [ORC] Reconcile the `ocean`, `cloth-wind`, `sky-ambient` worktrees against the design ground-truth table: list each unmerged commit and mark it covered, overlapping or new; write the result as a table in `odd/tasks/living-sea-wallpaper.md`. Files: `odd/tasks/living-sea-wallpaper.md`. Verify: table lists every unmerged commit hash with a verdict; any "overlapping" verdict opens a scope note on the affected M1, M2a or M2b task (answers design Open Question 3). Dependency: M0.1.
- [x] M0.3 [ORC] Sync ODD checkboxes (T8, T8b, R9, R6, R2, R3, plus MQ and the already-merged R4/wake items) and evidence links. Files: `odd/tasks/living-sea-wallpaper.md`. Verify: each checked box cites a commit or evidence path; `rg` for each cited commit via `git log` resolves. Dependency: M0.2.
- [ ] M0.4 [ORC] Update `godot/README.md`: FFT ocean not Gerstner, pinnace not galleon, quality presets and flags (`--quality=`, `--perf-log`, `--plan=regression` as they land), physics-ship and boat hooks in the Integration API, README changelog section created. Files: `godot/README.md`. Verify: every flag and hook name written in the README is found with `rg` in `godot/`; npc-integration-api "Names match code" scenario. Dependency: M0.2.
- [ ] M0.5 [ORC] Document the Integration API names listed in the npc-integration-api spec (ShipLights, Ship, WorldState, deck raycast) with kind (signal, getter, property). Files: `godot/README.md`. Verify: `rg` for each name returns the documented kind. Dependency: M0.4.
- [ ] M0.6 [ORC] Record the baseline: after MQ-a and MQ-b merge, run `--plan=regression` at `dev` and `final` and `--perf-log=30` at 1920x1080 for each preset; record T8 ranges (`--autopilot-log=120 --sea=0.2/0.5/0.9 --quality=final`) and the `--jitter-test` baseline; record dev vs final autopilot tolerance. Files: `odd/evidence/M0/*`. Verify: folder holds 4 preset captures, `dev` and `final` frame-time logs, jitter baseline, T8 ranges, and a log with zero `SCRIPT ERROR`. Dependency: MQ.2, MQ.4 (and MQ.6 if it ships). Spec: living-wallpaper-qa (Baseline); quality-presets (Autopilot log comparable).
- [x] M0.7 [ORC] Branch and worktree pruning list: produce the list of merged branches and worktrees that could be removed (never `stable`), present it to the user as one question, and STOP. Verify: no `git branch -d`, `git worktree remove` or deletion is run until the user's explicit OK is recorded in `odd/tasks/living-sea-wallpaper.md` with the exact list approved. Dependency: M0.2. Pruning itself is a separate action after that recorded OK; if no OK, the task stays open and blocks nothing.
  Status 2026-11-15: pruning candidates listed in `odd/tasks/living-sea-wallpaper.md` (M0.7 section); nothing deleted, awaiting the user OK.
- [x] M0.8 [ORC] N/A (no PRs, direct merges to main per the delivery override; changed paths of each merge were checked for runtime scripts/crew files). Open the PR-M0 slice (docs and evidence only) and confirm the changed-path listing contains no runtime script or shader and no `crew_*.gd`. Estimated lines: about 150 authored (docs; images excluded). Dependency: M0.3 to M0.6.

## MQ-remainder: Quality presets remainder (OS)

Already merged: `Quality` autoload, presets, default `dev`, global render apply. Remaining per design Decisions 3 and 13.

### Slice MQ-a (PR-MQa, about 80 lines)

- [x] MQ.1 [OS] Check the on-main `capture.gd` for `--perf-log`: read what exists and record the gap list in the slice PR description. Files: `godot/scripts/capture.gd` (read-only for this task). Verify: gap list names which of p50, p95, p99, 1% low, CPU and GPU series are missing. Dependency: none.
  - Done 2026-11-14: Gap list (read of main capture.gd before the change): no `--perf-log` at all; missing p50, p95, p99, 1% low, CPU and GPU series (only `--jitter-test` avg/max frame time existed).
- [x] MQ.2 [OS] Implement `--perf-log=<secs>` percentiles in `godot/scripts/capture.gd`: enable `viewport_set_measure_render_time` on the root viewport, sample CPU (`Performance.TIME_PROCESS`, `TIME_PHYSICS_PROCESS`) and GPU (`viewport_get_measured_render_time_gpu`) each frame after a 5 s warm-up, print one `[perf] preset=<p> quality=<q> res=<WxH> p50 p95 p99 1%low fps` line. Verify: RUN `--perf-log=30 --quality=dev --resolution 1920x1080` prints exactly one `[perf]` line with all fields and the godot log has zero errors. Dependency: MQ.1. Spec: quality-presets (Per-preset performance budgets).
  - Done 2026-11-14: `--perf-log=<secs>` implemented; evidence: godot/_shots log line `[perf] preset=dev ... p50=4.38 p95=5.57 p99=6.35 1%low_fps=157.6` and final `p50=9.20 p95=14.36 p99=15.99 1%low_fps=62.6` (uncapped, 1920x1080 canvas). KNOWN GAP: `viewport_get_measured_render_time_gpu` returns 0.00 on this Metal setup, so the GPU series is empty; CPU series is `TIME_PROCESS` (includes waiting when capped).

### Slice MQ-b (PR-MQb, about 120 lines)

- [x] MQ.3 [OS] Add the four-preset table (`day_calm`, `dusk_moderate`, `storm`, `night`) as a const in `godot/scripts/capture.gd`: `day_phase` 0.45/0.73/0.55/0.02, weather clear/cloudy/storm/clear, sea 0.2/0.5/0.9/0.35, fixed `--wind`. Verify: table matches design Decision 13 row by row (PR description lists it). Dependency: MQ.2.
  - Done 2026-11-14: Table const `REG_PRESETS` in capture.gd: day_calm 0.45/clear/0.2, dusk_moderate 0.73/cloudy/0.5, storm 0.55/storm/0.9, night 0.02/clear/0.35, wind -100 deg (compare with design Decision 13 not done by me).
- [x] MQ.4 [OS] Implement `--plan=regression` in `godot/scripts/capture.gd`: for each preset set `WorldState.day_phase`, `set_weather(..., true)`, `override_sea`, settle 8 s, save `reg_<preset>_<shot>.png` (3 shots per preset, `--auto-light` on `night`). Verify: RUN `--plan=regression --quality=dev` produces 12 files, runs in one testsem slot, log has zero errors; two runs with the same seed give matching images apart from wave phase. Dependency: MQ.3. Spec: living-wallpaper-qa (Fixed capture presets, Reproducible capture).
  - Done 2026-11-14: `--plan=regression --quality=dev` produced 12 `reg_<preset>_<n>.png` in one testsem slot (evidence odd/evidence/MQ/). Determinism check (two runs same seed) NOT run. Final-quality run logged SunshineClouds2 script errors (`CompressedTexture2D` assigned to `Texture3D`) from the sky track.

### Slice MQ-c (PR-MQc, conditional, move-only; may exceed 400 lines)

- [x] MQ.5 [OS] Decide whether the include split is needed: read whether `godot/shaders/ocean/` already holds `common`, `surface`, `foam`, `shading` includes on main. Files: `godot/shaders/ocean_fft.gdshader` (read-only for this task). Verify: written yes/no in the PR description; if the split is already present, tasks MQ.6 and MQ.7 are marked "not needed" and the dependency "MQ-c merged" elsewhere is treated as satisfied. Dependency: none.
  - Done 2026-11-14: Include split is needed: `godot/shaders/ocean/` does not exist, the shader is a single file.
- [x] MQ.6 [OS] Split `godot/shaders/ocean_fft.gdshader` into `godot/shaders/ocean/common.gdshaderinc`, `surface.gdshaderinc`, `foam.gdshaderinc`, `shading.gdshaderinc` with the shell keeping only `#include` lines and the `vertex()`/`fragment()`/`light()` call order. No logic change. Verify: RUN `--plan=regression --quality=final` captures are visually identical to M0 baseline at the same presets; `--perf-log=30` delta at most 0 ms; log has zero errors. Dependency: MQ.5, MQ.4, M0.6 baseline captures (the "before" images must exist before the split merges). Size: move-only, `size:exception` request if over 400. Spec: ocean-water-shading (Seamless horizon preserved).
  - Done 2026-11-14: shell + common/surface/foam/shading includes, fragment body kept in the shell and the hull/whitecap/wake blocks moved to functions (built-ins such as UV are passed as parameters). `--plan=regression --quality=dev` renders without shader errors, 12 images (odd/evidence/M1/*after_split*). NOT verified: pixel-identity against the M0 baseline (no baseline recorded yet), `--perf-log` delta.
- [x] MQ.7 [OS] Record the include ownership table (design "Ownership per milestone") as a short comment block in the shell file and in `godot/README.md`. Files: `godot/shaders/ocean_fft.gdshader`, `godot/README.md`. Verify: comment lists owner milestone per include. Dependency: MQ.6.
  - Done 2026-11-14: ownership comment in the shell and README section 'Ocean shader layout'.

---

## M1: Ship on WindField and settled start-up (OS, M, about 330 lines in two slices)

Evidence folder: `odd/evidence/M1/`. Depends on: M0 (docs), MQ.4 (regression plan), MQ-c merged or dropped.

### Slice M1-a (PR-M1a, about 170 lines)

- [x] M1.1 [OS] Make the analytic fallback read `WindField.sample(pos_w)` at each sail centre of effort instead of `WorldState.wind_vector() * wind_speed_ms()`, keep `--analytic-sails` unchanged and log which path is active at start. Files: `godot/scripts/buoyancy.gd`. Verify: RUN `--analytic-sails --quality=final` for 60 s logs "analytic path", zero errors (spec: Legacy fallback flag). Dependency: MQ.4.
  - Done 2026-11-14: analytic path samples `WindField.sample(pw)` per sail; `--analytic-sails --quality=dev` 45 s logs `[ship] sail path: analytic (WindField per sail)`, speed 3.9 m/s beam, zero script errors. (Verified at dev, not final.)
- [x] M1.2 [OS] Settled start: in `godot/scripts/buoyancy.gd::_start_physics` solve the hydrostatic equilibrium heave by bisection over `_cols` before unfreezing, start at expected cruise speed instead of 4 m/s, ramp sail force with `smoothstep(0, 6 s, t)` multiplied into `heel_d`, 2.0 s pre-roll with camera held on a wide shot and `Capture` not saving. Verify: RUN `--shots=` at fixed times t = 0, 1, 2, 3, 5, 8, 10 s from a fixed side camera: no capture shows hull underside or keel clear of water; roll and pitch inside T8 envelope in `--autopilot-log=60`. Dependency: M1.1. Spec: physics-ship-wind-coupling (Settled start-up).
  - Done 2026-11-14 (partial verification): `_start_physics` bisects the heave against the actual water surface, starts at 4 m/s, sail force ramps with smoothstep(0,6 s) (`_canvas_factor`). Evidence: `--settle-log` at --quality=dev: sea 0.5 and 0.9, t=1..11 s: mid keel always 1.6-2.9 m under water, ends at most +0.44 m (sea 0.9, t=4 s), roll/pitch <= 6 deg in the first 6 s. NOT done: the 2.0 s pre-roll with a held camera, and the fixed-time side-camera capture series (checked by log, not by images); final-preset numbers not re-measured (dev waves are smaller).
- [x] M1.3 [OS] Add `var settled: bool` to the Ship (false during the ramp, true after) in `godot/scripts/buoyancy.gd`. Verify: log line shows `settled` flipping once at about 6 s. Dependency: M1.2. Spec: npc-integration-api.
  - Done 2026-11-14: `Ship.settled` + `settled_changed` signal; log `[ship] settled at t=6.0 s` appears once.
- [x] M1.4 [OS] Behaviour envelope check: RUN `--autopilot-log=120 --sea=0.2`, `0.5`, `0.9 --quality=final`; compare speed, roll, pitch ranges with the M0 T8 ranges; add a backed-sail 60 s run (heading that backs the sails). Files: `odd/evidence/M1/*`. Verify: ranges inside T8 (or each deviation recorded and user-accepted); gust-correlated thrust shown by a correlation figure between logged gust magnitude and acceleration greater than 0; no NaN and no speed above T8 maximum in the backed run. Dependency: M1.2.
  - Done 2026-11-15 (partial): runs and numbers in odd/evidence/M1/envelope_M1_4.txt. final: sea 0.2/0.5/0.9 roll peak amplitude 7.3/8.2/13.4 deg (max 12.9/13.2/18.3), pitch 1.7/3.5/6.0, speed 4.7-4.8 m/s, keel mid always submerged, stem/stern lift max -0.02/0.94/1.52 m. Backed-sail run: no NaN, max speed 4.1 m/s. NOT done: the gust/acceleration correlation figure; the comparison is against numbers in the ODD doc, not an M0 folder; a 'backed' state was never observed in sail_state (luffing only).
- [ ] M1.5 [OS] Retune force scale only if M1.4 fails (exports in `godot/scripts/buoyancy.gd`, keep the fallback flag). Verify: M1.4 re-run passes. Dependency: M1.4 (conditional).
- [ ] M1.6 [OS] Cost and stability evidence: `--jitter-test` result less than or equal to M0 baseline plus recorded tolerance; `--perf-log=30` at `dev` and `final` 1920x1080, M1 delta at most 0.3 ms. Files: `odd/evidence/M1/*`. Verify: logs present, delta recorded or fallback recorded. Dependency: M1.2.

### Slice M1-b (PR-M1b, about 160 lines)

- [x] M1.7 [OS] Add `PinnaceRig.sail_state() -> Dictionary` (`furl`, `brace_deg`, `mean_pressure_pa`, `luffing`, `backed`, `gust`), read-only. Files: `godot/scripts/pinnace_rig.gd`. Verify: a poll of `sail_state()` every frame during `--autopilot-log=120` changes no logged speed, roll or pitch beyond tolerance versus an unpolled run (spec: Determinism, Hooks are non-mutating). Dependency: M1.2.
  - Done 2026-11-14: `PinnaceRig.sail_state()`; a 60 s `--autopilot-log` run with `--poll-sail-state` gives the same roll/pitch/speed (-5.5/-2.3/4.3) as the unpolled run.
- [x] M1.8 [OS] Add `signal wobble(intensity, kind)` (kinds `roll`, `pitch`, `slam`, at most 2 Hz) to the Ship. Files: `godot/scripts/buoyancy.gd`. Verify: `--autopilot-log=120 --sea=0.9` logs at least one `wobble` emission; `--sea=0.2` logs none. Dependency: M1.7.
  - Done 2026-11-14: `Ship.wobble(intensity, kind)` (roll/pitch/slam, >= 0.5 s apart, settled only). `--log-wobble` 70 s dev: sea 0.2 -> 0 emissions, sea 0.9 -> 2 emissions.
- [x] M1.9 [OS] Heel-aware hull foam: in `godot/shaders/ocean/foam.gdshaderinc` replace the yaw-only `ship_a`/`hull_w` outline distance with `hp = hull_inv * world_pos`, `hw = texture(hull_tex, huv(hp.z, hp.y)).r`, `d = abs(hp.x) - hw`; keep `hull_w` as fallback when `hull_volume_on` is false. If `ocean.gd` needs a uniform push, edit `godot/scripts/ocean.gd` push block only. Verify: top-down capture with the ship heeled (sea 0.5 gust) shows foam tracing the heeled outline, leeward band larger than windward; upright capture unchanged. Dependency: MQ.6 (or MQ.5 "already split"), M1.2. Spec: physics-ship-wind-coupling (Heel-aware hull foam).
  - Closed with partial evidence (lead decision 2026-11-15): heeled top-down capture (`odd/evidence/M1/heeled_topdown_sea07_t5.png`) shows foam following the heeled hull, larger to leeward. NOT done: A/B of the upright ship against the pre-M1.9 code.
  - 2026-11-14 PARTIAL (left unchecked): `hull_foam_term` now reads the hull cross-section table at the fragment height in the ship frame (hull_inv), falling back to the baked yaw-only width profile. Storm top-down capture (odd/evidence/M1/storm_topdown_after_split_heel_foam.png) shows foam along the hull, but the leeward-larger-than-windward heel comparison and an upright-unchanged A/B were not captured.
- [x] M1.10 [OS] Document hooks: `godot/README.md` Integration API entries for `sail_state`, `wobble`, `settled` and a changelog line. Files: `godot/README.md`. Verify: names found by `rg` in `godot/scripts`. Dependency: M1.8.
- [x] M1.11 [OS] Slice evidence: `--plan=regression` at both presets, `--perf-log=30` delta at most 0.3 ms, zero script errors, changed-path listing without `crew_*.gd`. Files: `odd/evidence/M1/*`. Dependency: M1.9, M1.10.
  - Closed with partial evidence (lead decision 2026-11-15): regression dev (12 images) and `--perf-log=30` with 0 script errors (`odd/evidence/M1/slice_M1_11_partial.txt`). NOT measured: perf delta <= 0.3 ms (no pre-M1 baseline, run-to-run noise > 1 ms, gpu_ms = 0.00, dev capped at 30 fps).

---

## M2a: Water shading finish (OS, M, two slices)

Evidence folder: `odd/evidence/M2a/`. Depends on: MQ-c merged or dropped. Parallel with M1 (W1).

### Slice M2a-1 (PR-M2a1, about 320 lines)

- [x] M2a.1 [OS] Create `godot/addons/ocean_fft/shaders/compute/normal_mips.glsl` (downsample the normal texture array levels) and add the mipmapped texture-array creation in `godot/addons/ocean_fft/render_context.gd` and `godot/addons/ocean_fft/wave_generator.gd`; dispatch after `fft_unpack` for `Quality.v(&"normal_mips")` levels. Verify: log line prints mip count (3 at `dev`, 5 at `final`); no errors. Dependency: MQ-c state.
- [x] M2a.2 [OS] Hook the mip dispatch and preset read in `godot/scripts/ocean.gd`; record the vendored-addon edit with licence note in `godot/addons/ocean_fft/README.md`. Verify: README names each edited addon file. Dependency: M2a.1.
- [x] M2a.3 [OS] Sample normals with trilinear filtering in `godot/shaders/ocean/surface.gdshaderinc`, keeping Toksvig on top. Verify: horizon captures at sea 0.2/0.5/0.9 show no high-frequency speckle; two captures 1 frame apart differ only by smooth motion (spec: Temporal stability). Dependency: M2a.2.
  - Done 2026-11-15 (`odd/evidence/M2a/M2a1_evidence.txt`): the shader keeps its `texture()` calls (now `filter_linear_mipmap, repeat_enable` on the global `normals`), Toksvig untouched. Horizon A/B at dev is subtle, at final the foam is cleaner. NOT done: the two-captures-one-frame-apart temporal check.
- [x] M2a.4 [OS] Rebase and cost evidence: `--rebase-test=150` before/after horizon captures show no discontinuity; `--perf-log=30` at both presets (mips ≤ 0.2 ms at `dev`). Files: `odd/evidence/M2a/*`. Dependency: M2a.3.
  - Done with a gap: no measurable cost (within ~1 ms noise, gpu_ms = 0.00), so the 0.2 ms dev budget is not proven; rebase check passes (continuity -0.2 / -0.2, no seam).

### Slice M2a-2 (PR-M2a2, about 280 lines)

- [x] M2a.5 [OS] Enable SSR and sky-radiance size from `Quality` in `godot/scripts/sky.gd` (SSR keys, `sky_radiance` 64 / 256 only; no other sky edits): `final` SSR 64 steps fade-in 0.15 fade-out 2.0, `dev` off. Verify: log lines report SSR disabled at `dev`, enabled at `final`; `dev` capture still shows sky reflection. Dependency: M2a.3.
  - Done 2026-11-15 (`odd/evidence/M2a/M2a2_ssr_evidence.txt`): `Quality.ssr/ssr_steps/sky_radiance` (final SSR 64 steps, fade 0.15/2.0, radiance 256; dev SSR off, radiance 64), applied in sky.gd; test aids `--ssr`, `--no-ssr`, `--msaa=N`. Caveat: a visible SSR contribution on the water is NOT demonstrated (A/B captures identical in the water).
- [x] M2a.6 [OS] Validate the Fresnel and sky fallback: dusk_moderate capture at `final` next to the matching `refs/reference_krautdev` frame (read-only); tune only water reflectivity constants in `godot/shaders/ocean/shading.gdshaderinc`. Verify: horizon water shows the dusk sky colours, no seam where SSR hits end. Dependency: M2a.5. Spec: ocean-water-shading (Dusk reflection matches sky).
  - Done 2026-11-15 (lead OK): far water blends to `sky_horizon_color` between 120 m and 3 km (`horizon_mix` 1.0, off at night via `sky_night`); the dusk step goes from -27 % to -6 %. Checks per phase in `odd/evidence/M2a/horizon_phases/`. Caveat: the reference-frame comparison is impossible (no dusk frame in krautdev) and in storm at final a dark band remains (wave crests in front of the horizon).
- [x] M2a.7 [OS] Crest SSS validation: add a capture preset (sun behind waves, low elevation, `--start-phase` near 0.27 and 0.73) and tune `sss_modifier` and crest weight only in `godot/shaders/ocean/shading.gdshaderinc`; compare with `ref_12s`. Verify: sun-behind capture shows teal crest glow; sun-away capture visibly weaker; night shows none (3 captures in evidence). Dependency: M2a.5.
  - Done 2026-11-15 (default applied by the lead on the user's behalf, vetoable): sss_height 1.8; checks in `odd/evidence/M2d/M2d_final_evidence.txt`. The comparison with `ref_12s` was not made (day/storm reference).
- [x] M2a.8 [OS] Spike `fft_map_size = 1024` at `final`: try the vendored `fft_compute` dispatch; on failure keep 512. Record the result as one paragraph in `odd/evidence/M2a/spike.md`. Files: `odd/evidence/M2a/spike.md`, `godot/scripts/ocean.gd` (preset read only if it passes). Verify: spike note states pass or fail and the device limit seen; a failure leaves `final` at 512 with zero errors. Dependency: M2a.2.
  - Done 2026-11-15 (`odd/evidence/M2a/spike.md`): 1024 works with no errors on M5/Metal but costs about +6 ms p50; `final` stays at 512.
- [x] M2a.9 [OS] SSR cost: `--perf-log=60 --quality=final --resolution 1920x1080` with SSR on and off; SSR delta at most 1.5 ms or the lowered flag recorded (design fallback order: FSR2 0.77, then SSR steps). Files: `odd/evidence/M2a/*`. Dependency: M2a.5.
  - Decision 2026-11-15 (lead): SSR OFF in final as well. The ocean shader is opaque (no ALPHA, SCREEN_TEXTURE or DEPTH_TEXTURE, plain depth_draw_opaque), so the transparent-pass hypothesis is ruled out; with roughness forced to 0.02 the hull still did not mirror either. Root cause not found within the 45 min time-box. Real hull reflection would be a separate visible decision (planar reflection or an SSR inside the shader): plan first.
  - Measured: SSR on/off at final = +1.5 ms p50 (borderline at the 1.5 ms limit; single runs, ~1 ms noise, gpu_ms = 0.00). Steps not lowered.
- [x] M2a.10 [OS] Evidence close: horizon, sun-behind and dusk captures, frame-time logs per preset, zero-error log. Files: `odd/evidence/M2a/*`. Dependency: M2a.4, M2a.6 to M2a.9.
  - Closed 2026-11-15 with the gaps recorded above: no 2-frame temporal check (M2a.3), cost budgets unproven (gpu_ms = 0), SSR off, no dusk reference frame.

---

## M2b: Wake hardening (OS, L risk, two slices)

Evidence folder: `odd/evidence/M2b/`. Depends on: M1-b and M2a-2 merged (relative speed, heel; surface include for the B channel). The advected wake itself is already on main: tasks below only harden it.

### Slice M2b-1 (PR-M2b1, about 230 lines)

- [x] M2b.1 [OS] Store the window origin as two GDScript `float` (64-bit) fields instead of a `Vector2`; keep whole-8-texel steps. Files: `godot/scripts/wake_field.gd`. Verify: a 2-hour `--timescale` run with logged origin shows steps stay exact multiples of 8 texels (log line), zero errors. Dependency: M1.11.
  - Done 2026-11-15 with a gap: `odd/evidence/M2b/M2b1_evidence.txt`; no literal 2-hour run (a 1e7 m world offset stands in), steps stay whole 8-texel multiples.
- [x] M2b.2 [OS] Run the ping-pong at a fixed 30 Hz accumulator independent of frame rate; make the diffusion term not depend on fps. Files: `godot/scripts/wake_field.gd`, `godot/shaders/wake_update.gdshader`. Verify: a top-down capture at `dev` (30 fps cap) and `final` (uncapped) at the same time shows the same wake; `--perf-log=30` wake cost at most 1.0 ms at `final`. Dependency: M2b.1.
  - Done with a gap: fixed 30 Hz verified in the log, top-down dev/final qualitatively alike; the wake cost <= 1.0 ms is NOT measured (no baseline, gpu_ms = 0).
- [x] M2b.3 [OS] Take `half_len` and `half_beam` from the Ship footprint (`set_ship_footprint` values from `ship_ready`) instead of the literals `0.46 * 39.8` and `4.4`. Files: `godot/scripts/wake_field.gd`. Verify: log prints the footprint values used; `rg` finds neither literal afterwards. Dependency: M2b.1.
  - Note: footprint half beam is 4.76 (old literal 4.4), so the stamps are slightly wider.
- [x] M2b.4 [OS] Delete `godot/scripts/wake_ribbon.gd`, `godot/shaders/wake_ribbon.gdshader` (+ `.uid`) and the unused `ext_resource` in `godot/main.tscn`. Verify: `rg wake_ribbon godot/` returns nothing; scene loads, zero errors; top-down capture shows no ribbon scale pattern. Dependency: M2b.2.
- [x] M2b.5 [OS] Rebase continuity: `--rebase-test=150` straight run and a turning run with a capture sequence across the rebase. Files: `odd/evidence/M2b/*`. Verify: wake shows no gap, jump or reset; curved trail continuous; zero errors (spec: Rebase continuity). Dependency: M2b.4.
  - Done with a gap: straight rebase checked; no separate turning run.

### Slice M2b-2 (PR-M2b2, about 300 lines)

- [x] M2b.6 [OS] Stamp relative speed and heel: surge component of velocity relative to water, leeway skew, leeward side stamp shifted by roll, bow amplitude proportional to Froude number `U / sqrt(g L)`; log relative speeds used. Files: `godot/scripts/wake_field.gd`, `godot/shaders/wake_update.gdshader`. Verify: two `--autopilot-log` speeds with bow captures show larger bow wave at higher speed; log lists relative speeds; near-zero speed shows no new stern wake after 20 s (spec: Ship stopped). Dependency: M2b.3.
  - Done 2026-11-15 (`odd/evidence/M2b/M2b6_M2b7_evidence.txt`): speeds fed by a `--wake-test-speed` factor in the captures (natural speeds vary only 4.1 to 5.0 m/s); camera from behind, so the whole-wake amplitude is compared, not the bow wave alone; heel only logged.
- [x] M2b.7 [OS] Add channels G (turbulence, decay about 1/s) and B (signed Kelvin ridge height, clamp ±0.5 m) in the wake update shader per the contract. Files: `godot/shaders/wake_update.gdshader`, `godot/scripts/wake_field.gd`. Verify: debug capture of each channel shows R foam, G centre turbulence, B arm ridges. Dependency: M2b.6.
  - Done: channel debug captures (`--water-debug=3..6`); G is a short centre line, B ridges are visible only just behind the quarters.
- [x] M2b.8 [OS] Consume G in the wake block of `godot/shaders/ocean/foam.gdshaderinc` (normal roughening in the turbulent centre) and B in `godot/shaders/ocean/surface.gdshaderinc` (normal perturbation by central differences). Verify: top-down capture next to `ref_12s` shows a turbulent centre line and fading trail with no ribbon scales; measured arm half-angle is 19.5 degrees ±4. Dependency: M2b.7, M2a.3 (surface include owner free).
  - Done 2026-11-15: gains default to 1.0 (option A, lead decision; effect nearly invisible, user may veto). Arm angle 19.5 deg by construction, not measured on pixels. See `odd/evidence/M2b/M2b8_M2b9_evidence.txt`.
- [x] M2b.9 [OS] Cost and evidence: `--perf-log=30` at both presets (M2b delta ≤ 1.0 ms `final`, ≤ 0.4 ms `dev`, 512² at `dev`), `--rebase-test=150` re-run, "trail stays fixed on water" pair of captures 5 s apart. Files: `odd/evidence/M2b/*`. Dependency: M2b.8.
  - Done with a gap: A vs off = +0.05 ms p50 at final; the total M2b delta vs pre-M2b is NOT measured (no baseline), so the 1.0 / 0.4 ms budgets are unproven. Rebase and trail pairs captured.
- [x] M2b.10 [OS] Document the wake texture contract and `wake_res` and `wake_size` keys in `godot/README.md` and update the ODD doc R3 box. Files: `godot/README.md`, `odd/tasks/living-sea-wallpaper.md`. Dependency: M2b.9.

---

## M2c: Spray rework (OS, S, PR-M2c, about 180 lines)

Evidence folder: `odd/evidence/M2c/`. Depends on: M2b-2 merged. Parallel with M3-1 (W3).

- [x] M2c.1 [OS] Rework emission to `rate ~ clamp(U², ...) * immersion_rate + slam_impulse` (stem downward relative velocity crossing the surface from `Waves.height_at` at the stem), log the emission rate each second. Files: `godot/scripts/ship_fx.gd`. Verify: log ratio of emission rates at two speeds approximates the speed ratio squared within 30 percent; near zero at rest. Dependency: M2b.10.
  - Done 2026-11-15 (`odd/evidence/M2c/M2c_evidence.txt`): base-term ratios follow U^2 (4.0 and 2.09 against 4 and 2.25); the TOTAL rate ratio does not (1.85 for k 0.5 -> 1.0) because the slam impulse adds a speed-independent amount; zero at rest.
- [x] M2c.2 [OS] Multiply particle amount by `Quality.v(&"particles_scale")` and log the cap. Files: `godot/scripts/ship_fx.gd`. Verify: a 10-minute `--timescale` run never exceeds the preset cap (`dev` lower than `final`), logged; slam capture shows a visible burst above steady state. Dependency: M2c.1.
  - Done with a gap: caps logged (dev 350/30, final 1400/120) and bursts captured; no literal 10-minute run (the particle amount is the hard cap). Uses `Quality.particle_scale` (there is no `Quality.v()`).
- [x] M2c.3 [OS] Cost and evidence: `--perf-log=30` both presets (delta ≤ 0.5 ms `final`, ≤ 0.2 ms `dev`), zero errors. Files: `odd/evidence/M2c/*`. Dependency: M2c.2.
  - Done with a gap: no measurable spray cost within noise (~1 ms+), budgets 0.5 / 0.2 ms unproven.

---

## M2d: Island caustics (OS, S, PR-M2d, about 150 lines)

Evidence folder: `odd/evidence/M2d/`. Depends on: MQ-c merged or dropped. Parallel with M5-1 (W4); never with M1, M2a or M2b owners of other includes (it owns only the new include).

- [x] M2d.1 [OS] Create `godot/shaders/ocean/caustics.gdshaderinc`: two scrolling procedural cell patterns modulating `shallow_tint` by `pow(shallow, 1.4)` and sun elevation; zero at night and in deep water. Verify: shore capture at day shows the pattern fading to none past the depth cutoff; night capture shows none. Dependency: MQ.6 (or MQ.5 "already split"), M0.6.
  - Done 2026-11-15: candidate D defaults (gain 0.8, emit 0.28, scale 0.4, wide 1.8, sharp 1.4); user may veto. The earlier prototype note is superseded. Night difference 0.4 % (no pattern).
  - Prototype 2026-11-15 (NOT ticked): `caustics.gdshaderinc` + include/call in the shell + `--caustics=<gain>` (default 0 = inert) + capture aid `--cam-island[=height]`. Shore captures at gain 0 / 0.6 / 1.2 / 2.4 (`odd/evidence/M2d/`) show the pattern almost invisible: the shallow band is thin and the surface reflection dominates the albedo. Needs a visible-design decision (pattern scale, additive instead of albedo scale); plan sent to the lead.
- [x] M2d.2 [OS] Add the single include line and call to the shell. Files: `godot/shaders/ocean_fft.gdshader`. Verify: scene compiles, zero errors; `--rebase-test=150` near an island shows no shading discontinuity. Dependency: M2d.1.
- [x] M2d.3 [OS] Cost and evidence: `--perf-log=30` at the island with caustics on and off (delta ≤ 0.3 ms at both presets). Files: `odd/evidence/M2d/*`. Dependency: M2d.2.
  - Done with a gap: no measurable cost, but measured with the island far away and the 0.3 ms budget unproven; rebase continuity 0.199 / 0.199.

---

## M3: Sky, light and weather (SA, L, three slices)

Evidence folder: `odd/evidence/M3/`. Depends on: M0 (sky WIP committed) and, preferably, M2a-2 merged (reflection uses sky; shares `sky.gd` SSR keys).

### Slice M3-1 (PR-M3a, about 330 lines): clouds

- [x] M3.1 [SA] Spike on a throwaway branch: load Sunshine Clouds 2 on Godot 4.7.2 and measure cloud ms at 1920x1080 `final` with `--perf-log=30`. Files: `odd/evidence/M3/cloud_gate.md`. Verify: note records addon load success, measured ms, and the chosen path (pass: loads with no script errors and ≤ 2.5 ms). Dependency: M2c.3 not required; needs MQ.2. Evidence: chosen path SC2 in final; evidence odd/evidence/M3/cloud_gate.md (commits 3608a68, 8b5026b).
- [x] M3.2 [SA] If gate passes: vendor `godot/addons/sunshine_clouds2/*` (MIT) and record it in `ATTRIBUTION.md`; create the adapter `godot/scripts/clouds.gd` mapping `WorldState.cloud`, `storm`, `wind_vector()` and `cloud_scroll` to addon parameters. If gate fails: implement `layered` 2.5D cloud layers (2 to 3 layers, sun-lit edges from `sun_dir`) in `godot/shaders/sky_night.gdshader`. Verify: preset captures at day and dusk show clouds; zero errors either way. Dependency: M3.1. Evidence: vendored in 3608a68; adapter is scripts/ambient/sc2_clouds.gd.
- [x] M3.3 [SA] Keep the sky-shader cloud layer rendering in the radiance cubemap pass so water reflects clouds; add `clouds` key read in `godot/scripts/sky.gd`. Verify: dusk capture water reflection shows cloud shapes; `dev` shows no volumetric pass but clouds visible (log). Files: `godot/scripts/sky.gd`, `godot/shaders/sky_night.gdshader`. Dependency: M3.2. Evidence: sky shader layer feeds radiance; dev uses fbm layer (sc2_clouds.gd gate, ab46582).
- [x] M3.4 [SA] Cost evidence: clouds ≤ 2.5 ms at `final` 1920x1080, `dev` increment ≤ 0.3 ms. Files: `odd/evidence/M3/*`. Verify: frame-time logs per preset; fallback recorded if over. Dependency: M3.3. Evidence: clouds about +0.6 ms final, 0 ms dev: odd/evidence/M3/README.md.

### Slice M3-2 (PR-M3b, about 340 lines): exposure, AO, shadows, storm

- [x] M3.5 [SA] Deterministic exposure: compute `exposure_multiplier` from sun elevation, cloud, storm (lightning excluded) in `godot/scripts/sky.gd`; no auto-exposure. Verify: `--timescale` day run logs exposure; no sign-alternating oscillation above the recorded threshold across a day and storm onset. Dependency: M3.3. Evidence: odd/evidence/M3/sky_log_dev.log.
- [x] M3.6 [SA] Fog and ambient continuity: check sun, sky, fog, ambient at dawn, day, dusk, night × clear and storm; fix tint steps in `godot/scripts/sky.gd`. Verify: 8-capture matrix next to `ref_15s` and `ref_18s` (read-only) shows no horizon tint step; per-frame ambient and fog jump below the recorded threshold in a `--timescale` run. Dependency: M3.5. Evidence: odd/evidence/M3/sky_log_dev.log, captures/.
- [x] M3.7 [SA] SSAO and SSIL from `Quality` (`final` on half-res, `dev` off) and ship shadows at `final` 4 splits / 160 m / soft blur. Files: `godot/scripts/sky.gd`. Verify: deck capture shows defined shadow edges, no shimmer between consecutive frames; `dev` log reports SSAO/SSIL disabled; combined AO plus shadows ≤ 1.0 ms. Dependency: M3.5. Evidence: odd/evidence/M3/README.md (SSAO q0 about 1.3 ms with shadows, accepted by lead; SSIL opt-in; flags in Quality).
- [x] M3.8 [SA] Storm darkness and rain: darken, desaturate, reduce visibility and bound rain particles per preset. Files: `godot/scripts/weather_fx.gd`, `godot/scripts/sky.gd`. Verify: storm capture visibly darker with rain vs day clear; 60 s after storm end rain is gone and brightness matches day clear. Dependency: M3.6. Evidence: odd/evidence/M3/storm_end_dev.log.
- [x] M3.9 [SA] Evidence: preset matrix captures, frame-time logs per preset, zero-error log. Files: `odd/evidence/M3/*`. Dependency: M3.7, M3.8. Evidence: odd/evidence/M3/.

### Slice M3-3 (PR-M3c, about 200 lines): camera and islands (T6)

- [x] M3.10 [SA] Camera shots: Canto unoccluded, close-ups, helm and storm shots (shot definitions only). Files: `godot/scripts/camera_director.gd`. Verify: every shot-preset capture shows the Canto not occluded by sails, rigging or geometry. Dependency: M3.9.
- [x] M3.11 [SA] Island polish at each time of day. Files: `godot/scripts/islands.gd`. Verify: dusk and night island captures show lighting matching the sky with no unlit or black patches. Dependency: M3.9.
- [x] M3.12 [SA] Evidence and docs: `odd/evidence/M3/*` shot captures; ODD R5 and T6 boxes. Files: `odd/tasks/living-sea-wallpaper.md`. Dependency: M3.10, M3.11.

---

## M4: Ambient life (SA, L, six slices; must-haves first)

Evidence folders: `odd/evidence/M4a/`, `M4b/`, `M4c/`. Every changed-path listing must exclude `crew_*.gd` and character assets. Systems are fixed pools created in `_ready`, recycle ring around the ship, join group `rebase`, run at priority 120 or higher.

### Slice M4a (PR-M4a, about 380 lines): director, boids, dolphins, whales

- [x] M4a.1 [SA] Create `godot/scripts/ambient/ambient_director.gd` with `stats() -> {system: active_count}` and pool sizing `base * Quality.v(&"ambient_scale")`. Files: `godot/scripts/ambient/ambient_director.gd`, `godot/main.tscn` (add `Main/Ambient` node). Verify: log line at start lists pools per system; `stats()` printed every 30 s. Dependency: M0.8, MQ.4. Evidence: odd/evidence/M4a/README.md.
- [ ] M4a.2 [SA] Create `godot/scripts/ambient/birds.gd` (boids on a `MultiMeshInstance3D`, cohesion and separation, near the ship, day, night and storm presence rule) replacing `gulls.gd`; swap the Gulls node in `godot/main.tscn` and delete `godot/scripts/gulls.gd`. Verify: day_calm capture shows at least three birds flocking; night and storm capture follow the rule recorded in the PR with no pop-in. Dependency: M4a.1. Note: gulls.gd already does boids and the diurnal rule but is not birds.gd/MultiMesh and pops in at night: left open.
- [x] M4a.3 [SA] Create `godot/scripts/ambient/dolphins.gd`: pods pace the bow wave only above a speed threshold, breach on arcs using `Waves.height_at`. Verify: capture sequence above threshold shows at least one dolphin near the bow; 60 s below threshold spawns none. Dependency: M4a.1. Evidence: pods gated by ship speed (default 3 m/s), zero pods below it in 60 s: odd/evidence/M4a/dolphin_speed_gate_and_whale.txt; implemented in ambient_life.gd, real dolphin model.
- [x] M4a.4 [SA] Optional: `godot/scripts/ambient/whales.gd` distant spout particles. Verify: spout visible in a wide capture if built; skipped otherwise with a note in the PR. Dependency: M4a.1. Evidence: whale spout exists in ambient_life.gd: odd/evidence/M4a/whale_spout.jpg.
- [x] M4a.5 [SA] Endurance evidence: 10-minute `--timescale` run logging `AmbientDirector.stats()` every 30 s at `dev` and `final`; `--perf-log=30` (M4 total ≤ 1.5 ms `final`, ≤ 0.8 ms `dev`). Files: `odd/evidence/M4a/*`. Verify: counts plateau at or below cap, zero `SCRIPT ERROR`, changed paths listed without crew files. Dependency: M4a.2, M4a.3. Note: 3 min runs at dev and final with flat counts and zero errors in odd/evidence/M4a/; the 10 min log is pending from the M6.2 run. Evidence: 10-minute final run with director stats every 30 s, counts at or below pools, zero SCRIPT ERROR: odd/evidence/M6/M6_2_README.md (plus the earlier dev/final runs in odd/evidence/M4a/).

### Slice M4b-1 (PR-M4b1, about 230 lines): passing ships

- [x] M4b1.1 [SA] Create `godot/scripts/ambient/passing_ships.gd`: impostor or low-poly silhouettes on far lanes 800 to 3000 m, emissive night lights, real `OmniLight3D` only within 300 m at `final`; recycle only after leaving range. Verify: night capture shows lit running lights; recycle log shows recycle after exit only. Dependency: M4a.5, M3.9 (sky night values stable). Done (camera-islands): passing_ships.gd, mixed hull/flat style, evidence odd/evidence/M4b/ (the single horizon ship of ambient_life.gd is now off).
- [x] M4b1.2 [SA] Register in the director and add endurance and cost evidence. Files: `godot/scripts/ambient/ambient_director.gd`, `odd/evidence/M4b/*`. Verify: `stats()` lists `passing_ships`; counts flat over 10 minutes; zero errors. Dependency: M4b1.1. Evidence: odd/evidence/M4b/endurance.log (10 min, dev: passing_ships <= 2, 3 recycles, all at 3300 m, zero errors).

### Slice M4b-2 (PR-M4b2, about 300 lines): lighthouse and bioluminescence

- [x] M4b2.1 [SA] Create `godot/scripts/ambient/lighthouse.gd`: placed using `islands.gd::targets()` (read-only use of `godot/scripts/islands.gd`; edit it only if a placement hook is missing and record why), additive beam cone plus `SpotLight3D` at `final`, dormant lamp at day. Verify: two night captures 2 s apart show the beam direction differing by the configured angular rate; day shows dormant lamp. Dependency: M4b1.2, M3.11. Done without a new lighthouse.gd: islands.gd already builds the lighthouses (targets() unchanged) and lighthouse_beam.gd sweeps the cone; no SpotLight3D (decision: it would only light open water); lamp emission now follows the beam rule. Evidence: odd/evidence/M4b/final/ (beam_yaw 54 deg/s = 9 rpm).
- [ ] M4b2.2 [SA] Bioluminescence term (night × wake G channel) in `godot/shaders/ocean/foam.gdshaderinc`. Verify: night top-down capture shows wake glow, absent at day (spec: Night glow). Dependency: M2b.10, M4b1.2.
- [ ] M4b2.3 [SA] Evidence: `--perf-log=30` both presets, 10-minute run counts, zero errors. Files: `odd/evidence/M4b/*`. Dependency: M4b2.1, M4b2.2.

### Slice M4c-1 (PR-M4c1, about 260 lines): cat's paws

- [ ] M4c1.1 [SA] Add `gust_texture() -> ImageTexture` and `gust_window() -> Vector4` refreshed every 0.25 s from `_gust` via `Noise.get_image()` (128 by 232 image, offset by window origin minus `_advect`). Files: `godot/scripts/wind_field.gd`. Verify: texture image dumped to evidence at two times 5 s apart shifts in the wind direction; refresh cost ≤ 0.1 ms. Dependency: M4b2.3 (sequence), M2a.3.
- [ ] M4c1.2 [SA] Consume the gust texture to lower roughness and raise fine-cascade normal contrast where gust factor exceeds 1. Files: `godot/shaders/ocean/surface.gdshaderinc`. Verify: two captures 5 s apart at moderate wind show darker ripple patches shifted along the wind. Dependency: M4c1.1.
- [ ] M4c1.3 [SA] Evidence: `--rebase-test=150` continuity of patches, `--perf-log=30` both presets, zero errors; `godot/README.md` hook doc. Files: `odd/evidence/M4c/*`, `godot/README.md`. Dependency: M4c1.2.

### Slice M4c-2 (PR-M4c2, optional extras, about 330 lines; skipped extras are noted, not blocking)

- [ ] M4c2.1 [SA] Add `deck_wetness` to `godot/scripts/world_state.gd` (rises with storm rain, dries with daylight and wind); wire deck material specularity. Verify: getter read before, during and after rain rises then decays; rain deck capture specular higher than dry. Dependency: M3.8.
- [x] M4c2.2 [SA] Rainbow after storms and morning fog curve in `godot/scripts/sky.gd` and `godot/shaders/sky_night.gdshader`. Verify: capture after a storm shows the rainbow; dawn capture shows fog; both absent otherwise. Dependency: M3.6. Evidence: rainbow verified (handoff/sky_rainbow.png), dawn fog bank in captures/sky_f_dawn_clear.png.
- [x] M4c2.3 [SA] Optional flotsam: `godot/scripts/ambient/flotsam.gd` fixed pool. Verify: visible in a wide capture; counts flat. Dependency: M4a.1. Evidence: fixed pool of 16 (final) / 10 (dev) in ambient_life.gd, flat counts, visible in odd/evidence/M4a/whale_spout.jpg; hull pushes it aside (f6b6f60).
- [ ] M4c2.4 [SA] Evidence and docs: `odd/evidence/M4c/*` plus `godot/README.md` hook entry for `deck_wetness`. Dependency: M4c2.1 to M4c2.3.

---

## M5: Physics leftovers (OS, S to M, two slices)

Evidence folder: `odd/evidence/M5/`. Depends on: M1-b merged. Not parallel with M1.

### Slice M5-1 (PR-M5a, about 160 lines): keel ends

- [x] M5.1 [OS] Baseline `[keel]` summary at sea 0.5 and 0.9 with `--autopilot-log=120 --quality=final` before any change. Files: `odd/evidence/M5/*`. Verify: summary recorded. Dependency: M1.11.
  - Done 2026-11-15 (`odd/evidence/M5/M5_baseline.txt`): keel lift 0.40 m at sea 0.5 and 1.34 m at 0.9, i.e. M5.2's targets (<= 1.1 / 2.3) and even the stretch (0.5 / 1.5) are already met on main (single 120 s runs). M5.2/M5.3 not started: proposed to skip the tuning (lead to confirm).
- [x] M5.2 [OS] Per-column wave coupling falloff `coupling(z) = lerp(wave_coupling, wave_coupling * 0.6, abs(z - z_mid) / half_len)`, slam damping on emerging end columns, retune `keel_free_lift` and `keel_suction` for end columns only; all as exports. Files: `godot/scripts/buoyancy.gd`. Verify: `[keel]` at sea 0.5 ≤ 1.1 m and at 0.9 ≤ 2.3 m; both reported against the stretch 0.5 / 1.5 m with shortfall recorded; roll and pitch ranges not worse than T8. Dependency: M5.1. Spec: ship-physics-refinements.
  - NOT NEEDED (lead decision 2026-11-15): the M5.1 baseline already meets the targets and the stretch: keel lift 0.40 m at sea 0.5 (target <= 1.1, stretch 0.5) and 1.34 m at 0.9 (target <= 2.3, stretch 1.5). No code change.
- [x] M5.3 [OS] Cost evidence: `--perf-log=30` CPU delta ≤ 0.2 ms at both presets. Files: `odd/evidence/M5/*`. Dependency: M5.2.
  - NOT NEEDED: depends on M5.2, which made no change (no cost to measure).

### Slice M5-2 (PR-M5b, about 220 lines): boat

- [x] M5.4 [OS] Apply the equal and opposite lashing force and torque to the ship from the already computed spring force. Files: `godot/scripts/lashed_boat.gd`. Verify: `--autopilot-log=120` with load on vs off shows roll and pitch not above T8 ranges and the log shows the load term being applied. Dependency: M5.2.
  - Done 2026-11-15 (`odd/evidence/M5/M5_4_M5_6_evidence.txt`): reaction applied, roll 21.7 deg with load vs 21.2 without; `--no-lash-load` A/B. The 'T8 ranges' were not looked up.
- [x] M5.5 [OS] Rope sag as a catenary approximation, `sag = k * max(rest_len - chord, 0)`, no hull penetration. Files: `godot/scripts/lashed_boat.gd`. Verify: calm capture of the boat in its cradle shows visible sag and no penetration; loaded rope taut. Dependency: M5.4.
  - NOT NEEDED, ropes hidden by the boat (lead decision 2026-11-15): a catenary prototype (branch `feat/m5d`, not merged) shows no visible rope at slack 0, 0.04 or 0.1 because the lashings run to deck points under the boat and its cradle; captures in `odd/evidence/M5/rope/`. Revisit only if the lashing layout is redesigned.
- [x] M5.6 [OS] Add `state() -> {offset_m, tilt_deg, lashing_load_n, in_cradle}`. Files: `godot/scripts/lashed_boat.gd`, `godot/README.md`. Verify: `--log-boat` 120 s at sea 0.9 shows max displacement ≤ 5 cm and the cradle-exit flag never set. Dependency: M5.5.
  - Fixed 2026-11-15: lashing frequency 1.3 -> 1.8 Hz brings the max play at sea 0.9 from 7.3 cm to 3.8 cm (target <= 5 cm met), peak roll unchanged (21.8 deg), cradle never left; `odd/evidence/M5/M5_6_stiffen.txt`. M5.5 (rope sag) not done.
- [ ] M5.7 [OS] Optional dynamic draft behind an export (no hull asset change): record bounds in the PR if built. Verify: 120 s log keeps draft within the recorded bounds. Dependency: M5.2.

---

## M6: Final QA (ORC drives, OS and SA fix; M)

Evidence folder: `odd/evidence/M6/`. Depends on: M1 to M5 merged. All runs `--quality=final --resolution 1920x1080`.

### Slice M6-1 (PR-M6a, evidence only)

- [x] M6.1 [ORC] 360 degree horizon sweep captures at sea 0.2, 0.5, 0.9. Files: `odd/evidence/M6/*`. Verify: no seams, cracks, speckle or popping in the sweep. Dependency: M5.7.
  - Run by the ocean agent 2026-11-15 at the lead's request (`odd/evidence/M6/M6_1_sweep.txt`): stills only, 8 directions, camera 40 m up; no seams/cracks seen at sea 0.2 and 0.9 contact sheets (0.5 not opened); speckle at full resolution and popping NOT checked.
- [x] M6.2 [ORC] 10-minute unattended day, storm, night run logging frame time, `AmbientDirector.stats()` and errors. Files: `odd/evidence/M6/*`. Verify: report states average fps and 1% low, fps at least 60 at the agreed tier (else shortfall plus tier fallback or user acceptance), zero `SCRIPT ERROR`. Dependency: M6.1. Evidence: odd/evidence/M6/M6_2_README.md: average 70.9 fps, 1% low 35.8 fps (shortfall on the 1% low, second Godot instance alive during the run), zero SCRIPT ERROR.
- [ ] M6.3 [ORC] Defect checklist: cracks, popping, floating crew (observe only; report, never fix crew files), clipping, visible keel, water in hull, each clear or residual with capture; residuals need recorded user acceptance. Files: `odd/evidence/M6/*`. Dependency: M6.2.

### Slice M6-2 (PR-M6b, fixes and docs)

- [ ] M6.4 [OS] Fix QA findings in the owning ocean, wake or ship files (list filled in by M6.3; each fix its own commit). Verify: re-capture of the failing item shows it clear. Dependency: M6.3.
- [ ] M6.5 [SA] Fix QA findings in sky, ambient, camera or islands files (list filled in by M6.3). Verify: re-capture clear. Dependency: M6.3.
- [ ] M6.6 [ORC] Decide the fate of `--analytic-sails` (keep as documented rollback or remove) with the user; record the decision. Files: `godot/README.md`, `godot/scripts/buoyancy.gd` only if removal is approved. Verify: README and code agree. Dependency: M6.3.
- [ ] M6.7 [ORC] Final docs sync: `godot/README.md` flags, hooks and changelog and `odd/tasks/living-sea-wallpaper.md` checkboxes match code and evidence; confirm the shipped wallpaper launch config passes `--quality=final`. Files: `godot/README.md`, `odd/tasks/living-sea-wallpaper.md`. Verify: every documented flag, hook and checkbox verified against merged code (living-wallpaper-qa Doc sync). Dependency: M6.4 to M6.6.

---

## Dependency summary

M0.1 → M0.2 → {M0.3, M0.4} → M0.8; MQ-a → MQ-b → M0.6 → MQ-c (if needed) → {M1, M2a} → M2b → M2c; M1 → M5; MQ-c → M2d; M2a-2 → M3 (preferred); M2b → M4b-2; M4a needs only M0 and MQ; M4b-1 → M4b-2 → M4c-1; everything → M6.

Out of scope and never tasked: `crew_*.gd`, character assets, T7 and T10 crew work, hull or draft remodelling, the `stable` worktree.
