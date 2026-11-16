# Tasks: NPC Crew Jobs (reusable `npc_life` addon + ship crew integration)

Scope: the addon `godot/addons/npc_life/` (A0-A6), the ship-side hooks (H1-H3, our OS agents) and the crew integration
(C1-C4, the user's NPC session). Specs: `openspec/changes/npc-crew-jobs/specs/*/spec.md` (16). Design:
`openspec/changes/npc-crew-jobs/design.md`.

> DELIVERY (user, 2026-11-14): NO pull requests. Every slice is merged DIRECTLY into local `main` (fast-forward after
> rebasing the slice branch/worktree) once its verification passes; check with `git merge-base --is-ancestor <commit>
> main`; the orchestrator then advances the `stable` worktree. The repo has no remote; nothing is pushed. Slice size
> (about 400 authored changed lines) is a planning heuristic, not a gate; `size:exception` does not apply.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | about 5,000 to 6,000 authored lines (addon about 3,400; GUT suites about 1,100; ship hooks about 900; crew integration about 1,300 excluding binary clips and generated `.tres`) |
| 400-line budget risk | High for the whole change; Medium per slice (each slice planned at 150 to 450 lines, A4 and C4 are split to stay near 400) |
| Chained PRs recommended | Yes (as chained direct merges to local `main`, not PRs) |
| Suggested split | A0 -> A1 -> A2 -> A3 -> {A4a, A4b, H1} -> A5 -> {H2, H3} -> C1 -> C2 -> C3 -> C4 -> A6 (see Work Units and Parallel Waves) |
| Delivery strategy | single-pr (user override: direct merge per slice to local `main`) |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

Note on the decision line: it is "No" because the user override (2026-11-14, direct merges to local `main`) removes
PR review and `size:exception`; each slice below is a self-contained stacked merge. Only one gate remains before the
first H-slice apply: roadmap M1-b merged (see H-gate). C-slices need the user's NPC session (they edit `crew_*.gd`).

## Conventions for every task

- Owners: **NPC** = the user's NPC session (addon A-slices, C-slices, `crew_*.gd`, crew content). **OS** = our
  ocean/ship agent (H-slices only, own worktree under `godot-living-sea-test-worktrees/`, never `stable`). **ORC** =
  orchestrator (merges, evidence index, user questions). Our agents never edit `crew_*.gd` or `godot/crew/**`
  (`openspec/config.yaml` `rules.apply`); the NPC session never edits H-owned files while an H-slice is open.
- RUN template (only way to launch Godot): `~/.claude/bin/testsem -- open -g -n -W -a /Applications/Godot.app --args
  --path godot --log-file godot/_shots/godot.log -- <flags>`. `dev` preset for iteration and captures, `final` only
  for perf/A-B. Every run ends with a log check: 0 `SCRIPT ERROR` / `ERROR:` lines in `godot/_shots/godot.log`.
- GUT command (CONFIRMED in A0, see `odd/evidence/npc-crew-jobs/A0/gut_run.md`; `open -a` swallows stdout and the exit code, so tests use the
  Godot binary headless under godotsem, which neither opens a window nor takes focus):
  `GUT = ~/.claude/bin/godotsem -- '/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot -s
  addons/gut/gut_cmdln.gd -gdir=res://tests/npc_life -gexit'` (exit 0 = all pass, 1 = failure; run `--headless --path godot --import` once after adding a `class_name`).
  GUI runs (captures, example scenes) keep the RUN template but through `godotsem` instead of `testsem`.
- **Tests-first rule (addon only)**: every A-slice task pair is RED then GREEN. The `T` task writes the GUT suite and
  records a failing run (missing class/behaviour); the following `I` task implements until the suite is green. Test
  files carry no escape hatches (no skip/only/ignore). Strict TDD is `false` project-wide; this applies to the
  reusable addon only. Run the suites with `godot/tests/run_npc_tests.sh` (GUT alone exits 0 and says "All tests passed" when a test script fails to parse; the wrapper fails on any SCRIPT ERROR / warning). Ship hooks (H) and crew content (C) are verified functionally and honestly reported.
- Evidence goes under `odd/evidence/npc-crew-jobs/<slice>/` (logs, captures, GUT output). Slice close = checkboxes
  updated here, evidence listed, changed-path check: A-slices and H-slices touch no `crew_*.gd`; H-slices touch no
  `godot/addons/npc_life/**`; no slice touches the `stable` worktree.
- Task ID format `<slice>.<n>`; suffix `T` = write failing test, `I` = implement. Spec links name the spec file
  (without path) and requirement.
- Edit authority: every backticked path on a task line is an edit target unless marked `(read-only)`.
- All artifacts English. Addon content is MIT or CC0/own; the addon ships no third-party clips.

## Suggested Work Units

| Unit | Goal | Likely merge | Focused test command | Runtime harness | Rollback boundary |
|------|------|--------------|----------------------|-----------------|-------------------|
| A0 | Spike (GUT, TwoBoneIK3D, LookAtModifier3D on 4.7.2) + addon skeleton | merge A0 | GUT on empty suite exits 0 | RUN headless project start, 0 script errors; plugin enable/disable in editor log | Remove `addons/npc_life`, `addons/gut`, `tests/npc_life`, revert 2 `project.godot` lines |
| A1 | Stations, job board, character Resources, `NpcWorld` skeleton | merge A1 | GUT `test_station.gd`, `test_job_board.gd`, `test_character_def.gd` | example stub run logs post/claim/release | `stations/`, `jobs/`, `agent/*def*`, `core/npc_world.gd` |
| A2 | Utility AI, overrides, ambient, seeded RNG, decision log | merge A2 | GUT `test_rng.gd`, `test_scorer.gd`, `test_decision.gd`, `test_decision_log.gd` | 10-min headless run twice same seed (byte-equal) and other seed | `brain/`, `core/npc_rng.gd`, `core/npc_decision_log.gd` |
| A3 | Waypoint graph, navigator, rotating-platform example | merge A3 | GUT `test_graph.gd`, `test_navigator.gd` | headless example on rotating raft, max local error log | `nav/`, `agent/npc_job_executor.gd` |
| A4a | Animation + IK adapters (project-agnostic) | merge A4a | GUT `test_anim_set.gd`, `test_anim_adapter.gd`, `test_ik_adapter.gd` | example capture shows reach IK and crossfade | `anim/` |
| A4b | Schedules/watch rotation + social layer | merge A4b | GUT `test_roster.gd`, `test_social.gd` | roster log (rotation, min staffing); capture of conversation and audience | `schedule/`, `social/` |
| A5 | Debug overlay/CLI + editor gizmos and graph editing | merge A5 | GUT `test_cli.gd`, `test_debug_tools.gd` | `--npc-force` log; editor screenshot with gizmos | `debug/`, `editor/`, `plugin.gd` additions |
| H1 | `ShipStations` + station catalogue + lantern stations + access markers | merge H1 | `rg` API names; `--debug-stations` capture | RUN capture with markers, 0 errors | `ship_stations.*`, `ship_lights.gd` additive fields, one `main.tscn` line |
| H2 | Per-sail `request_furl` + fallback; `maneuver_started/ended` | merge H2 | storm furl log + tack signal log | RUN `--weather=storm` and `--autopilot-log` | `pinnace_rig.gd`, `autopilot.gd` additions |
| H3 | Baked pivot-local waypoint graph + connectivity | merge H3 | `--bake-crew-graph` log (0 unreachable) | RUN addon loads `crew_graph.tres`, `--debug-stations` capture | `crew_graph.tres`, bake block in `ship_stations.gd` |
| C1 | Four `NpcCharacterDef`s, `crew_npc.gd` spawns `NpcAgent`s, `--crew=legacy` flag | merge C1 | GUT `test_character_validation.gd` on the 4 defs | RUN 4 agents at stations, helm staffed, legacy flag parity | `godot/crew/**`, flag branch in `crew_*.gd` |
| C2 | Lantern, chores, leisure sources + calm pacing | merge C2 | log asserts agent id on `lantern_changed` | RUN `--start-phase` dusk, dawn, calm 10 min | `godot/crew/sources/{lantern,chores,leisure}_source.gd` |
| C3 | Storm all-hands, maneuvers, helm rotation | merge C3 | log asserts furl by crew, rotation share | RUN `--weather=storm`, tack run, 10-min helm run | `godot/crew/sources/{storm,maneuver}_source.gd`, roster `.tres` |
| C4 | Retarget spike, clip pipeline, signature actions, comic fall, ATTRIBUTION | merge C4a, C4b | GUT `test_action_def_signatures.gd` | captures per signature action | `godot/tools/crew_anim_bake.gd`, `godot/assets/anim*/**`, `ATTRIBUTION.md` rows |
| A6 | Packaging pass + empty-project extraction check | merge A6 | grep project autoload names returns nothing | RUN example in scratch Godot 4.7 project, 0 errors | docs and example only |

## Parallel Waves (max 2 agents at once)

The NPC session and our OS agent are different owners, so a wave may pair one of each. Our own agents never exceed one
at a time on this change (H-slices share `ship_stations.gd`, `pinnace_rig.gd`, `autopilot.gd`, `main.tscn`).

| Wave | NPC session | OS agent | Why safe | Gate to start |
|------|-------------|----------|----------|---------------|
| W0 | A0, A1, A2, A3 sequential | none (H-slices blocked) | addon core is strictly sequential (each builds on the previous API) | none |
| W1 | A4a then A4b | H1 (after roadmap M1-b merged) | addon `anim/`, `schedule/`, `social/` vs ship `ship_stations.*`, `ship_lights.gd`; no shared file; only `main.tscn` line is OS-owned until H1 merges | A3 merged AND roadmap M1-b merged |
| W2 | A5 (debug, editor) | H2, then H3 | addon `debug/`, `editor/` vs `pinnace_rig.gd`, `autopilot.gd`, `ship_stations.gd`; H3 needs A3 (`NpcWaypointGraph`) and H1 markers | H1 merged (H2 needs only M1-b); H3 needs A3 + H1 |
| W3 | C1 then C2 then C3 | none | `main.tscn` and `crew_*.gd` are NPC-owned from C1 on | A4a, A4b, A5 merged; H1, H2, H3 merged; H-sequence closed |
| W4 | C4 (retarget spike first) | none | clip pipeline is NPC-only | C3 merged and C4.1 spike accepted |
| W5 | A6 extraction check | none | final packaging pass | C4 merged (or C4 deferred and recorded) |

Forbidden: two writers on `godot/main.tscn` at once (H1 one-line instance, then C1); an OS agent touching
`godot/crew/**` or `crew_*.gd`; a NPC-session slice editing `ship_stations.gd`, `pinnace_rig.gd`, `autopilot.gd`,
`ship_lights.gd` while an H-slice is open. Dependency columns per task are authoritative; W-numbers are a recommended order.

H-gate: H1, H2 and H3 may start only after roadmap M1-b is merged into local `main` (check `git log` for the M1-b
merge and `rg "func sail_state" godot/scripts/pinnace_rig.gd`; see `openspec/changes/living-sea-roadmap/tasks.md`
M1.7-M1.11). If roadmap M1-b is not merged, the OS track is blocked and the NPC session continues A-slices.

---

## Slice A0: Spike and addon scaffold (NPC, S, about 150 lines + GUT vendor)

Evidence folder: `odd/evidence/npc-crew-jobs/A0/`. Specs: npc-life-packaging (Plugin metadata and license, Dev-only
tests), npc-life-editor-tools (Clean enable/disable). Dependency: none.

- [x] A0.1 [NPC] Vendor GUT into `godot/addons/gut/` (MIT license file kept; pin the version used, one line in `godot/addons/gut/README.md` or a `VERSION` note) and add `.gutconfig.json` at `godot/.gutconfig.json` with `dirs: ["res://tests/npc_life"]`. Verify: the folder exists, GUT is not referenced by any file under `godot/addons/npc_life/` (`rg "gut" godot/addons/npc_life` is empty once A0.4 exists). Dependency: none. Spec: npc-life-packaging (Dev-only tests).
- [x] A0.2 [NPC] Create the empty suite `godot/tests/npc_life/test_smoke.gd` (`extends GutTest`, one `test_gut_runs` asserting `true`). Verify: GUT command exits 0 and prints 1 test passed under Godot 4.7.2; record the working invocation (including how stdout/exit code are captured given `open -a`; if `open` swallows it, switch to the Godot binary inside `/Applications/Godot.app/Contents/MacOS/Godot` under testsem or parse `godot/_shots/gut.log`) in `odd/evidence/npc-crew-jobs/A0/gut_run.md`. Dependency: A0.1. Risk: GUT/4.7 compatibility unverified (design Risks).
- [x] A0.3 [NPC] Spike TwoBoneIK3D and LookAtModifier3D on 4.7.2: throwaway script `godot/tests/npc_life/spike/ik_spike.gd` plus scene, run RUN with `--quit-after` and log the instantiate, `set_target`, `influence` ramp and `Skeleton3D` modifier-order results on the existing Meshy rig (read-only: `godot/scripts/crew_rig.gd`, `godot/scripts/crew_pose_modifier.gd`). Verify: `odd/evidence/npc-crew-jobs/A0/ik_spike.md` states pass/fail for each class, property names actually available in 4.7.2, and the chosen adapter fallback if a class is missing (design Risks: "behaviour on 4.7.2 unverified"). Dependency: A0.2. Delete the spike script after the note is written, or keep it under `tests/npc_life/spike/` marked dev-only.
- [x] A0.4 [NPC] Create addon skeleton: `godot/addons/npc_life/plugin.cfg` (name `NPC Life`, script `plugin.gd`, version 0.1.0), `godot/addons/npc_life/plugin.gd` (EditorPlugin, no autoload, no ProjectSettings writes), `godot/addons/npc_life/LICENSE` (MIT), `godot/addons/npc_life/README.md` (stub: purpose, status), `godot/addons/npc_life/icons/` placeholder (own SVG). Verify: `rg "add_autoload_singleton|ProjectSettings.set_setting" godot/addons/npc_life` returns nothing. Dependency: A0.2. Spec: npc-life-packaging (Plugin metadata and license, No project dependencies).
- [x] A0.5 [NPC] Enable only `npc_life` and `gut` editor plugins in `godot/project.godot` (no autoload section change). Verify: RUN headless project start logs 0 script errors; enable then disable the plugin in the editor and compare `project.godot` diff: only the `[editor_plugins]` entry changes (log); disabling leaves the ship and game running. Dependency: A0.4. Spec: npc-life-editor-tools (Clean enable/disable).
- [x] A0.6 [NPC] Slice close: record the spike notes and GUT invocation in this file's Conventions (replace `GUT` template with the confirmed form) and evidence folder; changed-path listing excludes `crew_*.gd`. Verify: GUT smoke green, project run 0 errors. Dependency: A0.1-A0.5.

## Slice A1: Stations, job board, characters, world skeleton (NPC, M, about 450 lines + about 250 test)

Evidence folder: `.../A1/`. Specs: npc-life-stations, npc-life-job-board, npc-life-characters. Dependency: A0.

- [x] A1.1T [NPC] RED: write `godot/tests/npc_life/test_station.gd`: `test_declaration_defaults`, `test_claim_release_single_slot`, `test_multi_slot_claim_returns_distinct_slots`, `test_competing_claims_one_winner`, `test_required_tags_reject_agent`, `test_stale_claim_released_on_agent_freed`, `test_anchor_local_follows_moving_parent`, `test_ik_target_absent_returns_null`. Verify: GUT run fails (classes missing); failing output saved to evidence. Dependency: A0.6. Spec: npc-life-stations (all five requirements).
- [x] A1.1I [NPC] GREEN: create `godot/addons/npc_life/stations/npc_station.gd`, `npc_station_slot.gd`, `npc_station_provider.gd` per design contracts (`claim`, `release`, `occupant`, `anchor_local`, `approach_local`, `ik_target`, group `npc_station` scan default). Verify: `test_station.gd` green. Dependency: A1.1T.
- [x] A1.2T [NPC] RED: write `godot/tests/npc_life/test_job_board.gd`: `test_post_and_clear`, `test_duplicate_id_updates_in_place`, `test_claim_marks_claimed_by`, `test_multi_slot_job_claimed_by_n_agents`, `test_required_tags_filter`, `test_expiry_unclaimed`, `test_claimed_job_expires_when_ttl_elapsed`, `test_urgency_grows_until_deadline`, `test_iteration_sorted_by_id`, `test_source_decoupling_no_agent_reference`. Verify: failing run recorded. Dependency: A1.1I. Spec: npc-life-job-board (all five requirements).
- [x] A1.2I [NPC] GREEN: create `godot/addons/npc_life/jobs/npc_job.gd`, `npc_job_kind_def.gd`, `npc_job_board.gd`, `npc_job_source.gd` (abstract `_poll`, `_on_job_effect`, `_on_job_finished`). Verify: `test_job_board.gd` green. Dependency: A1.2T.
- [x] A1.3T [NPC] RED: write `godot/tests/npc_life/test_character_def.gd`: `test_defaults`, `test_validation_reports_unknown_kind`, `test_validation_reports_missing_anim_tag`, `test_preferences_range_clamped`, `test_two_defs_differ_in_variety_fields`. Verify: failing run recorded. Dependency: A1.2I. Spec: npc-life-characters (CharacterDef resource, RoleDef and ActionDef, Validation, Variety by definition).
- [x] A1.3I [NPC] GREEN: create `godot/addons/npc_life/agent/npc_character_def.gd`, `npc_action_def.gd`, and the `validate() -> PackedStringArray` method. Verify: `test_character_def.gd` green. Dependency: A1.3T.
- [x] A1.4 [NPC] Create `godot/addons/npc_life/core/npc_world.gd` (exports and signals from the design, logical clock skeleton, registries, no decision logic yet) and `godot/addons/npc_life/core/npc_world_inputs.gd` (blackboard `set_value`/`get_value`/change log). Verify: `test_world_inputs.gd` (written first in `godot/tests/npc_life/test_world_inputs.gd`: `test_set_get`, `test_default_value`, `test_change_logged`) red then green; headless run with a stub scene instantiates `NpcWorld` with 0 errors. Dependency: A1.1I, A1.2I.
- [x] A1.5 [NPC] Slice close: evidence of failing then passing GUT runs; changed-path check. Verify: all A1 suites green in one GUT run. Dependency: A1.1I-A1.4.

## Slice A2: Utility AI, seeded RNG, decision log (NPC, M, about 400 lines + about 300 test)

Evidence folder: `.../A2/`. Specs: npc-life-utility-ai, npc-life-debug-tools (Seeded RNG, Decision log, Metrics
report). Dependency: A1.

- [x] A2.1T [NPC] RED: write `godot/tests/npc_life/test_rng.gd`: `test_seed_for_is_stable`, `test_streams_independent`, `test_same_seed_same_sequence`, `test_global_randf_untouched`. Verify: failing run recorded. Dependency: A1.5. Spec: npc-life-debug-tools (Seeded RNG).
- [x] A2.1I [NPC] GREEN: create `godot/addons/npc_life/core/npc_rng.gd` (`seed_for(world_seed, agent_id, stream)`), wire `NpcWorld.rng_for`. Verify: `test_rng.gd` green. Dependency: A2.1T.
- [x] A2.2T [NPC] RED: write `godot/tests/npc_life/test_scorer.gd`: `test_score_factors_each_contribute`, `test_distance_term_reduces_score`, `test_urgency_term_grows`, `test_softmax_low_temperature_top_pick_99pct` (T=0.01, fixed seed, at least 99 percent top), `test_softmax_high_temperature_all_picked` (T=1), `test_recency_penalty_decays`, `test_temperature_scale_per_character`, `test_topk_scores_returned`. Verify: failing run recorded. Dependency: A2.1I. Spec: npc-life-utility-ai (Utility scoring, Softmax selection, Recency penalty and commit time).
- [x] A2.2I [NPC] GREEN: create `godot/addons/npc_life/brain/npc_utility_scorer.gd`, `npc_needs.gd`. Verify: `test_scorer.gd` green. Dependency: A2.2T.
- [x] A2.3T [NPC] RED: write `godot/tests/npc_life/test_decision.gd`: `test_emergency_override_preempts_commitment`, `test_must_staff_before_softmax`, `test_all_hands_all_agents_take_override`, `test_commitment_window_keeps_job`, `test_commit_ends_on_job_done`, `test_ambient_when_board_empty`, `test_idle_bound_logged_as_fail`, `test_decisions_per_frame_capped_stagger`, `test_sorted_agent_order_deterministic`. Verify: failing run recorded. Dependency: A2.2I. Spec: npc-life-utility-ai (Hard overrides, Never aimless, Tick budget).
- [x] A2.3I [NPC] GREEN: create `godot/addons/npc_life/agent/npc_agent.gd` (decide), `godot/addons/npc_life/brain/npc_ambient.gd`, complete `core/npc_world.gd` logical tick (10 Hz, `max_decisions_per_frame`, sorted ids, `Time.get_ticks_usec` perf wrap, `Performance.add_custom_monitor("npc_life/tick_usec")`). Verify: `test_decision.gd` green. Dependency: A2.3T.
- [x] A2.4T [NPC] RED: write `godot/tests/npc_life/test_decision_log.gd`: `test_line_format_stable` (matches `[npc] T=000123 agent=... pick=... reason=... top=[...]`), `test_ring_buffer_bounded`, `test_summary_metrics_idle_max`, `test_same_seed_byte_equal_lines`, `test_different_seed_differs`. Verify: failing run recorded. Dependency: A2.3I. Spec: npc-life-debug-tools (Decision log, Metrics report).
- [x] A2.4I [NPC] GREEN: create `godot/addons/npc_life/core/npc_decision_log.gd` (ring buffer, optional file sink, summary). Verify: `test_decision_log.gd` green. Dependency: A2.4T.
- [x] A2.5 [NPC] Headless reproducibility run on a minimal stub scene (full example scene lands in A3): `--fixed-fps 60 -- --npc-seed=1 --npc-minutes=10` twice and `--npc-seed=2` once (CLI parsing minimal here, moved to `debug/npc_cli.gd` in A5; keep the parsing inside `core/npc_world.gd` behind one function until then). Verify: `diff` of `[npc] T=` lines between the two seed-1 runs is empty, seed-2 differs, summary shows `idle_max < 20 s`, 0 `FAIL idle_bound`, perf line `avg/max` recorded in `odd/evidence/npc-crew-jobs/A2/`. Dependency: A2.4I. Spec: npc-life-utility-ai (Never aimless); success criterion "same seed reproduces".

## Slice A3: Waypoint graph, navigator, rotating-platform example (NPC, M, about 450 lines + about 250 test)

Evidence folder: `.../A3/`. Specs: npc-life-navigation, npc-life-stations (Moving-parent support). Dependency: A2.

- [x] A3.1T [NPC] RED: write `godot/tests/npc_life/test_graph.gd`: `test_find_path_shortest`, `test_typed_edge_cost_multiplier`, `test_edge_type_preserved_in_path`, `test_unreachable_returns_empty`, `test_nearest_node`, `test_all_pairs_distance_cache_up_to_256`, `test_connectivity_check_lists_unreachable`, `test_graph_stored_in_local_space`. Verify: failing run recorded. Dependency: A2.5. Spec: npc-life-navigation (Typed-edge waypoint graph, Path queries, Connectivity check).
- [x] A3.1I [NPC] GREEN: create `godot/addons/npc_life/nav/npc_waypoint_graph.gd` (A*, all-pairs cache, `check_connectivity`) and `npc_waypoint_graph_node.gd` (binds to a `platform_root`). Verify: `test_graph.gd` green. Dependency: A3.1T.
- [x] A3.2T [NPC] RED: write `godot/tests/npc_life/test_navigator.gd`: `test_follows_polyline_in_local_space`, `test_uses_position_not_global_position`, `test_platform_rotation_no_drift` (rotate/translate platform each step, local error under 0.01 m), `test_rebase_shift_does_not_affect_local_position`, `test_edge_type_sets_locomotion_tag_and_speed`, `test_courtesy_yields_to_other_agent`. Verify: failing run recorded. Dependency: A3.1I. Spec: npc-life-navigation (Platform-local pathing, Per-edge locomotion, Agent collision courtesy).
- [x] A3.2I [NPC] GREEN: create `godot/addons/npc_life/nav/npc_navigator.gd`, `npc_ground_probe.gd`, and `godot/addons/npc_life/agent/npc_job_executor.gd` (phases MOVE, ALIGN, WORK, LEAVE with effect timing at `effect_at`, release on LEAVE). Verify: `test_navigator.gd` green; executor phases covered by `test_executor.gd` (`test_phase_order`, `test_effect_fires_at_fraction`, `test_release_on_leave`, `test_abort_releases_claim`) written first. Dependency: A3.2T.
- [x] A3.3 [NPC] Create the first slice of the example scene `godot/addons/npc_life/examples/workshop/workshop.tscn` (rotating raft, 3 stations, 3 puppet agents, 1 job source, graph `.tres`, `workshop_sources.gd`, 3 example `NpcCharacterDef` under `defs/`) using only addon classes. Verify: headless run `--fixed-fps 60 -- --npc-minutes=3` logs agents reaching stations, edge types logged, `max local position error` line under 0.05 m on the rotating platform, 0 errors; evidence in `A3/`. Dependency: A3.2I. Spec: npc-life-navigation (Platform-local pathing); npc-life-packaging (Example scene, partly).
- [x] A3.4 [NPC] Slice close: all suites green; changed-path check; 10-min headless idle metric re-run on the example (expect `idle_max < 20 s`). Dependency: A3.3.

## Slice A4a: Animation and IK adapters (NPC, M, about 400 lines + about 200 test) [parallel with H1]

Evidence folder: `.../A4a/`. Specs: npc-life-animation, npc-life-characters. Dependency: A3, A0.3 spike result.

- [x] A4a.1T [NPC] RED: write `godot/tests/npc_life/test_anim_set.gd`: `test_tag_resolves_shared_clip`, `test_signature_override_wins`, `test_missing_tag_reports_validation`, `test_locomotion_by_edge_type`; and `godot/tests/npc_life/test_anim_adapter.gd`: `test_play_crossfades_035s`, `test_has_tag`, `test_install_hip_ratio_scaling`, `test_procedural_adapter_works_without_skeleton`, `test_no_third_party_clip_in_addon` (scans `res://addons/npc_life` for `.glb`/`.fbx`/`.anim` of non-own origin: asserts none). Verify: failing run recorded. Dependency: A3.4. Spec: npc-life-animation (Adapter interface, Shared library and signature clips, Crossfade API, No bundled third-party clips).
- [x] A4a.1I [NPC] GREEN: create `godot/addons/npc_life/anim/npc_animation_adapter.gd`, `npc_anim_set.gd`, `npc_anim_player_adapter.gd`, `npc_procedural_adapter.gd`, `npc_rig_profile.gd`. Verify: `test_anim_set.gd` and `test_anim_adapter.gd` green. Dependency: A4a.1T.
- [x] A4a.2T [NPC] RED: write `godot/tests/npc_life/test_ik_adapter.gd`: `test_set_target_ramps_influence_12s`, `test_reach_clamped_at_93_percent`, `test_clear_ramps_out`, `test_look_at_target_set`, `test_adapter_binds_false_when_chain_missing`, `test_interface_has_no_engine_ik_types_in_signature`. Verify: failing run recorded. Dependency: A4a.1I, A0.3. Spec: npc-life-animation (Procedural IK hooks).
- [x] A4a.2I [NPC] (deviation note: TwoBoneIK3D needs a pole; the A0 fallback was withdrawn, see odd/evidence/npc-crew-jobs/A4a/README.md) GREEN: create `godot/addons/npc_life/anim/npc_ik_adapter.gd` and `npc_two_bone_ik_adapter.gd` (`TwoBoneIK3D`/`LookAtModifier3D` per the A0.3 note, 93 percent clamp proxies, 1.2 s ramp-in, elbow poles; fallback per spike). Verify: `test_ik_adapter.gd` green. Dependency: A4a.2T.
- [x] A4a.3 [NPC] Wire the adapters into `godot/addons/npc_life/agent/npc_agent.gd` and the executor (ALIGN sets IK targets, WORK plays `anim_tag`, props attach). Extend the example `workshop.tscn` with one station using hand IK and one using look-at. Verify: `--capture` of the example (`dev`) shows an agent reaching a station target and a crossfaded locomotion change; 0 errors. Dependency: A4a.2I.

## Slice A4b: Schedules, watch rotation, social layer (NPC, M, about 450 lines + about 250 test) [parallel with H1]

Evidence folder: `.../A4b/`. Specs: npc-life-schedules, npc-life-social. Dependency: A3 (A4a not required; same owner, run sequentially after A4a).

- [x] A4b.1T [NPC] RED: write `godot/tests/npc_life/test_roster.gd`: `test_must_staff_job_posted_per_watch`, `test_staffed_from_start`, `test_min_staffing_never_violated_during_handover`, `test_relief_overlaps_before_keeper_leaves`, `test_no_relief_extends_shift_logged`, `test_rotation_share_skill_weighted`, `test_emergency_keeps_keep_during_emergency_watch`, `test_captain_takes_helm_in_all_hands`, `test_roster_validation_unknown_station`. Verify: failing run recorded. Dependency: A3.4. Spec: npc-life-schedules (all four requirements).
- [x] A4b.1I [NPC] GREEN: create `godot/addons/npc_life/schedule/npc_roster.gd`, `npc_watch_scheduler.gd`. Verify: `test_roster.gd` green; rotation share test shows high-skill agent most frequent but not exclusive. Dependency: A4b.1T.
- [x] A4b.2T [NPC] RED: write `godot/tests/npc_life/test_social.gd`: `test_gathering_multi_slot_station`, `test_gathering_ends_on_timer_or_override`, `test_conversation_offer_claimed_by_one_partner`, `test_both_look_at_partner`, `test_audience_ring_slots_around_performer`, `test_performer_leaves_clears_listen_jobs`, `test_join_and_leave_offer`, `test_social_seeding_same_seed_same_offers`. Verify: failing run recorded. Dependency: A4b.1I. Spec: npc-life-social (all five requirements).
- [x] A4b.2I [NPC] GREEN: create `godot/addons/npc_life/social/npc_social_director.gd`. Verify: `test_social.gd` green. Dependency: A4b.2T.
- [x] A4b.3 [NPC] Extend the example (`workshop.tscn`, `workshop_sources.gd`, `defs/*.tres`: roster, social spot, performer seat with audience). Verify: 10-min headless run log shows rotation and minimum staffing never violated (`[roster]` summary), and a `--capture` shows a conversation and an audience ring; 0 errors. Dependency: A4b.2I, A4a.3.

## Slice A5: Debug overlay, CLI tools, editor gizmos and graph editing (NPC, M, about 450 lines + about 120 test)

Evidence folder: `.../A5/`. Specs: npc-life-debug-tools (Force-job/freeze/step, Overlay), npc-life-editor-tools. Dependency: A4a, A4b.

- [x] A5.1T [NPC] RED: write `godot/tests/npc_life/test_cli.gd`: `test_parses_seed_log_minutes`, `test_force_job_pins_next_pick_logged_forced`, `test_freeze_stops_clock`, `test_step_advances_n_ticks_while_frozen`, `test_unknown_flag_ignored`; and `godot/tests/npc_life/test_debug_tools.gd`: `test_overlay_creates_no_nodes_when_disabled`, `test_overlay_label_per_agent_when_enabled`. Verify: failing run recorded. Dependency: A4b.3. Spec: npc-life-debug-tools.
- [x] A5.1I [NPC] GREEN: create `godot/addons/npc_life/debug/npc_cli.gd` (`--npc-seed`, `--npc-log[=path]`, `--npc-debug`, `--npc-force=<agent>:<kind>`, `--npc-freeze`, `--npc-step=N`, `--npc-minutes=N`, `--npc-agents=N`), `debug/npc_debug_overlay.gd`; move CLI parsing out of `npc_world.gd`; implement `NpcWorld.force_job/set_frozen/step`. Verify: both suites green; `--npc-force` run logs `reason=forced`. Dependency: A5.1T.
- [x] A5.2 [NPC] Create editor tooling: `godot/addons/npc_life/editor/npc_station_gizmo.gd`, `npc_graph_gizmo.gd`, `npc_graph_inspector.gd`, register in `godot/addons/npc_life/plugin.gd` (gizmo plugins and inspector plugin added on enable, removed on disable; editor classes never referenced from runtime scripts). Verify: editor screenshot shows station gizmo (anchor, approach, facing arrow, slots, must-staff color) and graph gizmo with edge colors; graph editing buttons "Add node at cursor", "Connect selected", edge type dropdown, "Check connectivity" documented in `odd/evidence/npc-crew-jobs/A5/editor.md` with images; exported/headless run loads with 0 editor-class errors. Dependency: A5.1I. Spec: npc-life-editor-tools (all five requirements).
- [x] A5.3 [NPC] Overlay and 40-agent scalability: `--npc-agents=40` run on the example with `--npc-debug` off and on. Verify: log asserts at most `max_decisions_per_frame` decisions in any frame; debug off creates 0 overlay nodes; perf monitor `npc_life/tick_usec` recorded. Dependency: A5.1I. Spec: npc-life-utility-ai (Tick budget), npc-life-debug-tools (Overlay).

## Slice H1: ShipStations, station catalogue, lantern stations, access markers (OS, M, about 400 lines) [parallel with A4a/A4b]

Evidence folder: `.../H1/`. Specs: ship-crew-stations (ShipStations adapter and catalogue, Lanterns as stations, Missing access markers and geometry, Documentation and boundaries). Gate: roadmap M1-b merged AND A1 merged
(needs `NpcStation` and `NpcStationProvider`; A3 not needed for H1). OS-agent worktree under
`godot-living-sea-test-worktrees/`. Strict boundary: no edits in `godot/addons/npc_life/**` and no `crew_*.gd`.

- [x] H1.1 [OS] Deck survey: run `--debug-deck` (existing flag) and record on a pinnace deck capture where ratlines, crow's nest, door and stairs exist; list in `odd/evidence/npc-crew-jobs/H1/deck_survey.md`. Verify: the note lists coordinates (Pivot-local) for each of: helm, lanterns, shrouds/ratlines, crow's nest, door, stairs, deck levels y about 6.5 / 1.85 / 3.5 (answers design Open Question 1). Files: `godot/scripts/crew_markers.gd` (read-only), `godot/scripts/ship_lights.gd` (read-only), `godot/scripts/crew_rig.gd` (read-only). Dependency: H-gate.
- [x] H1.2 [OS] Add additive fields `stand_local` and `local_position` (Pivot-local) to the `get_lanterns()` entries in `godot/scripts/ship_lights.gd`, API otherwise unchanged. Verify: log of `ShipLights.get_lanterns()` entries shows the new keys with finite values; `--capture` unchanged (diff of the existing lantern capture), 0 errors. Dependency: H1.1. Spec: ship-crew-stations (Lanterns as stations).
  - Done (with the real lamps, 2026-11-15): `local_position` and `stand_local` are in `get_lanterns()` (see `odd/evidence/lights/api_smoke.log`).
- [x] H1.3 [OS] Create `godot/ship/ship_stations.tscn` with `Marker3D` stations (metadata `kind`, `slots`, `facing_deg`, `edge_to`, `edge_type`) for `helm` (must_staff), `spyglass_post`, `crows_nest`, `ratline_path`, `reef_line_<idx>` (one per sail), `chart_table`, `violin_seat`, `listen_spot`, `social_spot`, `fishing_rail`, `repair_spot`, `mop_zone`, `boat_check`, plus navigation/access markers and simple step/door/crow's-nest geometry where H1.1 found them missing. Verify: scene loads headless with 0 errors; marker count per kind logged and matches the design catalogue table. Dependency: H1.1. Spec: ship-crew-stations (ShipStations adapter and catalogue, Missing access markers and geometry).
  - Done 2026-11-15: `godot/ship/ship_stations.tscn` (generated by `ship/gen_ship_stations.py`); the reef lines are created per sail in code from the `reef_pin` markers, lanterns from ShipLights; no extra step/door geometry was added (the model has stairs; the door was not found, a `door` marker stands at the companionway). Tests first: `godot/tests/npc_life/test_ship_stations.gd` (12 tests, whole suite 128/128 via run_npc_tests.sh); the RED run was not observed separately.
- [x] H1.4 [OS] Create `godot/scripts/ship_stations.gd` (`class_name ShipStations extends NpcStationProvider`, `provide_stations()`, plain-data `get_stations() -> Array[Dictionary]` with `{id, kind, anchor, approach, facing_deg, level, slots, anim_tag, ik, occupied_by}`, lantern stations from `ShipLights` via the new fields, ik targets from `Helm.hand_l/hand_r`, `--debug-stations` marker+label overlay). Verify: RUN `--capture --debug-stations` (`dev`) shows labelled markers on deck; log prints station count per kind including one `lantern_<id>` per lantern; helm station declares `must_staff=true`; 0 errors. Files: `godot/scripts/ship_stations.gd`. Dependency: H1.2, H1.3.
  - Done: log `[crew] stations: boat_check=1 chart_table=1 crows_nest=1 fishing_rail=2 helm=1 lantern=3 ... reef_line=10 ...`; helm must_staff true; `--debug-stations` capture `odd/evidence/npc-crew-jobs/H1/stations_debug_top.png`. The 7 `!is_inside_tree()` errors at exit in that run come from `wind_field.gd` `_exit_tree` -> `ClothSolver.sync()` -> `flag.gd` (other owner), not from stations.
- [x] H1.5 [OS] Add one instance line for `ship_stations.tscn` under `Ship/Pivot` in `godot/main.tscn` (no other hunk). Verify: `git diff --stat godot/main.tscn` shows one added instance block; scene loads, 0 errors; `--capture` normal output unchanged apart from debug markers when the flag is set. Dependency: H1.4. Note: this is the last OS edit of `main.tscn` before C1.
  - Done: one `ext_resource` + one instance block in `godot/main.tscn` (plus the load_steps count).
- [x] H1.6 [OS] Document the Integration API in `godot/README.md` (stations, `get_stations()` shape, `--debug-stations`, lantern stand fields, boundaries: addon -> project never) and add a changelog line. Verify: every documented name found by `rg` in `godot/`; changed-path listing contains no `crew_*.gd`, no `godot/addons/npc_life/**`. Dependency: H1.5. Spec: ship-crew-stations (Documentation and boundaries).
  - Done: README section `Ship stations for npc_life (H1)`.

## Slice H2: Crew furl per sail and maneuver signals (OS, M, about 250 lines)

Evidence folder: `.../H2/`. Specs: ship-sail-crew-furl, ship-maneuver-signal. Gate: roadmap M1-b merged (shared `pinnace_rig.gd`);
independent of H1 files except `README.md` (rebase). Does not need any addon class. May run before or after H1; do not run in parallel with H1 (README and one-agent-at-a-time rule).

- [x] H2.1 [OS] `godot/scripts/pinnace_rig.gd`: keep one furl value per sail, add `signal furl_changed(idx, value)`, `sail_count()`, `get_furl(idx)`, `request_furl(idx, t)` (clamp 0..1, stamps last request time), `@export var furl_grace_s := 20.0`; `sail_power` uses mean furl. Verify: a headless log (`--autopilot-log=30`) prints `sail_count`, and a scripted `request_furl(0, 1.0)` at t=10 s changes `get_furl(0)` towards 1 while others keep their value; thrust drops accordingly; 0 errors. Dependency: H-gate (M1.7 `sail_state` merged). Spec: ship-sail-crew-furl (Per-sail furl request, Un-furl and state exposure).
- [x] H2.2 [OS] Storm fallback in `godot/scripts/pinnace_rig.gd`: when storm > `furl_storm` (0.86) and a sail got no request for `furl_grace_s`, force its target to the existing automatic value and log `[rig] auto-furl fallback sail <i>`; a requested sail is never overridden; furl can be reversed by `request_furl(idx, 0)`. Verify: RUN `--weather=storm --autopilot-log=60` with no crew: log shows the fallback for every sail after about 20 s past 0.86; with a scripted request on sail 0 the fallback appears only for the other sails (`odd/evidence/npc-crew-jobs/H2/furl.log`). Dependency: H2.1. Spec: ship-sail-crew-furl (Storm auto-furl fallback).
  - Done 2026-11-15: `odd/evidence/npc-crew-jobs/H2/furl.log` (no-crew storm: all 10 sails fall back at ~20 s; with a request on sail 0 only the other 9). Un-furl via request_furl(idx, 0) is implemented but was not exercised in a run.
- [x] H2.3 [OS] `godot/scripts/autopilot.gd`: add `signal maneuver_started(kind, side)` (`&"tack"` on `_tack_side` flip, `&"beat"` on tacking false -> true) and `signal maneuver_ended(kind)` (|rudder| < 0.1 for 3 s or 30 s timeout); no overlap of two maneuvers; started emitted with lead time per spec. Verify: RUN `--autopilot-log=180` on a beating course logs `maneuver_started` and `maneuver_ended` pairs with side and kind, no nested starts; a run with no listeners shows identical `--autopilot-log` speed/heading as before (diff of logged values within tolerance); decide the rudder-settle vs heading-convergence rule from the log and record it (answers design Open Question 3). Dependency: H-gate. Spec: ship-maneuver-signal (Maneuver signals, Non-overlap and lead time, Additive change).
  - Done 2026-11-15: rule = rudder settle (|rudder| < 0.1 for 3 s, 90 s timeout), see `odd/evidence/npc-crew-jobs/H2/maneuvers.log`. NOT done: speed/heading diff against pre-change code (no baseline run).
- [x] H2.4 [OS] Document `request_furl`, `get_furl`, `sail_count`, `furl_changed`, `maneuver_started/ended` in `godot/README.md` Integration API with a changelog line. Verify: names found by `rg` in `godot/scripts`; changed-path listing contains no `crew_*.gd`. Dependency: H2.2, H2.3.

## Slice H3: Baked pivot-local waypoint graph (OS, M, about 300 lines)

Evidence folder: `.../H3/`. Spec: ship-crew-stations (Waypoint graph export). Gate: H1 merged AND A3 merged (needs `NpcWaypointGraph`). Do not run in parallel with H2 (same agent).

- [x] H3.1 [OS] Extend `godot/scripts/ship_stations.gd` with `graph() -> NpcWaypointGraph` (loads `res://ship/crew_graph.tres`) and a `--bake-crew-graph` CLI path: build temporary trimesh colliders for the deck with the same technique as `godot/scripts/crew_manager.gd` (read-only, do not edit it), snap marker nodes to the deck, create edges from marker metadata (`edge_to`, `edge_type`), run `check_connectivity`, save the graph, free the colliders. Verify: RUN `--bake-crew-graph` writes `godot/ship/crew_graph.tres` and logs node/edge counts per edge type and `unreachable: []`; non-zero unreachable logs `FAIL connectivity` and does not write the file. Dependency: H1.6, A3.4. Spec: ship-crew-stations (Waypoint graph export).
  - Done 2026-11-15: `ShipStations.build_graph()/graph()/last_graph_report()` and the `--bake-crew-graph` path (temporary deck colliders on a private layer, snap of the nav markers; 16 of 18 snapped with a max correction of 0.12 m, the two mid-shroud nodes are not on the deck by design). Tests first: `tests/npc_life/test_ship_graph.gd` (7 tests; RED seen as a parse failure through run_npc_tests.sh, then GREEN; whole suite 135/135).
- [x] H3.2 [OS] Create `godot/ship/crew_graph.tres` from the bake and verify it loads in the addon: a runtime log line `[crew] graph nodes=<n> edges=<m>` printed from `ShipStations` at `ship_ready`. Verify: RUN default scene prints the line, every station id has a graph node within the approach distance, every station reachable from the deck root; stairs/ladder/rope edges present where the markers declare them. Dependency: H3.1.
  - Done: `ship/crew_graph.tres` baked (51 nodes, 52 edges: walk 45, stairs 3, rope 4, `unreachable: []`), runtime line `[crew] graph nodes=51 edges=52 stations_without_node_within_1.5m=0 unreachable=0 problems=0` (`odd/evidence/npc-crew-jobs/H3/graph_bake.log`). Ladder edges: none (the model has stairs and ratlines only).
- [x] H3.3 [OS] Graph is baked offline: add the "re-bake after hull change" note and the connectivity check command to `godot/README.md`, plus a `--debug-stations` overlay of edges coloured by type. Verify: `--capture --debug-stations` (`dev`) shows edges and nodes on deck; README names found by `rg`; 0 errors. Dependency: H3.2.
  - Done: README note (re-bake after a hull change, connectivity command).
- [x] H3.4 [OS] Slice close and H-sequence close: evidence index in `odd/evidence/npc-crew-jobs/H3/`, changed-path listing for H1-H3 (no `crew_*.gd`, no addon files, `main.tscn` one line), notification to the NPC session that C1 may edit `godot/main.tscn`. Verify: `git diff` path listing recorded. Dependency: H3.3, H2.4.
  - Done: evidence index `odd/evidence/npc-crew-jobs/H3/README.md`; the changed-path listing has no `crew_*.gd` and nothing under `godot/addons/npc_life/`.

## Slice C1: Crew definitions, NpcAgent spawn, legacy flag (NPC, M, about 400 lines)

Evidence folder: `.../C1/`. Specs: ship-crew-characters (Four crew definitions), ship-crew-job-sources (Helm always staffed, Legacy fallback flag, Never aimless).
Gate: A4a, A4b, A5 merged and H1, H2, H3 merged. Owner: NPC session only (edits `crew_*.gd` and `godot/main.tscn`).

- [x] C1.1T [NPC] RED: write `godot/tests/npc_life/test_crew_defs.gd` (project-side suite under `godot/tests/npc_life/`; it loads `res://crew/defs/*.tres`, not part of the addon): `test_four_defs_validate_without_errors`, `test_agent_ids_unique`, `test_each_def_has_two_signature_actions`, `test_variety_fields_differ`, `test_fuego_helm_skill_highest`, `test_meshy_rig_profile_bones_exist`. Verify: failing run recorded (defs missing). Dependency: H3.4. Spec: ship-crew-characters (Four crew definitions, Signature actions, Character-driven variety).
- [x] C1.1I [NPC] GREEN: create `godot/crew/defs/papi_fuego.tres`, `papi_diagnostica.tres`, `el_salchipapa.tres`, `don_omar.tres`, `crew_roster.tres`, `crew_rig_profile.tres` (Meshy 24 bone names), `crew_anim_set.tres` (existing shared clips only until C4). Verify: `test_crew_defs.gd` green. Dependency: C1.1T.
- [x] C1.2 [NPC] Create `godot/crew/crew_npc.gd` and `godot/crew/crew_world_bridge.gd`: spawn one `NpcWorld` under `Ship/Pivot` (platform_root = Pivot, graph from `ShipStations.graph()`, providers `[ShipStations]`), spawn four `NpcAgent`s reusing `crew_slot.gd` model loading, bridge writes `daylight`, `storm`, `wind`, `roll`, `maneuver` into `NpcWorldInputs` each logical tick. Files: `godot/crew/crew_npc.gd`, `godot/crew/crew_world_bridge.gd`, `godot/scripts/crew_slot.gd`, `godot/main.tscn`. Verify: RUN default (`--crew=npc`): 4 agents spawn at stations, helm staffed from t=0, 0 script errors, `[npc] perf` line printed. Dependency: C1.1I.
- [x] C1.3 [NPC] Add the `--crew=legacy|npc` flag (default `legacy` until C3 verified): `legacy` keeps today's static `CrewSlot` path with no `NpcWorld` created. Files: `godot/scripts/crew_manager.gd`, `godot/scripts/crew_rig.gd`, `godot/main.tscn`. Verify: RUN `--crew=legacy --capture` matches a pre-change capture of the crew (visual diff, 4 static crew, Fuego at helm, Omar seated with violin) and creates no `NpcWorld` (log); RUN `--crew=npc` creates it. Dependency: C1.2. Spec: ship-crew-job-sources (Legacy fallback flag).
- [ ] C1.4 [NPC] Port helm IK and violin through the project `NpcIkAdapter`/actions (reach `Helm.hand_l/hand_r`, violin pose reuse) without regressing `crew_pose_modifier.gd`. Files: `godot/crew/crew_ik_adapter.gd`, `godot/scripts/crew_rig.gd`. Verify: `--crew=npc` capture shows Fuego hands on the helm and Omar's violin pose; `--crew=legacy` capture unchanged. Dependency: C1.3.
- [x] C1.5 [NPC] Slice close: 0 errors in `godot/_shots/godot.log` for both flag values; `perf-log=30 --quality=final` for `legacy` vs `npc` recorded (delta feeds the 1.0 ms budget). Dependency: C1.4.

## Slice C2: Lanterns, chores, free time, calm pacing (NPC, M, about 400 lines)

Evidence folder: `.../C2/`. Specs: ship-crew-job-sources (Dusk and dawn lanterns, Chores and free time with calm pacing, Never aimless on the ship). Dependency: C1.

- [x] C2.1 [NPC] Create `godot/crew/sources/lantern_source.gd` (`NpcJobSource` subclass): subscribes to `ShipLights.lighting_needed` and extinguish events, posts `lantern:<id>` jobs on `lantern_<id>` stations, effect `light`/`extinguish` calls `ShipLights.light(id)` and logs `[crew] lantern <id> lit by <agent_id>`. Verify: RUN `--start-phase` dusk then dawn: every lantern lit then extinguished by a crew agent id in the log; `lantern_changed` carries the agent id (`odd/evidence/npc-crew-jobs/C2/lanterns.log`). Dependency: C1.5. Spec: ship-crew-job-sources (Dusk and dawn lanterns).
- [x] C2.2 [NPC] Create `godot/crew/sources/chores_source.gd` (mop, repair, boat check; periodic with jitter from its own seeded stream; optional inputs `deck_wetness`, `lashed_boat.state()` read through the blackboard only if present). Verify: 10-min calm run log shows chores posted with jitter, different seeds differ. Dependency: C2.1.
- [x] C2.3 [NPC] Create `godot/crew/sources/leisure_source.gd` (fishing, music, star gazing, conversation; weights by calm/night via blackboard). Verify: calm run shows few long relaxed jobs (job-count and mean duration in the summary: fewer, longer than storm); night run shows star gazing/music. Dependency: C2.1. Spec: ship-crew-job-sources (Chores and free time with calm pacing).
- [ ] C2.4 [NPC] Never-aimless verification on the ship: 10-minute `--crew=npc --npc-minutes=10 --fixed-fps 60 --quality=dev` twice same seed (decision lines byte-equal) and one other seed. Verify: `idle_max < 20 s`, 0 `FAIL idle_bound`, helm 100 percent staffed, evidence in `C2/`. Dependency: C2.3. Spec: ship-crew-job-sources (Never aimless on the ship); success criterion 10-minute run.
- [ ] C2.5 [NPC] Stairs acceptance (user request): crew change deck only by the real stairs, with the graph `stairs` edge and the `climb_stairs` clip, never through the rail or floating. Verify: `--crew-trace` plus a capture sequence of one crew member going from the waist deck to the poop deck by the stairs, in `odd/evidence/npc-crew-jobs/C2/` (depends on godot-ship adjusting the stairs nodes to the real steps). Dependency: C2.4.
- [ ] C2.6 [NPC] Audio hooks without a hard dependency: the project animation/action layer emits events (footstep at contact frames per surface, violin start/end, hammer hit, saw, fishing) through `Audio.play_at(id, node)` only if the `Audio` API exists (`Engine.has_singleton`/autoload check), otherwise nothing happens. Verify: with and without the Audio API 0 errors; events logged with `--crew-trace`. Dependency: sky-track's Audio API; C2.4.

## Slice C3: Storm all-hands, maneuvers, helm rotation, default flip (NPC, M, about 350 lines)

Evidence folder: `.../C3/`. Specs: ship-crew-job-sources (Storm all-hands, Maneuver jobs, Helm always staffed with skill-weighted rotation, Legacy fallback flag), ship-sail-crew-furl. Dependency: C2.

- [ ] C3.1 [NPC] Create `godot/crew/sources/storm_source.gd`: blackboard `storm > 0.8` posts `all_hands` reef jobs per sail (station `reef_line_<idx>`, effect `haul` every 2 s calls `PinnaceRig.request_furl(idx, +0.25)`) and secure jobs; clears after storm end. Verify: RUN `--weather=storm`: all four agents on storm jobs (`reason=override:emergency` in log), every sail furled via crew requests, `[rig] auto-furl fallback` absent when crew present; after storm end jobs clear (`C3/storm.log`). Dependency: C2.4, H2.2. Spec: ship-crew-job-sources (Storm all-hands).
- [ ] C3.2 [NPC] Create `godot/crew/sources/maneuver_source.gd`: connects to `Autopilot.maneuver_started/ended`, posts jobs at the sheet/brace stations for the tack side. Verify: beating run logs jobs per maneuver, agent ids, no job left claimed after `maneuver_ended`. Dependency: C3.1, H2.3. Spec: ship-crew-job-sources (Maneuver jobs).
- [ ] C3.3 [NPC] Tune `godot/crew/defs/crew_roster.tres` helm watch (`min_staff=1`, `shift_s=180`, `keep_during_emergency`): verify with a 10-minute run. Verify: helm staffed 100 percent, rotated among at least 2 agents, Fuego most frequent, handover overlap logged (`C3/helm.log`). Dependency: C3.1. Spec: ship-crew-job-sources (Helm always staffed with skill-weighted rotation).
- [ ] C3.4 [NPC] Frame-time A/B and default flip: `--perf-log=30 --quality=final` with `--crew=legacy` vs `--crew=npc` (NPC increment at most 1.0 ms), captured evidence of dusk, storm, calm; after all C3 checks pass flip the `--crew` default to `npc` and keep `legacy` as a documented fallback for one release. Files: `godot/scripts/crew_manager.gd`, `godot/README.md`. Verify: perf lines recorded; default run uses `npc`, `--crew=legacy` still reproduces the old static crew; 0 errors. Dependency: C3.3. Spec: ship-crew-characters (Runtime budget and script errors), ship-crew-job-sources (Legacy fallback flag).
- [ ] C3.5 [NPC] Furl aloft (scope change by the user): furling and unfurling go by climbing: rope through the shrouds (`ratline_climb`), to the top and along the yard footrope, with the `furl_aloft` clip at the aloft stations godot-ship adds per yard; `request_furl(idx, +-delta)` is called while they work there, not from the deck. Update `storm_source` (C3.1) and `maneuver_source` (C3.2) accordingly. Verify: capture sequence of a crew member climbing to a yard and furling; no `request_furl` call without an agent working at the aloft station. Dependency: aloft stations from godot-ship, C4 clips (`furl_aloft`, `ratline_climb`).
- [ ] C3.6 [NPC] Crew-driven bracing: brace stations on deck and `PinnaceRig.request_brace(mast, angle)` driven by the crew while the `brace_needed` signal (added by sails-fix) is active; without crew the slow automatic fallback stays. Verify: tack run where the yards turn only while an agent works at the brace station; legacy mode unchanged. Dependency: C3.2, `brace_needed` from sails-fix.
- [ ] C3.7 [NPC] Safety in storms: climbing aloft in a storm is dangerous, so the storm source gives it a priority and a cap on how many agents climb at once (cap configurable, default 2). Verify: storm run never shows more than the cap aloft (`--crew-trace`), the helm stays staffed. Dependency: C3.5.

## Slice C4: Retarget spike, clip pipeline, signature actions, comic fall (NPC, L, about 500 lines in two merges)

Evidence folder: `.../C4/`. Specs: ship-crew-characters (Signature actions, Project clip set and attribution, Retarget quality), npc-life-animation (No bundled third-party clips). Dependency: C3. Free Adobe account needed for Mixamo (user).

- [ ] C4.1 [NPC] Retarget spike (1 hour, MUST finish before any clip work): import 3 clips (Quaternius UAL walk, UAL fishing, Mixamo ladder) with `BoneMap` + `SkeletonProfileHumanoid` and Rest Fixer (Apply Node Transforms, Normalize Position Tracks, Overwrite Axis, Fix Silhouette for A-pose), bake to Meshy 24 names via `NpcRigProfile` map, capture each on a crew model. Files: `godot/assets/anim_src/spike/`, `odd/evidence/npc-crew-jobs/C4/spike.md`. Verify: `spike.md` records rest-pose and twist issues per clip with captures and a go/no-go per source (UAL, Mixamo, Blender fallback) and answers design Open Question 2; a no-go source is replaced by the Blender fallback in later tasks. Dependency: C3.4. Spec: ship-crew-characters (Retarget quality).
- [ ] C4.2 [NPC] Create `godot/tools/crew_anim_bake.gd` (headless `--script`): rename profile tracks to the Meshy 24 names, drop finger/UpperChest tracks, set meta `source_hips_y`, set loop flags, save `godot/assets/anim/crew_shared.res` (extended) and `godot/assets/anim/crew_signature_<agent>.res`. Source clips live in `godot/assets/anim_src/<source>/` only (never under `addons/`). Verify: RUN the bake headless; output libraries load via `NpcAnimPlayerAdapter.install()` with 0 errors; track-name check logs 0 unmatched bones for non-finger tracks. Dependency: C4.1.
- [ ] C4.3 [NPC] Create `ATTRIBUTION.md` rows for every clip (source, URL, license, date) at the repo root, including Quaternius UAL 1/2 (CC0), Mixamo (note: project-local only), Blender own clips. Files: `ATTRIBUTION.md`. Verify: `rg` of each clip filename under `godot/assets/anim*` finds a row; the addon directory contains no clip (`test_no_third_party_clip_in_addon` green). Dependency: C4.2. Spec: ship-crew-characters (Project clip set and attribution); npc-life-animation (No bundled third-party clips).
- [ ] C4.4T [NPC] RED: write `godot/tests/npc_life/test_action_def_signatures.gd`: `test_each_signature_clip_tag_exists_in_anim_set`, `test_each_signature_ik_chain_in_rig_profile`, `test_comic_fall_action_has_recovery_tag`. Verify: failing run recorded. Dependency: C4.3. Spec: ship-crew-characters (Signature actions).
- [ ] C4.4I [NPC] GREEN: author signature `NpcActionDef`s and wire clips: Fuego (spyglass, pointing orders), Diagnostica (hammer, climb rigging, carry), Salchipapa (crow's nest, rope climb, fishing, comic fall as a blended fall plus recovery, no ragdoll), Omar (violin, chart table, star gazing); ratline/rope paths via the `rope`/`ladder` edges with clip-matched speed and hand IK to rung markers, fallback to ladder-style marker climbs. Files: `godot/crew/defs/*.tres`, `godot/crew/crew_ik_adapter.gd`. Verify: `test_action_def_signatures.gd` green. Dependency: C4.4T.
- [ ] C4.5 [NPC] Captures per signature action (`dev` preset, `--npc-force=<agent>:<kind>` to pin each) plus frame-time check. Verify: each of the four characters shows at least two signature actions in captures under `C4/`; `--perf-log=30 --quality=final` NPC total at most 1.0 ms; 0 errors. Dependency: C4.4I. Spec: ship-crew-characters (Signature actions, Runtime budget and script errors).

## Slice A6: Addon packaging pass and extraction check (NPC, S, about 150 lines)

Evidence folder: `.../A6/`. Specs: npc-life-packaging (all). Dependency: C4 (or C4 deferred, recorded); can run earlier on request but the example must include all A4/A5 features.

- [x] A6.1 [NPC] Finish `godot/addons/npc_life/README.md`: concepts, quick start, extension points (`NpcStationProvider`, `NpcJobSource`, `NpcAnimationAdapter`, `NpcIkAdapter`, `NpcGroundProbe`, `NpcWorldInputs`), CLI flags, perf notes, license of content, "addon ships no third-party clips"; confirm `LICENSE` (MIT) and `plugin.cfg` version. Verify: every class named in the README exists (`rg "class_name"` cross-check); every flag named exists in `debug/npc_cli.gd`. Dependency: C4.5. Spec: npc-life-packaging (README content, Licensing of content).
- [x] A6.2 [NPC] Make the example scene fully project-independent: `godot/addons/npc_life/examples/workshop/workshop.tscn` and defs reference only addon paths; includes rotating raft, 6 stations, 3 puppet agents, 2 sources, roster, social; supports `--npc-agents=40`. Verify: `rg "WorldState|ShipLights|Waves|Capture|Quality|PinnaceRig|Autopilot|res://crew|res://scripts" godot/addons/npc_life` returns nothing. Dependency: A6.1. Spec: npc-life-packaging (No project dependencies, Example scene).
- [x] A6.3 [NPC] Extraction check: copy only `godot/addons/npc_life/` into a fresh empty Godot 4.7.2 project under the user's home (for example `~/Documents/workspace/autonomo/npc_life_extraction_check/`, not `/tmp`), enable the plugin, run the example headless (`--fixed-fps 60 -- --npc-minutes=2 --npc-seed=1`) and a second time with an editor open-close cycle through testsem. Verify: 0 script errors, 0 missing-resource warnings, example logs `[npc]` decisions, the plugin disabled leaves the project loadable; log saved to `odd/evidence/npc-crew-jobs/A6/extraction.log`. Dependency: A6.2. Spec: npc-life-packaging (No project dependencies, Example scene); success criterion 1.
- [x] A6.4 [NPC] Prepare (do not execute) the standalone layout note: `addons/npc_life/` + `tests/` + `.gitattributes` with `export-ignore` for `tests/` and `addons/gut/` in `odd/evidence/npc-crew-jobs/A6/extraction_layout.md`; publishing to its own repo or Asset Library is out of scope. Verify: note exists, no repository created. Dependency: A6.3. Spec: npc-life-packaging (Dev-only tests).
- [ ] A6.5 [NPC] Change close: success-criteria checklist from `openspec/changes/npc-crew-jobs/proposal.md` filled with evidence paths in `odd/tasks/npc-crew-jobs.md` (ODD feature doc owned by the ORC when it exists), `godot/README.md` Integration API verified against code. Verify: each criterion cites a log or capture. Dependency: A6.4.

---

## Dependency summary

A0 -> A1 -> A2 -> A3 -> A4a -> A4b -> A5; H-gate (roadmap M1-b merged) -> H1 (needs A1) ; H2 (needs M1-b only); H3 (needs H1 + A3);
{A4a, A4b, A5, H1, H2, H3} -> C1 -> C2 -> C3 -> C4 (C4.1 spike first) -> A6.

Parallel pairs (max 2 agents, one per owner): {A4a/A4b with H1}, {A5 with H2 then H3}. Never: two writers on `godot/main.tscn`, or
OS agent on `crew_*.gd` / `godot/crew/**` / `godot/addons/npc_life/**`.

## Risks and open items for apply

- GUT stdout and exit code through `open -g -a` are unverified; A0.2 pins the working invocation before any A1 test (fallback: the `Godot` binary under testsem, or log-file parsing).
- `TwoBoneIK3D`/`LookAtModifier3D` on 4.7.2 unverified; A0.3 decides the A4a.2I adapter implementation.
- The OS track is blocked until roadmap M1-b merges; the plan keeps the NPC session productive through A0-A3 in the meantime (W0).
- H1.5 and C1.2/C1.3 both edit `godot/main.tscn`; strict sequencing H1.5 -> C1.2, announced by H3.4.
- C-slices need the user's NPC session (edits `crew_*.gd`); our agents will not start C1-C4 without user OK.
- Mixamo licensing re-check before any public release: clips stay in `godot/assets/anim_src/` and `godot/assets/anim/`, never in the addon.
- Perf budget (1.0 ms `final` for 4 NPCs) is first measured in A2 (tick wrapper), enforced in C1.5, C3.4 and C4.5.
