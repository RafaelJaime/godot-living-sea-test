extends Node
## Adds the procedural animation layers to the crew once they are placed:
## - every crew member: counter-lean with the ship's roll/pitch (CrewPoseModifier)
## - Papi Fuego (helmsman): hands on the wheel via TwoBoneIK3D, head looks toward the turn, leans into turns
## - Don Omar: seated on a barrel, playing a violin (see violin.gd)

@export var crew_path := NodePath("../CrewMarkers")
@export var ship_path := NodePath("../..")
@export var helm_path := NodePath("../Helm")

var _ship: Node
var _pivot: Node3D
var _clamped: Array = [] # [{proxy, source, sk, side, len}]

func _ready() -> void:
	_ship = get_node(ship_path)
	_pivot = get_parent() as Node3D
	get_node(crew_path).crew_ready.connect(_on_crew_ready)

## IK target proxy: follows `source` but is pulled inside 93% of the arm's reach from the shoulder, so the arm never
## fully extends (a straight arm has an undefined elbow plane and flips).
func make_clamped_target(sk: Skeleton3D, side: String, source: Node3D) -> Node3D:
	var proxy := Node3D.new()
	proxy.name = side + "ReachTarget"
	proxy.top_level = true
	sk.add_child(proxy)
	var gt := sk.global_transform
	var a := sk.get_bone_global_rest(sk.find_bone(side + "Arm")).origin
	var f := sk.get_bone_global_rest(sk.find_bone(side + "ForeArm")).origin
	var h := sk.get_bone_global_rest(sk.find_bone(side + "Hand")).origin
	var length := (a.distance_to(f) + f.distance_to(h)) * gt.basis.get_scale().x
	_clamped.append({"proxy": proxy, "source": source, "sk": sk, "side": side, "len": length})
	proxy.global_position = source.global_position
	return proxy

func _update_clamped() -> void:
	for c in _clamped:
		var sk: Skeleton3D = c["sk"]
		var shoulder := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(String(c["side"]) + "Arm")).origin
		var src: Node3D = c["source"]
		var d := src.global_position - shoulder
		(c["proxy"] as Node3D).global_position = shoulder + d.limit_length(float(c["len"]) * 0.93)

## Modifiers fade in over RAMP_TIME so enabling them never pops the pose.
const RAMP_TIME := 1.2
var _ramping: Array = []
func _ramp_in(m: SkeletonModifier3D) -> void:
	m.influence = 0.0
	_ramping.append([m, 0.0])

func _skeleton_of(slot: Node) -> Skeleton3D:
	var v := slot.get("visual") as Node
	if v == null:
		return null
	var l := v.find_children("*", "Skeleton3D", true, false)
	return l[0] as Skeleton3D if not l.is_empty() else null

func _on_crew_ready() -> void:
	var crew := get_node(crew_path)
	for slot in crew.get_children():
		var sk := _skeleton_of(slot)
		if sk == null:
			continue
		var mod := CrewPoseModifier.new()
		mod.name = "CrewPose"
		mod.ship = _ship
		mod.pivot = _pivot
		match String(slot.name):
			"Papi_Fuego":
				mod.turn_lean = 1.0
				mod.head_look = 0.3
				mod.brace_gain = 1.0
				# Helming: the idle only drives hips/legs; upper body, head and arms are neutral (IK/layers drive them).
				mod.neutral_bones = PackedStringArray(["Spine02", "Spine01", "Spine", "neck", "Head", "headfront", "head_end",
					"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"])
			"Don_Omar":
				mod.counter_roll = 0.6
				mod.brace_gain = 0.0
				mod.neutral_bones = PackedStringArray(["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"])
			_:
				mod.brace_gain = 0.5
		sk.add_child(mod)
		_ramp_in(mod)
		if CrewNpc.is_npc():
			mod.neutral_active = false # CrewIkAdapter turns it on while IK or the violin holds the arms
			continue # helm IK and violin are driven by CrewIkAdapter (agent.ik)
		if slot.name == "Papi_Fuego":
			_setup_helmsman(slot, sk)
		elif slot.name == "Don_Omar":
			_setup_violin(slot, sk)

func _setup_helmsman(slot: Node3D, sk: Skeleton3D) -> void:
	var helm := get_node(helm_path)
	# Elbow hints (pole targets) beside the body, in slot space (ship axes): down and outward.
	var pole_l := Marker3D.new(); pole_l.name = "PoleL"; pole_l.position = Vector3(-0.75, 1.0, 0.25); slot.add_child(pole_l)
	var pole_r := Marker3D.new(); pole_r.name = "PoleR"; pole_r.position = Vector3(0.75, 1.0, 0.25); slot.add_child(pole_r)
	var ik := TwoBoneIK3D.new()
	ik.name = "ArmsIK"
	ik.setting_count = 2
	var sides := [["Left", make_clamped_target(sk, "Left", helm.hand_l), pole_l], ["Right", make_clamped_target(sk, "Right", helm.hand_r), pole_r]]
	sk.add_child(ik)
	for i in 2:
		var side: String = sides[i][0]
		ik.set_root_bone_name(i, side + "Arm")
		ik.set_middle_bone_name(i, side + "ForeArm")
		ik.set_end_bone_name(i, side + "Hand")
		ik.set_target_node(i, ik.get_path_to(sides[i][1]))
		if not OS.get_cmdline_user_args().has("--no-pole"):
			ik.set_pole_node(i, ik.get_path_to(sides[i][2]))
	_ramp_in(ik)
	print("[rig] helmsman IK ready")

func _setup_violin(_slot: Node3D, sk: Skeleton3D) -> void:
	var v := Violin.new()
	v.name = "Violin"
	sk.add_child(v)
	v.setup(sk, self)

var _dbg_sk: Skeleton3D
var _dbg_helm: Node
var _dbg_n := 0
func _process(delta: float) -> void:
	_update_clamped()
	for r in _ramping.duplicate():
		r[1] += delta
		var k := smoothstep(0.0, 1.0, clampf(float(r[1]) / RAMP_TIME, 0.0, 1.0))
		(r[0] as SkeletonModifier3D).influence = k
		if float(r[1]) >= RAMP_TIME:
			_ramping.erase(r)
	if _dbg_sk != null or not OS.get_cmdline_user_args().has("--debug-rig"):
		return
	var f := get_node(crew_path).get_node_or_null("Papi_Fuego")
	if f and _skeleton_of(f):
		_dbg_sk = _skeleton_of(f)
		_dbg_helm = get_node(helm_path)
		_dbg_sk.skeleton_updated.connect(_dbg_report)

var _prev_q := {}
var _prev_ms := 0
var _max_w := {}
func _dbg_report() -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - _prev_ms) / 1000.0
	if dt < 0.05: # measure over >= 50 ms windows (skeleton_updated can fire several times per frame)
		return
	_prev_ms = now
	if dt > 0.5:
		_prev_q.clear()
		return
	_dbg_n += 1
	for slot_name: String in ["Papi_Fuego", "Don_Omar"]:
		var sk := _skeleton_of(get_node(crew_path).get_node(slot_name))
		for b: String in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"]:
			var q := sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
			var key: String = str(slot_name) + "/" + str(b)
			if _prev_q.has(key):
				var w := rad_to_deg((_prev_q[key] as Quaternion).angle_to(q)) / dt
				_max_w[key] = maxf(_max_w.get(key, 0.0), w)
			_prev_q[key] = q
	if _dbg_n % 20 == 0:
		var out := []
		for k in _max_w:
			out.append("%s=%d" % [k, int(_max_w[k])])
		print("[armvel deg/s max] ", ", ".join(out))
		_max_w.clear()
