class_name CrewNpc
extends Node
## Autonomous crew (C1.2). With `--crew=npc` it builds an NpcWorld under the ship pivot, one NpcAgent per crew slot, and the world bridge that
## feeds the blackboard. The CrewSlot markers keep owning the model (loading, fitting, camera lookups by name); each frame the slot follows its
## agent, so cameras and the lean modifiers keep working. With `--crew=legacy` (default until C3 is verified) this node does nothing at all:
## no NpcWorld, no agents, the static slots behave exactly as before.

const MODE_LEGACY := &"legacy"
const MODE_NPC := &"npc"
const DEF_DIR := "res://crew/defs/"

@export var crew_path := NodePath("../CrewMarkers")
@export var stations_path := NodePath("../ShipStations/Provider")
@export var ship_path := NodePath("../..")

var world: NpcWorld
var bridge: CrewWorldBridge
var agents: Dictionary = {} # slot node name -> NpcAgent
var _trace := OS.get_cmdline_user_args().has("--crew-trace") ## test aid: one status line per agent every 2 s (logical time)
var _trace_next := 2.0
var _slots: Dictionary = {} # slot node name -> Node3D

## `--crew=legacy|npc` (user args). Unknown values warn and fall back to legacy.
static func mode(args: PackedStringArray = OS.get_cmdline_user_args()) -> StringName:
	for a in args:
		if a.begins_with("--crew="):
			var v := a.get_slice("=", 1)
			if v == "npc":
				return MODE_NPC
			if v != "legacy":
				push_warning("[crew] unknown --crew value '%s', using legacy" % v)
	return MODE_LEGACY

static func is_npc() -> bool:
	return mode() == MODE_NPC

func _ready() -> void:
	if not is_npc():
		set_process(false)
		return
	process_priority = 100 # after the world has moved the agents this frame
	get_node(crew_path).crew_ready.connect(_on_crew_ready)

func _on_crew_ready() -> void:
	var pivot := get_parent() as Node3D
	var provider := get_node_or_null(stations_path) as ShipStations
	if provider == null or provider.graph() == null:
		push_error("[crew] --crew=npc needs ShipStations and its baked graph; staying static")
		set_process(false)
		return
	world = NpcWorld.new()
	world.name = "NpcWorld"
	world.platform_root = pivot
	world.graph = provider.graph()
	add_child(world)
	var sched := NpcWatchScheduler.new()
	sched.name = "Roster"
	sched.source_id = &"roster"
	sched.roster = load(DEF_DIR + "crew_roster.tres") as NpcRoster
	world.add_child(sched)
	bridge = CrewWorldBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)
	bridge.bind(world, get_node(ship_path))
	for slot in get_node(crew_path).get_children():
		if slot is Marker3D: # the barrels are siblings too
			_spawn(slot as Node3D, pivot)
	if OS.get_cmdline_user_args().has("--crew-demo-violin"): # test aid until the free-time source (C2) posts these jobs: Omar plays at once
		var j := NpcJob.new()
		j.id = &"demo:violin"
		j.kind = &"violin_seat"
		j.station_id = &"violin_seat"
		j.priority = 1.0
		j.ttl_s = 0.0
		world.board.post(j, world.now())
	print("[crew] npc mode:%d agents, graph %d nodes, roster %d watches" % [agents.size(), world.graph.node_count(), sched.roster.watches.size()])

func _spawn(slot: Node3D, pivot: Node3D) -> void:
	var visual := slot.get("visual") as Node3D
	var def_path := DEF_DIR + String(slot.name).to_lower() + ".tres"
	if visual == null or not ResourceLoader.exists(def_path):
		push_warning("[crew] %s: no model or no def (%s), left static" % [slot.name, def_path])
		return
	var def := load(def_path) as NpcCharacterDef
	var yaw_deg: float = slot.get("final_model_yaw_deg")
	var facing_deg: float = slot.get("facing_deg")
	visual.position.y = 0.0 # seat / sit offsets belong to the old static pose
	visual.rotation.y = deg_to_rad(yaw_deg) # facing now comes from the agent
	var agent := NpcAgent.new()
	agent.def = def
	agent.name = String(def.agent_id)
	agent.position = slot.position
	agent.rotation.y = deg_to_rad(facing_deg)
	pivot.add_child(agent)
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = def.anim_set as NpcAnimSet
	ad.rig_profile = def.rig_profile as NpcRigProfile
	ad.bind(agent, visual)
	agent.anim = ad
	var sks := visual.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var ik := CrewIkAdapter.new()
		ik.rig = pivot.get_node_or_null("CrewRig")
		if ik.bind(agent, sks[0] as Skeleton3D, def.rig_profile as NpcRigProfile):
			agent.ik = ik
	agents[slot.name] = agent
	_slots[slot.name] = slot

func _process(_delta: float) -> void:
	if _trace and world != null and world.now() >= _trace_next:
		_trace_next += 2.0
		for n in agents:
			var a := agents[n] as NpcAgent
			var ik := a.ik as CrewIkAdapter
			print("[crew-trace] t=%.1f %s phase=%s job=%s action=%s pos=%s violin=%s hand_l=%.2f hand_r=%.2f" % [world.now(), a.agent_id, a.phase(), a.current_job_id(), a.last_action_id(),
				a.position.snapped(Vector3.ONE * 0.1), ik.violin_active() if ik else false, ik.weight_of(&"hand_l") if ik else 0.0, ik.weight_of(&"hand_r") if ik else 0.0])
	for n in agents:
		var a := agents[n] as NpcAgent
		var s := _slots[n] as Node3D
		s.position = a.position
		s.rotation.y = a.rotation.y
