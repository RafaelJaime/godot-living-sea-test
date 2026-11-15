class_name NpcStationSlot
extends Marker3D
## Optional per-slot override under an NpcStation: place it where slot `slot_index` should work, optionally with its own approach point and facing.

@export var slot_index := 0
## Approach point of this slot, local to the slot marker. Ignored unless `use_approach` is set.
@export var approach_offset := Vector3(0, 0, 0.6)
@export var use_approach := false
## Facing of this slot (same convention as NpcStation.facing_deg). Ignored unless `use_facing` is set.
@export var facing_deg := 0.0
@export var use_facing := false
