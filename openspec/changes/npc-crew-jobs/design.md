# Design: NPC Crew Jobs (reusable `npc_life` addon + ship crew integration)

## Technical Approach

Two layers with a one-way dependency: **project -> addon**, never addon -> project.

1. `godot/addons/npc_life/` (MIT, Godot 4.7, pure GDScript) is a game-agnostic "smart objects + job board + utility AI"
   framework. It knows about stations, jobs, agents, waypoint graphs, schedules, social offers and an abstract
   animation/IK adapter. It knows nothing about ships, `WorldState`, `ShipLights`, `Waves` or any project autoload.
2. The ship is one integration, written in project files: ship-side hooks (ours: `ShipStations`, per-sail
   `request_furl`, `Autopilot.maneuver_*` signals, baked pivot-local waypoint graph) and crew content (NPC session:
   job sources, four `NpcCharacterDef`s, animation adapter configuration, signature clips).

The proposal's option 1 maps directly: world-driven job sources post `NpcJob`s on an `NpcJobBoard`; every
`NpcAgent` decides on a staggered logical clock (overrides -> roster -> commitment -> softmax over utility scores with
recency penalty -> ambient fallback); the agent executes the job through a small phase machine (move along a
platform-local typed-edge graph -> align -> work -> leave) and drives animation through an `NpcAnimationAdapter`.
All spatial state of an agent lives in the local space of a `platform_root` (the ship `Pivot`), so roll, pitch, yaw
and the floating-origin `rebase()` used across the project cannot cause drift.

Specs referenced: `npc-life-stations`, `npc-life-job-board`, `npc-life-utility-ai`, `npc-life-schedules`,
`npc-life-social` (written in parallel; names below follow them: Station, Job, CharacterDef, roster, ambient job,
`override:emergency` log tag, 20 s idle bound, 4 decisions/frame stagger example).

## Architecture Decisions

### Decision: Addon is a scene-placed `NpcWorld` node, no autoload
**Choice**: The coordinator is an `NpcWorld` node the game places in its scene (one per simulated world/platform
group). The addon registers no autoload and writes no project settings on enable.
**Alternatives considered**: Addon-owned autoload singleton (the proposal allowed it if self-contained); static
registry class.
**Rationale**: Enabling the plugin must not mutate `project.godot` (A0 "enable/disable clean", A6 extraction check).
Several independent worlds (e.g. two ships, or an example scene next to the game) are possible. Deviation from the
project convention `rules.design: autoload-based state` is intentional and confined to the addon; the project keeps
its autoloads (`WorldState`, `ShipLights`) and reaches the addon only through nodes.

### Decision: `Npc` class-name prefix for every global class
**Choice**: All `class_name`s are prefixed (`NpcWorld`, `NpcStation`, `NpcJob`, `NpcAgent`, `NpcCharacterDef`, ...).
Spec terms map 1:1 (Station = `NpcStation`, CharacterDef = `NpcCharacterDef`, Job = `NpcJob`).
**Alternatives considered**: Unprefixed names (`Station`, `Job`), or no `class_name` at all with `preload` constants.
**Rationale**: Godot's global class namespace is shared across every addon of a host game; `Station`/`Job` collide
easily. `preload`-only is collision-proof but loses editor "Add Node" entries, typed exports and inspector
`Resource` pickers that the Asset Library audience expects.

### Decision: Integration through abstract adapter scripts + signals + Resources
**Choice**: Extension points are abstract base scripts the game extends: `NpcStationProvider`, `NpcJobSource`,
`NpcAnimationAdapter`, `NpcIkAdapter`, optional `NpcGroundProbe`, and `NpcWorldInputs` (blackboard). Content is
Resources (`NpcCharacterDef`, `NpcJobKindDef`, `NpcActionDef`, `NpcRoster`, `NpcRigProfile`, `NpcAnimSet`,
`NpcWaypointGraph`). Outbound events are signals on `NpcWorld`/`NpcJobBoard`/`NpcAgent`.
**Alternatives considered**: Duck-typed `has_method` calls on arbitrary nodes (the current crew style, e.g.
`ship.get("roll")`); a message bus autoload.
**Rationale**: Abstract bases give typed, documented contracts and inspector discoverability while keeping the addon
free of game knowledge. Duck typing remains allowed only inside project-side adapters.

### Decision: Blackboard (`NpcWorldInputs`) instead of the addon reading game state
**Choice**: The game feeds world facts into a string-keyed blackboard (`inputs.set_value(&"storm", 0.9)`); job
sources, scorer "need" curves and roster rules read only the blackboard and their own state.
**Alternatives considered**: Job sources reading `WorldState` directly from addon code; callbacks per fact.
**Rationale**: Keeps decision inputs explicit, loggable and replayable (the decision log snapshots the blackboard
keys consulted), which is what makes the seeded-reproducibility criterion testable. Project-side job sources may
still read autoloads directly; only addon code is restricted.

### Decision: Utility AI with softmax + recency + commitment, layered under hard overrides
**Choice**: Fixed precedence per decision: (1) emergency / all-hands override jobs, (2) roster must-staff jobs,
(3) commitment window (keep current job), (4) softmax over utility scores of eligible board jobs, (5) ambient
fallback job. Scoring is linear and weight-configurable; selection uses the agent's own seeded RNG stream.
**Alternatives considered**: Behaviour trees per character, GOAP, timeline schedules, argmax utility (rejected in
the proposal: ad-hoc coordination, overkill, predictable, predictable respectively).
**Rationale**: Softmax gives the required unpredictability with a single tunable (temperature); overrides give the
guarantees (helm staffed, storm all hands) that pure scoring cannot; commitment + recency prevent oscillation and
repetition; ambient fallback makes "never aimless" structural instead of statistical.

### Decision: Deterministic logical clock for decisions
**Choice**: `NpcWorld` accumulates `delta` into a logical clock and runs decisions on fixed logical ticks
(default 10 Hz, configurable). Agents are processed in sorted `agent_id` order; board iteration is sorted by job id;
RNG streams are `seed_for(world_seed, agent_id, stream)` (`hash` of the triple) and never the global `randf()`.
Reproducibility runs use Godot's `--fixed-fps 60` so movement (and therefore arrival times) is frame-independent.
**Alternatives considered**: Per-frame decisions with variable delta; global `seed()`.
**Rationale**: Same-seed reproduction is a success criterion. Variable frame deltas would change arrival times and
cascade into different picks; the global RNG is shared with ship/ambient code (`crew_slot.gd` uses `randf()` for the
idle seek) and would be perturbed by any unrelated change.

### Decision: Platform-local typed-edge waypoint graph, not NavigationServer3D
**Choice**: `NpcWaypointGraph` Resource stores node positions and edges in the local space of a `platform_root`.
Agents are children of `platform_root` and move by setting `position`, never `global_position`. Edges carry a type
(`walk`, `stairs`, `ladder`, `rope`) selecting speed, locomotion tag and IK. A* on demand; all-pairs distances
precomputed at load for graphs up to 256 nodes (used for scoring distance cheaply).
**Alternatives considered**: `NavigationServer3D` navmesh baked on the deck; free steering with deck raycasts.
**Rationale**: Navmeshes have no typed edges (ladders, ropes), and agents on a rolling/rotating platform would need
per-frame world <-> local conversion. Local-space motion is roll-proof by construction (the existing crew already
relies on Pivot-local placement) and immune to the project's floating-origin `rebase(shift)`.

### Decision: Ship graph baked offline to a `.tres`, loaded at runtime
**Choice**: H3 adds a `--bake-crew-graph` CLI run that builds temporary trimesh colliders (same technique as
`crew_manager.gd`, re-implemented in `ship_stations.gd`, not by editing `crew_*.gd`), snaps authored nav markers to
the deck, runs a connectivity check and saves `res://ship/crew_graph.tres`. Runtime only loads it.
**Alternatives considered**: Build the graph at `ship_ready` using `crew_manager`'s raycast snap callable.
**Rationale**: The snap colliders live inside `crew_manager.gd` (NPC-session file, `rules.apply` forbids edits) and
are freed right after `crew_ready`; a baked resource is deterministic, has zero startup physics cost, is inspectable
in the editor gizmo, and is re-baked only when the hull changes.

### Decision: Two-layer animation behind `NpcAnimationAdapter` + `NpcIkAdapter`
**Choice**: Layer 1: full-body clips addressed by **tags** (`&"walk"`, `&"climb_ladder"`, `&"work_hammer"`), resolved
through an `NpcAnimSet` Resource = shared library + per-character signature overrides. Layer 2: procedural IK chains
(hands, look-at) driven through `NpcIkAdapter` with targets supplied by stations/actions. The default implementations
port the proven project patterns: 0.35 s crossfade, hip-ratio scaling on install, IK targets clamped at 93 % reach,
1.2 s influence ramp-in, elbow pole markers.
**Alternatives considered**: AnimationTree state machine owned by the addon; clips referenced by name directly in
jobs.
**Rationale**: Tags decouple jobs from clip naming and rigs (other games remap tags), the adapter lets a game swap in
an AnimationTree, and the IK interface keeps `TwoBoneIK3D`/`LookAtModifier3D` specifics out of decision logic.

### Decision: Ship stations as an in-scene node under `Ship/Pivot`, not an autoload
**Choice**: `ShipStations` (ours) is a node in its own sub-scene `godot/ship/ship_stations.tscn`, instanced under
`Ship/Pivot`, extending `NpcStationProvider`. It creates `NpcStation` children (pivot-local) from authored markers,
lanterns and rig bones. A plain-data API (`get_stations() -> Array[Dictionary]`) is also exposed for the README.
**Alternatives considered**: `ShipStations` autoload (exploration wording).
**Rationale**: Stations must live in platform-local space and some anchors follow moving rig parts (braced yards);
autoloads sit outside the ship tree. This follows the existing in-ship pattern (`Helm`, `CrewRig`, `CrewMarkers`,
`PinnaceRig` under `Ship/Pivot`). A separate sub-scene limits our `main.tscn` edit to one instance line, reducing
conflicts with the NPC session's C1 edits.

### Decision: Crew-driven furl per sail with automatic fallback
**Choice**: `pinnace_rig.gd` keeps one furl value per sail. `request_furl(idx, t)` sets that sail's target; when
storm > `furl_storm` (0.86) and a sail has received no crew request for `furl_grace_s` (default 20 s), its target is
forced to the existing automatic value. `sail_power` uses the mean furl.
**Alternatives considered**: Crew-only furl (no fallback); keep the global scalar and let the crew only "animate"
reefing.
**Rationale**: Confirmed default 2. Fallback keeps the ship safe when the crew is disabled (`--crew=legacy`), busy,
or the addon is off; per-sail state makes the crew's work visibly causal.

### Decision: Deck-level reef stations (haul at the pin rail), yard climbing optional
**Choice**: Each sail gets a `reef_line` station at the deck pin rail; the effect of the haul action is
`request_furl(idx, ramp)`. Yard/ratline climbing is a separate optional `rope` path used by signature actions
(Diagnóstica, Salchipapa) when the graph provides it.
**Alternatives considered**: Reefing only by climbing to the braced yards.
**Rationale**: Hand IK on moving braced yards is the highest-risk item; anchoring the causal reef job on the deck
keeps C3 deliverable, while climbing stays a visual enrichment with a fallback to ladder-style marker climbs.

### Decision: Retarget into a profile, bake to the Meshy 24-bone names
**Choice**: Source clips (Quaternius UAL 1/2, Mixamo) are imported with Godot `BoneMap` + `SkeletonProfileHumanoid`
and Rest Fixer; a project bake script renames profile tracks to the Meshy rig names via an `NpcRigProfile` mapping,
drops tracks for bones the rig lacks (fingers, UpperChest), writes `source_hips_y` metadata and saves project
`AnimationLibrary` resources. Blender hand-made clips are the fallback.
**Alternatives considered**: Re-import the characters themselves with a BoneMap (renames their bones to profile
names); retarget everything in Blender.
**Rationale**: Renaming the characters' bones would break every existing bone-name reference (`LeftArm`, `neck`,
`Hips` in `crew_rig.gd`, `violin.gd`, `crew_pose_modifier.gd`). Baking keeps the runtime rig untouched and reuses the
existing `CrewAnim.install()` hip-ratio contract.

### Decision: GUT, dev-only, tests outside the addon folder
**Choice**: GUT installed at `godot/addons/gut/` (dev-only, never referenced by `npc_life`), tests at
`godot/tests/npc_life/`. On extraction the standalone repo uses `addons/npc_life/` + `tests/` with
`.gitattributes export-ignore` for `tests/` and `addons/gut/`.
**Alternatives considered**: Tests inside `addons/npc_life/tests/` (ships test code to users); `.gdignore` inside the
addon (GUT could not load them); gdUnit4.
**Rationale**: Confirmed decision (GUT, not shipped). Keeps the addon folder a clean, copy-only artifact for the A6
extraction check.

## Module Layout (`godot/addons/npc_life/`)

```
addons/npc_life/
├── plugin.cfg                     name="NPC Life", script="plugin.gd"
├── plugin.gd                      EditorPlugin: gizmo plugins, inspector plugin, custom types (no autoload)
├── LICENSE                        MIT
├── README.md                      concepts, quick start, extension points, CLI flags, perf notes
├── core/
│   ├── npc_world.gd               NpcWorld: logical clock, tick budget, RNG streams, registries, signals
│   ├── npc_world_inputs.gd        NpcWorldInputs: blackboard (StringName -> Variant), change log
│   ├── npc_rng.gd                 NpcRng: seeded stream wrapper (RandomNumberGenerator), seed_for()
│   └── npc_decision_log.gd        NpcDecisionLog: ring buffer + optional file sink, summary metrics
├── stations/
│   ├── npc_station.gd             NpcStation (Node3D): kind, tags, slots, approach, facing, IK targets, claims
│   ├── npc_station_slot.gd        NpcStationSlot (Marker3D): per-slot anchor/approach/facing override
│   └── npc_station_provider.gd    NpcStationProvider (Node): abstract; default = group "npc_station" scan
├── jobs/
│   ├── npc_job.gd                 NpcJob (RefCounted): runtime job record
│   ├── npc_job_kind_def.gd        NpcJobKindDef (Resource): defaults per kind (base score, needs, action)
│   ├── npc_job_board.gd           NpcJobBoard (RefCounted, owned by NpcWorld): post/clear/claim/expire
│   └── npc_job_source.gd          NpcJobSource (Node): abstract poller + effect/finish callbacks
├── brain/
│   ├── npc_utility_scorer.gd      NpcUtilityScorer (RefCounted): score(), softmax_pick(), recency
│   ├── npc_needs.gd               NpcNeeds: per-agent need levels (grow/satisfy)
│   └── npc_ambient.gd             ambient fallback job factory (idle-at-station, look-around, chat offer)
├── schedule/
│   ├── npc_roster.gd              NpcRoster (Resource): watches, shift length, min staff, eligibility
│   └── npc_watch_scheduler.gd     NpcWatchScheduler (NpcJobSource): must-staff jobs, rotation, handover
├── social/
│   └── npc_social_director.gd     NpcSocialDirector (NpcJobSource): gatherings, conversations, audiences
├── nav/
│   ├── npc_waypoint_graph.gd      NpcWaypointGraph (Resource): nodes, typed edges, A*, all-pairs cache
│   ├── npc_waypoint_graph_node.gd NpcWaypointGraphInstance (Node3D): binds a graph to a platform_root (+gizmo)
│   ├── npc_navigator.gd           NpcNavigator (RefCounted): path follow in local space, edge-type locomotion
│   └── npc_ground_probe.gd        NpcGroundProbe: optional abstract height correction (default: none)
├── agent/
│   ├── npc_agent.gd               NpcAgent (Node3D): brain + navigator + executor + adapters
│   ├── npc_job_executor.gd        phase machine MOVE -> ALIGN -> WORK -> LEAVE, effect timing
│   ├── npc_character_def.gd       NpcCharacterDef (Resource)
│   └── npc_action_def.gd          NpcActionDef (Resource): signature/generic action (tags, IK, effect time)
├── anim/
│   ├── npc_animation_adapter.gd   NpcAnimationAdapter (RefCounted): abstract
│   ├── npc_anim_player_adapter.gd default: AnimationPlayer + NpcAnimSet, crossfade, hip-ratio install
│   ├── npc_procedural_adapter.gd  skeleton-less puppet adapter (bob/tilt by tag) for the example scene
│   ├── npc_anim_set.gd            NpcAnimSet (Resource): tag -> clip, shared library + signature overrides
│   ├── npc_ik_adapter.gd          NpcIkAdapter (RefCounted): abstract chains (hand_l, hand_r, look)
│   ├── npc_two_bone_ik_adapter.gd default: TwoBoneIK3D/LookAtModifier3D, 93 % clamp, ramp-in, poles
│   └── npc_rig_profile.gd         NpcRigProfile (Resource): bone names per chain + retarget name map
├── debug/
│   ├── npc_debug_overlay.gd       CanvasLayer + Label3D per agent, path lines, station occupancy
│   └── npc_cli.gd                 parses `--npc-*` user args (seed, log, force, freeze, step, debug)
├── editor/
│   ├── npc_station_gizmo.gd       EditorNode3DGizmoPlugin: anchor, approach, facing arrow, slots
│   ├── npc_graph_gizmo.gd         EditorNode3DGizmoPlugin: nodes/edges colored by type, drag handles
│   └── npc_graph_inspector.gd     EditorInspectorPlugin: add/remove/connect nodes, edge type picker
├── examples/workshop/
│   ├── workshop.tscn              rotating raft with 6 stations, 3 puppet agents, 2 sources, roster, social
│   ├── workshop_sources.gd        example job sources (day/night lamp, chores, free time)
│   └── defs/*.tres                3 example NpcCharacterDefs, roster, job kinds, graph
└── icons/*.svg                    own-made icons (MIT)
```

## Interfaces / Contracts

```gdscript
# ---- core ---------------------------------------------------------------
class_name NpcWorld extends Node
@export var world_seed: int = 0                   # overridden by --npc-seed=N
@export var platform_root: Node3D                 # local space for agents, stations, graph
@export var graph: NpcWaypointGraph
@export var station_providers: Array[NodePath]    # empty = default group scan
@export var decision_hz := 10.0                   # logical clock
@export var max_decisions_per_frame := 2          # stagger budget
@export var commit_time_s := 5.0
@export var idle_bound_s := 20.0
@export var softmax_temperature := 0.35
var inputs: NpcWorldInputs
var board: NpcJobBoard
var decision_log: NpcDecisionLog                  # not `log`: would shadow the built-in log()
signal agent_decided(agent_id: StringName, job: NpcJob, reason: StringName) # reason: override:emergency|roster|commit|softmax|ambient|forced
signal job_effect(job: NpcJob, agent_id: StringName, effect: StringName)
signal job_finished(job: NpcJob, agent_id: StringName, result: StringName)  # done|aborted|expired|preempted
func now() -> float                                   # logical seconds
func rng_for(agent_id: StringName, stream := &"brain") -> NpcRng
func get_stations(kind := &"") -> Array[NpcStation]
func force_job(agent_id: StringName, kind: StringName) -> void   # pins next pick; logged as `forced`
func set_frozen(frozen: bool) -> void
func step(ticks := 1) -> void                          # while frozen

# ---- stations -----------------------------------------------------------
class_name NpcStation extends Node3D
@export var station_id: StringName
@export var kind: StringName                      # helm, lantern, reef_line, listen_spot, ...
@export var tags: PackedStringArray
@export var slot_count := 1                       # or NpcStationSlot children
@export var approach_offset := Vector3(0, 0, 0.6) # local to the station
@export var facing_deg := 0.0                     # yaw about platform +Y: 0 = -Z (bow), +90 = -X (port); same as ShipLantern
@export var anim_tag: StringName                  # default work tag
@export var ik_targets: Dictionary[StringName, NodePath] # chain -> target node (may move every frame)
@export var required_tags: PackedStringArray      # agent must have all
@export var must_staff := false
func claim(agent_id: StringName, slot := -1) -> int   # slot index or -1
func release(agent_id: StringName) -> void
func occupant(slot: int) -> StringName
func anchor_local(slot: int, platform: Node3D) -> Transform3D  # re-read each frame: platform^-1 * global
func approach_local(slot: int, platform: Node3D) -> Vector3
func ik_target(chain: StringName) -> Node3D            # null if absent (spec: optional IK target)

class_name NpcStationProvider extends Node
func provide_stations() -> Array[NpcStation]           # virtual
signal stations_changed()

# ---- jobs ---------------------------------------------------------------
class_name NpcJob extends RefCounted
var id: StringName                     # unique; duplicate post = update in place (spec: Duplicate id)
var kind: StringName
var source_id: StringName
var priority := 0.0
var urgency := 0.0                     # base; grows by urgency_rate per s until deadline
var urgency_rate := 0.0
var required_tags := PackedStringArray()
var station_id: StringName             # optional
var slots := 1                         # multi-slot (spec: Multi-slot job)
var ttl_s := 120.0                     # expiry even if claimed (spec: Claimed job expires)
var override := &""                    # "" | must_staff | emergency | all_hands
var action: NpcActionDef               # null = kind default
var payload := {}                      # source-private data (e.g. lantern_id, sail_idx)
var claimed_by: Array[StringName] = []

class_name NpcJobSource extends Node
@export var source_id: StringName
@export var poll_hz := 2.0
func _poll(world: NpcWorld, now: float) -> void: pass                                   # post/clear
func _on_job_effect(job: NpcJob, agent: NpcAgent, effect: StringName) -> void: pass     # world side effect
func _on_job_finished(job: NpcJob, agent: NpcAgent, result: StringName) -> void: pass

# ---- characters / actions ----------------------------------------------
class_name NpcCharacterDef extends Resource
@export var agent_id: StringName
@export var display_name: String
@export var roles: PackedStringArray                 # also act as tags
@export var tags: PackedStringArray
@export var preferences: Dictionary[StringName, float] # kind -> -1..1
@export var skills: Dictionary[StringName, float]      # kind or roster watch -> 0..1
@export var needs: Dictionary[StringName, float]       # need -> growth per minute
@export var signature_actions: Array[NpcActionDef]
@export var anim_set: NpcAnimSet
@export var rig_profile: NpcRigProfile
@export var temperature_scale := 1.0                   # personality: more/less erratic
@export var walk_speed := 1.2

class_name NpcActionDef extends Resource
@export var action_id: StringName
@export var job_kinds: PackedStringArray     # which kinds this action can perform
@export var anim_tag: StringName
@export var duration_range := Vector2(6, 14) # seconds of WORK phase
@export var effect_at := 0.5                 # fraction of WORK when job_effect fires
@export var effect: StringName               # e.g. &"light", &"haul"
@export var ik: Dictionary[StringName, StringName] # chain -> station ik target key
@export var look_at: StringName              # station ik key or &"partner"/&"performer"
@export var props: Array[PackedScene]        # optional (spyglass, hammer) attached by the adapter

# ---- animation / IK -----------------------------------------------------
class_name NpcAnimationAdapter extends RefCounted
func bind(agent: NpcAgent, visual_root: Node) -> bool: return false
func play(tag: StringName, loop := true, blend := 0.35) -> void: pass
func has_tag(tag: StringName) -> bool: return false
func set_locomotion(edge_type: StringName, speed: float) -> void: pass  # tag via anim_set.locomotion[edge_type]
func attach_prop(scene: PackedScene, socket: StringName) -> Node3D: return null

class_name NpcIkAdapter extends RefCounted
func bind(agent: NpcAgent, skeleton: Skeleton3D, profile: NpcRigProfile) -> bool: return false
func set_target(chain: StringName, target: Node3D, weight := 1.0, ramp_s := 1.2) -> void: pass
func clear(chain: StringName, ramp_s := 0.5) -> void: pass
func set_look_at(target: Node3D, weight := 1.0) -> void: pass
func process(delta: float) -> void: pass     # clamp proxies, ramps (called by NpcAgent)

# ---- navigation ---------------------------------------------------------
class_name NpcWaypointGraph extends Resource
@export var positions: PackedVector3Array    # platform-local
@export var node_tags: Array[StringName]      # e.g. &"deck_waist", station ids near the node
@export var edges: PackedInt32Array           # pairs a,b
@export var edge_types: Array[StringName]     # walk|stairs|ladder|rope (parallel to edges/2)
@export var edge_cost_mul: PackedFloat32Array
func find_path(from_local: Vector3, to_local: Vector3) -> PackedInt32Array
func distance(from_node: int, to_node: int) -> float   # all-pairs cache when nodes <= 256
func nearest_node(p_local: Vector3) -> int
func check_connectivity(root_node: int) -> Array[int]   # unreachable nodes
```

Ship-side contracts (ours, project files):

```gdscript
# godot/scripts/ship_stations.gd  (scene node under Ship/Pivot)
class_name ShipStations extends NpcStationProvider
func get_stations() -> Array[Dictionary]   # plain data, pivot-local: {id, kind, anchor, approach, facing_deg, level, slots, anim_tag, ik:{}, occupied_by}
func graph() -> NpcWaypointGraph           # loads res://ship/crew_graph.tres
# CLI: --bake-crew-graph (writes graph + connectivity log), --debug-stations (markers + labels)

# godot/scripts/pinnace_rig.gd (additive)
signal furl_changed(idx: int, value: float)
func sail_count() -> int
func request_furl(idx: int, t: float) -> void   # t in 0..1, stamps last crew request time
func get_furl(idx: int) -> float
@export var furl_grace_s := 20.0                # fallback delay before auto-furl overrides an unrequested sail

# godot/scripts/autopilot.gd (additive)
signal maneuver_started(kind: StringName, side: float)   # kind: &"tack" (on _tack_side flip), &"beat" (tacking false->true)
signal maneuver_ended(kind: StringName)                  # rudder settled (|rudder| < 0.1 for 3 s) or 30 s timeout

# godot/scripts/ship_lights.gd (additive, API unchanged)
# get_lanterns() entries gain: stand_local (pivot-local), local_position (pivot-local)
```

## Data Flow

Per frame (`NpcWorld._process(delta)`):

```
 game adapters ──set──> NpcWorldInputs (storm, daylight, maneuver, ...)
        │
        ▼
 NpcWorld clock += delta ──(every 1/decision_hz)──> logical tick T
        │
        ├─ sources due this tick (poll_hz) ── _poll() ──> NpcJobBoard.post/clear
        │                                                   │ expire(T), urgency(T)
        ├─ decision queue (sorted agent ids, round-robin, ≤ max_decisions_per_frame)
        │      agent.decide(T):
        │        1 override jobs (emergency/all_hands) ─┐
        │        2 roster must-staff jobs              ─┤──> claim on board + station
        │        3 commitment window? keep current     ─┤
        │        4 eligible jobs ─ NpcUtilityScorer ─ softmax(rng_agent) ─┤
        │        5 ambient fallback                    ─┘──> NpcDecisionLog (T, agent, pick, reason, top-k scores, inputs used)
        │
        └─ every agent, every frame:
               NpcJobExecutor: MOVE (NpcNavigator, local-space path, edge type ─> anim.set_locomotion)
                               ALIGN (rotate to station facing, ik.set_target ramps)
                               WORK  (anim.play(tag); at effect_at ─> world.job_effect ─> source._on_job_effect)
                               LEAVE (release station + board claim ─> job_finished)
               NpcIkAdapter.process(delta)  (93 % clamp proxies, ramps)
```

Ship example of one causal chain (dusk lantern):

```
WorldState.daylight < 0.30 ─> ShipLights.lighting_needed(ids)
   ─> LanternJobSource (NPC session) posts job lantern:<id> {station lantern_<id>, urgency_rate}
   ─> agent picks via softmax ─> walks pivot-local path ─> reach IK to lantern
   ─> job_effect(&"light") ─> LanternJobSource calls ShipLights.light(id)
   ─> ShipLights.lantern_changed(id, true) ─> log "[crew] lantern <id> lit by <agent_id>"
```

Storm reef chain: `storm > 0.8` blackboard -> `StormJobSource` posts `all_hands` reef jobs per sail (station
`reef_line_<idx>`) -> WORK effect `haul` repeats every 2 s calling `PinnaceRig.request_furl(idx, +0.25)` -> sail
furls; any sail unrequested for 20 s past 0.86 falls back to auto-furl (logged `[rig] auto-furl fallback sail <i>`).

## Scheduling, Social and Ambient Details

- **Scoring** (per eligible job `j`, agent `a`):
  `s = w_base*kind.base + w_need*need_a(kind.satisfies) + w_pref*pref_a[kind] + w_skill*skill_a[kind]
       - w_dist*dist(a, j)/ref_dist + w_urg*urgency_j(T) + priority_j - R*exp(-(T - last_done_a[kind])/tau)`.
  Weights live in `NpcWorld` defaults, overridable per `NpcCharacterDef`. Softmax:
  `p_i = exp((s_i - s_max)/(T_world*temperature_scale)) / sum`, sampled with the agent's `brain` stream. Top-k (3)
  scores are logged for tuning.
- **Commitment**: a non-override job keeps the agent for `commit_time_s` after pick; job completion, expiry, or an
  override ends it early.
- **Roster** (`NpcWatchScheduler`): for each watch (e.g. `helm`, `min_staff=1`, `shift_s=180`), posts a `must_staff`
  job bound to the station. Next keeper = softmax over eligible agents of `skill[watch] - fatigue` excluding the
  current keeper (rotation; Fuego favoured by skill). Handover: relief job posted `handover_lead_s` before shift end;
  the keeper releases only when the relief reports ALIGN complete at the station (overlap => minimum staffing never
  violated). If no relief is available, the keeper's shift extends (logged). In `all_hands`, watches flagged
  `keep_during_emergency` (helm) stay staffed; the scheduler prefers the highest skill (captain takes the helm).
- **Social** (`NpcSocialDirector`): conversation offers are jobs posted by an initiator agent (`chat_offer:<id>`)
  claimable by one partner; both get `look_at = partner`. Performer stations (violin seat) post `listen` jobs while
  occupied, with ring slots generated at radius `r` around the performer, facing it; performer leaving clears them.
  Gatherings: social spots with multi-slot stations, ended by a timer or a pre-empting override.
- **Ambient** (never aimless): built from the agent's last station or the nearest station tagged `ambient_ok`;
  variants `idle_at_station`, `look_around`, `chat_offer`; duration 8–20 s, low base score so any real job wins.
  `idle_max_seconds` per agent is tracked from the gap between job_finished and next claim; above `idle_bound_s` it
  is logged as `FAIL idle_bound`.

## Performance Design

Budget: <= 1.0 ms CPU per frame on `final` for 4 NPCs (addon + crew GDScript), measured, and scalable by stagger.

| Item | Strategy | Target (4 NPCs) |
|------|----------|-----------------|
| Decisions | logical 10 Hz, ≤ 2 decisions/frame, scoring O(jobs) with all-pairs distance lookup | ≤ 0.15 ms amortized |
| Job sources | `poll_hz` 1–2 Hz, signal-driven where possible (ShipLights, Autopilot) | ≤ 0.05 ms |
| Path follow | A* only on job change; per-frame lerp along cached local polyline | ≤ 0.08 ms |
| IK targets | proxy clamp per chain per frame (existing pattern), native `TwoBoneIK3D` solve | ≤ 0.30 ms |
| Pose modifier | existing `CrewPoseModifier` (unchanged cost, already in today's frame) | baseline |
| Debug overlay / log file | off by default, zero cost when disabled (no nodes created) | 0 |

Measurement: `NpcWorld` wraps its tick in `Time.get_ticks_usec()` and publishes `Performance.add_custom_monitor(
"npc_life/tick_usec")` plus a 10 s rolling max/avg in the log (`[npc] perf avg=… max=…`). Crew-level A/B: same run
with `--crew=legacy` vs default, `final` preset, frame-time delta reported. Scalability check: example scene with
`--npc-agents=40` asserts ≤ `max_decisions_per_frame` decisions in any frame (spec "Staggered updates"). Further
optional LOD hook: `NpcAgent.update_interval` for off-camera agents (not needed for 4).

## Debug and Editor Tooling

- CLI (addon, game-agnostic, all prefixed): `--npc-seed=N`, `--npc-log[=path]`, `--npc-debug`,
  `--npc-force=<agent>:<kind>`, `--npc-freeze`, `--npc-step=N`, `--npc-minutes=N` (auto-quit + summary),
  `--npc-agents=N` (example only).
- Overlay: per-agent `Label3D` (job, phase, reason), path polyline, station occupancy colors; CanvasLayer list with
  top-k scores of the last decision.
- Decision log line format (stable, diffable):
  `[npc] T=000123 agent=Papi_Fuego pick=helm:watch reason=roster top=[helm 2.10, mop 0.80, fish 0.55]`.
  Reproducibility check = byte-equal `[npc] T=` lines between two runs with same seed and `--fixed-fps 60`.
- Editor: station gizmo (anchor sphere, approach dot, facing arrow, slot markers, must-staff color); graph gizmo
  (nodes as handles, edges colored by type); inspector plugin buttons "Add node at cursor", "Connect selected",
  edge type dropdown, "Check connectivity".

## Ship Integration (project-side)

### Station catalogue (H1, ours)

| Kind | Anchor source | Notes |
|------|---------------|-------|
| `helm` (must_staff) | `Helm` node, hand targets `Helm.hand_l/hand_r` | ik: hand_l, hand_r; facing bow |
| `lantern` × N | `ShipLantern.stand_local`, `stand_facing_deg`; ik target = lantern | from `ship_lantern` group |
| `spyglass_post`, `crows_nest` | new markers (crow's nest + simple platform mesh if absent) | rope edge to reach nest |
| `ratline_path` | markers along shrouds -> graph `rope` edges | optional climbing |
| `reef_line_<idx>` | pin-rail markers, one per sail | effect -> `request_furl` |
| `chart_table`, `violin_seat`, `listen_spot`, `social_spot` | markers; violin seat reuses barrel position | listen ring from performer |
| `fishing_rail`, `repair_spot`, `mop_zone`, `boat_check` | markers; boat check near `lashed_boat` | M4c/M5 inputs optional |
| access: `stairs`, `door` | markers + simple step geometry (default 1) | deck levels y≈6.5 / 1.85 / 3.5 |

Markers live in `godot/ship/ship_stations.tscn` (Marker3D with metadata `kind`, `slots`, `facing_deg`,
`edge_to`, `edge_type`), positioned in Pivot space. `--debug-stations` shows them in a `--capture`.

### Job sources and characters (NPC session)

- `godot/crew/sources/`: `lantern_source.gd` (ShipLights signals), `storm_source.gd` (all-hands reef/secure,
  blackboard `storm`), `maneuver_source.gd` (`Autopilot.maneuver_*`), `chores_source.gd` (mop, repair, boat check,
  periodic with jitter from its own seeded stream), `leisure_source.gd` (fishing, music, star gazing, conversation;
  weighted by calm/night). Calm pacing = few long relaxed jobs; storm = override all hands.
- `godot/crew/crew_world_bridge.gd`: writes `WorldState`/Ship facts into `NpcWorldInputs` each logical tick
  (daylight, storm, wind, roll, maneuver).
- `godot/crew/defs/`: `papi_fuego.tres` (helm skill 0.9, spyglass, pointing orders), `papi_diagnostica.tres`
  (hammer, rigging climb, carry), `el_salchipapa.tres` (crow's nest, rope climb, fishing, comic fall), `don_omar.tres`
  (violin, chart table, star gazing), `crew_roster.tres`, `crew_rig_profile.tres` (Meshy 24 names), `crew_anim_set.tres`.
- Migration: a new `godot/crew/crew_npc.gd` spawns `NpcAgent`s reusing `crew_slot.gd` model loading; `crew_rig.gd`
  logic (pose modifier, helm IK, violin) is reached through the project `NpcIkAdapter`/actions. `--crew=legacy`
  keeps the current static path until C3 is verified.

### Animation sourcing pipeline (C4, NPC session)

```
UAL 1/2 GLB (CC0) ─┐
Mixamo FBX (free) ─┼─> godot/assets/anim_src/<source>/  (project only, never in addons/)
Blender clips ─────┘        │ import: BoneMap + SkeletonProfileHumanoid, Rest Fixer
                            │ (Apply Node Transforms, Normalize Position Tracks, Overwrite Axis,
                            │  Fix Silhouette for A-pose sources), no root motion
                            ▼
              tools/crew_anim_bake.gd (headless --script)
                 profile names -> Meshy 24 names (crew_rig_profile.tres map)
                 drop finger/UpperChest tracks, set meta source_hips_y, loop flags
                            ▼
   res://assets/anim/crew_shared.res (extended)  +  crew_signature_<agent>.res
                            ▼
   NpcAnimPlayerAdapter.install() (hip-ratio scaling, same contract as CrewAnim.install)
```

- 1 h spike before C4 on 3 clips (UAL walk, UAL fishing, Mixamo ladder) with captures; record rest-pose and twist
  issues. Hands/props: procedural IK (no finger bones). Ladder rung mismatch solved by moving along the `ladder` edge
  at clip-matched speed with hand IK to rung markers.
- Fallback per missing clip: hand-made in Blender on the Meshy rig, exported to `assets/anim_src/blender/`.
- `ATTRIBUTION.md`: one row per clip (source, URL, license, date). The addon ships no third-party clips.

## File Changes

| File | Action | Owner | Description |
|------|--------|-------|-------------|
| `godot/addons/npc_life/**` (layout above) | Create | NPC session | Addon code, Resources, editor tools, example, LICENSE, README |
| `godot/addons/gut/**` | Create | NPC session | GUT dev-only test framework (not referenced by addon) |
| `godot/tests/npc_life/*.gd` | Create | NPC session | GUT suites |
| `godot/project.godot` | Modify | NPC session (A0) | Enable `npc_life` and `gut` editor plugins only; no autoload |
| `godot/ship/ship_stations.tscn` | Create | Ours (H1) | Station + nav markers, access geometry |
| `godot/scripts/ship_stations.gd` | Create | Ours (H1/H3) | `ShipStations` provider, plain-data API, graph bake + connectivity |
| `godot/ship/crew_graph.tres` | Create | Ours (H3) | Baked pivot-local graph |
| `godot/scripts/ship_lights.gd` | Modify | Ours (H1) | Additive local-space fields in `get_lanterns()` |
| `godot/scripts/pinnace_rig.gd` | Modify | Ours (H2) | Per-sail furl, `request_furl`, fallback, `furl_changed` |
| `godot/scripts/autopilot.gd` | Modify | Ours (H2) | `maneuver_started/ended` signals |
| `godot/main.tscn` | Modify | Ours (H1: one instance line) then NPC session (C1) | Sequential, never concurrent |
| `godot/README.md` | Modify | Ours (H1–H3) | Integration API: stations, furl, maneuver, graph |
| `godot/crew/**` (sources, defs, bridge, crew_npc.gd) | Create | NPC session | Ship crew integration |
| `godot/scripts/crew_*.gd` | Modify | NPC session only | Legacy flag, adapter wiring |
| `godot/tools/crew_anim_bake.gd`, `godot/assets/anim*/**` | Create/Modify | NPC session | Clip pipeline |
| `ATTRIBUTION.md` | Modify | NPC session | Clip licenses |

Ship hooks (H1–H3) start only after roadmap M1-b is merged (shared `pinnace_rig.gd`/buoyancy files).

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit (GUT, headless) | Board post/clear/duplicate/claim/multi-slot/tags/expiry/urgency; station claim/release/competition/constraints/stale claim; scorer factors; softmax at T=0.01 (≥99 % top) and T=1 (all picked) with fixed seed; recency; commitment; overrides; ambient on empty board; roster handover/no-relief/staffed-from-start/rotation share; social lifecycle; A* + typed edges + connectivity; RNG stream independence | `godot/tests/npc_life/test_*.gd`; run `~/.claude/bin/testsem -- open -g -n -W -a /Applications/Godot.app --args --headless --path godot -s addons/gut/gut_cmdln.gd -gdir=res://tests/npc_life -gexit` |
| Integration (example scene) | Rotating platform drift (max local error logged), 10-min idle metric, same-seed byte-equal log, stagger with 40 agents, perf monitor | headless example run with `--npc-seed`, `--npc-minutes`, `--fixed-fps 60` |
| Extraction (A6) | Addon alone in an empty Godot 4.7 project | copy `addons/npc_life/` into a scratch project under the user's home, run example, 0 errors, grep for project autoload names |
| Ship functional (H/C) | Station markers capture, furl requests + fallback (`--weather=storm`), maneuver signal on tack, graph connectivity, dusk/dawn lantern agent ids, storm all hands, helm rotation share, captures of signature actions, frame-time A/B | existing CLI flags via testsem with `open -g`, `dev` preset for captures, `final` for perf; 0 script errors in `godot/_shots/godot.log` |

Strict TDD is `false` in `openspec/config.yaml`; GUT is adopted for the addon only. Ship hooks keep functional CLI
verification (no unit runner on the project side), reported honestly.

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration
boundary. The `--npc-*` and `--bake-crew-graph` flags are in-process Godot user args; the bake writes one
`res://` resource only.

## Migration / Rollout

- Slices in the proposal order; each is a direct merge to local `main`, reverted by reverting that merge.
- `--crew=legacy` (default until C3 verified) keeps today's static `CrewSlot` behaviour; then the default flips and
  legacy stays one release as a fallback.
- Ship hooks are additive: `request_furl` optional with auto-furl fallback, signals and `ShipStations` read-only for
  existing code. Disabling the plugin in Project Settings only removes editor tooling (gizmos, inspector); the addon
  scripts under `res://` stay loadable, so the ship and crew keep running.
- The `stable` worktree is never modified.

## Risks

| Risk | Mitigation |
|------|------------|
| Reproducibility broken by frame-rate-dependent inputs (WorldState, ship motion) | Logical clock, sorted iteration, per-agent streams, `--fixed-fps 60` in repro runs; log compares decision lines only |
| `TwoBoneIK3D` / `LookAtModifier3D` / GUT behaviour on 4.7.2 unverified | A0 spike; adapters isolate engine APIs; fallback to functional checks |
| Hand IK on braced, moving yards | Deck-level reef stations carry the causal job; climbing optional; anchors re-read per frame; 93 % clamp |
| Retarget quality (A-pose, no fingers, twist) | Bake to Meshy names, Rest Fixer, 1 h spike, Blender fallback |
| Addon leaks project assumptions | No autoload, blackboard inputs, A6 extraction + grep check |
| `main.tscn` shared between our H1 and the NPC session C1 | Separate sub-scene, one instance line, strict sequencing |
| Graph stale after hull change | Bake-time connectivity check fails loudly; README documents re-bake |
| Perf above 1.0 ms on `final` | Custom monitor, stagger budget, debug off by default, LOD interval hook |

## Open Questions

- [ ] Exact deck coordinates/presence of ratlines, crow's nest, door and stairs on the current pinnace GLB (resolved
      during H1 with `--debug-deck`; default 1 adds markers/geometry). Not blocking.
- [ ] Which UAL Standard clips retarget cleanly (C4 spike). Not blocking for A/H slices.
- [ ] Whether `maneuver_ended` should use rudder settle or heading convergence (decided in H2 from logs). Not blocking.
