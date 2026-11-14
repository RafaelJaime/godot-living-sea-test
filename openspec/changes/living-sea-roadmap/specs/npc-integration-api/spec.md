# NPC Integration API Specification

## Purpose

Document and keep stable the hooks the separate NPC/crew session consumes. This spec covers hooks, signals and getters only. NPC behaviour, `crew_*.gd` and character assets are out of scope and SHALL NOT be modified.

## Requirements

### Requirement: Existing hooks documented and stable

`godot/README.md` SHALL document in an Integration API section: `ShipLights` (`get_lanterns`, `light`, `extinguish`, `is_lit`; signals `lighting_needed`, `extinguish_suggested`, `lantern_changed`); Ship (`roll`, `pitch`, rates, `yaw`, `yaw_rate`, `rudder`, `forward`, `current_speed`, `linear_velocity`); WorldState (`daylight`, `night`, `storm`, `cloud`, `wind_vector`, `wind_speed_ms`, `sun_elevation_deg`); and the deck raycast.

#### Scenario: Names match code

- GIVEN the README section
- WHEN each documented name is searched in `godot/`
- THEN every name exists with the documented kind (signal, getter or property)

#### Scenario: Run does not break hooks

- GIVEN a scene run after changes
- WHEN the log is checked
- THEN no missing-member error on a documented hook appears

### Requirement: New read-only hooks

The following SHALL be added as read-only getters or signals, with no NPC logic: sail state summary and ship-wobble signal (M1), boat state (M5), deck wetness (M4c). Each SHALL be documented when added.

#### Scenario: Sail state summary

- GIVEN M1 merged
- WHEN a test script calls the sail summary getter
- THEN it returns the documented fields and does not modify state

#### Scenario: Ship-wobble signal

- GIVEN a sea state that induces roll beyond the documented threshold
- WHEN `--autopilot-log` runs
- THEN the signal emission is logged, with at least one emission and none at calm

#### Scenario: Deck wetness

- GIVEN rain active (M4c, if implemented)
- WHEN the getter is read before, during and after rain
- THEN value rises during rain and decays after

### Requirement: Hooks are non-mutating

Hooks SHALL be getters or signals only; consuming them SHALL NOT alter simulation outcomes.

#### Scenario: Determinism

- GIVEN two `--autopilot-log=120` runs, one with a script polling every hook each frame
- WHEN logs are compared
- THEN speed, roll and pitch agree within the recorded tolerance

### Requirement: Breaking-change changelog

Any breaking change to a hook SHALL be announced in a README changelog entry in the same PR, and no PR SHALL edit `crew_*.gd` or character assets without user OK.

#### Scenario: Rename announced

- GIVEN a PR renaming a hook
- WHEN reviewed
- THEN it has a changelog entry naming old and new

#### Scenario: Crew files untouched

- GIVEN any milestone PR
- WHEN changed paths are listed
- THEN none match `crew_*.gd` or character asset paths without a recorded user OK
