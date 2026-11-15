extends Node3D
## Example scene root: gives each agent a stick-figure puppet with the default animation and IK adapters, drives the example day/night through the
## blackboard and lets the NpcWorld run. Headless:
##   godot --headless --fixed-fps 60 --path <project> res://addons/npc_life/examples/workshop/workshop.tscn -- --npc-seed=1 --npc-minutes=3
## Captures (needs a window): add `--workshop-shots=<dir>` (and `--workshop-want=a,b`, `--workshop-demo-social` for the social shots): saves reach.png (hand IK on the workbench), crossfade.png (a clip change mid-blend),
## conversation.png (two agents facing each other) and audience.png (listeners in a ring around the fiddler), then quits.

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
var _social: NpcSocialDirector
var _focus_pos := Vector3.INF # world position focus (conversation, audience); offset is in raft-local axes
var _focus_off := Vector3.ZERO
var _conv_at := -1.0
var _conv_pair: Array = []
var _shot_conv := false
var _shot_aud := false

func _ready() -> void:
	cam.fov = 50.0
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
		elif a == "--workshop-demo-social":
			(world.get_node("Source") as Node).set("quiet", true) # demo mode: no chores, so the social scenes happen early
			(world.get_node("Social") as NpcSocialDirector).chat_chance = 0.5
		elif a == "--workshop-demo-chat": # idle agents that only talk: no chores, no fiddler, no gatherings
			(world.get_node("Source") as Node).set("quiet", true)
			(world.get_node("Source") as Node).set("no_play", true)
			var sd := world.get_node("Social") as NpcSocialDirector
			sd.gatherings_enabled = false
			sd.audiences_enabled = false
			sd.chat_chance = 0.6
		elif a.begins_with("--workshop-want="): # which shots to take (default all): reach, crossfade, conversation, audience
			var want := a.get_slice("=", 1).split(",")
			_shot_reach = not want.has("reach")
			_shot_cross = not want.has("crossfade")
			_shot_conv = not want.has("conversation")
			_shot_aud = not want.has("audience")
	var tints := {&"Ana": Color(0.85, 0.45, 0.35), &"Bruno": Color(0.35, 0.6, 0.85), &"Cleo": Color(0.5, 0.8, 0.45)}
	for n in raft.get_children():
		if n is NpcAgent:
			_dress(n as NpcAgent, tints.get((n as NpcAgent).def.agent_id, Color.WHITE))
	_social = world.get_node("Social") as NpcSocialDirector
	_social.conversation_started.connect(func(a: StringName, b: StringName) -> void:
		print("[workshop] conversation ", a, " <-> ", b)
		if _conv_at < 0.0:
			_conv_at = world.now() + 3.0
			_conv_pair = [world.get_agent(a), world.get_agent(b)])
	_social.gathering_started.connect(func(spot: StringName, agents: Array) -> void: print("[workshop] gathering at ", spot, ": ", agents))
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
	if _focus_pos != Vector3.INF:
		cam.global_position = _focus_pos + raft.global_basis * _focus_off
		cam.look_at(_focus_pos + Vector3(0, 1.0, 0))
	elif _focus != null:
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
			_focus_pos = Vector3.INF
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
	if not _shot_conv and _conv_at >= 0.0 and world.now() >= _conv_at and _pending_file == "":
		var a: NpcAgent = _conv_pair[0]
		var b: NpcAgent = _conv_pair[1]
		_focus_pos = (a.global_position + b.global_position) * 0.5
		_focus_off = Vector3(0.5, 1.3, 2.1)
		print("[workshop] conversation shot: pair distance %.2f m, focus %s" % [a.global_position.distance_to(b.global_position), _focus_pos])
		_pending_file = "conversation.png"
		_pending_wait = 3
		_shot_conv = true
	if not _shot_aud and _pending_file == "":
		var listeners := 0
		for sp in _social.audience_spots(&"fiddle_seat"):
			if not sp.is_free():
				listeners += 1
		if listeners >= 2:
			var seat := world.find_station(&"fiddle_seat")
			_focus_pos = seat.global_position
			_focus_off = Vector3(0.0, 2.3, 3.2)
			_pending_file = "audience.png"
			_pending_wait = 3
			_shot_aud = true
			print("[workshop] audience: ", listeners, " listeners around the fiddler")
	var done := _shot_reach and _shot_cross and _shot_conv and _shot_aud and _pending_file == "" and _focus == null and _focus_pos == Vector3.INF
	if done or world.now() > 400.0:
		print("[workshop] shots done reach=%s crossfade=%s conversation=%s audience=%s" % [_shot_reach, _shot_cross, _shot_conv, _shot_aud])
		get_tree().quit()

func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(file))
