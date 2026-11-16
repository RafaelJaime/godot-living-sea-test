class_name CrewLanternSource
extends NpcJobSource
## Dusk and dawn lanterns (C2.1). `ShipLights.lighting_needed(ids)` posts one light job per lantern on its `lantern_<id>` station,
## `extinguish_suggested(ids)` one extinguish job. The job's effect moment toggles the lantern through `ShipLights.light/extinguish`
## and logs `[crew] lantern <id> lit|out by <agent id>`, so every change is attributable to a crew agent (`last_actor`).

var lights: Object ## ShipLights (autoload) by default; tests inject a fake with the same signals and methods
var last_actor: Dictionary = {} # lantern id -> agent id

func _init() -> void:
	source_id = &"lanterns"
	poll_hz = 0.5

func _ready() -> void:
	if lights == null:
		lights = get_node_or_null("/root/ShipLights")
	if lights == null:
		push_warning("[crew] no ShipLights: the lantern source stays idle")
		return
	lights.connect(&"lighting_needed", func(ids: Array) -> void: _post_all(ids, true))
	lights.connect(&"extinguish_suggested", func(ids: Array) -> void: _post_all(ids, false))

func _post_all(ids: Array, lit: bool) -> void:
	for id in ids:
		var j := NpcJob.new()
		j.id = StringName("lantern:%s" % id)
		j.kind = &"lantern"
		j.station_id = StringName("lantern_%s" % id)
		j.priority = 0.8
		j.ttl_s = 0.0
		j.payload = {"id": String(id), "lit": lit}
		var act := NpcActionDef.new()
		act.action_id = &"light_lantern" if lit else &"snuff_lantern"
		act.job_kinds = PackedStringArray(["lantern"])
		act.anim_tag = &"light"
		act.duration_range = Vector2(4.0, 6.0)
		act.effect_at = 0.6
		act.effect = &"light"
		j.action = act
		post_job(j)

func _on_job_effect(job: NpcJob, agent: Node, _effect: StringName) -> void:
	if lights == null or not job.payload.has("id"):
		return
	var id: String = job.payload["id"]
	var lit: bool = job.payload["lit"]
	if lit:
		lights.call("light", id)
	else:
		lights.call("extinguish", id)
	var who: StringName = (agent as NpcAgent).agent_id if agent is NpcAgent else &"?"
	last_actor[id] = who
	print("[crew] lantern %s %s by %s" % [id, "lit" if lit else "out", who])

func _on_job_finished(job: NpcJob, _agent: Node, result: StringName) -> void:
	if result == &"done":
		clear_job(job.id) # an aborted or preempted job stays on the board for another agent
