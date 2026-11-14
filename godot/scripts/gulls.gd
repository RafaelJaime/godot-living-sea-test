extends Node3D
## A few seagulls circling near the ship (simple V-shaped wings that flap).

@export var count := 5
@export var ship_path := NodePath("../Ship")

var _ship: Node3D
var _birds: Array[Dictionary] = []

func _ready() -> void:
	_ship = get_node(ship_path)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.95)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wing := _wing_mesh()
	for i in count:
		var bird := Node3D.new()
		var l := MeshInstance3D.new(); l.mesh = wing; l.material_override = mat
		var r := MeshInstance3D.new(); r.mesh = wing; r.material_override = mat
		r.scale.x = -1.0
		bird.add_child(l); bird.add_child(r)
		add_child(bird)
		_birds.append({
			"node": bird, "l": l, "r": r,
			"phase": randf() * TAU,
			"radius": randf_range(25.0, 60.0),
			"speed": randf_range(0.18, 0.32) * (1.0 if i % 2 == 0 else -1.0),
			"height": randf_range(14.0, 34.0),
			"center": Vector3(randf_range(-70.0, 70.0), 0.0, randf_range(-140.0, -40.0)),
			"flap": randf_range(5.0, 8.0),
		})

func _wing_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0, 0.35), Vector3(0, 0, -0.3), Vector3(1.6, 0.05, -0.1)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	return st.commit()

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in _birds:
		var a: float = float(b["phase"]) + t * float(b["speed"])
		var c: Vector3 = b["center"]
		var rad: float = b["radius"]
		var p := _ship.global_position + c + Vector3(cos(a) * rad, float(b["height"]) + sin(t * 0.4 + float(b["phase"])) * 2.0, sin(a) * rad)
		var node: Node3D = b["node"]
		node.global_position = p
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(float(b["speed"]))
		node.look_at(p + tangent, Vector3.UP)
		node.rotation.z = -0.35 * signf(float(b["speed"]))
		var flap := sin(t * float(b["flap"]) + float(b["phase"])) * 0.45
		(b["l"] as Node3D).rotation.z = flap
		(b["r"] as Node3D).rotation.z = -flap
