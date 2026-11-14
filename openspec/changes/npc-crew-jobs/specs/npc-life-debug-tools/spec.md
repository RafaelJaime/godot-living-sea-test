# npc-life-debug-tools Specification

## Purpose

Seeded randomness, decision log, overlay, and force-job / freeze / step tools for `npc_life`. These make unpredictable behaviour reproducible for QA. Verifiable by GUT tests and headless example runs.

## Requirements

### Requirement: Seeded RNG

`NpcWorld` SHALL own a world seed; each agent SHALL derive its own RNG stream from (world seed, agent id). No addon code SHALL use the global RNG for decisions. If no seed is given, one SHALL be generated and logged at start.

#### Scenario: Same seed reproduces
- GIVEN two headless runs of 10 minutes with seed 1234 and identical inputs
- WHEN decision logs are compared
- THEN they SHALL be byte-identical

#### Scenario: Different seeds differ
- GIVEN runs with seeds 1 and 2
- WHEN job sequences are compared
- THEN at least one agent SHALL have a different job sequence

#### Scenario: Stream independence
- GIVEN agent A and B with the same world seed
- WHEN agent B is removed from the world
- THEN agent A's decision sequence SHALL be unchanged

#### Scenario: Seed announced
- GIVEN a run started without a seed
- WHEN it starts
- THEN the generated seed SHALL be logged so the run can be replayed

### Requirement: Decision log

Each decision SHALL be logged with: time, agent id, chosen job, top candidates with scores, temperature, override flag, and RNG draw index. Log verbosity SHALL be switchable and off by default in release builds.

#### Scenario: Log content
- GIVEN an agent picks a job
- WHEN the log is read
- THEN the entry SHALL contain time, agent, job id, candidate scores, override flag

#### Scenario: Log off
- GIVEN decision logging disabled
- WHEN agents decide
- THEN no decision entries SHALL be written and behaviour SHALL be unchanged

### Requirement: Force-job, freeze, step

Debug tools SHALL provide: force a specific job on an agent (pinned, bypassing scoring), freeze all AI, and single-step by N ticks.

#### Scenario: Force job pinned
- GIVEN force-job "mop" on agent A
- WHEN 60 s elapse with other jobs posted
- THEN A SHALL keep "mop" and the log SHALL mark it `forced`
- AND clearing the force SHALL return A to normal decisions

#### Scenario: Freeze and step
- GIVEN AI frozen
- WHEN no steps are requested
- THEN no decisions or movement SHALL occur
- AND `step(3)` SHALL advance exactly 3 ticks then freeze again

### Requirement: Overlay

A debug overlay SHALL display per agent: current job, state, target station, and idle timer, plus station occupancy. It SHALL be toggleable and absent from release builds by default.

#### Scenario: Toggle
- GIVEN the overlay off
- WHEN toggled on
- THEN each agent SHALL show its job and idle timer

### Requirement: Metrics report

The headless run SHALL end with a summary: per-agent idle max, jobs per kind, roster staffing minimum observed, and script error count.

#### Scenario: Summary printed
- GIVEN a headless 10-minute run completes
- WHEN it ends
- THEN a single summary block SHALL be logged containing those metrics
