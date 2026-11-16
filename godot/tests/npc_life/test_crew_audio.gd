extends GutTest
## Spec ship-crew-job-sources / C2.6: crew sounds through the optional Audio API (footsteps, violin, hammer); nothing happens without it.

class FakeAudio extends Node:
	var calls: Array = []
	var players: Array = []
	func footstep(target: Variant, surface: StringName = &"wood", _opts: Dictionary = {}) -> Object:
		calls.append(["footstep", surface])
		return null
	func play_at(id: StringName, _target: Variant, _opts: Dictionary = {}) -> Object:
		calls.append(["play_at", id])
		return null
	func loop_at(id: StringName, _target: Variant, _opts: Dictionary = {}) -> Object:
		calls.append(["loop_at", id])
		var o := Node.new()
		players.append(o)
		return o
	func stop(_player: Object, _fade := 0.4) -> void:
		calls.append(["stop"])

class FakeAnim extends RefCounted:
	signal tag_changed(from_tag: StringName, to_tag: StringName, blend: float)

var audio: FakeAudio
var ca: CrewAudio
var agent: Node3D

func after_each() -> void:
	for p in audio.players:
		if is_instance_valid(p):
			p.free()

func before_each() -> void:
	audio = FakeAudio.new()
	add_child_autofree(audio)
	ca = CrewAudio.new()
	ca.audio = audio
	add_child_autofree(ca)
	agent = Node3D.new()
	add_child_autofree(agent)

func _names() -> Array:
	return audio.calls.map(func(c: Array) -> String: return "%s:%s" % [c[0], c[1] if c.size() > 1 else ""])

func test_violin_loop_follows_the_tag() -> void:
	var an := FakeAnim.new()
	ca.watch(&"don_omar", agent, an)
	an.tag_changed.emit(&"idle", &"violin_play", 0.3)
	assert_eq(_names(), ["loop_at:violin"])
	an.tag_changed.emit(&"violin_play", &"walk", 0.3)
	assert_eq(_names(), ["loop_at:violin", "stop:"])

func test_hammer_loop_for_repair_tags() -> void:
	var an := FakeAnim.new()
	ca.watch(&"papi_diagnostica", agent, an)
	an.tag_changed.emit(&"walk", &"hammer_repair", 0.3)
	assert_eq(_names(), ["loop_at:hammer_loop"])
	an.tag_changed.emit(&"hammer_repair", &"idle", 0.3)
	assert_eq(_names().back(), "stop:")

func test_footsteps_have_a_cadence_and_only_while_walking() -> void:
	ca.step_agent(agent, &"walk", &"move", 0.3)
	assert_eq(audio.calls.size(), 0, "not yet a step")
	ca.step_agent(agent, &"walk", &"move", 0.5)
	assert_eq(_names(), ["footstep:wood"], "one step after about 0.65 s")
	audio.calls.clear()
	ca.step_agent(agent, &"idle", &"work", 5.0)
	ca.step_agent(agent, &"walk", &"work", 5.0)
	assert_eq(audio.calls.size(), 0, "no steps while working or standing")

func test_wet_deck_changes_the_surface() -> void:
	ca.wet = 0.9
	ca.step_agent(agent, &"walk", &"move", 1.0)
	assert_eq(_names(), ["footstep:wet"])

func test_no_audio_api_is_harmless() -> void:
	var c2 := CrewAudio.new()
	add_child_autofree(c2)
	c2.audio = null
	var an := FakeAnim.new()
	c2.watch(&"don_omar", agent, an)
	an.tag_changed.emit(&"idle", &"violin_play", 0.3)
	c2.step_agent(agent, &"walk", &"move", 2.0)
	assert_true(true, "reached the end without an error")
