# ship-crew-characters Specification

## Purpose

The four crew `CharacterDef` definitions, signature actions and project-side clip set (NPC session). Clips live in the project, never in the addon. Verified by captures, logs and `ATTRIBUTION.md`.

## Requirements

### Requirement: Four crew definitions

The project SHALL define Fuego, Diagnostica, Salchipapa and Omar as `CharacterDef` Resources, replacing hardcoded roles in `crew_rig.gd` through `NpcAgent`.

#### Scenario: Spawn
- GIVEN the ship run (not legacy)
- WHEN the scene starts
- THEN 4 agents SHALL spawn at stations, 0 script errors SHALL be logged, and the helm SHALL be staffed from the first tick

### Requirement: Signature actions

Each character SHALL perform at least two signature actions visible in captures:
- Fuego: helm, spyglass, pointing orders
- Diagnostica: hammer, climb rigging, carry
- Salchipapa: crow's nest, rope climb, fishing, comic fall
- Omar: violin, chart table, star gazing

#### Scenario: Captures per action
- GIVEN a 10-minute run with forced-job tooling available
- WHEN each signature action is forced or occurs
- THEN a capture SHALL exist per action showing the matching animation/pose

#### Scenario: Two actions minimum
- GIVEN the run log
- WHEN signature actions per character are counted
- THEN every character SHALL have performed >= 2 distinct signature actions

#### Scenario: Comic fall recovers
- GIVEN Salchipapa performs the comic fall
- WHEN it ends
- THEN the agent SHALL return to a valid standing state on the deck and re-enter job selection with no stuck state

### Requirement: Character-driven variety

Characters SHALL differ in preferences and skills (Fuego favoured at the helm), so over a run job histories differ per character.

#### Scenario: Helm skill
- GIVEN Fuego helm skill is highest
- WHEN 10 minutes run
- THEN Fuego SHALL have the most helm time and each other character SHALL have at least one non-helm preferred job type chosen more often than the others

### Requirement: Project clip set and attribution

Crew clips (Quaternius UAL 1/2 CC0, Mixamo, hand-made Blender) SHALL reside in project paths outside `addons/npc_life/`. `ATTRIBUTION.md` SHALL list every clip with source and license.

#### Scenario: Attribution complete
- GIVEN all clip files under the project crew clip directory
- WHEN compared with `ATTRIBUTION.md`
- THEN every clip SHALL have an entry with source and license

#### Scenario: Addon clean
- GIVEN the addon directory
- WHEN scanned for Mixamo-derived files
- THEN none SHALL be found

### Requirement: Retarget quality

Clips from A-pose or finger-less sources SHALL be retargeted via a humanoid BoneMap and rest-pose fix, with procedural IK for hands where finger bones are absent.

#### Scenario: Retarget check
- GIVEN a retargeted clip
- WHEN a capture is taken in the first frame
- THEN the character SHALL not show inverted limbs or rest-pose T/A offset beyond visible tolerance (reviewed in capture)

### Requirement: Runtime budget and script errors

The crew integration SHALL produce 0 script errors across the runs and add <= 1.0 ms per frame on `final`.

#### Scenario: Final preset measure
- GIVEN `final` preset run with and without crew AI
- WHEN frame time is compared
- THEN the increment SHALL be <= 1.0 ms
