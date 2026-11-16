# Sky, Light and Weather Specification

## Purpose

A sky and lighting system consistent across the day and weather cycle: clouds, sun/sky/fog/ambient consistency, auto-exposure, SSAO/SSIL, crisp shadows, storm darkness and rain, plus camera and island polish (milestone M3). Targets references `ref_15s` and `ref_18s`.

## Requirements

### Requirement: Clouds behind a gate

Clouds SHALL be rendered by the Sunshine Clouds 2 addon if it works on Godot 4.7.2 and costs at most 2.5 ms at 1920x1080 under `final`; otherwise a custom layered shader SHALL be used. Cloud resolution/steps SHALL be preset-driven; under `dev` they SHALL be reduced or replaced by a cheap layer. Addon use SHALL be recorded in `ATTRIBUTION.md`.

#### Scenario: Gate decision recorded

- GIVEN the M3 cloud work
- WHEN the evidence is inspected
- THEN it records addon load success on 4.7.2, measured cloud ms at 1920x1080, and the chosen path

#### Scenario: Addon rejected

- GIVEN the addon fails to load or exceeds 2.5 ms
- WHEN the scene runs
- THEN the custom layered clouds are used and zero script errors are logged

#### Scenario: Dev clouds cheap

- GIVEN preset `dev`
- WHEN the scene runs
- THEN no volumetric cloud pass runs and clouds are still visible

### Requirement: Sun, sky, fog and ambient consistency

Sun direction and colour, sky colours, fog and ambient light SHALL be consistent at every time of day and weather state, with no mismatched horizon, tint step or ambient jump.

#### Scenario: Preset matrix

- GIVEN fixed captures at dawn, day, dusk and night, each in clear and storm
- WHEN compared with the references
- THEN each shows sun/sky/fog consistent with its time and weather, with no visible horizon tint step

#### Scenario: Continuous transition

- GIVEN a `--timescale` day run
- WHEN frames are logged across a day
- THEN ambient and fog values change continuously, with no per-frame jump above the recorded threshold

### Requirement: Stable auto-exposure

Exposure SHALL adapt to scene brightness without visible pumping (oscillation) across a `--timescale` day run and storm onset.

#### Scenario: No pumping

- GIVEN a `--timescale` day run
- WHEN the logged exposure is analysed
- THEN it has no sign-alternating oscillation above the recorded amplitude and rate threshold

### Requirement: Ambient occlusion and shadows

Under `final`, SSAO/SSIL SHALL be active where affordable, and the ship SHALL cast crisp, soft-edged shadows on deck and water. Combined cost of SSAO/SSIL and shadows SHALL be at most 1.0 ms, and both SHALL be disabled under `dev` per `quality-presets`.

#### Scenario: Ship shadows

- GIVEN a day capture of the deck
- WHEN inspected
- THEN rigging and sail shadows on the deck have defined edges without shimmer between consecutive frames

#### Scenario: Dev disabled

- GIVEN preset `dev`
- WHEN the scene runs
- THEN the log reports SSAO/SSIL disabled

### Requirement: Storm darkness and rain

During storms the scene SHALL darken, desaturate, reduce visibility, and show rain visible as streaks over the camera view. Rain intensity SHALL follow `WorldState.storm` and fade out when it ends. Rain particle count SHALL be bounded per preset.

#### Scenario: Storm capture

- GIVEN a storm preset capture
- WHEN compared with day clear
- THEN the scene is visibly darker with visible rain and reduced horizon visibility

#### Scenario: Storm end

- GIVEN the storm ends
- WHEN 60 s of scene time pass
- THEN rain is no longer visible and brightness has returned to day clear

### Requirement: Camera and island polish

The camera SHALL keep the sun unoccluded, include close-ups, helm and storm shots, and islands SHALL read as finished at each time of day.

#### Scenario: sun unoccluded

- GIVEN the fixed shot presets
- WHEN each capture is inspected
- THEN the sun is not occluded by sails, rigging or geometry in any preset shot

#### Scenario: Island at dusk and night

- GIVEN island captures at dusk and night
- WHEN inspected
- THEN island lighting matches the sun/sky state with no unlit or black patches

### Requirement: Evidence and cost

M3 SHALL report cost per feature (clouds at most 2.5 ms, SSAO/SSIL plus shadows at most 1.0 ms under `final`), preset captures, and zero script errors.

#### Scenario: Evidence

- GIVEN the M3 PR
- WHEN the evidence folder is inspected
- THEN it holds the preset matrix captures, frame-time logs per preset, and a log with zero script errors
