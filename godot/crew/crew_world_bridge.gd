class_name CrewWorldBridge
extends Node
## Writes the ship's facts into the NpcWorld blackboard (C1.2); the NPC sources and the scorer read only `world.inputs`, never the game.
## Keys: daylight 0..1, storm 0..1, wind 0..1 (all quantized), roll_deg (abs, 2 deg steps), maneuver (kind or &""), maneuver_side (-1/0/+1).
## Writes happen at SYNC_HZ and are quantized, so the blackboard log does not churn every frame.

const SYNC_HZ := 5.0

var world: NpcWorld
var _ship: Node
var _acc := 0.0

func bind(w: NpcWorld, ship: Node) -> void:
	world = w
	_ship = ship
	var ap := ship.get_node_or_null("Autopilot")
	if ap != null and ap.has_signal("maneuver_started"):
		ap.connect(&"maneuver_started", _on_maneuver_started)
		ap.connect(&"maneuver_ended", _on_maneuver_ended)
	world.inputs.set_value(&"maneuver", &"")
	world.inputs.set_value(&"maneuver_side", 0)
	sync_now()

func _process(delta: float) -> void:
	_acc += delta
	if _acc >= 1.0 / SYNC_HZ:
		_acc = 0.0
		sync_now()

func sync_now() -> void:
	if world == null:
		return
	world.inputs.set_value(&"daylight", snappedf(WorldState.daylight, 0.05))
	world.inputs.set_value(&"storm", snappedf(WorldState.storm, 0.05))
	world.inputs.set_value(&"wind", snappedf(WorldState.wind_strength, 0.05))
	var roll: Variant = _ship.get("roll") if _ship != null else null
	world.inputs.set_value(&"roll_deg", snappedf(absf(rad_to_deg(float(roll if roll != null else 0.0))), 2.0))

func _on_maneuver_started(kind: StringName, side: int) -> void:
	world.inputs.set_value(&"maneuver_side", side)
	world.inputs.set_value(&"maneuver", kind)

func _on_maneuver_ended(_kind: StringName) -> void:
	world.inputs.set_value(&"maneuver", &"")
	world.inputs.set_value(&"maneuver_side", 0)
