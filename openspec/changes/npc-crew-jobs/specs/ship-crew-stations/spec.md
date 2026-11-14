# ship-crew-stations Specification

## Purpose

Ship-side `ShipStations` adapter (project files outside the addon, our agents, after roadmap M1-b). Exposes ship stations to `npc_life` through the `StationProvider` interface, with pivot-local anchors, lantern stations, missing-access markers, and a pivot-local waypoint graph export. Must not edit `crew_*.gd`. Verified by `--capture` with station debug markers and logs. To be reconciled with the roadmap's `npc-integration-api` at archive.

## Requirements

### Requirement: ShipStations adapter and catalogue

A `ShipStations` adapter SHALL implement the addon `StationProvider` and expose stations for: helm, lanterns, spyglass post, crow's nest, ratline path, reef yards, chart table, fishing rail, repair spots, mop zones, violin seat, listen spots, boat check, social spots. All anchors SHALL be children of `Ship/Pivot` and expressed in pivot-local space.

#### Scenario: Catalogue logged
- GIVEN the ship scene loaded
- WHEN ShipStations initialises
- THEN a log line SHALL list each station kind with its count (>= 1 for every kind above)
- AND 0 script errors SHALL be logged

#### Scenario: Pivot-local anchors
- GIVEN the ship rolling and pitching in a storm
- WHEN each station's local anchor is logged at two times
- THEN local anchors SHALL be identical while world positions differ

#### Scenario: Debug capture
- GIVEN `--capture` with station debug markers enabled
- WHEN the capture completes
- THEN the image SHALL show a marker at every catalogue station and the log SHALL name them

### Requirement: Lanterns as stations

`ShipLights` SHALL register each lantern as a station with an on/off interaction; existing `ShipLights` API SHALL remain unchanged. A crew action toggling a lantern SHALL emit `lantern_changed` including the acting agent id.

#### Scenario: Registration
- GIVEN the ship with N lanterns
- WHEN ShipStations initialises
- THEN N lantern stations SHALL exist, each referencing its lantern

#### Scenario: Toggle with attribution
- GIVEN a crew agent lights lantern 2 at dusk
- WHEN the action completes
- THEN `lantern_changed` SHALL be logged with lantern index 2, state on, and the agent id

#### Scenario: API compatibility
- GIVEN existing code calling the prior `ShipLights` API
- WHEN run without ShipStations
- THEN behaviour SHALL be unchanged

### Requirement: Missing access markers and geometry

Where the ship lacks ratlines, crow's nest, door, or stairs, simple markers and simple geometry SHALL be added under `Ship/Pivot` so the station is reachable and visible. Hull and rig SHALL NOT otherwise be remodelled.

#### Scenario: Access present
- GIVEN the ship scene
- WHEN node paths are listed
- THEN markers or geometry for ratlines, crow's nest, door and stairs SHALL exist under `Ship/Pivot`

#### Scenario: Visual check
- GIVEN a capture from the deck camera
- WHEN inspected
- THEN the added geometry SHALL be visible and not intersect the hull unexpectedly (no z-fighting or floating)

### Requirement: Waypoint graph export

The ship integration SHALL export a pivot-local `WaypointGraph` from ship markers, with typed edges (walk, stairs, ladder, rope) loadable by the addon.

#### Scenario: Graph loads in addon
- GIVEN the exported graph resource
- WHEN loaded by the addon in `Ship/Pivot`
- THEN node and edge counts SHALL match the markers and no validation error SHALL be reported

#### Scenario: Every station reachable
- GIVEN the addon connectivity check from the deck root node
- WHEN run on the ship graph
- THEN it SHALL log `unreachable: 0`

### Requirement: Documentation and boundaries

`godot/README.md` Integration API SHALL document stations, the waypoint graph, furl and maneuver hooks. The ship hooks SHALL be additive and read-only for existing code, and SHALL NOT modify `crew_*.gd` or the `stable` worktree.

#### Scenario: README updated
- GIVEN the README after H1
- WHEN read
- THEN it SHALL describe the ShipStations adapter and station catalogue

#### Scenario: No crew edits
- GIVEN the H1 diff
- WHEN file paths are listed
- THEN no `crew_*.gd` file SHALL be present
