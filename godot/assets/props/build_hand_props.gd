extends SceneTree
## Generates the grip-ready prop scenes (res://assets/props/*_prop.tscn) from the grip table below, using the rest frames of the crew rig.
## Grip frame (hand bone local, cm): F = fingers (forearm->hand), N = palm normal (towards the body centre line), A = forward-pointing axis across the fist (F x N, sign
## fixed so it points to +Z at rest). A prop maps its butt->working-end axis u to u_to and a second model axis v to v_to, is pitched by tilt about N and rolled about u,
## and its grip point (fraction t of its extent along u from the butt end) goes to wrist + F*4.5 cm + N*1.5 cm. The orientation values were chosen with
## assets/props/grip_solve.gd (grid search against the baked clips).
## usage: godot --headless --path godot --script res://assets/props/build_hand_props.gd
const CREW := "res://assets/characters/papi_fuego.glb"
const PROPS := {
	"fishing_rod": {"f": "res://assets/props/fishing_rod/rod_q1.glb", "len": 2.0, "u": Vector3.UP, "v": Vector3.BACK, "t": 0.12, "u_to": "F", "v_to": "A", "tilt": -45.0, "roll": 0.0, "upright": false},
	"hammer": {"f": "res://assets/props/hammer/wooden_hammer_01/wooden_hammer_01.gltf", "len": 0.28, "u": Vector3.UP, "v": Vector3.BACK, "t": 0.15, "u_to": "A", "v_to": "N", "tilt": 0.0, "roll": 0.0, "upright": false},
	"saw": {"f": "res://assets/props/saw/handsaw_wood/handsaw_wood.gltf", "len": 0.63, "u": Vector3.BACK, "v": Vector3.UP, "t": 0.08, "u_to": "F", "v_to": "-N", "tilt": 0.0, "roll": 240.0, "upright": false},
	"lantern": {"f": "res://assets/props/lantern/wooden_lantern_01/wooden_lantern_01.gltf", "len": 0.35, "u": Vector3.DOWN, "v": Vector3.BACK, "t": 0.03, "u_to": "F", "v_to": "A", "tilt": 0.0, "roll": 0.0, "upright": true},
	"spyglass": {"f": "", "len": 0.45, "u": Vector3.UP, "v": Vector3.BACK, "t": 0.4, "u_to": "A", "v_to": "N", "tilt": 0.0, "roll": 0.0, "upright": false},
	"mop": {"f": "", "len": 1.3, "u": Vector3.DOWN, "v": Vector3.BACK, "t": 0.2, "u_to": "A", "v_to": "N", "tilt": 0.0, "roll": 0.0, "upright": false},
}
var crew_sk: Skeleton3D

func _init() -> void:
	_run.call_deferred()

func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		acc.append(t * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children():
		_aabb(c, t, acc)

func _cyl(parent: Node3D, owner_node: Node, name: String, r_top: float, r_bot: float, h: float, y: float, col: Color, metal: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.45
	mi.material_override = m
	mi.position = Vector3(0, y, 0)
	parent.add_child(mi)
	mi.owner = owner_node

func _procedural(id: String, owner_node: Node) -> Node3D:
	# own CC0 helpers. spyglass: three telescoping brass tubes, eyepiece at y=0, 0.45 m extended. mop (swab): rope head at y=0..0.2, 1.1 m pole above, 1.3 m total.
	var n := Node3D.new()
	n.name = "Model"
	owner_node.add_child(n)
	n.owner = owner_node
	if id == "spyglass":
		_cyl(n, owner_node, "Barrel", 0.017, 0.017, 0.16, 0.08, Color(0.62, 0.38, 0.14), 0.4)
		_cyl(n, owner_node, "Mid", 0.013, 0.013, 0.15, 0.235, Color(0.78, 0.6, 0.2), 0.7)
		_cyl(n, owner_node, "Tip", 0.010, 0.010, 0.14, 0.38, Color(0.85, 0.68, 0.25), 0.7)
		_cyl(n, owner_node, "Eyecup", 0.020, 0.020, 0.012, 0.0, Color(0.15, 0.1, 0.06), 0.0)
	else:
		_cyl(n, owner_node, "Pole", 0.012, 0.012, 1.1, 0.75, Color(0.5, 0.35, 0.2), 0.0)
		_cyl(n, owner_node, "Band", 0.018, 0.018, 0.04, 0.22, Color(0.3, 0.3, 0.3), 0.3)
		_cyl(n, owner_node, "RopeHead", 0.02, 0.09, 0.2, 0.1, Color(0.82, 0.78, 0.66), 0.0)
	return n

func _axis(name: String, F: Vector3, N: Vector3, A: Vector3) -> Vector3:
	var s := -1.0 if name.begins_with("-") else 1.0
	var k := name.trim_prefix("-")
	return s * (F if k == "F" else (N if k == "N" else A))

func _run() -> void:
	var crew := (load(CREW) as PackedScene).instantiate()
	root.add_child(crew)
	crew_sk = crew.find_children("*", "Skeleton3D", true, false)[0]
	var hand := "Right"
	var hi := crew_sk.find_bone(hand + "Hand")
	var fa := crew_sk.find_bone(hand + "ForeArm")
	var rb := crew_sk.get_bone_global_rest(hi).basis
	var F := (rb.inverse() * (crew_sk.get_bone_global_rest(hi).origin - crew_sk.get_bone_global_rest(fa).origin)).normalized()
	var N := rb.inverse() * Vector3.RIGHT
	N = (N - F * N.dot(F)).normalized()
	var A := F.cross(N)
	if (rb * A).z < 0.0:
		A = -A
	for id in PROPS:
		var cfg: Dictionary = PROPS[id]
		var holder := Node3D.new()
		holder.name = id.capitalize().replace(" ", "")
		holder.set_script(load("res://assets/props/hand_prop.gd"))
		var model: Node3D
		if cfg["f"] == "":
			model = _procedural(id, holder)
		else:
			model = (load(cfg["f"]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			model.name = "Model"
			holder.add_child(model)
			model.owner = holder
		var acc := []
		_aabb(model, Transform3D.IDENTITY, acc)
		var box: AABB = acc[0]
		for a in acc:
			box = box.merge(a)
		var long := maxf(box.size.x, maxf(box.size.y, box.size.z))
		var s: float = cfg["len"] / long
		var u: Vector3 = (cfg["u"] as Vector3).normalized()
		var v: Vector3 = (cfg["v"] as Vector3).normalized()
		var ut := _axis(cfg["u_to"], F, N, A)
		var vt := _axis(cfg["v_to"], F, N, A)
		vt = (vt - ut * vt.dot(ut)).normalized()
		vt = Basis(ut, deg_to_rad(cfg["roll"])) * vt
		var tilt := Basis(N, deg_to_rad(cfg["tilt"]))
		ut = tilt * ut
		vt = tilt * vt
		var rot := Basis(ut, vt, ut.cross(vt)) * Basis(u, v, u.cross(v)).inverse()
		var ext := absf(box.size.dot(u.abs()))
		var g := box.get_center() - u * (ext * 0.5) + u * (ext * float(cfg["t"]))
		holder.set("scale_m", s)
		holder.set("grip_model", g)
		holder.set("grip_rotation", rot)
		holder.set("palm_cm", F * 4.5 + N * 1.5)
		holder.set("upright", cfg["upright"])
		var ps := PackedScene.new()
		var err := ps.pack(holder)
		var path := "res://assets/props/%s_prop.tscn" % id
		var err2 := ResourceSaver.save(ps, path)
		print("[props] ", path, " pack=", err, " save=", err2, " scale_m=", snappedf(s, 0.0001), " grip=", g)
		holder.free()
	quit()
