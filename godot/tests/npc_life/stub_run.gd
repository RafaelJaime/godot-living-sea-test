extends SceneTree
## A1 stub run (dev-only): NpcWorld + one source + one station, logs post / claim / release. godot --headless -s tests/npc_life/stub_run.gd

class LampSource extends NpcJobSource:
	func _poll(world: Node, now: float) -> void:
		var j := NpcJob.new()
		j.id = &"lamp:1"
		j.kind = &"lantern"
		j.station_id = &"lamp_post"
		post_job(j, now)

func _initialize() -> void:
	await process_frame
	var world := NpcWorld.new()
	var src := LampSource.new()
	src.source_id = &"lamps"
	world.add_child(src)
	var st := NpcStation.new()
	st.station_id = &"lamp_post"
	st.kind = &"lantern"
	world.add_child(st)
	get_root().add_child(world)
	world.board.job_posted.connect(func(j: NpcJob) -> void: print("[stub] posted ", j.id, " kind=", j.kind))
	world.board.job_claimed.connect(func(j: NpcJob, a: StringName) -> void: print("[stub] claimed ", j.id, " by ", a))
	world.board.job_released.connect(func(j: NpcJob, a: StringName) -> void: print("[stub] released ", j.id, " by ", a))
	world.step(2)
	print("[stub] open jobs=", world.board.open_jobs().size(), " stations=", world.get_stations().size(), " tick=", world.tick_count, " now=", world.now())
	var j := world.board.get_job(&"lamp:1")
	print("[stub] claim=", world.board.claim(j.id, &"Fuego"), " station slot=", st.claim(&"Fuego"))
	world.board.release(j.id, &"Fuego")
	st.release(&"Fuego")
	print("[stub] DONE errors=none")
	quit(0)
