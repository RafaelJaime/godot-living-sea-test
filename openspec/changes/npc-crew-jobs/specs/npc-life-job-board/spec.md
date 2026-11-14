# npc-life-job-board Specification

## Purpose

World-driven job board for `npc_life`. Job sources post and clear jobs; agents claim them. Verifiable by GUT tests and the example scene.

## Requirements

### Requirement: Job posting and clearing

A `JobBoard` SHALL accept jobs carrying: id, kind, priority, urgency, required tags, deadline (optional), station references, and source id. `JobSource` implementations SHALL be able to post and clear their own jobs.

#### Scenario: Post and list
- GIVEN an empty JobBoard
- WHEN a source posts a job with priority 2 and a station ref
- THEN `open_jobs()` SHALL contain that job once
- AND a `job_posted(job)` signal SHALL be emitted

#### Scenario: Clear by source
- GIVEN a source has posted 3 jobs
- WHEN the source clears one job id
- THEN only that job SHALL be removed and `job_cleared(job)` SHALL be emitted once

#### Scenario: Duplicate id
- GIVEN a job with id X is open
- WHEN a source posts another job with id X
- THEN the board SHALL update the existing job and SHALL NOT create a duplicate

### Requirement: Claiming

An agent SHALL claim an open job at most once at a time. A claimed job SHALL be hidden from other agents' candidate lists unless the job declares multiple slots. Claim and release SHALL be reflected in the job's state.

#### Scenario: Exclusive job
- GIVEN an open single-slot job
- WHEN agent A claims it
- THEN agent B's candidate list SHALL NOT include it
- AND if A releases it, the job SHALL return to the open list

#### Scenario: Multi-slot job
- GIVEN a job with 3 slots (e.g. all-hands reef)
- WHEN 3 agents claim it
- THEN all 3 claims SHALL succeed and a fourth SHALL fail

#### Scenario: Required tags
- GIVEN a job requiring tag `"climber"`
- WHEN an agent without the tag requests candidates
- THEN the job SHALL NOT appear in its list

### Requirement: Expiry

Jobs with a deadline SHALL expire when the deadline passes without completion. Expired jobs SHALL be removed, any claim released, and `job_expired(job)` emitted. Time SHALL come from the world tick clock, not wall-clock.

#### Scenario: Stale job expires
- GIVEN an open job with deadline 10 s
- WHEN the world clock advances to 10 s
- THEN the job SHALL be removed and `job_expired` emitted once

#### Scenario: Claimed job expires
- GIVEN a job claimed by agent A with deadline 10 s
- WHEN the deadline passes
- THEN A's claim SHALL be released and A SHALL be eligible to pick a new job on its next decision

### Requirement: Ordering and urgency

Candidates SHALL be exposed with priority and urgency so the utility AI can score them. Urgency MAY rise over time toward the deadline.

#### Scenario: Urgency growth
- GIVEN a job with deadline 20 s and rising urgency
- WHEN queried at 0 s and 18 s
- THEN urgency at 18 s SHALL be strictly greater than at 0 s

### Requirement: Source decoupling

The board SHALL be usable with sources written outside the addon through the abstract `JobSource` interface only.

#### Scenario: External source
- GIVEN a custom script extending `JobSource` in the example scene
- WHEN it posts a job
- THEN the board SHALL accept it without referencing any project singleton
