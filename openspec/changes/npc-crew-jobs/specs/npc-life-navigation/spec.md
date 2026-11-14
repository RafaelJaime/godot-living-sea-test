# npc-life-navigation Specification

## Purpose

Waypoint graph navigation for `npc_life`, authored in the local space of a `platform_root` Node3D so it works on moving or rolling platforms. Does not use `NavigationServer3D`. Verifiable by GUT tests and an example scene with a rotating platform.

## Requirements

### Requirement: Typed-edge waypoint graph

A `WaypointGraph` Resource SHALL hold nodes (local positions) and edges with a type from at least: `walk`, `stairs`, `ladder`, `rope`. Each edge SHALL have a cost and be directional or bidirectional.

#### Scenario: Graph load
- GIVEN a graph resource with 5 nodes and 5 edges of 3 types
- WHEN loaded in a `platform_root`
- THEN node and edge counts and types SHALL match the resource

#### Scenario: Unknown edge type
- GIVEN an edge with an unregistered type
- WHEN the graph validates
- THEN validation SHALL report an error naming the edge and SHALL NOT crash

### Requirement: Platform-local pathing

Paths SHALL be computed and followed in platform-local coordinates and converted to world space only for final positioning, so platform motion does not alter the path.

#### Scenario: Rotating platform
- GIVEN a platform rotating and translating
- WHEN an agent walks a 10 m path to a station
- THEN the agent SHALL reach the station approach point
- AND the maximum local-position error to the path SHALL be <= 0.05 m (logged)

#### Scenario: Rolling platform
- GIVEN a platform rolling +-15 deg
- WHEN an agent walks
- THEN the agent local height SHALL stay equal to the path height (no sliding from platform motion)

### Requirement: Path queries

The graph SHALL return the lowest-cost path between nodes or snap arbitrary local points to the nearest node. Unreachable targets SHALL return an empty path and a reason, not an error.

#### Scenario: Shortest path
- GIVEN two routes of cost 4 and 7
- WHEN a path is requested
- THEN the cost-4 route SHALL be returned

#### Scenario: Unreachable
- GIVEN a station whose node is disconnected
- WHEN a path is requested
- THEN the result SHALL be empty with reason `unreachable`
- AND the agent SHALL mark the job not-eligible and pick another

### Requirement: Connectivity check

The addon SHALL provide a connectivity check reporting every station not reachable from a given root node.

#### Scenario: Full connectivity
- GIVEN all stations have nodes connected to the root
- WHEN the check runs
- THEN it SHALL log `unreachable: 0`

#### Scenario: Disconnected station
- GIVEN one disconnected station
- WHEN the check runs
- THEN it SHALL log that station's identity

### Requirement: Per-edge locomotion

Path following SHALL select locomotion state and IK hint from the current edge type (walk, stairs, ladder, rope) via the animation adapter and log the edge type on traversal.

#### Scenario: Edge type logged
- GIVEN a path with walk then ladder edges
- WHEN the agent traverses it
- THEN the log SHALL show `walk` then `ladder` entries in order and the animator SHALL receive the matching locomotion tag

### Requirement: Agent collision courtesy

Agents on the same edge SHALL avoid occupying the same position by waiting or sidestepping within a bounded delay.

#### Scenario: Two agents, one corridor
- GIVEN two agents opposite on a single walk edge
- WHEN they meet
- THEN both SHALL pass within 5 s without deadlock
