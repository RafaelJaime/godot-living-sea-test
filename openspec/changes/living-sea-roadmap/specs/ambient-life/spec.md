# Ambient Life Specification

## Purpose

Add ambient life around the ship (milestone M4). Must-haves: boids, dolphins, passing ships with lights, lighthouse beam, bioluminescence, cat's paws. Optional: whale spouts, flotsam/seaweed, wet deck, rainbow, morning fog. No crew or NPC behaviour is in scope.

## Requirements

### Requirement: Seabird boids

Gulls/albatross SHALL fly as boids with cohesion and separation, staying near the ship region, with day/night and weather appropriate presence.

#### Scenario: Visible at day

- GIVEN the day-calm capture preset
- WHEN a capture is taken
- THEN at least three birds are visible in flocking arrangement

#### Scenario: Night or storm

- GIVEN the night or storm preset
- WHEN a capture is taken
- THEN bird visibility is reduced per the rule recorded in the PR, with no pop-in within the capture window

### Requirement: Dolphins at the bow

Dolphins SHALL occasionally surf the bow wave, jumping and re-entering the water with consistent heading, only when ship speed exceeds a threshold.

#### Scenario: Bow dolphins

- GIVEN ship speed above the threshold at day
- WHEN a capture sequence is taken
- THEN at least one dolphin is visible near the bow wave in at least one frame

#### Scenario: Ship stopped

- GIVEN speed below the threshold
- WHEN 60 s pass
- THEN no new dolphin spawns

### Requirement: Passing ships with lights

Distant ships SHALL pass along the horizon with navigation lights visible at night, spawning and despawning beyond view range without popping.

#### Scenario: Night lights

- GIVEN the night preset
- WHEN a capture is taken
- THEN a distant ship shows lit running lights

#### Scenario: Despawn out of view

- GIVEN a passing ship leaves view range
- WHEN the log is inspected
- THEN it was recycled only after exiting range

### Requirement: Lighthouse beam

A lighthouse SHALL show a rotating beam at night and a dormant lamp at day.

#### Scenario: Rotating beam

- GIVEN two night captures 2 s apart with a fixed camera
- WHEN compared
- THEN the beam direction differs by the configured angular rate

### Requirement: Bioluminescence

At night, ship wake and breaking water SHALL show a faint glow that fades to none at day and requires the advected wake of `ship-wake-spray`.

#### Scenario: Night glow

- GIVEN a night top-down capture
- WHEN compared to day
- THEN the wake shows a visible glow absent at day

### Requirement: Cat's paws

Gust patches SHALL ripple the water surface driven by WindField gusts, moving with the wind.

#### Scenario: Patch moves with wind

- GIVEN two captures 5 s apart at moderate wind
- WHEN compared
- THEN darker ripple patches shift in the wind direction

### Requirement: Optional elements

Whale spouts, flotsam/seaweed, wet deck in rain, rainbow after storms and morning fog MAY be implemented. If implemented, each SHALL meet the same capture-visibility and bounded-count rules.

#### Scenario: Wet deck

- GIVEN rain is active
- WHEN the deck is captured
- THEN deck specularity is higher than in dry captures and returns to dry after rain ends

### Requirement: Bounded counts and cost

Spawn/recycle SHALL be stable: over a 10-minute run the node count of ambient systems SHALL not grow unbounded, per-preset caps SHALL apply (`dev` lower), and total ambient cost SHALL be at most 1.5 ms under `final`.

#### Scenario: Node count stable

- GIVEN a 10-minute run logging ambient node counts each minute
- WHEN analysed
- THEN the count plateaus at or below its cap

#### Scenario: Zero errors

- GIVEN the same run
- WHEN `godot/_shots/godot.log` is checked
- THEN zero script errors appear

### Requirement: No crew changes

Ambient work SHALL NOT modify `crew_*.gd` or character assets.

#### Scenario: Diff check

- GIVEN an M4 PR
- WHEN its changed paths are listed
- THEN none match `crew_*.gd` or character asset paths
