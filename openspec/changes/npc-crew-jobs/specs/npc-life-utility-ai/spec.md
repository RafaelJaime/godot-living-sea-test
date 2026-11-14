# npc-life-utility-ai Specification

## Purpose

Per-agent decision making for `npc_life`: utility scoring, softmax selection, recency penalty, hard overrides, and the never-aimless guarantee. Verifiable by GUT tests (with fixed seeds) and the example scene decision log.

## Requirements

### Requirement: Utility scoring

An agent SHALL score every eligible candidate job from need, preference, skill, distance, and urgency. Each factor weight SHALL be configurable via the agent's `CharacterDef` or world config. Ineligible jobs (tags, constraints) SHALL NOT be scored.

#### Scenario: Preference raises score
- GIVEN two otherwise identical jobs, one matching agent preference "fishing"
- WHEN the agent scores both
- THEN the preferred job's score SHALL be strictly higher

#### Scenario: Distance lowers score
- GIVEN two identical jobs at 2 m and 20 m path distance
- WHEN scored
- THEN the nearer job SHALL score higher

### Requirement: Softmax selection with temperature

The agent SHALL choose among scored candidates by softmax sampling with a configurable temperature, using only its own seeded RNG stream. Lower temperature SHALL approach argmax; higher SHALL approach uniform.

#### Scenario: Low temperature is near-deterministic
- GIVEN candidates scored 1.0, 0.5, 0.1 and temperature 0.01
- WHEN 1000 picks are drawn with a fixed seed
- THEN the top candidate SHALL be picked at least 99% of the time

#### Scenario: Variety at moderate temperature
- GIVEN the same candidates and temperature 1.0
- WHEN 1000 picks are drawn
- THEN every candidate SHALL be picked at least once

### Requirement: Recency penalty and commit time

A recently completed job kind SHALL receive a score penalty that decays over time. After picking a job, the agent SHALL stay committed for a configurable minimum time before pre-emption by a non-override job, to avoid oscillation.

#### Scenario: Repeat avoidance
- GIVEN an agent just finished a job of kind "mop" and an equivalent "repair" job is open
- WHEN it decides immediately
- THEN "repair" SHALL have a higher adjusted score than "mop"

#### Scenario: No oscillation
- GIVEN an agent committed to job J with commit time 5 s
- WHEN a slightly higher-scoring non-override job appears at 2 s
- THEN the agent SHALL keep J until at least 5 s

### Requirement: Hard overrides

The system SHALL support overrides that bypass scoring and commit time: must-staff stations, emergencies, and all-hands. Override jobs SHALL be assigned before any scored pick.

#### Scenario: Emergency pre-empts
- GIVEN an agent mid-way through a relaxed job
- WHEN an all-hands emergency job is posted
- THEN the agent SHALL release its job and claim the emergency job within one decision tick
- AND the decision log SHALL mark the pick as `override:emergency`

#### Scenario: Must-staff
- GIVEN a station flagged must-staff is free
- WHEN agents decide
- THEN at least one eligible agent SHALL be assigned to it before any non-override job is assigned

### Requirement: Never aimless

Every agent SHALL always have an active job. When no scored candidate exists, an always-available ambient job (idle at station, look around, chat offer) SHALL be assigned. No agent SHALL be without an active job for longer than the configured idle bound (default 20 s).

#### Scenario: Empty board
- GIVEN a world with agents and no posted jobs
- WHEN 10 simulated minutes elapse
- THEN every agent SHALL hold an active (possibly ambient) job at every decision tick
- AND the maximum recorded no-job interval SHALL be <= 20 s

#### Scenario: Idle metric
- GIVEN any 10-minute headless run
- WHEN the log is summarised
- THEN an `idle_max_seconds` metric per agent SHALL be reported
- AND any value above the bound SHALL be reported as a failure

### Requirement: Tick budget

Decision updates SHALL be staggered across frames so per-frame AI cost does not scale with agent count in a single frame.

#### Scenario: Staggered updates
- GIVEN 40 agents and a tick budget of 4 decisions per frame
- WHEN 10 frames run
- THEN no frame SHALL process more than 4 decisions
- AND every agent SHALL have decided at least once
