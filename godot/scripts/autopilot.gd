extends Node
## Autopilot: sails from island to island, steering with `Ship.rudder_cmd` (the ship smooths it into `Ship.rudder`).
## When the next waypoint is inside the no-go zone (upwind) it tacks: it alternates headings at +-tack_angle from the
## wind and switches tack when the cross-track error leaves the corridor. Speed follows the point of sail and wind.

@export var ship_path := NodePath("..")
@export var islands_path := NodePath("../../Islands")
@export var arrive_radius := 110.0
@export var pass_clearance := 150.0 ## distance to keep from an island's shore when sailing past
@export var tack_angle_deg := 78.0
@export var tack_corridor := 110.0

var target := Vector2.ZERO
var has_target := false
var tacking := false
var _leg_start := Vector2.ZERO
var _tack_side := 1.0
var _pass_side := 1.0
var _ship: Node3D
var _islands: Node
var _hold_yaw := 9999.0
var _tack_test := false
var _rudder_test := OS.get_cmdline_user_args().has("--rudder-test")

func _ready() -> void:
	add_to_group("rebase")
	_ship = get_node(ship_path)
	_islands = get_node(islands_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with('--hold-heading='):
			_hold_yaw = deg_to_rad(float(a.get_slice('=', 1)))
		elif a == '--tack-test':
			_tack_test = true

func rebase(shift: Vector3) -> void:
	var s := Vector2(shift.x, shift.z)
	target -= s
	_leg_start -= s

func _heading_vec(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))

static func _yaw_of(v: Vector2) -> float:
	return atan2(-v.x, -v.y)

func _pick_target(pos: Vector2, fwd: Vector2) -> void:
	var best := -1.0e9
	var best_t: Dictionary = {}
	for t in _islands.targets():
		var rel: Vector2 = t["pos"] - pos
		var d := rel.length()
		if d < arrive_radius * 2.5 or d > 2000.0:
			continue
		var ang := acos(clampf(rel.normalized().dot(fwd), -1.0, 1.0))
		var score := -d * 0.5 - ang * 350.0 + 400.0
		# Avoid waypoints that need beating to windward (the ship can only point ~75 deg off the wind).
		var wind_from := -WorldState.wind_vector()
		if rel.normalized().dot(wind_from) > cos(deg_to_rad(88.0)):
			score -= 700.0
		if ang > 1.9:
			continue
		if score > best:
			best = score
			best_t = t
	if best_t.is_empty():
		target = pos + fwd * 900.0
	else:
		var rel2: Vector2 = best_t["pos"] - pos
		var dir := rel2.normalized()
		_pass_side = -_pass_side
		var perp := Vector2(-dir.y, dir.x) * _pass_side
		target = best_t["pos"] + perp * (float(best_t["radius"]) + pass_clearance)
	has_target = true
	_leg_start = pos

func _process(_delta: float) -> void:
	if not _ship.active:
		return
	var pos := Vector2(_ship.global_position.x, _ship.global_position.z)
	var fwd: Vector2 = _ship.forward
	if _tack_test and not has_target:
		target = pos + (-WorldState.wind_vector()) * 700.0
		has_target = true
		_leg_start = pos
	if not has_target or pos.distance_to(target) < arrive_radius:
		_pick_target(pos, fwd)
	var want := (target - pos).normalized()
	var upwind := -WorldState.wind_vector() # direction the wind comes FROM
	var angle_to_wind := acos(clampf(want.dot(upwind), -1.0, 1.0))
	var tack_rad := deg_to_rad(tack_angle_deg)
	var desired := want
	tacking = angle_to_wind < tack_rad
	if tacking:
		# Beat to windward: sail at +-tack_angle from the wind, tack when we stray from the leg line.
		var leg := (target - _leg_start)
		var leg_dir := leg.normalized() if leg.length() > 1.0 else want
		var cross := (pos - _leg_start).cross(leg_dir) # signed lateral offset
		if absf(cross) > tack_corridor and signf(cross) * _tack_side < 0.0:
			_tack_side = -_tack_side
		elif absf(cross) < tack_corridor * 0.25 and randf() < 0.0:
			pass
		var up_ang := atan2(upwind.y, upwind.x)
		var h := up_ang + tack_rad * 1.05 * _tack_side
		desired = Vector2(cos(h), sin(h))
		# Prefer the tack that already points toward the waypoint's side.
		if _tack_side * want.cross(upwind) > 0.0 and absf(cross) < tack_corridor * 0.5:
			_tack_side = -_tack_side
	# Avoid islands: steer away when too close and heading toward one.
	for t in _islands.targets():
		var rel: Vector2 = t["pos"] - pos
		var d := rel.length()
		var danger := float(t["radius"]) + 70.0
		if d < danger + 120.0 and rel.normalized().dot(fwd) > 0.0:
			var side := signf(fwd.cross(rel))
			var away := Vector2(-fwd.y, fwd.x) * -side
			desired = (desired + away * clampf((danger + 120.0 - d) / 120.0, 0.0, 1.5)).normalized()
	if _rudder_test:
		_ship.rudder_cmd = sin(Time.get_ticks_msec() / 1000.0 * 0.45)
		return
	var err := wrapf(_yaw_of(desired) - _ship.yaw, -PI, PI)
	if _hold_yaw < 9000.0:
		err = wrapf(_hold_yaw - _ship.yaw, -PI, PI)
	# PD on heading error; rudder > 0 turns to starboard (yaw decreases).
	var cmd := -clampf(err * 1.7 - _ship.yaw_rate * 5.0, -1.0, 1.0)
	_ship.rudder_cmd = cmd
	# Point of sail -> speed (slow into the wind, fast on a reach/run), more wind = faster.
	var heading_vs_wind := acos(clampf(fwd.dot(upwind), -1.0, 1.0))
	var eff := smoothstep(0.55, 2.2, heading_vs_wind)
	if _ship.has_method("best_brace") and not _ship.legacy_motion:
		_ship.brace_cmd = _ship.best_brace()
	_ship.speed_scale = clampf(lerpf(0.7, 1.1, eff) * (0.7 + 0.5 * WorldState.wind_strength), 0.4, 1.3)
