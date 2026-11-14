# npc-life-packaging Specification

## Purpose

Plugin boundary and distribution readiness of `npc_life` (`godot/addons/npc_life/`): no project coupling, metadata, license, README, ship-independent example, dev-only tests. Extraction is prepared, not executed.

## Requirements

### Requirement: Plugin metadata and license

The addon SHALL contain `plugin.cfg` (name `npc_life`, Godot 4.7 compatible), a `LICENSE` file with the MIT license, and a `README.md`.

#### Scenario: Files present
- GIVEN the addon directory
- WHEN listed
- THEN `plugin.cfg`, `LICENSE` (MIT) and `README.md` SHALL exist

#### Scenario: Enable cleanly
- GIVEN the addon in a project
- WHEN enabled then disabled in Project Settings > Plugins
- THEN 0 errors SHALL be logged both times

### Requirement: No project dependencies

Addon scripts and scenes SHALL NOT reference this project's autoloads (`Waves`, `WorldState`, `Capture`) or any path outside `res://addons/npc_life/`. Integration SHALL be via adapter interfaces, signals and Resources only. An addon-owned autoload is permitted only if self-contained.

#### Scenario: Static scan
- GIVEN a text scan of the addon for project autoload names and non-addon `res://` paths
- WHEN run
- THEN it SHALL find 0 matches

#### Scenario: Empty-project extraction
- GIVEN a new empty Godot 4.7 project
- WHEN ONLY `addons/npc_life/` is copied in and enabled
- THEN the example scene SHALL run with 0 script errors and complete a headless 60 s run

### Requirement: Example scene

The addon SHALL include a ship-independent example scene (a small workshop/camp) with at least 3 station kinds, a job source, 2+ agents with distinct CharacterDefs, a waypoint graph on a platform, and a social spot. It SHALL use only addon-owned or CC0/own placeholder assets.

#### Scenario: Example runs
- GIVEN the example in an empty project
- WHEN run for 10 simulated minutes headless with seed S
- THEN jobs SHALL be posted, claimed and released, at least one conversation SHALL occur, and idle max SHALL be <= 20 s

#### Scenario: Example is deterministic
- GIVEN two headless runs with seed S
- WHEN decision logs are compared
- THEN they SHALL be identical

### Requirement: Dev-only tests

GUT SHALL be used as a dev-only framework; it SHALL NOT be shipped inside `addons/npc_life/`. Unit tests SHALL live outside the addon directory (e.g. `godot/tests/npc_life/`) and run through `~/.claude/bin/testsem`.

#### Scenario: Addon contains no test framework
- GIVEN the addon directory
- WHEN scanned
- THEN it SHALL contain no GUT files

#### Scenario: Suite runs
- GIVEN GUT installed under the project addons
- WHEN the suite runs headless via testsem
- THEN it SHALL execute and report pass/fail counts, with 0 skipped-by-suppression tests

### Requirement: Licensing of content

The addon SHALL contain only MIT-licensed code and CC0/own content. Mixamo raw files or any non-CC0/non-own content SHALL NOT be present.

#### Scenario: License audit
- GIVEN the addon files
- WHEN audited
- THEN every non-code asset SHALL be listed with its license and none SHALL be Mixamo-derived

### Requirement: README content

The README SHALL document installation, the adapter interfaces (`StationProvider`, `JobSource`, `AnimationAdapter`, `IkAdapter`), seeds and debug tools, and the extraction/Asset Library steps (prepared, not executed).

#### Scenario: README sections
- GIVEN the README
- WHEN read
- THEN it SHALL contain sections for install, adapters, determinism/seeds, debug tools, and extraction

### Requirement: Performance budget

NPC logic, navigation and animation adapter cost for the shipped crew integration SHALL add <= 1.0 ms per frame on the `final` preset, measured and logged; the addon SHALL expose a tick budget setting.

#### Scenario: Budget measured
- GIVEN the 4-agent ship run on `final`
- WHEN frame time is compared with and without NPC processing
- THEN the logged increment SHALL be <= 1.0 ms
