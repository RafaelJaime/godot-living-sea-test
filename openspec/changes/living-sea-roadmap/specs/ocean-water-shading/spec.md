# Ocean Water Shading Specification

## Purpose

Realistic shading of the FFT ocean: Fresnel sky reflection (SSR with sky fallback), crest subsurface scattering, far-field normal filtering without speckle, and island shallows caustics (milestones M2a, M2d). Preset-dependent costs follow `quality-presets`.

## Requirements

### Requirement: Fresnel sky reflection with SSR and sky fallback

The water SHALL reflect the sky with a Fresnel term (more reflective at grazing angles). Under `final` the reflection SHALL use screen-space reflections with a sky-probe fallback where SSR has no hit; under `dev` it SHALL use sky-only reflection. The reflected colour SHALL track the current sky (time of day, weather).

#### Scenario: Dusk reflection matches sky

- GIVEN the dusk-moderate capture preset with a fixed camera
- WHEN a capture is taken and compared with the matching `refs/reference_krautdev` frame
- THEN the water near the horizon shows the sky's dusk colours
- AND no hard seam is visible where SSR hits end and fallback begins

#### Scenario: Dev uses sky-only reflection

- GIVEN preset `dev`
- WHEN the scene runs
- THEN the log reports SSR disabled and the water still shows sky reflection in the capture

#### Scenario: SSR cost within budget

- GIVEN preset `final` at 1920x1080
- WHEN frame time is measured with and without SSR over 60 s
- THEN the SSR delta is at most 1.5 ms or a tier fallback is recorded in the PR

### Requirement: Crest subsurface scattering

Wave crests lit from behind SHALL show a teal-green transmitted glow whose strength increases as the sun moves behind the waves relative to the camera, and SHALL be absent when the sun is not behind the waves.

#### Scenario: Sun behind waves

- GIVEN a fixed camera facing the sun at moderate sea state
- WHEN a capture is taken
- THEN crests show teal glow comparable to the reference frame `ref_12s`

#### Scenario: Sun in front of the camera side

- GIVEN the same sea state with the camera facing away from the sun
- WHEN a capture is taken
- THEN crest glow is visibly weaker than in the sun-behind capture

#### Scenario: Night

- GIVEN the night capture preset
- WHEN a capture is taken
- THEN no sun-driven crest glow is visible

### Requirement: Far-field normal filtering

Water normals SHALL be filtered with distance (mipmapped or equivalent) so the horizon region shows no speckle, shimmering or moire in still captures or between consecutive frames.

#### Scenario: Horizon capture free of speckle

- GIVEN a horizon-facing fixed camera at each of calm, moderate and storm sea states
- WHEN a capture is taken
- THEN the horizon band shows no visible high-frequency speckle

#### Scenario: Temporal stability

- GIVEN two captures 1 frame apart at a fixed camera and the horizon band
- WHEN they are compared
- THEN the horizon band differs only by smooth wave motion, with no frame-to-frame sparkle

### Requirement: Seamless horizon preserved

Shading changes SHALL NOT introduce a seam, tint step or popping at ocean cascade/LOD boundaries or at the 1600 m world rebase.

#### Scenario: Rebase continuity

- GIVEN `--rebase-test=150`
- WHEN the rebase occurs
- THEN captures before and after show no water-shading discontinuity at the horizon or ring boundaries
- AND the log shows zero script errors

### Requirement: Island shallows caustics

Water over island shallows SHALL show animated caustic light patterns whose intensity falls off with depth and is absent in deep water and at night when no light source drives them.

#### Scenario: Caustics near an island

- GIVEN a fixed camera on an island shore at day
- WHEN a capture is taken
- THEN the shallows show a caustic pattern, fading to none past the depth cutoff

#### Scenario: Caustics cost

- GIVEN preset `final`
- WHEN frame time is measured at the island with caustics on and off
- THEN the delta is at most 0.3 ms

### Requirement: Water shading validation

The M2a/M2d PRs SHALL include fixed-preset captures, frame-time logs per preset, and zero Godot script errors in `godot/_shots/godot.log`.

#### Scenario: Evidence present

- GIVEN the M2a PR
- WHEN `odd/evidence/M2a/` is inspected
- THEN it holds the horizon, sun-behind-waves and dusk captures, the frame-time log, and a log with zero script errors
