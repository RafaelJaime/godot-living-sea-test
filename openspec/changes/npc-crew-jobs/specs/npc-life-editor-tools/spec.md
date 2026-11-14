# npc-life-editor-tools Specification

## Purpose

Godot editor tooling for `npc_life`: station gizmos and waypoint graph editing with edge typing. Editor code is inactive at runtime. Verifiable by editor screenshots and a headless plugin-load check.

## Requirements

### Requirement: Station gizmos

In the editor, a selected `Station` SHALL draw handles for anchor, approach point, facing, and slots, editable by dragging, with undo/redo support.

#### Scenario: Gizmo visible
- GIVEN a Station selected in the 3D editor
- WHEN a screenshot is taken
- THEN anchor, approach and facing indicators SHALL be visible

#### Scenario: Drag with undo
- GIVEN the approach handle is dragged 1 m
- WHEN Undo is invoked
- THEN the approach point SHALL return to its prior value

### Requirement: Waypoint graph editing

The editor SHALL allow adding, moving, deleting nodes and connecting nodes with edges in a `WaypointGraph` edit mode, within a `platform_root`'s local space.

#### Scenario: Add and connect
- GIVEN a graph edit session
- WHEN two nodes are added and connected
- THEN the resource SHALL contain 2 nodes and 1 edge saved on scene save

#### Scenario: Moving platform parent
- GIVEN a platform_root with a non-identity transform
- WHEN a node is placed at a world point
- THEN it SHALL be stored in local coordinates

### Requirement: Edge typing

Each edge SHALL be assignable a type (walk, stairs, ladder, rope) in the editor, shown by distinct colour/label in the viewport.

#### Scenario: Type change
- GIVEN a walk edge
- WHEN set to ladder
- THEN the resource SHALL store `ladder` and the viewport colour SHALL change

### Requirement: Runtime isolation

Editor-only scripts SHALL be loaded only by the EditorPlugin (`@tool`-guarded) and SHALL NOT run or error in exported/game runs.

#### Scenario: Headless game run
- GIVEN the plugin enabled
- WHEN the project runs headless as a game
- THEN no editor script SHALL be instantiated and 0 script errors SHALL be logged

### Requirement: Clean enable/disable

Enabling and disabling the plugin SHALL register and unregister its custom types, gizmos and docks with 0 errors and no residual UI.

#### Scenario: Toggle plugin
- GIVEN the plugin enabled then disabled
- WHEN the editor log is read
- THEN 0 errors SHALL be present and gizmos SHALL no longer draw
