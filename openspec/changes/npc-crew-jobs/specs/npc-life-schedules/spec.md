# npc-life-schedules Specification

## Purpose

Rosters, shifts, skill-weighted rotation and minimum staffing guarantees for `npc_life`. Verifiable by GUT tests and the example scene roster log.

## Requirements

### Requirement: Roster and shift definition

A `Roster` SHALL define, per must-staff station: eligible agents, shift length, and minimum staffing (>= 1). Shift length MAY be randomised within a range using the seeded RNG.

#### Scenario: Roster loads
- GIVEN a roster with a station "helm", agents A and B, shift length 60 s
- WHEN the world starts
- THEN exactly one of A or B SHALL be assigned to "helm" at t=0

### Requirement: Minimum staffing never violated

A must-staff station SHALL have at least its minimum staffing at every tick, including during handover.

#### Scenario: Handover overlap
- GIVEN A holds "helm" and the shift expires
- WHEN B is to take over
- THEN B SHALL reach the station and take the slot BEFORE A is released
- AND the roster log SHALL show zero ticks with staffing below minimum

#### Scenario: Relief unavailable
- GIVEN A's shift expires and no other eligible agent is free
- WHEN the handover time arrives
- THEN A SHALL remain on the station and the shift SHALL be extended
- AND an `extended_shift` event SHALL be logged

#### Scenario: Staffed from start
- GIVEN a world with a must-staff station and at least one eligible agent
- WHEN the first tick runs
- THEN the station SHALL already be staffed (no unstaffed interval at start)

### Requirement: Skill-weighted rotation

The next watch holder SHALL be chosen by weighted random selection where weight derives from the agent's skill for that role. The same agent MAY be re-chosen, but a configurable maximum consecutive shifts SHALL force rotation when at least 2 eligible agents exist.

#### Scenario: Favoured but rotating
- GIVEN Fuego skill 0.9 and Omar skill 0.5 for "helm"
- WHEN 200 shifts are simulated with fixed seeds
- THEN Fuego SHALL hold more shifts than Omar
- AND Omar SHALL hold at least one shift
- AND no agent SHALL hold more consecutive shifts than the configured maximum

#### Scenario: Single eligible agent
- GIVEN only one eligible agent for a station
- WHEN the maximum consecutive shifts is reached
- THEN the agent SHALL continue without a staffing gap

### Requirement: Emergency suspension

All-hands events SHALL suspend normal shifts while preserving minimum staffing of must-staff stations if the event permits.

#### Scenario: All-hands with helm
- GIVEN an all-hands job is active and the helm is must-staff
- WHEN the roster ticks
- THEN the helm SHALL stay staffed by one agent while the rest take all-hands jobs
