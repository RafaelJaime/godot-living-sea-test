extends Node3D
## Creates the pinnace's lanterns under the ship pivot (positions in ship-pivot space: +x starboard, -z bow, y up from the
## waterline). Retune the table when the hull changes. Procedural lantern meshes: a dark cap + emissive glass.

const TABLE := [
	# id, position, stand point (deck), stand facing (deg), shadow, window?
	{"id": "stern_port", "pos": Vector3(-2.9, 9.5, 18.3), "stand": Vector3(-2.2, 6.6, 17.0), "face": 150.0, "shadow": false},
	{"id": "stern_starboard", "pos": Vector3(2.9, 9.5, 18.3), "stand": Vector3(2.2, 6.6, 17.0), "face": -150.0, "shadow": false},
	{"id": "helm", "pos": Vector3(0.9, 8.1, 16.2), "stand": Vector3(0.9, 6.5, 15.4), "face": 180.0, "shadow": true},
	{"id": "waist", "pos": Vector3(1.4, 3.7, 0.8), "stand": Vector3(1.4, 1.85, 1.6), "face": 180.0, "shadow": true},
	{"id": "forecastle", "pos": Vector3(0.0, 5.4, -10.2), "stand": Vector3(0.0, 3.5, -9.2), "face": 180.0, "shadow": false},
]
const WINDOWS := [Vector3(-1.5, 6.0, 20.0), Vector3(-0.5, 6.0, 20.0), Vector3(0.5, 6.0, 20.0), Vector3(1.5, 6.0, 20.0)]

func _ready() -> void:
	for d in TABLE:
		var l := ShipLantern.new()
		l.name = "Lantern_" + String(d["id"])
		l.id = d["id"]
		l.position = d["pos"]
		l.stand_local = d["stand"]
		l.stand_facing_deg = d["face"]
		l.casts_shadow = d["shadow"]
		add_child(l)
		# Lantern body: cap on top, frame ring.
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02; cm.bottom_radius = 0.2; cm.height = 0.16
		cap.mesh = cm
		cap.position = Vector3(0, 0.22, 0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.06, 0.05)
		m.roughness = 0.6
		cap.material_override = m
		l.add_child(cap)
	# Cabin: stern window glow (a single logical lantern "cabin" made of four lit panes + one soft inner light).
	var cabin := ShipLantern.new()
	cabin.name = "Lantern_cabin"
	cabin.id = "cabin"
	cabin.position = Vector3(0.0, 6.0, 19.6)
	cabin.is_window = true
	cabin.glass_size = 0.9
	cabin.light_energy = 1.2
	cabin.light_range = 9.0
	cabin.stand_local = Vector3(0.0, 6.5, 15.8)
	cabin.stand_facing_deg = 0.0
	add_child(cabin)
	for i in range(1, WINDOWS.size()):
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 1.15)
		q.mesh = qm
		q.position = WINDOWS[i] - cabin.position
		q.set_meta("window_pane", true)
		cabin.add_child(q)
	# Share the cabin's emissive material with the extra panes once the lantern built it.
	cabin.ready.connect(func() -> void:
		for c in cabin.get_children():
			if c.has_meta("window_pane"):
				(c as MeshInstance3D).material_override = cabin._glass.material_override)
