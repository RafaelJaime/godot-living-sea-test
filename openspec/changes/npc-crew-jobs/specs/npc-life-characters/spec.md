# npc-life-characters Specification

## Purpose

Character definition Resources for `npc_life`: roles, preferences, skills, signature actions, schedule. Game-agnostic and editable in the Godot inspector. Verifiable by GUT tests and the example scene.

## Requirements

### Requirement: CharacterDef resource

A `CharacterDef` Resource SHALL hold: id, display name, role list (`RoleDef`), preferences (kind -> weight), skills (role/tag -> 0..1), signature actions (`ActionDef` list), and optional schedule/roster hints.

#### Scenario: Create and save
- GIVEN a CharacterDef created in code with 2 roles and 3 signature actions
- WHEN saved to `.tres` and reloaded
- THEN all fields SHALL round-trip equal

#### Scenario: Defaults
- GIVEN a new CharacterDef with only an id
- WHEN an agent is built from it
- THEN the agent SHALL run with neutral preferences, skill 0.5 everywhere, and no signature actions without errors

### Requirement: RoleDef and ActionDef

`RoleDef` SHALL declare tags granted to the agent (e.g. `helmsman`, `climber`). `ActionDef` SHALL declare an animation tag, duration range, optional IK usage, optional required station kind, and a cooldown.

#### Scenario: Role grants tags
- GIVEN a role granting `climber`
- WHEN the agent is built
- THEN the agent tag set SHALL contain `climber` and jobs requiring it SHALL be eligible

#### Scenario: Action cooldown
- GIVEN a signature action with cooldown 60 s
- WHEN it was performed 30 s ago
- THEN it SHALL be excluded from candidates

### Requirement: Validation

Loading a CharacterDef SHALL validate ranges (skills within 0..1, positive durations, non-empty id) and report each violation by field name without crashing.

#### Scenario: Out-of-range skill
- GIVEN skill value 1.7
- WHEN validated
- THEN the validator SHALL report the field and clamp or reject per documented policy

### Requirement: Variety by definition

Two characters with different definitions in the same world and seed SHALL produce different job histories over a 10-minute run.

#### Scenario: Divergent behaviour
- GIVEN characters X (prefers "music") and Y (prefers "fishing")
- WHEN a 10-minute run completes with ample jobs of both kinds
- THEN X SHALL have performed more "music" jobs than Y and Y more "fishing" than X
