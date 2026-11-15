extends SceneTree
## A2.5 reproducibility run (dev-only), no scene needed:
##   godot --headless --fixed-fps 60 --path godot -s tests/npc_life/repro_run.gd -- --npc-seed=1 --npc-minutes=10 --npc-log=<file>
## Four agents with different tastes, one source that posts jobs of four kinds with its own seeded stream.

class MixedSource extends NpcJobSource:
	var _n := 0
	var _next := 0.0
	func _poll(world: Node, now: float) -> void:
		if now < _next:
			return
		var rng: NpcRng = (world as NpcWorld).rng_for(&"mixed_source", &"post")
		var kinds := [&"music", &"fishing", &"mop", &"repair", &"stargaze"]
		var j := NpcJob.new()
		_n += 1
		j.kind = kinds[rng.randi() % kinds.size()]
		j.id = StringName("%s:%d" % [j.kind, _n])
		j.ttl_s = rng.randf_range(20.0, 90.0)
		j.priority = rng.randf_range(0.0, 0.6)
		var act := NpcActionDef.new()
		act.action_id = j.kind
		act.duration_range = Vector2(6.0, 16.0)
		j.action = act
		post_job(j, now)
		_next = now + rng.randf_range(2.0, 9.0)

func _initialize() -> void:
	await process_frame
	var w := NpcWorld.new()
	w.name = "NpcWorld"
	for spec in [[&"Fuego", {&"fishing": 0.9}, 0.9], [&"Diag", {&"mop": 0.8, &"repair": 0.9}, 0.5], [&"Salchi", {&"fishing": 0.6, &"stargaze": 0.7}, 0.5], [&"Omar", {&"music": 1.0}, 0.3]]:
		var d := NpcCharacterDef.new()
		d.agent_id = spec[0]
		for k in spec[1]:
			d.preferences[k] = spec[1][k] # typed Dictionary property: fill it, an untyped Dictionary cannot be assigned
		d.skills[&"helm"] = spec[2]
		d.needs[&"boredom"] = 4.0
		var a := NpcAgent.new()
		a.def = d
		w.add_child(a)
	var src := MixedSource.new()
	src.source_id = &"mixed"
	src.poll_hz = 2.0
	w.add_child(src)
	get_root().add_child(w)
