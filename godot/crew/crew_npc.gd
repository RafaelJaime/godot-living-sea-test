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
	print("[crew] npc mode: %d agents, graph %d nodes, roster %d watches" % [agents.size(), world.graph.node_count(), sched.roster.watches.size()])

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
	agents[slot.name] = agent
	_slots[slot.name] = slot

func _process(_delta: float) -> void:
	for n in agents:
		var a := agents[n] as NpcAgent
		var s := _slots[n] as Node3D
		s.position = a.position
		s.rotation.y = a.rotation.y
