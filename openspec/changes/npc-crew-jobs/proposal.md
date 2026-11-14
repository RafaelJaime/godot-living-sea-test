# Proposal: NPC Crew Jobs (reusable `npc_life` addon + ship crew integration)

## Intent

The four crew members stand on static `CrewSlot` markers with hardcoded roles (`crew_rig.gd`: Fuego helm IK, Omar
seated violin IK, the others idle). There is no locomotion, navigation, scheduler or job logic, so the ship looks
crewed by mannequins. The product intent is a ship that feels run entirely by its crew: each member always has a
reason to be where they are (never aimless wandering), behaviour is unpredictable and varied, and the world drives
the work (dusk lanterns, storm reefing, maneuvers, chores, free time).

New user requirement (overrides the exploration framing): the NPC system must be a REUSABLE Godot 4.7 plugin so the
NPCs and behaviours can move to other games. The ship becomes one integration of that plugin, living in project
files outside the addon.

Why now: the roadmap exposes the NPC hooks in M1-b (wobble, `sail_state`); the crew is the main remaining source of
"life" that the roadmap explicitly left to the NPC session.

Success: in an unattended run, the crew visibly works the ship (helm always staffed with rotation, lanterns lit at
dusk and extinguished at dawn by a crew member, sails reefed by the crew in storms, chores and social moments in
calm), no crew member idles without a job for more than a bounded time, two runs with different seeds differ while
one seed reproduces, and the addon runs its own example scene with zero dependency on this project.

## Ownership and project rules

- The user's NPC session executes the addon and the crew integration (`godot/addons/npc_life/`, `crew_*.gd`, crew
  characters/clips). Our agents implement only the ship-side hooks (H-slices below). Per `openspec/config.yaml`
  (`rules.proposal`), NPC/crew code is flagged as owned by the NPC session; per `rules.apply`, our agents do not touch
  `crew_*.gd` without user OK.
- Delivery: direct merges to local `main` (no PRs, user 2026-11-14). The 400 authored changed-line budget is a
  per-slice planning heuristic.
- Every Godot run goes through `~/.claude/bin/testsem` with `open -g` (focus-free); `dev` quality preset for
  development captures.

## Scope

### In Scope

Addon (`godot/addons/npc_life/`, game-agnostic, executed by the NPC session):
- Work stations / smart objects: a `Station` node (anchors, approach point, facing, slots, claim/release, anim tag,
  IK targets, constraints, occupancy) usable in any scene, on static or moving parents.
- World-driven job board: job sources post/clear jobs (priority, urgency, required tags, deadline, station refs);
  agents claim jobs; stale jobs expire.
- Utility AI: per-agent scoring (need, preference, skill, distance, urgency) with softmax selection (temperature),
  recency penalty, and hard overrides (must-staff stations, emergencies, all-hands).
- Schedules and watch rotation: rosters with shift length, skill-weighted rotation, minimum staffing guarantees.
- Social layer: gatherings, two-party conversations, audiences around a performer (listen rings), join/leave offers.
- Navigation: waypoint graph with typed edges (walk, stairs, ladder, rope), authored and baked in a parent's local
  space so it works on moving platforms; path following with per-edge-type locomotion.
- Animation adapter: shared `AnimationLibrary`, per-character signature clips, crossfade API, procedural IK hooks
  (reach, look-at, hand targets) behind an interface; no bundled third-party clips.
- Character definitions as `Resource`s: role(s), preferences, skills, signature actions, schedule.
- Seeded RNG (per world and per agent), debug overlay, force-job / freeze / step tools, decision log.
- Editor tooling: station gizmos (anchor, approach, facing, slots), waypoint graph editing and edge typing.
- Integration boundary: no autoload dependencies on this project; integration through adapter interfaces, signals
  and Resources. Optional addon-owned autoload only if it is self-contained.
- Packaging: `plugin.cfg`, `LICENSE` (MIT proposed), `README.md`, a ship-independent example scene (e.g. a small
  workshop/camp with a few stations), extractable to its own repo and Asset Library-ready.

Ship integration (project files outside the addon):
- Ship-side hooks (our agents, after roadmap M1-b): a `ShipStations` adapter exposing ship stations to the addon
  (helm, lanterns, spyglass post, crow's nest, ratline path, reef yards, chart table, fishing rail, repair spots,
  mop zones, violin seat, listen spots, boat check, social spots), pivot-local anchors; lanterns registered as
  stations via `ShipLights`; per-sail crew furl `request_furl(idx, t)` with the existing auto-furl at storm > 0.86
  kept as fallback; `Autopilot.maneuver_started` signal; pivot-local waypoint graph export from ship markers;
  markers/simple geometry for missing ratlines, crow's nest, door, stairs (default 1); README Integration API docs.
- Ship job sources (NPC session): dusk/dawn lanterns, storm reef/secure, maneuvers (tack/jibe), periodic chores
  (mop, repair, boat check), free time (fishing, music, star gazing, conversation).
- Crew characters (NPC session): four `Resource` definitions with signature actions:
  Fuego (helm, spyglass, pointing orders), Diagnóstica (hammer, climb rigging, carry), Salchipapa (crow's nest,
  rope climb, fishing, comic fall), Omar (violin, chart table, star gazing).
- Crew clips in the project (not in the addon): Quaternius UAL 1/2 (CC0), Mixamo (free account) and hand-made
  Blender clips; licenses recorded in `ATTRIBUTION.md`.

### Out of Scope
- Paid animation generation by default (Meshy/Higgsfield/MoCap Online); CMU or non-commercial mocap.
- Bundling Mixamo raw files (or any non-CC0/non-own content) inside the addon.
- `NavigationServer3D` navmeshes; GOAP; per-character behaviour trees.
- Foot IK on the rolling deck (roadmap T10, NPC session follow-up), hair/cloth on characters, ragdoll physics beyond
  a blended comic fall.
- Dialogue text, voice, player interaction, combat.
- Publishing the addon to its own repo or the Asset Library (prepared, not executed).
- Hull/rig remodelling beyond simple markers/geometry for missing access paths.
- Any change to the `stable` worktree.

## Capabilities

`openspec/specs/` is empty. The in-flight roadmap change declares `npc-integration-api` (not archived), so the ship
hooks are written as a new capability here and reconciled with it at archive.

### New Capabilities

Addon (game-agnostic):
- `npc-life-stations`: smart-object stations, slots, claim/release, occupancy, anchors in local space, IK targets.
- `npc-life-job-board`: job sources, posting/clearing/expiry, claiming, priorities and urgency.
- `npc-life-utility-ai`: scoring, softmax pick with temperature, recency penalty, hard overrides, no-idle guarantee.
- `npc-life-schedules`: rosters, shifts, skill-weighted rotation, minimum staffing.
- `npc-life-social`: gatherings, conversations, audiences around performers, join/leave.
- `npc-life-navigation`: typed-edge waypoint graph in platform-local space, pathing, edge-type locomotion.
- `npc-life-animation`: animation adapter, shared library + signature clips, crossfade, procedural IK hook interface.
- `npc-life-characters`: character definition Resources (roles, preferences, skills, signature actions, schedule).
- `npc-life-debug-tools`: seeded RNG, decision log, overlay, force-job/freeze/step.
- `npc-life-editor-tools`: station gizmos, graph editing and edge typing.
- `npc-life-packaging`: plugin boundary (no project autoloads), `plugin.cfg`, LICENSE, README, example scene.

Ship integration (project-side):
- `ship-crew-stations`: `ShipStations` adapter, station catalogue, lantern stations, missing access markers, waypoint
  graph export (ship-side hooks, our agents).
- `ship-sail-crew-furl`: per-sail crew furl request with storm auto-furl fallback (ship-side hook, our agents).
- `ship-maneuver-signal`: `Autopilot.maneuver_started` / end signals (ship-side hook, our agents).
- `ship-crew-job-sources`: lantern, storm, maneuver, chore and free-time job sources and pacing (NPC session).
- `ship-crew-characters`: the four crew definitions, signature actions and project clip set (NPC session).

### Modified Capabilities
- None (no archived specs). Reconcile with the roadmap's in-flight `npc-integration-api` at archive.

## Approach

Exploration option 1, re-cut along a plugin boundary:

1. Addon core is pure logic plus nodes with no project knowledge: `Station`, `JobBoard`, `NpcAgent`
   (brain + navigator + animator adapters), `WaypointGraph` (Resource, local to a `platform_root` Node3D),
   `CharacterDef`/`RoleDef`/`ActionDef` Resources, `NpcWorld` coordinator (seeded RNG, tick budget). Integration is
   through abstract adapter scripts (`StationProvider`, `JobSource`, `AnimationAdapter`, `IkAdapter`) and signals.
2. Decision loop: job sources post jobs; each agent scores candidate jobs (utility) and picks via softmax with a
   recency penalty; overrides pre-empt (must-staff, emergency, all-hands); if nothing scores, an always-available
   "ambient" job (idle-at-station, look-around, chat offer) prevents aimless wandering.
3. Navigation runs in platform-local coordinates (the ship `Pivot`), roll-proof by construction; edges carry a type
   that selects the locomotion clip and IK (stairs, ladder, rope).
4. Two-layer animation: full-body clips (shared library + signature clips) plus procedural IK for station work,
   following the proven helm/violin approach.
5. The ship integration is a thin project layer: `ShipStations` (ship hooks, ours) implements `StationProvider` and
   exports the waypoint graph; ship job sources and crew definitions (NPC session) implement `JobSource` and
   `CharacterDef`. `crew_rig.gd`/`crew_manager.gd` migrate to `NpcAgent` under the NPC session's control.

Rejected: behaviour trees per character (ad-hoc coordination), GOAP (overkill), timeline schedules (predictable),
NavigationServer (no typed edges, poor on a rolling moving platform).

### Milestones / slices (each with observable verification)

Order: A0 → A1 → A2 → A3 → {A4 ∥ H1 after M1-b} → A5 → H2/H3 → C1 → C2 → C3 → C4 → A6. Slices are sized against the
~400-line heuristic.

| Slice | Owner | Content | Observable verification |
|-------|-------|---------|-------------------------|
| A0 | NPC session | Addon skeleton: `plugin.cfg`, LICENSE, README stub, enable/disable clean, test runner decision applied | Plugin enables/disables in editor with 0 errors; headless project run logs 0 script errors; runner executes an empty suite |
| A1 | NPC session | Stations + job board + character Resources | Unit tests (if runner adopted) for claim/release/expiry; example scene log shows jobs posted/claimed/released |
| A2 | NPC session | Utility AI (softmax, recency, overrides, ambient fallback) + seeded RNG + decision log | Same seed => identical decision log; different seeds => different logs; no agent unassigned > N s in a 10-min headless log |
| A3 | NPC session | Waypoint graph (local space, typed edges), path follow, example on a moving/rotating platform | Example: agents reach stations on a rotating platform without drift (log max local-position error); edge types logged |
| A4 | NPC session | Animation + IK adapter, schedules/watch rotation, social layer | Example capture shows conversation/audience; roster log shows rotation and minimum staffing never violated |
| A5 | NPC session | Debug overlay, force-job/freeze/step, editor gizmos + graph editing | Force-job flag pins a job in the log; gizmos visible in editor screenshot |
| H1 | Our agents (after M1-b) | `ShipStations` adapter + station catalogue + lanterns as stations + missing access markers/geometry | `--capture` with station debug markers; README Integration API updated; 0 script errors; no `crew_*.gd` edits |
| H2 | Our agents | Per-sail `request_furl(idx, t)` with storm auto-furl fallback; `Autopilot.maneuver_started` | `--weather=storm` log shows crew furl requests honoured and fallback at > 0.86 when unrequested; maneuver signal logged on tack |
| H3 | Our agents | Pivot-local waypoint graph export from ship markers | Exported graph loads in the addon; connectivity check log: every station reachable from the deck |
| C1 | NPC session | Crew `CharacterDef`s, migrate `crew_rig`/`crew_manager` to `NpcAgent` | 4 agents spawn at stations; 0 script errors; helm staffed from start |
| C2 | NPC session | Ship job sources (lanterns, chores, free time) + calm pacing | `--start-phase` dusk run: lanterns lit by crew (`lantern_changed` logged with agent id); calm log shows few relaxed jobs |
| C3 | NPC session | Storm all-hands (reef/secure), maneuvers, helm rotation skill-weighted | Storm run: all agents on storm jobs, sails furled by crew; helm log shows Fuego most often but rotating |
| C4 | NPC session | Signature actions and clips (UAL/Mixamo/Blender), comic fall | Captures per signature action; `ATTRIBUTION.md` lists every clip source |
| A6 | NPC session | Addon packaging pass: example scene independent of the ship, README, extraction check | Copying `addons/npc_life/` alone into an empty Godot 4.7 project runs the example with 0 errors |

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `godot/addons/npc_life/**` | New | Addon code, Resources, editor plugin, example scene, LICENSE, README (NPC session) |
| `godot/addons/<test runner>/` | New (if adopted) | Dev-only test framework, not shipped with the addon (decision 1) |
| `godot/scripts/ship_stations.gd` (+ station catalogue) | New | `ShipStations` adapter and waypoint export (our agents) |
| `godot/scripts/ship_lights.gd` | Modified | Register lanterns as stations, API unchanged |
| pinnace rig script (sail furl) | Modified | `request_furl(idx, t)` + fallback |
| autopilot script | Modified | `maneuver_started` / `maneuver_ended` signals |
| ship scene markers under `Ship/Pivot` | New/Modified | Station anchors, ratline/crow's nest/door/stairs markers and simple geometry |
| `godot/scripts/crew_*.gd`, crew job sources, crew definitions | Modified/New | NPC session only |
| project clip assets, `ATTRIBUTION.md` | New/Modified | Crew clips (UAL CC0, Mixamo, Blender) |
| `godot/README.md` | Modified | Integration API: stations, furl, maneuver, waypoint graph |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Retarget quality (rest pose, A-pose sources, no finger bones) | High | 1 h UAL/Mixamo spike before C4; BoneMap + SkeletonProfileHumanoid with rest fixer; procedural IK for hands |
| Rigging/rope IK on braced, moving yards | High | Anchors re-read per frame from rig nodes; clamp reach; fallback to ladder-style climb on markers |
| Addon boundary leaks project assumptions (autoloads, ship space) | Med | Adapter interfaces only; A6 extraction check in an empty project |
| Randomness vs reproducibility for QA | Med | Seeded RNG per world/agent, decision log, force-job tool |
| Crew idles or oscillates between jobs | Med | Ambient fallback job, hysteresis/commit time, recency penalty, idle-time metric in logs |
| Walking on a rolling deck without foot IK | Med | Platform-local motion + existing counter-lean; foot IK deferred to T10 |
| IK/modifier/AI tick cost | Med | Tick budget and staggered agent updates; measure in `dev` and `final` presets |
| Shared-file conflicts with roadmap M1/M5 | Med | H-slices start after M1-b merges; one owner per file at a time |
| Mixamo license if the repo or addon goes public | Med | Clips stay in the project, never in the addon; re-check official terms (helpx returned 403) |
| Test framework compatibility with Godot 4.7 unverified | Med | Spike in A0; fall back to functional CLI checks if incompatible |
| Ship lacks ratlines/crow's nest/door/stairs | Med | Default 1: ship side adds markers/simple geometry in H1 |

## Rollback Plan

Every slice is a self-contained direct merge to local `main`; rollback = revert that merge commit. The addon is
disableable from Project Settings > Plugins, and the crew integration is gated by a project flag (e.g.
`--crew=legacy`) that keeps the current static `CrewSlot` behaviour until C3 is verified. Ship hooks are additive:
`request_furl` is optional (auto-furl fallback stays), `maneuver_started` and `ShipStations` are read-only for
existing code. The `stable` worktree is never modified.

## Dependencies

- Roadmap M1-b merged (wobble, `sail_state`, shared buoyancy/rig files) before H1–H3; M4c (`deck_wetness`) and M5
  (`lashed_boat.state()`) are optional inputs for mop and boat-check jobs.
- Godot 4.7.2; `~/.claude/bin/testsem`.
- Quaternius UAL 1/2 (CC0); a free Adobe account for Mixamo (default 4); Blender for gap clips.
- Optional test framework (decision 1).

## Success Criteria

- [ ] `addons/npc_life/` copied alone into an empty Godot 4.7 project runs its example scene with 0 script errors and
      no reference to this project's autoloads.
- [ ] 10-minute unattended ship run (`dev` preset): helm staffed 100 % of the time, rotated between at least 2 crew,
      Fuego the most frequent; no agent without an active job for more than the configured idle bound (e.g. 20 s).
- [ ] Dusk/dawn run: every lantern lit/extinguished by a crew member (agent id in the log).
- [ ] Storm run: all four agents on storm jobs; sails furled through crew requests, auto-furl only as fallback.
- [ ] Same seed reproduces the decision log; two seeds produce different job sequences.
- [ ] Each of the four characters performs at least two signature actions visible in captures.
- [ ] 0 script errors across the runs; frame-time increment within the agreed NPC budget per preset.
- [ ] `ATTRIBUTION.md` lists every clip; the addon contains only CC0/own content or none.
- [ ] `godot/README.md` Integration API documents stations, furl, maneuver and waypoint graph hooks.

## Decisions

### Proposed defaults (recorded; the user replied with the plugin requirement instead of confirming them)
1. Missing ratlines/crow's nest/door/stairs: the ship side adds markers/simple geometry (H1).
2. Sails furl when the crew reefs them; auto-furl at storm > 0.86 kept as fallback.
3. Pacing: calm = few relaxed jobs; storm = all-hands frenzy.
4. Mixamo allowed (repo local/private); the user needs a free Adobe account; clips live in the project only.
5. Helm watch: skill-weighted (Fuego more often) but rotating.

### Confirmed by the user (2026-11-15) — all pending defaults accepted
GUT as dev-only test framework (not shipped in the plugin); plugin name `npc_life`, MIT; ship-integration defaults
(markers/simple geometry for missing rigging/crow's nest/door/stairs; crew-driven furl with auto-furl fallback at
storm > 0.86; calm = few relaxed jobs, storm = all hands; Mixamo allowed with clips kept project-side only;
skill-weighted rotating helm watch with Fuego favoured); NPC frame budget <= 1.0 ms on `final`; idle limit 20 s.

### Previously pending (now confirmed above)
1. Test framework for the addon: adopt GUT (pure GDScript, MIT, headless CLI; proposed default) or gdUnit4 (richer
   scene runner and CLI, heavier), dev-only and not shipped inside the addon; or none (functional CLI checks only).
   Godot 4.7 compatibility of both is unverified. Gates A0 and the "unit tests" verification in A1–A5.
2. Addon name and license: `npc_life` + MIT proposed. Gates A0 only.
3. Confirmation of ship defaults 1–5 above. Gates H1 (1), H2 (2), C2/C3 (3, 5), C4 (4).
4. NPC frame-time budget per preset (proposed ≤ 1.0 ms `final`). Gates the success criterion, not the build.
5. Idle bound for the "never aimless" metric (proposed 20 s). Gates the success criterion only.

Independent work (A1–A3 logic, H-slice design) can proceed while these are open.
