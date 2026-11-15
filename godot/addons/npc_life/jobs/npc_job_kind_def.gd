class_name NpcJobKindDef
extends Resource
## Defaults per job kind: the base score and need it satisfies, and the default action. Referenced by the scorer and the executor.

@export var kind: StringName
@export var base_score := 0.0
## Need this kind satisfies when done (`NpcNeeds`), and by how much.
@export var satisfies: StringName
@export var satisfy_amount := 0.0
@export var default_action: Resource ## NpcActionDef
@export var anim_tag: StringName
