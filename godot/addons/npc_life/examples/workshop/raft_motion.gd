extends Node3D
## Example platform: a raft that turns, drifts in a circle and rolls, to prove that agents and paths live in platform-local space.

@export var yaw_deg_per_s := 20.0
@export var drift_radius := 6.0
@export var roll_deg := 7.0
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	rotation = Vector3(deg_to_rad(roll_deg) * sin(_t * 0.8), deg_to_rad(yaw_deg_per_s) * _t, deg_to_rad(roll_deg * 0.6) * cos(_t * 0.55))
	position = Vector3(cos(_t * 0.2), 0.15 * sin(_t * 1.1), sin(_t * 0.2)) * drift_radius
