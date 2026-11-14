# npc-life-animation Specification

## Purpose

Animation and IK adapter layer for `npc_life`: shared `AnimationLibrary`, per-character signature clips, crossfade, and procedural IK behind interfaces. The addon bundles no third-party clips. Verifiable by GUT tests (with stub adapters) and the example scene.

## Requirements

### Requirement: Adapter interface

The addon SHALL define abstract `AnimationAdapter` and `IkAdapter` interfaces. Agents SHALL talk to animation only through them, so any game can supply its own implementation.

#### Scenario: Stub adapter
- GIVEN a test adapter that records calls
- WHEN an agent performs a job
- THEN the stub SHALL receive play/crossfade/IK calls and no engine animation node SHALL be required

#### Scenario: Missing adapter
- GIVEN an agent without an assigned adapter
- WHEN it starts a job
- THEN a single warning SHALL be logged and the agent SHALL still run logic (no crash)

### Requirement: Shared library and signature clips

The adapter SHALL resolve an animation tag first to the character's signature clips, then to the shared library, then to a fallback tag. Missing clips SHALL log once per tag.

#### Scenario: Signature override
- GIVEN tag "work" exists in the shared library and in character X's signature set
- WHEN X plays "work"
- THEN the signature clip SHALL play

#### Scenario: Fallback
- GIVEN tag "fish" exists in neither set
- WHEN played
- THEN the fallback tag SHALL play and the missing tag SHALL be logged exactly once

### Requirement: Crossfade API

The adapter SHALL expose `play(tag, blend_time)` with crossfade; transitions SHALL not pop (no frame with zero blend weight total).

#### Scenario: Blend between tags
- GIVEN an agent playing "walk"
- WHEN `play("idle", 0.25)` is called
- THEN both clips SHALL be weighted during 0.25 s and the weights SHALL sum to 1.0 at each sampled frame

### Requirement: Procedural IK hooks

The IK interface SHALL support reach (hand targets), look-at, and release, activated from Station IK targets with blend-in/out weights. IK weight SHALL return to 0 when the job ends.

#### Scenario: Hand target
- GIVEN a Station with a `hand_r` target
- WHEN the agent works there
- THEN the IK adapter SHALL receive a `reach("hand_r", transform, weight)` call each frame with weight rising to 1.0
- AND on release it SHALL receive weight falling to 0.0

#### Scenario: Moving target
- GIVEN an IK target on a moving parent
- WHEN the platform moves
- THEN the target transform passed to IK SHALL be re-read each frame

### Requirement: No bundled third-party clips

The addon directory SHALL contain no animation files other than CC0 or author-owned minimal test clips, and SHALL NOT contain Mixamo raw files.

#### Scenario: Asset audit
- GIVEN the packaged `addons/npc_life/`
- WHEN a file scan lists `.anim`, `.fbx`, `.glb` and `.res` animation assets
- THEN each SHALL be listed as CC0 or own in the addon's license notes, and none SHALL be a Mixamo-derived file
