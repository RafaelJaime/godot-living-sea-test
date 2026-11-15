extends Node3D
## Example scene root: gives each agent a stick-figure puppet with the default animation and IK adapters, drives the example day/night through the
## blackboard and lets the NpcWorld run. Headless:
##   godot --headless --fixed-fps 60 --path <project> res://addons/npc_life/examples/workshop/workshop.tscn -- --npc-seed=1 --npc-minutes=3
## Captures (needs a window): add `--workshop-shots=<dir>`: saves reach.png (hand IK on the workbench) and crossfade.png (a clip change mid-blend), then quits.

@onready var world: NpcWorld = $Raft/NpcWorld
@onready var raft: Node3D = $Raft
@onready var cam: Camera3D = $Camera

var _anim_set: NpcAnimSet
var _shots_dir := ""
var _shot_reach := false
var _shot_cross_at := -1.0
var _shot_cross := false
var _agents: Array[NpcAgent] = []
var _focus: NpcAgent
var _pending_file := ""
var _pending_wait := 0
var _cross_agent: NpcAgent

func _ready() -> void:
	for kind_path in ["craft", "mend", "lamp"]:
		var kd := load("res://addons/npc_life/examples/workshop/defs/kind_%s.tres" % kind_path) as NpcJobKindDef
		world.kind_defs[kd.kind] = kd
	_anim_set = NpcAnimSet.new()
	_anim_set.library = NpcExamplePuppet.clips()
	_anim_set.shared = {&"idle": &"shared/idle", &"walk": &"shared/walk", &"work": &"shared/work"}
	_anim_set.locomotion = {&"walk": &"walk", &"stairs": &"walk", &"ladder": &"walk", &"rope": &"walk"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--workshop-shots="):
			_shots_dir = a.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_shots_dir)
	var tints := {&"Ana": Color(0.85, 0.45, 0.35), &"Bruno": Color(0.35, 0.6, 0.85), &"Cleo": Color(0.5, 0.8, 0.45)}
	for n in raft.get_children():
		if n is NpcAgent:
			_dress(n as NpcAgent, tints.get((n as NpcAgent).def.agent_id, Color.WHITE))
	await get_tree().process_frame
	for ag in _agents:
		ag.anim.play(&"idle")

func _dress(agent: NpcAgent, tint: Color) -> void:
	var puppet := NpcExamplePuppet.build(tint)
	agent.add_child(puppet)
	var profile := NpcRigProfile.new()
	var ad := NpcAnimPlayerAdapter.new()
	ad.anim_set = _anim_set
	ad.rig_profile = profile
	ad.bind(agent, puppet)
	ad.tag_changed.connect(func(from_tag: StringName, to_tag: StringName, blend: float) -> void:
		print("[workshop] ", agent.agent_id, " crossfade ", from_tag, " -> ", to_tag, " (", blend, " s)")
		if _shot_cross_at < 0.0 and from_tag != &"" and to_tag != &"idle":
			_cross_agent = agent
			_shot_cross_at = world.now() + 0.15)
	agent.anim = ad
	var ik := NpcTwoBoneIkAdapter.new()
	ik.bind(agent, NpcExamplePuppet.skeleton_of(puppet), profile)
	agent.ik = ik
	_agents.append(agent)

func _process(_delta: float) -> void:
	var day := fposmod(world.now() / 120.0, 1.0) # a 2-minute day
	world.inputs.set_value(&"daylight", snappedf(0.5 + 0.5 * sin(day * TAU), 0.05))
	if _focus != null:
		# close-up on the agent being captured: front-right of it, at chest height
		cam.global_position = _focus.global_position + _focus.global_basis * Vector3(1.5, 1.4, -1.5)
		cam.look_at(_focus.global_position + Vector3(0, 1.15, 0))
	else:
		cam.global_position = raft.global_position + Vector3(0, 6.5, 8.5)
		cam.look_at(raft.global_position + Vector3(0, 0.8, 0))
	if _pending_file != "":
		_pending_wait -= 1
		if _pending_wait <= 0: # two frames after the camera moved, so the viewport texture shows it
			_save(_pending_file)
			_pending_file = ""
			_focus = null
		return
	if _shots_dir == "":
		return
	if not _shot_reach:
		for ag in _agents:
			if ag.ik != null and (ag.ik as NpcTwoBoneIkAdapter).weight_of(&"hand_r") > 0.95:
				_focus = ag
				_pending_file = "reach.png"
				_pending_wait = 3
				print("[workshop] reach: ", ag.agent_id, " hand_r weight ", (ag.ik as NpcTwoBoneIkAdapter).weight_of(&"hand_r"))
				_shot_reach = true
				break
	if not _shot_cross and _shot_cross_at >= 0.0 and world.now() >= _shot_cross_at:
		_focus = _cross_agent
		_pending_file = "crossfade.png"
		_pending_wait = 3
		_shot_cross = true
	if (_shot_reach and _shot_cross and _pending_file == "" and _focus == null) or world.now() > 150.0:
		print("[workshop] shots done reach=%s crossfade=%s" % [_shot_reach, _shot_cross])
		get_tree().quit()

func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(file))
