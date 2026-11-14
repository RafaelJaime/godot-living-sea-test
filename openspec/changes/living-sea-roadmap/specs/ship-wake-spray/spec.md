# Ship Wake and Spray Specification

## Purpose

Replace the stern ribbon with an advected, rebase-safe wake texture that follows the ship, adds a speed-driven bow wave, Kelvin arms and a turbulent centre, and rework spray emission (milestones M2b, M2c). Depends on `physics-ship-wind-coupling` for relative speed and heel.

## Requirements

### Requirement: Advected wake texture

The wake SHALL be rendered from a ping-pong texture advected in world space that follows the ship, so trail features stay fixed on the water as the ship moves away. The stern ribbon "scales" artifact SHALL be gone.

#### Scenario: Top-down wake

- GIVEN a fixed top-down capture at moderate speed
- WHEN compared with reference `ref_12s`
- THEN the wake shows a turbulent centre line and fading trail with no repeating ribbon scale pattern

#### Scenario: Trail stays fixed on water

- GIVEN two top-down captures 5 s apart while the ship moves straight
- WHEN the trail section behind the ship is compared
- THEN the older trail has moved astern with the water and faded, not translated with the ship

#### Scenario: Ship stopped

- GIVEN the ship at near-zero relative speed
- WHEN a capture is taken after 20 s
- THEN the trail has faded and no new wake is generated at the stern

### Requirement: Bow wave by relative speed

Bow wave amplitude SHALL be driven by hull-versus-water relative speed, increasing with speed and absent near zero.

#### Scenario: Speed dependence

- GIVEN `--autopilot-log` runs at two speeds with captures at the bow
- WHEN the captures are compared
- THEN the higher-speed capture shows a larger bow wave
- AND the log records the relative speeds used

### Requirement: Kelvin wake arms

The wake SHALL show V-shaped arms at approximately 19.5 degrees half-angle from the ship's track.

#### Scenario: Arm angle

- GIVEN a straight-line top-down capture at steady speed
- WHEN the arm angle is measured from the capture
- THEN it is 19.5 degrees plus or minus 4 degrees

### Requirement: Rebase continuity

The wake SHALL survive the 1600 m world rebase continuous and unbroken, with the wake window shifted consistently with the world shift.

#### Scenario: Rebase test

- GIVEN `--rebase-test=150`
- WHEN the rebase fires during a straight run
- THEN a capture sequence across the rebase shows the wake with no gap, jump or reset
- AND zero script errors are logged

#### Scenario: Turning during rebase

- GIVEN a rebase while the ship is turning
- WHEN captures are compared before and after
- THEN the curved trail is continuous

### Requirement: Spray scales with speed and slamming

Spray emission SHALL scale with speed squared and with slamming events (bow impacts on wave crests), SHALL be near zero at rest, and SHALL be count-bounded per preset.

#### Scenario: Speed squared emission

- GIVEN a logged spray emission rate at two speeds
- WHEN the ratio is computed
- THEN the rate ratio approximates the speed ratio squared within 30 percent

#### Scenario: Slamming burst

- GIVEN a bow pitch-down impact into a wave
- WHEN captured at impact
- THEN a visible spray burst occurs at the bow, exceeding the steady-state emission

#### Scenario: Particle bound

- GIVEN a 10-minute run
- WHEN spray particle counts are logged
- THEN the maximum never exceeds the preset cap (`dev` lower than `final`)

### Requirement: Wake and spray budgets

Wake SHALL cost at most 1.0 ms and spray at most 0.5 ms over the baseline under `final` at 1920x1080, with the PR reporting frame time per preset and `dev` smooth per `quality-presets`.

#### Scenario: Budget reported

- GIVEN the M2b or M2c PR
- WHEN its evidence is inspected
- THEN the measured delta per preset is recorded and within budget, or a fallback is recorded
