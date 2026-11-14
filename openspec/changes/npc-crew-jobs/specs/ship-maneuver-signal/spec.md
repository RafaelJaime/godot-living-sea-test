# ship-maneuver-signal Specification

## Purpose

`Autopilot` maneuver signals so job sources can react to tacks and jibes (ship-side hook, our agents, slice H2). Verified by `--autopilot-log`.

## Requirements

### Requirement: Maneuver signals

`Autopilot` SHALL emit `maneuver_started(kind, ...)` when a tack or jibe begins and `maneuver_ended(kind, ...)` when it completes. Each pair SHALL be matched. Kind SHALL be one of `tack`, `jibe`.

#### Scenario: Tack logged
- GIVEN the autopilot with `--autopilot-log`
- WHEN a tack begins
- THEN the log SHALL contain `maneuver_started tack` with a timestamp
- AND on completion `maneuver_ended tack`

#### Scenario: Paired signals
- GIVEN a 10-minute run
- WHEN logs are counted
- THEN the count of `maneuver_started` SHALL equal `maneuver_ended` (or differ by at most 1 if a maneuver is in progress at end)

#### Scenario: No listeners
- GIVEN no connected consumer
- WHEN a maneuver occurs
- THEN autopilot behaviour SHALL be identical to before the change

### Requirement: Non-overlap and lead time

A started maneuver SHALL NOT be re-signalled before its end. The start signal SHOULD precede the sail/helm motion enough (configurable lead) for consumers to react.

#### Scenario: Re-entry guard
- GIVEN a maneuver in progress
- WHEN the autopilot re-evaluates heading
- THEN no second `maneuver_started` SHALL emit until `maneuver_ended`

### Requirement: Additive change

The signals SHALL be additive; existing autopilot outputs and logs SHALL keep their format.

#### Scenario: Existing log intact
- GIVEN the existing `--autopilot-log` parsers
- WHEN run after the change
- THEN prior lines SHALL parse identically
