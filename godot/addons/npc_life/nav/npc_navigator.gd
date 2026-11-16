class_name NpcNavigator
extends RefCounted
## Follows a polyline in the LOCAL space of the agent's parent (the platform): positions are set through `position`, never `global_position`,
## so roll, pitch, yaw and the floating-origin rebase cannot cause drift. The current edge type selects locomotion tag and speed. Agents
## that meet keep to their right (eased sidestep), so two agents in one corridor pass without deadlock.

signal edge_entered(edge_type: StringName, index: int)

## Speed multiplier by edge type.
var speed_mul: Dictionary[StringName, float] = {&"walk": 1.0, &"stairs": 0.7, &"ladder": 0.45, &"rope": 0.5}
var courtesy_distance := 1.8 ## look-ahead for other agents (m)
var sidestep := 0.5 ## how far to the right a meeting agent moves (m)
var sidestep_speed := 1.5
var turn_rate := 10.0 ## rad/s toward the walking direction
var ground_probe: NpcGroundProbe
## Largest gap between where the navigator put the agent and where the agent actually was on the next step (logged; should stay ~0).
var max_error := 0.0
var finished := true

var _pts := PackedVector3Array()
var _types: Array[StringName] = []
var _seg := 0
var _dist := 0.0 # distance travelled along the current segment
var _lat := 0.0
var _entered := -1
var _cur_type: StringName = &"walk"
var _last_set := Vector3.INF
var _hold := 0.0
var _hold_total := 0.0
var _hold_adv := 0.0

## Pause the walk for `seconds` (the agent plays a transition clip, e.g. stepping off a ladder); the path stays pending and resumes afterwards.
## `advance_m` is the root motion of that clip: the node covers that distance along the path during the hold (eased in and out) while the clip
## itself stays in place.
func hold(seconds: float, advance_m := 0.0) -> void:
	_hold = maxf(seconds, 0.0)
	_hold_total = _hold
	_hold_adv = advance_m

func set_path(points: PackedVector3Array, types: Array[StringName]) -> void:
	_hold = 0.0
	_hold_adv = 0.0
	_pts = points
	_types = types
	_seg = 0
	_dist = 0.0
	_lat = 0.0
	_entered = -1
	_last_set = Vector3.INF
	finished = points.size() < 2

## The polyline being followed (platform-local), for debug drawing.
func path_points() -> PackedVector3Array:
	return _pts

## Path length still ahead.
func remaining() -> float:
	if finished:
		return 0.0
	var r := _pts[_seg].distance_to(_pts[_seg + 1]) - _dist
	for i in range(_seg + 1, _pts.size() - 1):
		r += _pts[i].distance_to(_pts[i + 1])
	return r

## Edge type of the segment being walked (the last one after the path ended). Doubles as the locomotion tag.
func current_edge_type() -> StringName:
	return _cur_type

func locomotion_tag() -> StringName:
	return _cur_type

func current_speed(base_speed: float) -> float:
	return base_speed * speed_mul.get(_cur_type, 1.0)

## Advances `agent` along the path by `dt` seconds (agent.position only). `others` are Node3D neighbours in the same local space.
func step(agent: Node3D, dt: float, base_speed: float, others: Array = []) -> void:
	if finished:
		return
	if _last_set != Vector3.INF:
		max_error = maxf(max_error, (agent.position - _last_set).length())
	_enter_segment()
	var travel := current_speed(base_speed) * dt
	if _hold > 0.0: # a transition clip is playing: only its root motion, eased
		var u0 := 1.0 - _hold / maxf(_hold_total, 1.0e-6)
		_hold = maxf(_hold - dt, 0.0)
		if _hold < 1.0e-4: # float residue of the countdown must not cost one more step
			_hold = 0.0
		var u1 := 1.0 - _hold / maxf(_hold_total, 1.0e-6)
		travel = _hold_adv * (smoothstep(0.0, 1.0, u1) - smoothstep(0.0, 1.0, u0))
	while travel > 0.0 and not finished:
		var seg_len := _pts[_seg].distance_to(_pts[_seg + 1])
		var left := seg_len - _dist
		if travel < left:
			_dist += travel
			travel = 0.0
		else:
			travel -= left
			_dist = 0.0
			_seg += 1
			if _seg >= _pts.size() - 1:
				_seg = _pts.size() - 2
				_dist = _pts[_seg].distance_to(_pts[_seg + 1])
				finished = true
			else:
				_enter_segment()
	var a := _pts[_seg]
	var b := _pts[_seg + 1]
	var dir := (b - a).normalized() if a != b else Vector3.ZERO
	var ideal := a.lerp(b, _dist / maxf(a.distance_to(b), 1.0e-6)) if a != b else b
	# courtesy: keep to the right of whoever comes the other way, eased back to the path afterwards and exactly on it at the end
	var right := dir.cross(Vector3.UP)
	var want := 0.0
	if not finished and dir != Vector3.ZERO:
		for o in others:
			var rel: Vector3 = (o as Node3D).position - agent.position
			rel.y = 0.0
			if rel.dot(dir) > 0.0 and rel.length() < courtesy_distance and absf(rel.dot(right)) < sidestep * 1.6:
				want = sidestep
				break
	_lat = move_toward(_lat, want, sidestep_speed * dt)
	var end_fade := clampf(remaining() / 0.8, 0.0, 1.0)
	var pos := ideal + right * _lat * end_fade
	if ground_probe:
		var h := ground_probe.height_at(pos)
		if not is_nan(h):
			pos.y = h
	agent.position = pos
	_last_set = pos
	if dir != Vector3.ZERO:
		agent.rotation.y = lerp_angle(agent.rotation.y, atan2(-dir.x, -dir.z), clampf(turn_rate * dt, 0.0, 1.0))

func _enter_segment() -> void:
	if _seg != _entered and _seg < _types.size():
		_entered = _seg
		_cur_type = _types[_seg]
		edge_entered.emit(_cur_type, _seg)
