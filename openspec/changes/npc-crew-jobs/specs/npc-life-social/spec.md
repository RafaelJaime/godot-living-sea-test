# npc-life-social Specification

## Purpose

Social behaviours for `npc_life`: gatherings, two-party conversations, audiences around a performer, with join/leave offers. Verifiable by GUT tests and example scene captures/logs.

## Requirements

### Requirement: Social spots and gatherings

A social spot SHALL be a station-like node supporting N participants. A gathering SHALL form when participants meet at the spot and SHALL end when fewer than 2 remain or its duration elapses.

#### Scenario: Gathering forms
- GIVEN two agents choose the same social spot
- WHEN both arrive
- THEN a gathering SHALL start and `gathering_started(spot, agents)` SHALL be logged

#### Scenario: Gathering ends
- GIVEN a gathering with 2 members
- WHEN one leaves
- THEN the gathering SHALL end and the remaining agent SHALL pick a new job within the idle bound

### Requirement: Two-party conversation

A conversation SHALL pair two agents facing each other at speaking distance, alternate speaker/listener animation tags for a randomised duration, then release both.

#### Scenario: Conversation lifecycle
- GIVEN agent A offers a chat and B accepts
- WHEN the conversation runs
- THEN both SHALL face each other within 20 degrees
- AND speaker/listener tags SHALL alternate at least twice
- AND on end both SHALL be released and free to pick jobs

#### Scenario: Offer declined
- GIVEN A offers a chat and B has a higher-score job
- WHEN B evaluates the offer
- THEN B MAY decline, A SHALL continue with another job, and no deadlock SHALL occur

### Requirement: Audience around a performer

A performer job (e.g. music) SHALL define listen spots. Idle or ambient-eligible agents MAY join as listeners at free listen spots, face the performer, and leave when the performance ends or a higher-priority job appears.

#### Scenario: Listener joins
- GIVEN a performer is active with 2 free listen spots
- WHEN an agent in an ambient/relaxed state decides
- THEN it MAY choose "listen" and SHALL occupy a listen spot facing the performer

#### Scenario: Listener pre-empted
- GIVEN a listener and a new emergency job
- WHEN the emergency is posted
- THEN the listener SHALL leave immediately and the spot SHALL free

#### Scenario: No listeners
- GIVEN a performer and zero eligible listeners
- WHEN the performance runs
- THEN the performance SHALL proceed to completion without error

### Requirement: Join and leave offers

Social jobs SHALL expose join/leave offers through the job board so that joining is a normal utility pick, not a special path.

#### Scenario: Offer on board
- GIVEN a gathering with free capacity
- WHEN the board is queried
- THEN a join offer job SHALL be present until the gathering is full or ended

### Requirement: Social seeding

Social choices (who offers, duration, accept/decline) SHALL use the seeded RNG so a seed reproduces them.

#### Scenario: Reproducible conversation
- GIVEN two runs with the same seed
- WHEN conversation start times and partners are logged
- THEN both logs SHALL be identical
