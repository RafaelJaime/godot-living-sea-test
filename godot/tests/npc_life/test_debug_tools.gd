extends GutTest
## Specs: npc-life-debug-tools (overlay: off by default and absent when disabled, one label per agent when enabled).

var world: NpcWorld

func before_each() -> void:
	world = NpcWorld.new()
	world.world_seed = 5
	add_child_autofree(world)
	for id in [&"A", &"B", &"C"]:
		var d := NpcCharacterDef.new()
		d.agent_id = id
		var a := NpcAgent.new()
		a.def = d
		world.add_child(a)

func _labels(root: Node) -> int:
	return root.find_children("*", "Label3D", true, false).size()

func test_overlay_creates_no_nodes_when_disabled() -> void:
	var before := world.get_child_count()
	world.advance(1.0)
	assert_null(world.overlay(), "no overlay object")
	assert_eq(world.get_child_count(), before, "no node was added")
	assert_eq(_labels(world), 0)
	assert_eq(get_tree().get_nodes_in_group(&"npc_debug_overlay").size(), 0)

func test_overlay_label_per_agent_when_enabled() -> void:
	world.set_debug(true)
	world.advance(1.0)
	world.overlay().refresh() # (every real frame in a game)
	assert_not_null(world.overlay())
	assert_eq(_labels(world), 3, "a Label3D per agent")
	var a := world.get_agent(&"A") as NpcAgent
	var lab := a.find_children("*", "Label3D", true, false)[0] as Label3D
	assert_true(lab.text.contains("ambient"), "shows the job: %s" % lab.text)
	world.set_debug(false)
	assert_eq(_labels(world), 0, "switching it off removes every node")
	assert_null(world.overlay())

func test_overlay_lists_last_decision_scores() -> void:
	world.set_debug(true)
	var j := NpcJob.new()
	j.id = &"mop1"
	j.kind = &"mop"
	j.ttl_s = 0.0
	world.board.post(j, world.now())
	world.advance(0.3)
	world.overlay().refresh()
	var text := world.overlay().summary_text()
	assert_true(text.contains("A") and text.contains("mop"), "the list shows agents, picks and top scores: %s" % text)
