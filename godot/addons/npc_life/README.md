# NPC Life 0.1.0

Game-agnostic "smart objects + job board + utility AI" for Godot 4.7: stations that characters claim, a job board that world-driven
sources post to, agents that decide with a seeded softmax over utility scores (so crews behave in varied, reproducible ways),
platform-local navigation on a typed-edge waypoint graph (works on rolling ships and rotating rafts), and abstract animation and IK adapters.

- Pure GDScript, MIT (see `LICENSE`). No autoload, no project settings, no dependency on any game code. Every global class is prefixed `Npc`.
- The addon ships **no third-party animation clips or models**. The example uses a procedural stick-figure puppet and generated clips.
- Dev-only tests (GUT) live outside this folder, in the host project's `tests/npc_life/`; they are not needed to use the addon.

## Concepts

| Concept | Class | What it is |
|---|---|---|
| World | `NpcWorld` | A node you place in your scene. Owns the logical clock (decisions run on fixed ticks), the blackboard `inputs`, the job `board`, the registries. Set `platform_root` (the node whose local space everything lives in: a ship pivot, a raft) and `graph`. |
| Blackboard | `NpcWorldInputs` | The game writes world facts with `world.inputs.set_value(&"daylight", 0.2)`. Sources, the scorer and rosters read only this. |
| Station | `NpcStation` (+ `NpcStationSlot`) | A smart object: kind, slots, approach point, facing, animation tag, IK target nodes. |
| Job | `NpcJob`, `NpcJobBoard` | A task on the board: kind, station, priority, required tags, optional `override` (`must_staff`, `emergency`, `all_hands`). |
| Source | `NpcJobSource` | Posts and clears jobs from world facts. |
| Character | `NpcCharacterDef`, `NpcActionDef`, `NpcJobKindDef` | Data (Resources): roles, tags, preferences (-1..1), skills (0..1), needs, signature actions with cooldowns, walk speed, decision temperature. |
| Agent | `NpcAgent` | One autonomous character. Decision order: emergency overrides, roster must-staff, commitment, softmax over utility, ambient fallback. |
| Navigation | `NpcWaypointGraph`, `NpcNavigator` | Typed edges (`walk`, `stairs`, `ladder`, `rope`) with cost multipliers; paths are platform-local. |
| Schedule | `NpcRoster`, `NpcWatchDef`, `NpcWatchScheduler` | Watches with shifts, minimum staffing, handover overlap, emergency suspension. |
| Social | `NpcSocialDirector` | Conversations, gatherings, audiences. |
| Animation | `NpcAnimationAdapter`, `NpcAnimPlayerAdapter`, `NpcProceduralAdapter`, `NpcAnimSet`, `NpcRigProfile` | Tag to clip resolution, crossfades, hip-height scaling, props. |
| IK | `NpcIkAdapter`, `NpcTwoBoneIkAdapter` | Hand reach and look-at with ramps; a pole is required for `TwoBoneIK3D` on 4.7. |

## Quick start

1. Copy `addons/npc_life/` into your project and enable it in Project Settings > Plugins (it only adds gizmos and an inspector for the graph).
2. Add an `NpcWorld` node under your moving platform and set `platform_root` and `graph` (an `NpcWaypointGraph` resource, or add an `NpcWaypointGraphInstance` and edit it in the viewport).
3. Add `NpcStation` nodes (or an `NpcStationProvider` that creates them from your own data) and `NpcAgent` nodes with an `NpcCharacterDef`.
4. Add job sources (subclass `NpcJobSource`) and, if you need staffed posts, an `NpcWatchScheduler` with an `NpcRoster`.
5. Optional: give each agent an animation adapter and an IK adapter (`agent.anim`, `agent.ik`).

A complete runnable scene is in `examples/workshop/workshop.tscn` (rotating raft, 6 stations, 3 puppet agents, 2 sources, roster, social director).

## Extension points

- `NpcStationProvider`: override `provide_stations()` to build stations from your data.
- `NpcJobSource`: override `_poll(world, now)`; use `post_job`, `clear_job`, and the `_on_job_effect` / `_on_job_finished` hooks.
- `NpcAnimationAdapter` and `NpcIkAdapter`: implement them with any animation system; no engine IK type appears in their signatures.
- `NpcGroundProbe`: optional height correction for walking agents.
- `NpcWorldInputs`: your game's facts; `value_changed` is emitted on every change and changes are logged with a sequence number.

## Command line (everything after `--`)

`--npc-seed=N`, `--npc-log[=path]`, `--npc-debug`, `--npc-force=<agent>:<kind>`, `--npc-freeze`, `--npc-step=N`, `--npc-minutes=N`, `--npc-agents=N` (examples only).
The same seed gives byte-equal logs with `--fixed-fps 60`. Unknown flags are ignored.

## Performance notes

- Decisions are staggered (`max_decisions_per_frame`, default 2) on a 10 Hz logical tick. Typical cost is tens of microseconds per tick for a handful of agents.
- The monitor `npc_life/tick_usec` is registered in Debugger > Monitors.
- Any `WorkerThreadPool` use must be waited on in `_exit_tree`; the addon itself uses none.

## Licence of content

Code: MIT. The addon contains no third-party clips, models or sounds; if you add your own animation library through `NpcAnimSet`, its licence is yours to track.
