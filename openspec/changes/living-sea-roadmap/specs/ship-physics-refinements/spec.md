# Ship Physics Refinements Specification

## Purpose

Finish the physics leftovers (milestone M5): keel-end lift, boat rope sag, boat-to-ship reaction load, and optional dynamic draft, without hull or draft geometry edits.

## Requirements

### Requirement: Keel-end lift targets

Keel-end emergence SHALL be reported by the `[keel]` summary at sea 0.5 and 0.9. Accepted interim targets are at most 1.1 m (sea 0.5) and 2.3 m (sea 0.9); stretch targets are 0.5 m and 1.5 m, pursued without hull or draft geometry edits.

#### Scenario: Interim met

- GIVEN `--autopilot-log` with the `[keel]` summary at sea 0.5 and 0.9
- WHEN reported
- THEN values are at most 1.1 m and 2.3 m respectively

#### Scenario: Stretch unreachable

- GIVEN stretch targets are not reached after tuning
- WHEN the PR is prepared
- THEN the values are reported against both interim and stretch targets and the shortfall is recorded, not hidden

### Requirement: Boat rope sag

The lashed boat's ropes SHALL show natural sag when slack and tension when loaded, without penetrating the hull.

#### Scenario: Slack rope

- GIVEN a calm capture of the boat in its cradle
- WHEN inspected
- THEN ropes show a visible sag curve and no hull penetration

### Requirement: Boat cradle stability

With `--log-boat`, the boat SHALL move at most 5 cm in play and never leave the cradle.

#### Scenario: Boat log

- GIVEN `--log-boat` over a 120 s run at sea 0.9
- WHEN the log is analysed
- THEN maximum displacement is at most 5 cm and the cradle-exit flag is never set

### Requirement: Boat-to-ship reaction load

The boat's load SHALL be applied to the ship as a reaction force, and the ship's roll and pitch ranges SHALL not be worse than the T8 log.

#### Scenario: Load applied

- GIVEN `--autopilot-log=120` with the boat load enabled and disabled
- WHEN roll and pitch ranges are compared
- THEN enabled values do not exceed T8 ranges and the log shows the load term being applied

### Requirement: Optional dynamic draft

Dynamic draft MAY be implemented; if so it SHALL keep keel and waterline within recorded bounds and SHALL NOT alter geometry assets.

#### Scenario: Draft bounds

- GIVEN dynamic draft enabled
- WHEN a 120 s run is logged
- THEN draft stays within recorded bounds and no hull asset is changed

### Requirement: Cost and boat state hook

M5 SHALL cost at most 0.2 ms over baseline and SHALL expose the boat-state hook described in `npc-integration-api`.

#### Scenario: Cost and hook

- GIVEN the M5 PR
- WHEN evidence is inspected
- THEN delta is at most 0.2 ms per preset and the boat-state getter is documented
