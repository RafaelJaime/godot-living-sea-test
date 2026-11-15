extends Node3D
## Example scene root: drives the example day/night through the blackboard and lets the NpcWorld run. Headless:
##   godot --headless --fixed-fps 60 --path <project> res://addons/npc_life/examples/workshop/workshop.tscn -- --npc-seed=1 --npc-minutes=3

@onready var world: NpcWorld = $Raft/NpcWorld

func _ready() -> void:
	for kind_path in ["craft", "mend", "lamp"]:
		var kd := load("res://addons/npc_life/examples/workshop/defs/kind_%s.tres" % kind_path) as NpcJobKindDef
		world.kind_defs[kd.kind] = kd

func _process(_delta: float) -> void:
	var day := fposmod(world.now() / 120.0, 1.0) # a 2-minute day
	world.inputs.set_value(&"daylight", snappedf(0.5 + 0.5 * sin(day * TAU), 0.05))
