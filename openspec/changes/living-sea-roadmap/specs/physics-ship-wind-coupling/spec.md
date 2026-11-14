# Physics Ship and Wind Coupling Specification

## Purpose

Drive ship propulsion from the same WindField that animates sails and flags, via `SailRig.get_sail_forces()` / `WindField.sample`, remove the start-up glitch, and make hull foam follow heel (milestone M1).

## Requirements

### Requirement: Single wind model for propulsion

Ship propulsion SHALL derive from `SailRig.get_sail_forces()` using `WindField.sample`, not from `sail_force_local` plus WorldState wind. A flag SHALL keep the legacy force path selectable until M6.

#### Scenario: Thrust follows gusts

- GIVEN `--autopilot-log=120` at sea 0.5
- WHEN the log is analysed
- THEN thrust or acceleration correlates positively with logged WindField gust magnitude

#### Scenario: Legacy fallback flag

- GIVEN the legacy-force flag is set
- WHEN the scene runs for 60 s
- THEN propulsion uses the legacy path, the log states so, and no script error occurs

### Requirement: Behaviour envelope preserved

With the new force path, speed, roll and pitch SHALL stay within the ranges of the T8 autopilot log at sea states 0.2, 0.5 and 0.9.

#### Scenario: Sea-state ranges

- GIVEN `--autopilot-log=120` at sea 0.2, 0.5 and 0.9
- WHEN ranges are compared with the T8 log
- THEN speed, roll and pitch fall inside the T8 ranges (or each deviation is recorded and accepted)

#### Scenario: Backed sail

- GIVEN a heading that backs the sails
- WHEN the autopilot runs for 60 s
- THEN the ship does not diverge (no NaN, no speed above the T8 maximum) and the log shows zero script errors

### Requirement: Settled start-up

At scene start the ship SHALL begin in or near equilibrium so the hull underside is never visible and no launch transient appears.

#### Scenario: First 10 seconds

- GIVEN a fixed side-view camera
- WHEN captures are taken at 0, 2, 5 and 10 s
- THEN no capture shows the hull underside or keel clear of the water, and roll/pitch stay within the T8 envelope

### Requirement: Heel-aware hull foam

The hull foam footprint SHALL follow the hull waterline outline as the ship heels, with the foam on the leeward side growing with heel.

#### Scenario: Heeled top-down capture

- GIVEN a top-down capture with the ship heeled
- WHEN inspected
- THEN foam traces the heeled hull outline and not the upright outline

### Requirement: Stability metrics

`--jitter-test` results SHALL be no worse than the M0 baseline, and the ship-wobble hook SHALL be emitted (see `npc-integration-api`).

#### Scenario: Jitter not worse

- GIVEN the M0 baseline jitter value
- WHEN `--jitter-test` runs after M1
- THEN the result is less than or equal to the baseline plus the recorded tolerance

### Requirement: Cost

The coupling SHALL cost at most 0.3 ms over the M0 baseline per preset.

#### Scenario: Cost reported

- GIVEN M1 evidence
- WHEN the frame-time log is inspected
- THEN the delta is at most 0.3 ms or a fallback is recorded
