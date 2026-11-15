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

## Emitted when the crew should expect sail/helm work. kind: &"tack" (the tack side flips) or &"beat" (the ship starts beating to
## windward); side = sign of the new tack side (+1 / -1, the autopilot's own `_tack_side`). Never nested: a started maneuver is ended
## (maneuver_ended) before another one starts. Purely additive: nothing in the steering depends on listeners.
signal maneuver_started(kind: StringName, side: int)
## Emitted when the rudder has settled (|rudder| < settle_rudder for settle_s) or after maneuver_timeout_s.
signal maneuver_ended(kind: StringName)
## Seconds the autopilot waits between announcing a tack and flipping its side (0 = flip immediately, the old behaviour).
@export var maneuver_lead_s := 0.0
@export var settle_rudder := 0.1
@export var settle_s := 3.0
@export var maneuver_timeout_s := 90.0

var target := Vector2.ZERO
var has_target := false
var tacking := false
var _leg_start := Vector2.ZERO
var _tack_side := 1.0
var _pass_side := 1.0
var _ship: Node3D
var _becalmed := false
var _islands: Node
var _hold_yaw := 9999.0
var _tack_test := false
var _rudder_test := OS.get_cmdline_user_args().has("--rudder-test")
var _maneuver := &""        ## active maneuver kind ("" = none)
var _maneuver_t := 0.0      ## time since it started
var _settled_t := 0.0       ## time the rudder has been quiet
var _was_tacking := false
var _flip_in := -1.0        ## pending side flip countdown (only with maneuver_lead_s > 0)
var _log_maneuvers := false

func _ready() -> void:
	add_to_group("rebase")
	_ship = get_node(ship_path)
	_islands = get_node(islands_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with('--hold-heading='):
			_hold_yaw = deg_to_rad(float(a.get_slice('=', 1)))
		elif a == '--tack-test':
			_tack_test = true
		elif a.begins_with('--autopilot-log=') or a == '--maneuver-log':
			_log_maneuvers = true

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

func _flip_tack_side() -> void:
	if _flip_in >= 0.0:
		return # a flip is already announced
	_begin_maneuver(&"tack", -_tack_side)
	if maneuver_lead_s > 0.0:
		_flip_in = maneuver_lead_s
	else:
		_tack_side = -_tack_side

func _begin_maneuver(kind: StringName, side: float) -> void:
	if _maneuver != &"":
		_end_maneuver() # never two maneuvers at once
	_maneuver = kind
	_maneuver_t = 0.0
	_settled_t = 0.0
	if _log_maneuvers:
		print("[autopilot] maneuver_started ", kind, " side=", int(side), " t=", snappedf(Time.get_ticks_msec() / 1000.0, 0.1))
	maneuver_started.emit(kind, int(side))

func _end_maneuver() -> void:
	var k := _maneuver
	_maneuver = &""
	if _log_maneuvers:
		print("[autopilot] maneuver_ended ", k, " t=", snappedf(Time.get_ticks_msec() / 1000.0, 0.1))
	maneuver_ended.emit(k)

func _track_maneuver(delta: float) -> void:
	if _maneuver == &"":
		return
	_maneuver_t += delta
	_settled_t = _settled_t + delta if absf(float(_ship.get("rudder"))) < settle_rudder else 0.0
	if _settled_t >= settle_s or _maneuver_t >= maneuver_timeout_s:
		_end_maneuver()

func _process(_delta: float) -> void:
	if not _ship.active:
		return
	_track_maneuver(_delta)
	if _flip_in >= 0.0:
		_flip_in -= _delta
		if _flip_in < 0.0:
			_tack_side = -_tack_side
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
	if tacking and not _was_tacking:
		_begin_maneuver(&"beat", _tack_side)
	_was_tacking = tacking
	if tacking:
		# Beat to windward: sail at +-tack_angle from the wind, tack when we stray from the leg line.
		var leg := (target - _leg_start)
		var leg_dir := leg.normalized() if leg.length() > 1.0 else want
		var cross := (pos - _leg_start).cross(leg_dir) # signed lateral offset
		if absf(cross) > tack_corridor and signf(cross) * _tack_side < 0.0:
			_flip_tack_side()
		elif absf(cross) < tack_corridor * 0.25 and randf() < 0.0:
			pass
		var up_ang := atan2(upwind.y, upwind.x)
		var h := up_ang + tack_rad * 1.05 * _tack_side
		desired = Vector2(cos(h), sin(h))
		# Prefer the tack that already points toward the waypoint's side.
		if _tack_side * want.cross(upwind) > 0.0 and absf(cross) < tack_corridor * 0.5:
			_flip_tack_side()
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
	# Becalmed: a rudder with no flow only saturates and winds the heading up; centre it and let the ship drift.
	var spd: float = _ship.current_speed
	if not _becalmed and spd < 0.8 and WindField.mean_speed() < 2.5:
		_becalmed = true
	elif _becalmed and (spd > 1.3 or WindField.mean_speed() > 3.0):
		_becalmed = false
	if _becalmed:
		cmd = 0.0
	_ship.rudder_cmd = cmd
	# Point of sail -> speed (slow into the wind, fast on a reach/run), more wind = faster.
	var heading_vs_wind := acos(clampf(fwd.dot(upwind), -1.0, 1.0))
	var eff := smoothstep(0.55, 2.2, heading_vs_wind)
	if _ship.has_method("best_brace") and not _ship.legacy_motion:
		_ship.brace_cmd = 0.0 if _becalmed else _ship.best_brace()
	_ship.speed_scale = clampf(lerpf(0.7, 1.1, eff) * (0.7 + 0.5 * WorldState.wind_strength), 0.4, 1.3)
