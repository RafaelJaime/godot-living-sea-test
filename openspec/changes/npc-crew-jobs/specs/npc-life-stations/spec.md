# npc-life-stations Specification

## Purpose

Smart-object work stations for the `npc_life` addon (`godot/addons/npc_life/`). A `Station` is a game-agnostic node that describes where and how an agent works, and who occupies it. Verifiable by GUT unit tests and by the standalone example scene; no dependency on this project's autoloads.

## Requirements

### Requirement: Station declaration

A `Station` node SHALL expose: a work anchor, an approach point, a facing direction, N slots (N >= 1), an animation tag, optional IK target markers, optional constraints (required tags, minimum skill), and an occupancy state. All spatial data SHALL be expressed in the Station's own local space.

#### Scenario: Station with defaults
- GIVEN a `Station` node added to an empty scene with no configuration
- WHEN the scene is run
- THEN the Station SHALL have exactly 1 slot, 0 occupants, and report `is_free() == true`
- AND no script error is logged

#### Scenario: Multi-slot station
- GIVEN a `Station` configured with 3 slots
- WHEN occupancy is queried
- THEN `free_slots()` SHALL return 3 and `capacity()` SHALL return 3

### Requirement: Claim and release

The Station SHALL support `claim(agent)` and `release(agent)`. A claim SHALL succeed only when a slot is free and the agent satisfies the constraints. A claim SHALL be atomic: two agents claiming the last slot in the same tick SHALL result in exactly one success.

#### Scenario: Claim a free slot
- GIVEN a 1-slot Station that is free
- WHEN agent A calls `claim(A)`
- THEN the call SHALL succeed, the slot SHALL be bound to A, and `is_free()` SHALL be false
- AND a `claimed(agent, slot)` signal SHALL be emitted once

#### Scenario: Competing claims
- GIVEN a 1-slot Station that is free
- WHEN agents A and B call `claim` in the same tick
- THEN exactly one call SHALL succeed and the other SHALL fail without side effects

#### Scenario: Release
- GIVEN a Station claimed by A
- WHEN `release(A)` is called
- THEN the slot SHALL become free and a `released(agent, slot)` signal SHALL be emitted once
- AND releasing an agent that holds no slot SHALL be a no-op that does not error

#### Scenario: Constraint rejection
- GIVEN a Station requiring tag `"climber"`
- WHEN an agent without that tag calls `claim`
- THEN the call SHALL fail and the Station occupancy SHALL be unchanged

### Requirement: Stale-claim safety

When a claiming agent is freed from the scene tree, the Station SHALL release its slot automatically.

#### Scenario: Agent freed while claiming
- GIVEN agent A holds a Station slot
- WHEN A is freed
- THEN the slot SHALL become free within the same frame
- AND no dangling reference error SHALL be logged

### Requirement: Moving-parent support

Station anchors, approach point and facing SHALL resolve to world space on demand from the Station's current transform, so a Station parented to a moving or rotating node stays correct.

#### Scenario: Station on a rotating platform
- GIVEN a Station parented to a platform rotating at 30 deg/s
- WHEN world-space anchor is queried at t=0 and t=2 s
- THEN each result SHALL equal the Station's current `global_transform * local_anchor` within 1e-4 m
- AND the local anchor SHALL be unchanged

### Requirement: IK targets and animation tag

A Station SHALL expose named IK target markers (e.g. `hand_l`, `hand_r`, `look_at`) and an animation tag string. Absent markers SHALL return null, never error.

#### Scenario: Query optional IK target
- GIVEN a Station with a `hand_r` marker and no `look_at` marker
- WHEN `get_ik_target("hand_r")` and `get_ik_target("look_at")` are called
- THEN the first SHALL return the marker transform and the second SHALL return null
