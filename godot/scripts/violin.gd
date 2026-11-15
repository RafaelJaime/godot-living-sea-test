class_name Violin
extends Node
## Don Omar plays the violin: builds a violin + bow, holds the violin under the chin (attached to the Head bone),
## and drives two TwoBoneIK3D arms: the left hand holds the neck, the right hand strokes the bow back and forth.
## Skeleton units are ~cm (the rig is scaled by ~0.01), so all prop dimensions below are in cm.

var _sk: Skeleton3D
var _violin: Node3D
var _bow_target: Node3D
var _pole_l: Node3D
var _pole_r: Node3D
var _t := 0.0
var _ik: TwoBoneIK3D
var _on_demand := false ## npc crew: the violin only exists while Omar plays (set_playing), instead of always on
var _play := 0.0 ## 0..1 blend of the violin pose
var _play_goal := 0.0
@export var bow_speed := 1.9
@export var bow_amplitude := 10.0

func setup(sk: Skeleton3D, rig: Node, on_demand := false) -> void:
	_sk = sk
	_on_demand = on_demand
	_violin = _build_violin()
	_violin.top_level = true # positioned every frame in the character frame (see _place)
	add_child(_violin)

	var hold := Node3D.new() # left hand grip on the neck
	hold.name = "LeftGrip"
	hold.position = Vector3(0.0, 2.0, 30.0)
	_violin.add_child(hold)
	_bow_target = Node3D.new() # right hand: bow frog, moves along the violin's X axis
	_bow_target.name = "RightGrip"
	_bow_target.position = Vector3(0.0, 4.5, 14.0)
	_violin.add_child(_bow_target)
	_bow_target.add_child(_build_bow())

	_pole_l = Node3D.new(); _pole_l.name = "PoleL"; _pole_l.top_level = true; add_child(_pole_l)
	_pole_r = Node3D.new(); _pole_r.name = "PoleR"; _pole_r.top_level = true; add_child(_pole_r)

	var ik := TwoBoneIK3D.new()
	ik.name = "ViolinIK"
	ik.influence = 0.0
	_ik = ik
	if not on_demand:
		rig._ramp_in(ik)
	ik.setting_count = 2
	sk.add_child(ik)
	if on_demand:
		_violin.visible = false
	var sides := [["Left", rig.make_clamped_target(sk, "Left", hold), _pole_l], ["Right", rig.make_clamped_target(sk, "Right", _bow_target), _pole_r]]
	for i in 2:
		var side: String = sides[i][0]
		ik.set_root_bone_name(i, side + "Arm")
		ik.set_middle_bone_name(i, side + "ForeArm")
		ik.set_end_bone_name(i, side + "Hand")
		ik.set_target_node(i, ik.get_path_to(sides[i][1]))
		ik.set_pole_node(i, ik.get_path_to(sides[i][2]))

func _wood(c: Color, rough := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _build_violin() -> Node3D:
	var v := Node3D.new()
	v.name = "Violin"
	var varnish := _wood(Color(0.55, 0.22, 0.07), 0.25)
	var dark := _wood(Color(0.08, 0.05, 0.04), 0.6)
	# Body: two overlapping squashed spheres (upper/lower bout) along +Z.
	for part in [[Vector3(0, 0, 5.0), Vector3(7.0, 2.6, 8.0)], [Vector3(0, 0, 17.0), Vector3(8.5, 2.6, 10.0)]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 20
		sm.rings = 10
		mi.mesh = sm
		mi.scale = part[1]
		mi.position = part[0]
		mi.material_override = varnish
		v.add_child(mi)
	var neck := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(2.4, 1.8, 24.0)
	neck.mesh = nb
	neck.position = Vector3(0, 2.0, 27.0)
	neck.material_override = dark
	v.add_child(neck)
	var scroll := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 1.9
	ss.height = 3.8
	scroll.mesh = ss
	scroll.position = Vector3(0, 2.0, 40.0)
	scroll.material_override = varnish
	v.add_child(scroll)
	var bridge := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(4.0, 1.4, 0.4)
	bridge.mesh = bb
	bridge.position = Vector3(0, 3.1, 11.0)
	bridge.material_override = _wood(Color(0.8, 0.7, 0.5))
	v.add_child(bridge)
	return v

func _build_bow() -> Node3D:
	var b := Node3D.new()
	b.name = "Bow"
	# The bow lies along the violin's X axis, the hand holds the frog at its end (local origin).
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.5
	cm.height = 62.0
	cm.radial_segments = 6
	stick.mesh = cm
	stick.rotation.z = PI * 0.5
	stick.position = Vector3(-31.0, 0.0, 0.0)
	stick.material_override = _wood(Color(0.30, 0.12, 0.04), 0.4)
	b.add_child(stick)
	var hair := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(56.0, 0.15, 1.2)
	hair.mesh = hb
	hair.position = Vector3(-31.0, -1.1, 0.0)
	hair.material_override = _wood(Color(0.95, 0.93, 0.85), 0.8)
	b.add_child(hair)
	return b

## Character frame from the skeleton (robust to the animation's root orientation): left = right shoulder -> left
## shoulder, up = hips -> neck, forward = left x up. Returns [origin(head, world), basis(unscaled), scale].
func _frame() -> Array:
	var gt := _sk.global_transform
	var lp := (gt * _sk.get_bone_global_pose(_sk.find_bone("LeftArm")).origin)
	var rp := (gt * _sk.get_bone_global_pose(_sk.find_bone("RightArm")).origin)
	var hp := (gt * _sk.get_bone_global_pose(_sk.find_bone("Hips")).origin)
	var np := (gt * _sk.get_bone_global_pose(_sk.find_bone("neck")).origin)
	var head := (gt * _sk.get_bone_global_pose(_sk.find_bone("Head")).origin)
	var left := (lp - rp).normalized()
	var up := (np - hp).normalized()
	var fwd := left.cross(up).normalized()
	left = up.cross(fwd).normalized()
	return [head, Basis(left, up, fwd), gt.basis.get_scale().x, (lp + rp) * 0.5]

func _place() -> void:
	var f := _frame()
	var head: Vector3 = f[0]
	var b: Basis = f[1]
	var s: float = f[2]
	var chest: Vector3 = f[3]
	# Violin under the chin, on the left shoulder side; neck points forward and a little to the left, slightly down.
	var vb := b * Basis.from_euler(Vector3(deg_to_rad(10.0), deg_to_rad(28.0), deg_to_rad(-12.0)))
	var org := head + b * (Vector3(3.0, -7.5, 5.0) * s)
	_violin.global_transform = Transform3D(vb.scaled(Vector3(s, s, s)), org)
	_pole_l.global_position = chest + b * (Vector3(42.0, -26.0, -6.0) * s)
	_pole_r.global_position = chest + b * (Vector3(-42.0, -22.0, -10.0) * s)

## On-demand mode only: raises (true) or lowers (false) the violin pose; the blend takes about a second.
func set_playing(on: bool) -> void:
	_play_goal = 1.0 if on else 0.0

func is_playing() -> bool:
	return _play > 0.01

func _process(delta: float) -> void:
	if _bow_target == null:
		return
	if _on_demand:
		_play = move_toward(_play, _play_goal, delta / 1.2)
		_ik.influence = smoothstep(0.0, 1.0, _play)
		_violin.visible = _play > 0.01
		if _play <= 0.01:
			return
	_place()
	_t += delta
	# Bow strokes: down-bow / up-bow along the violin's X, with slight changes of position and pressure.
	var stroke := sin(_t * bow_speed)
	var swell := 0.5 + 0.5 * sin(_t * 0.37)
	_bow_target.position = Vector3(stroke * bow_amplitude + 4.0, 4.5 - 0.5 * swell, 13.0 + 3.0 * sin(_t * 0.23))
