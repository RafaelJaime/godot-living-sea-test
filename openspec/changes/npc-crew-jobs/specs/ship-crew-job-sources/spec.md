# ship-crew-job-sources Specification

## Purpose

Ship job sources implementing the addon `JobSource` interface (NPC session): lanterns, storm, maneuvers, chores, free time, and pacing. Verified by logs and captures on the ship (`--start-phase`, `--weather`, `--autopilot-log`).

## Requirements

### Requirement: Dusk and dawn lanterns

A lantern source SHALL post a light job per lantern at dusk and an extinguish job at dawn. Each lantern SHALL be toggled by a crew agent.

#### Scenario: Dusk run
- GIVEN `--start-phase` dusk with lanterns off
- WHEN the run progresses past the dusk threshold
- THEN every lantern SHALL be lit and each `lantern_changed` log entry SHALL carry an agent id

#### Scenario: Dawn run
- GIVEN lanterns on at dawn
- WHEN dawn threshold passes
- THEN every lantern SHALL be extinguished by a crew agent id

#### Scenario: No duplicate toggling
- GIVEN a lantern job claimed by agent A
- WHEN other agents decide
- THEN none SHALL claim the same lantern job

### Requirement: Storm all-hands

A storm source SHALL post reef and secure jobs for all sails and loose gear when storm intensity crosses a configured threshold (below 0.86), flagged all-hands override. All four agents SHALL take storm jobs; the helm SHALL remain staffed.

#### Scenario: Storm run
- GIVEN `--weather=storm`
- WHEN the storm threshold is crossed
- THEN each of the 4 agents SHALL log a storm job (reef, secure or helm)
- AND the sails SHALL be furled through `request_furl` with `furl_source=crew`

#### Scenario: Helm stays staffed
- GIVEN the all-hands event
- WHEN logs are examined
- THEN the helm SHALL show zero unstaffed ticks

#### Scenario: Storm ends
- GIVEN the storm subsides
- WHEN intensity falls below the release threshold
- THEN storm jobs SHALL clear and agents SHALL return to normal pacing

### Requirement: Maneuver jobs

A maneuver source SHALL consume `Autopilot.maneuver_started/ended` and post sail-handling jobs for the duration of a tack or jibe.

#### Scenario: Tack response
- GIVEN a tack begins
- WHEN `maneuver_started tack` is logged
- THEN at least one agent SHALL log a maneuver job within 5 s
- AND jobs SHALL clear after `maneuver_ended`

### Requirement: Chores and free time with calm pacing

Periodic chores (mop, repair, boat check) and free-time jobs (fishing, music, star gazing, conversation) SHALL be posted at a relaxed rate in calm weather: few concurrent relaxed jobs, not all agents busy at once with chores.

#### Scenario: Calm log
- GIVEN a 10-minute calm run
- WHEN the job log is summarised
- THEN the log SHALL show chores and free-time jobs with fewer than 3 concurrent chore jobs at any time
- AND at least one free-time job per agent over the run

#### Scenario: Seeded variety
- GIVEN two runs with different seeds
- WHEN the job sequences are compared
- THEN they SHALL differ
- AND the same seed SHALL reproduce the log exactly

### Requirement: Helm always staffed with skill-weighted rotation

The helm SHALL be staffed 100% of the run with a skill-weighted rotating watch between at least 2 crew, Fuego most frequent.

#### Scenario: 10-minute unattended run
- GIVEN a 10-minute `dev` preset run
- WHEN helm roster log is summarised
- THEN unstaffed time SHALL be 0 s
- AND at least 2 distinct agents SHALL hold the helm
- AND Fuego SHALL hold the most shifts

### Requirement: Never aimless on the ship

No crew agent SHALL be without an active job for more than 20 s.

#### Scenario: Idle metric
- GIVEN a 10-minute run in calm weather
- WHEN `idle_max_seconds` is reported per agent
- THEN every value SHALL be <= 20

### Requirement: Legacy fallback flag

A project flag (e.g. `--crew=legacy`) SHALL keep the static `CrewSlot` behaviour.

#### Scenario: Legacy mode
- GIVEN `--crew=legacy`
- WHEN the ship runs
- THEN no `npc_life` job logs SHALL appear and the crew SHALL stand on `CrewSlot` markers as before
