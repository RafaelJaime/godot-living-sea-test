class_name CrewAudio
extends Node
## Crew sounds through the optional `Audio` autoload (C2.6): footsteps on the surface the deck has (wet when `wet` is high), the violin while the
## animation tag is `violin_play`, and a hammering loop while a repair tag plays. No hard dependency: without the `Audio` singleton (or with
## `audio = null`) every call is skipped. One watcher per agent; `step_agent` and `watch` are public so tests can drive them without a running ship.

const STEP_PERIOD_S := 0.65 ## two steps per 1.33 s walk cycle
const WALK_TAGS: Array[StringName] = [&"walk", &"stairs", &"rope"]
const HAMMER_TAGS: Array[StringName] = [&"hammer_repair", &"repair"]
const VIOLIN_TAG := &"violin_play"
const WET_THRESHOLD := 0.4

var audio: Object ## the Audio autoload by default
var wet := 0.0 ## 0..1 deck wetness, fed by CrewNpc from the blackboard

var _phase: Dictionary = {} # agent node -> step accumulator
var _loops: Dictionary = {} # agent node -> {tag kind: player}

func _ready() -> void:
	if audio == null:
		audio = get_node_or_null("/root/Audio")

## Follow the tags of one agent's animation adapter (anything with a `tag_changed(from, to, blend)` signal).
func watch(_id: StringName, agent: Node3D, anim: Object) -> void:
	if anim == null or not anim.has_signal("tag_changed"):
		return
	anim.connect("tag_changed", func(_from: StringName, to_tag: StringName, _blend: float) -> void: _on_tag(agent, to_tag))

func _on_tag(agent: Node3D, tag: StringName) -> void:
	_set_loop(agent, &"violin", &"violin", tag == VIOLIN_TAG)
	_set_loop(agent, &"hammer", &"hammer_loop", HAMMER_TAGS.has(tag))

func _set_loop(agent: Node3D, key: StringName, sound: StringName, on: bool) -> void:
	if audio == null:
		return
	var mine: Dictionary = _loops.get(agent, {})
	if on and not mine.has(key):
		if audio.has_method("loop_at"):
			var p: Variant = audio.call("loop_at", sound, agent)
			mine[key] = p if p != null else true
	elif not on and mine.has(key):
		var p: Variant = mine[key]
		mine.erase(key)
		if audio.has_method("stop"):
			audio.call("stop", p if p is Object else null)
	_loops[agent] = mine

## Footstep cadence while the agent walks (phase `move` and a locomotion tag).
func step_agent(agent: Node3D, tag: StringName, phase: StringName, delta: float) -> void:
	if audio == null or phase != &"move" or not WALK_TAGS.has(tag):
		_phase[agent] = 0.0
		return
	var acc: float = float(_phase.get(agent, 0.0)) + delta
	if acc >= STEP_PERIOD_S:
		acc -= STEP_PERIOD_S
		if audio.has_method("footstep"):
			audio.call("footstep", agent, &"wet" if wet >= WET_THRESHOLD else &"wood")
	_phase[agent] = acc
