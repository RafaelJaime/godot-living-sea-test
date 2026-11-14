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

func _ready() -> void:
	_ship = get_node(ship_path)
	_pivot = get_parent() as Node3D
	get_node(crew_path).crew_ready.connect(_on_crew_ready)

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
				mod.head_look = 0.55
				mod.brace_gain = 1.0
			"Don_Omar":
				mod.counter_roll = 0.6
				mod.brace_gain = 0.0
			_:
				mod.brace_gain = 0.5
		sk.add_child(mod)
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
	var sides := [["Left", helm.hand_l, pole_l], ["Right", helm.hand_r, pole_r]]
	sk.add_child(ik)
	for i in 2:
		var side: String = sides[i][0]
		ik.set_root_bone_name(i, side + "Arm")
		ik.set_middle_bone_name(i, side + "ForeArm")
		ik.set_end_bone_name(i, side + "Hand")
		ik.set_target_node(i, ik.get_path_to(sides[i][1]))
		if not OS.get_cmdline_user_args().has("--no-pole"):
			ik.set_pole_node(i, ik.get_path_to(sides[i][2]))
	print("[rig] helmsman IK ready")

func _setup_violin(_slot: Node3D, sk: Skeleton3D) -> void:
	var v := Violin.new()
	v.name = "Violin"
	sk.add_child(v)
	v.setup(sk)

var _dbg_sk: Skeleton3D
var _dbg_helm: Node
var _dbg_n := 0
func _process(_delta: float) -> void:
	if _dbg_sk != null or not OS.get_cmdline_user_args().has("--debug-rig"):
		return
	var f := get_node(crew_path).get_node_or_null("Papi_Fuego")
	if f and _skeleton_of(f):
		_dbg_sk = _skeleton_of(f)
		_dbg_helm = get_node(helm_path)
		_dbg_sk.skeleton_updated.connect(_dbg_report)

func _dbg_report() -> void:
	_dbg_n += 1
	if _dbg_n % 90 != 0:
		return
	for side in ["Left", "Right"]:
		var hb := _dbg_sk.find_bone(side + "Hand")
		var hand := _dbg_sk.global_transform * _dbg_sk.get_bone_global_pose(hb).origin
		var shoulder := _dbg_sk.global_transform * _dbg_sk.get_bone_global_pose(_dbg_sk.find_bone(side + "Arm")).origin
		var tgt: Vector3 = (_dbg_helm.hand_l if side == "Left" else _dbg_helm.hand_r).global_position
		print("[dbg] ", side, " hand-target err=", snappedf(hand.distance_to(tgt), 0.001), " shoulder-target=", snappedf(shoulder.distance_to(tgt), 0.001))
