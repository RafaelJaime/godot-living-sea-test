# Living Wallpaper QA Specification

## Purpose

The regression suite and release gate for the scene: fixed capture presets, frame-time measurement, unattended run, and defect checklist (baseline at M0, final at M6). With no unit runner, captures and logs are the test suite.

## Requirements

### Requirement: Fixed capture presets

The project SHALL define fixed capture presets: day calm, dusk moderate, storm and night, each with fixed camera, sea state, time of day and seed, reproducible via `--capture`. Every Godot run SHALL go through `~/.claude/bin/testsem` with `open -g`.

#### Scenario: Reproducible capture

- GIVEN a preset and the same seed
- WHEN captured twice
- THEN the images match apart from continuous wave animation phase fixed by the preset

#### Scenario: Testsem enforced

- GIVEN any QA run
- WHEN its command line is reviewed
- THEN it is wrapped in `testsem` with `open -g`

### Requirement: Baseline

M0 SHALL record per preset and per quality preset frame time at 1920x1080, captures of all four capture presets, and the T8 behaviour ranges as the baseline for later milestones.

#### Scenario: Baseline stored

- GIVEN M0 is done
- WHEN `odd/evidence/M0/` is inspected
- THEN it holds captures for all four presets, frame-time logs for `dev` and `final`, and the jitter baseline

### Requirement: Per-PR evidence

Each milestone PR SHALL include captures at the affected presets next to the matching `refs/reference_krautdev` frame, applicable logs (`--jitter-test`, `--autopilot-log`, `--rebase-test=N`), frame time per preset, and zero script errors.

#### Scenario: Missing evidence

- GIVEN a PR without a frame-time log
- WHEN reviewed
- THEN it is not accepted as meeting this requirement

#### Scenario: Script errors

- GIVEN `godot/_shots/godot.log` from the PR run
- WHEN searched for script errors
- THEN none are found

### Requirement: Housekeeping truthfulness

M0 SHALL align `godot/README.md` and `odd/tasks/living-sea-wallpaper.md` with the code (FFT not Gerstner, pinnace not galleon, checkboxes T8, T8b, R9, R6, R2, R3), commit the uncommitted sky work to its own branch before any other change, and perform no behaviour change. Branches/worktrees SHALL be removed only with explicit recorded user OK; `stable` SHALL never be modified.

#### Scenario: Sky WIP preserved

- GIVEN uncommitted sky-ambient work
- WHEN M0 starts
- THEN it is committed to its own branch before any other action

#### Scenario: No unauthorised prune

- GIVEN M0 completes
- WHEN branches and worktrees are listed
- THEN none are removed without a recorded user OK and `stable` is untouched

### Requirement: Final unattended run

M6 SHALL perform a 10-minute unattended day, storm, night run at 1920x1080 under `final`, logging frame time and script errors.

#### Scenario: Run result

- GIVEN the unattended run
- WHEN complete
- THEN the report states average fps, 1% low, and that fps is at least 60 at the agreed tier
- AND zero script errors are logged

#### Scenario: Below target

- GIVEN fps below 60 at the agreed tier
- WHEN the report is written
- THEN the shortfall is stated and tier fallback or user acceptance is recorded

### Requirement: Horizon sweep

M6 SHALL capture a 360 degree horizon sweep at three sea states.

#### Scenario: Sweep clean

- GIVEN the sweep captures
- WHEN inspected
- THEN there are no seams, cracks, speckle or popping

### Requirement: Defect checklist

The checklist SHALL cover cracks, popping, floating crew, clipping, visible keel and water in the hull, each marked clear or residual. Residuals SHALL require recorded user acceptance.

#### Scenario: Residual defect

- GIVEN a residual defect
- WHEN the checklist is completed
- THEN it is listed with a capture and user acceptance, or release is held

#### Scenario: All clear

- GIVEN no defects
- WHEN the checklist is completed
- THEN every item is marked clear with a supporting capture

### Requirement: Docs final

At M6, `godot/README.md` and `odd/tasks/living-sea-wallpaper.md` SHALL match the code and evidence.

#### Scenario: Doc sync

- GIVEN M6 completes
- WHEN the docs are compared with the merged code
- THEN each documented flag, hook and checkbox matches reality
