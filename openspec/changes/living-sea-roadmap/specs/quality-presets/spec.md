# Quality Presets Specification

## Purpose

Define two quality presets, `dev` and `final`, centralised in one `quality.gd` autoload that every rendering, simulation and ambient system reads. `dev` keeps the development machine responsive and is used by all agent tests and captures. `final` is the shipped wallpaper quality. Budgets in other specs are stated per preset against this contract.

## Requirements

### Requirement: Central quality autoload

The project SHALL provide a single `quality.gd` autoload exposing the active preset name (`dev` or `final`) and typed per-preset values (render scale, fps cap, feature flags, resolution/count knobs). No system SHALL hard-code a quality-dependent value that is also defined by the preset.

#### Scenario: Systems read the preset

- GIVEN the project is launched with preset `dev`
- WHEN the ocean, cloth, wake/spray, sky/cloud, SSR/SSAO/SSIL and ambient systems initialise
- THEN each logs the preset-derived values it applied (one line per system in `godot/_shots/godot.log`)
- AND `rg` for quality-dependent literals duplicated outside `quality.gd` finds none for the knobs listed in this spec

#### Scenario: Unknown preset value

- GIVEN the launch argument requests a preset name that is neither `dev` nor `final`
- WHEN `quality.gd` initialises
- THEN it falls back to `dev`, logs one warning naming the rejected value
- AND no Godot script error is logged

### Requirement: Preset selection

The active preset SHALL be selectable by a launch flag (for example `--quality=dev|final`). When no flag is given, the default SHALL be `dev`, so any agent run that omits the flag is safe for the machine. The shipped wallpaper launch configuration SHALL pass `final` explicitly.

#### Scenario: Default is dev

- GIVEN a launch without a quality flag
- WHEN the scene starts
- THEN the log reports active preset `dev`

#### Scenario: Final selected explicitly

- GIVEN a launch with `--quality=final`
- WHEN the scene starts
- THEN the log reports active preset `final`
- AND no `dev`-only reduction is applied

### Requirement: Dev preset profile

The `dev` preset SHALL apply: reduced render scale, a 30 fps cap, SSR, SSAO, SSIL and volumetric effects disabled, reduced ocean ring count and FFT resolution, halved cloth solver iterations, and reduced particle counts. All agent-run tests, captures, `--jitter-test`, `--autopilot-log`, `--rebase-test` and soak runs SHALL use `dev` unless the run exists specifically to measure `final`.

#### Scenario: Dev disables heavy features

- GIVEN preset `dev`
- WHEN the scene runs for 30 s
- THEN the log shows SSR, SSAO, SSIL and volumetrics reported as disabled
- AND measured frame rate does not exceed the 30 fps cap
- AND cloth iterations equal half of the `final` value

#### Scenario: Dev stays responsive under load

- GIVEN preset `dev` and another Godot run occupying the second testsem slot
- WHEN the scene runs for 60 s at the dev render scale
- THEN the frame-time log reports 1% low frame rate at or above 25 fps
- AND the host remains interactive (no single frame above 200 ms)

### Requirement: Final preset profile

The `final` preset SHALL provide graphics visibly better than the current scene by scaling features up rather than dropping them: full render scale, SSR, volumetric clouds, higher FFT resolution, soft shadows, TAA/FSR2, SSAO/SSIL where affordable, and full cloth iterations and particle counts. Each feature SHALL be individually gated by a `quality.gd` flag so it can be reduced without reverting code.

#### Scenario: Final enables the full stack

- GIVEN preset `final` at 1920x1080 on Apple Silicon
- WHEN the scene runs for 30 s
- THEN the log lists SSR, soft shadows, TAA/FSR2 and higher FFT resolution as enabled
- AND clouds and SSAO/SSIL are reported enabled or reported as disabled with the gating reason

#### Scenario: Budget forces a feature down

- GIVEN preset `final` where the measured frame time exceeds 16.7 ms
- WHEN the gating flag for the most expensive feature (SSR first, then cloud resolution/steps, then SSAO/SSIL) is lowered
- THEN a re-run reports the new frame time and the PR records which flag changed
- AND the feature is scaled down (for example sky-only reflection) not removed from the code

### Requirement: Per-preset performance budgets

Frame-time budgets SHALL be defined and reported per preset. `dev` SHALL be smooth on the development Mac under load (see dev scenario). `final` SHALL target at least 60 fps (frame <= 16.7 ms) at 1920x1080, Forward+, vsync off, on Apple Silicon. Every milestone PR SHALL report measured frame time per capture preset for both `dev` and, when the change affects render cost, `final`.

#### Scenario: PR reports both presets

- GIVEN a milestone PR that adds a render feature
- WHEN its evidence is reviewed under `odd/evidence/<milestone>/`
- THEN it contains frame-time logs for `dev` and for `final` at 1920x1080
- AND the per-milestone increment over the M0 baseline is stated and within the roadmap increment or a recorded tier fallback or user OK

#### Scenario: Final misses 60 fps

- GIVEN a `final` run below 60 fps at 1920x1080
- WHEN the PR is prepared
- THEN it records the shortfall and the applied tier fallback, or an explicit user acceptance
- AND is not described as meeting the target

### Requirement: Preset parity of behaviour

Gameplay-visible behaviour (ship physics, wind, weather cycle, spawn/recycle logic) SHALL be identical across presets; presets SHALL change only fidelity and cost. Physics outputs measured with `--autopilot-log` under `dev` SHALL remain representative of `final`.

#### Scenario: Autopilot log comparable

- GIVEN `--autopilot-log=120` at sea 0.5 under `dev` and under `final`
- WHEN speed, roll and pitch ranges are compared
- THEN they agree within the tolerance recorded in the M0 baseline
