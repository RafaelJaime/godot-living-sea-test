extends SceneTree
## Builds the example resources and scene (run once, the outputs are committed):
##   godot --headless --path <project> -s addons/npc_life/examples/workshop/build_workshop.gd
const DIR := "res://addons/npc_life/examples/workshop/"

func _initialize() -> void:
	var g := NpcWaypointGraph.new()
	var dock := g.add_node(Vector3(-5, 0, 0), &"dock")
	var hub := g.add_node(Vector3(-1.5, 0, 0), &"hub")
	var mid := g.add_node(Vector3(2, 0, 0), &"mid")
	var bench := g.add_node(Vector3(5, 0, 0), &"workbench")
	var lamp := g.add_node(Vector3(-1.5, 0, 3), &"lamp")
	var net := g.add_node(Vector3(-1.5, 0, -3), &"net")
	g.connect_nodes(dock, hub, &"walk")
	g.connect_nodes(hub, mid, &"walk")
	g.connect_nodes(mid, bench, &"walk")
	g.connect_nodes(hub, lamp, &"stairs") # a step up to the lamp: shows a non-walk edge type
	g.connect_nodes(hub, net, &"walk")
	ResourceSaver.save(g, DIR + "defs/workshop_graph.tres")
	for k in [["craft", 0.2, &"focus", &"crafted"], ["mend", 0.15, &"focus", &"mended"], ["lamp", 0.3, &"", &"lit"]]:
		var act := NpcActionDef.new()
		act.action_id = StringName(k[0])
		act.job_kinds = PackedStringArray([k[0]])
		act.effect = k[3]
		act.duration_range = Vector2(6.0, 10.0)
		var kd := NpcJobKindDef.new()
		kd.default_action = act
		kd.kind = StringName(k[0])
		kd.base_score = k[1]
		kd.satisfies = k[2]
		kd.satisfy_amount = 0.4
		ResourceSaver.save(kd, DIR + "defs/kind_%s.tres" % k[0])
	var defs := [
		["Ana", "Ana", {&"craft": 0.9, &"mend": -0.2}, 0.8],
		["Bruno", "Bruno", {&"mend": 0.9, &"craft": -0.1}, 1.1],
		["Cleo", "Cleo", {&"lamp": 0.9, &"mend": 0.2}, 0.9],
	]
	for d in defs:
		var def := NpcCharacterDef.new()
		def.agent_id = StringName(d[0])
		def.display_name = d[1]
		for k in d[2]:
			def.preferences[k] = d[2][k]
		def.needs[&"focus"] = 3.0
		def.skills[&"lookout"] = {&"Ana": 0.8, &"Bruno": 0.5, &"Cleo": 0.6}[def.agent_id]
		if def.agent_id == &"Bruno":
			def.tags = PackedStringArray(["performer"])
		def.temperature_scale = d[3]
		ResourceSaver.save(def, DIR + "defs/%s.tres" % String(d[0]).to_lower())
	# roster: one watch at the watch post, shifts of 40 s with a 10 s overlapped handover
	var watch := NpcWatchDef.new()
	watch.watch_id = &"lookout"
	watch.station_id = &"watch_post"
	watch.job_kind = &"lookout"
	watch.eligible = PackedStringArray(["Ana", "Cleo"]) # Bruno is the fiddler
	watch.shift_s = 40.0
	watch.handover_lead_s = 10.0
	watch.max_consecutive = 2
	var roster := NpcRoster.new()
	roster.watches.append(watch)
	ResourceSaver.save(roster, DIR + "defs/roster.tres")
	# scene
	var root := Node3D.new()
	root.name = "Workshop"
	root.set_script(load(DIR + "workshop.gd"))
	var raft := Node3D.new()
	raft.name = "Raft"
	raft.set_script(load(DIR + "raft_motion.gd"))
	raft.set("drift_radius", 3.0)
	root.add_child(raft)
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var box := BoxMesh.new()
	box.size = Vector3(14, 0.2, 8)
	deck.mesh = box
	deck.position.y = -0.11
	raft.add_child(deck)
	var world := NpcWorld.new()
	world.name = "NpcWorld"
	world.platform_root = raft
	world.graph = load(DIR + "defs/workshop_graph.tres")
	raft.add_child(world)
	var src := (load(DIR + "workshop_sources.gd") as GDScript).new() as NpcJobSource
	src.name = "Source"
	src.source_id = &"workshop"
	world.add_child(src)
	var gi := NpcWaypointGraphInstance.new() # shows the graph in the editor (gizmo, inspector buttons); the world uses the same resource at run time
	gi.name = "GraphView"
	gi.graph = world.graph
	gi.platform_root = raft
	raft.add_child(gi)
	var sched := NpcWatchScheduler.new()
	sched.name = "Roster"
	sched.source_id = &"roster"
	sched.roster = load(DIR + "defs/roster.tres")
	world.add_child(sched)
	var social := NpcSocialDirector.new()
	social.name = "Social"
	social.source_id = &"social"
	social.chat_chance = 0.15
	world.add_child(social)
	for st in [["workbench", &"workbench", Vector3(5.5, 0, 0), 90.0], ["lamp_post", &"lamp", Vector3(-1.5, 0.3, 3.5), 180.0], ["net_rack", &"net", Vector3(-1.5, 0, -3.5), 0.0],
			["watch_post", &"watch", Vector3(4.5, 0, 2.6), 0.0], ["campfire", &"social_spot", Vector3(2.0, 0, 2.8), 0.0], ["fiddle_seat", &"performer_seat", Vector3(2.5, 0, -2.6), 180.0]]:
		var s := NpcStation.new()
		s.name = String(st[0]).capitalize().replace(" ", "")
		s.station_id = StringName(st[0])
		s.kind = st[1]
		s.position = st[2]
		s.facing_deg = st[3]
		s.approach_offset = Vector3(0, 0, 0)
		if st[0] == "campfire":
			s.slot_count = 3
			s.tags = PackedStringArray(["social"])
		elif st[0] == "fiddle_seat":
			s.tags = PackedStringArray(["performer"])
		raft.add_child(s)
		# IK markers in the station's local space (the agent stands on the station anchor facing `facing_deg`)
		if st[0] == "workbench":
			_marker(s, "hand_r", Vector3(-0.4, 1.05, -0.2))
			_marker(s, "look_at", Vector3(-1.0, 1.3, 0.0))
		elif st[0] == "net_rack":
			_marker(s, "look_at", Vector3(0.0, 1.4, -1.0))
	var starts := [Vector3(-5, 0, 0.4), Vector3(-5, 0, -0.4), Vector3(-4.2, 0, 0)]
	for i in 3:
		var a := NpcAgent.new()
		a.name = String(defs[i][0])
		a.def = load(DIR + "defs/%s.tres" % String(defs[i][0]).to_lower())
		a.position = starts[i]
		raft.add_child(a)
		# (the puppet with its skeleton is added at run time by workshop.gd)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.position = Vector3(0, 12, 14)
	root.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, DIR + "workshop.tscn")
	print("[build_workshop] saved ", DIR)
	quit(0)

func _marker(station: NpcStation, key: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = key
	m.position = pos
	station.add_child(m)
	var dot := MeshInstance3D.new() # a small visible target so captures show what the hand reaches for
	dot.name = "Dot"
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	dot.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.15) if key == "hand_r" else Color(1.0, 0.85, 0.1)
	dot.material_override = mat
	m.add_child(dot)
	station.ik_targets[StringName(key)] = NodePath(key)

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)
