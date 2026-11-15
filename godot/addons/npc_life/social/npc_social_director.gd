class_name NpcSocialDirector
extends NpcJobSource
## Social behaviour as ordinary jobs on the board (joining is a normal utility pick, not a special path):
##  - gatherings: a station tagged `social` with N slots gets a multi-slot join offer `gather:<spot>`; a gathering starts when two members work at the
##    spot and ends after its duration or when fewer than two remain;
##  - conversations: an agent idling on an ambient job offers a chat (`chat:<initiator>:<n>`, one slot, short ttl) at a speaking-distance spot in front of
##    it; the partner is whoever picks the offer by score; both look at each other and alternate `talk` / `listen` tags, then both are released;
##  - audiences: a station tagged `performer` whose occupant is working gets a ring of listen spots (dynamic stations facing the performer) with a
##    `listen:<seat>:<k>` job each; the ring disappears when the performance ends.
## Every choice draws from the world's seeded `social` stream. Add it as a child of the NpcWorld.

signal gathering_started(spot: StringName, agents: Array)
signal gathering_ended(spot: StringName, reason: StringName)
signal conversation_started(initiator: StringName, partner: StringName)
signal conversation_ended(initiator: StringName, partner: StringName)

@export var gathering_duration := Vector2(25.0, 50.0)
@export var gather_cooldown_s := 20.0
@export var conversation_duration := Vector2(8.0, 18.0)
@export var speak_turn_s := Vector2(2.0, 4.0)
@export var chat_offer_ttl_s := 12.0
## Per agent, after a chat.
@export var chat_cooldown_s := 30.0
## Chance per second that an idling agent offers a chat.
@export var chat_chance := 0.05
@export var gatherings_enabled := true
@export var audiences_enabled := true
@export var speaking_distance := 1.1
@export var listen_spots := 3
@export var listen_radius := 1.6

var _world: NpcWorld
var _rng: NpcRng
var _gather: Dictionary = {} # spot id -> {started, end, cooldown_until, members}
var _offers: Dictionary = {} # offer id -> {initiator, spot, serial}
var _convs: Array[Dictionary] = []
var _chat_serial: Dictionary = {} # initiator -> n
var _chat_cooldown: Dictionary = {} # agent -> logical time
var _audiences: Dictionary = {} # seat station id -> {spots: Array[NpcStation], jobs: Array[StringName]}

func _init() -> void:
	poll_hz = 5.0

# ---- queries --------------------------------------------------------------------------------------------------------------------------------

func audience_spots(seat_id: StringName) -> Array[NpcStation]:
	var out: Array[NpcStation] = []
	if _audiences.has(seat_id):
		for s in _audiences[seat_id]["spots"]:
			out.append(s)
	return out

## Starts a chat offer for an agent that is idling on an ambient job; returns the offer job id (empty when it cannot offer).
func offer_chat(initiator_id: StringName) -> StringName:
	var a := _world.get_agent(initiator_id) as NpcAgent if _world else null
	if a == null or a.current_job() == null or not NpcAmbient.is_ambient(a.current_job()) or a.phase() != &"work":
		return &""
	for o in _offers.values():
		if o["initiator"] == initiator_id:
			return &""
	var n: int = _chat_serial.get(initiator_id, 0) + 1
	_chat_serial[initiator_id] = n
	a.current_job().kind = &"ambient_chat_offer"
	a.executor.ensure_remaining(chat_offer_ttl_s + 2.0)
	var parent := a.get_parent()
	var spot := NpcStation.new()
	spot.station_id = StringName("chat:%s:%d:spot" % [initiator_id, n])
	spot.kind = &"chat_spot"
	spot.position = a.position + a.transform.basis * Vector3(0, 0, -speaking_distance)
	spot.facing_deg = rad_to_deg(a.rotation.y) + 180.0 # the partner faces the initiator
	spot.approach_offset = Vector3.ZERO
	parent.add_child(spot)
	var j := NpcJob.new()
	j.id = StringName("chat:%s:%d" % [initiator_id, n])
	j.kind = &"chat"
	j.station_id = spot.station_id
	j.slots = 1
	j.ttl_s = chat_offer_ttl_s
	j.priority = 0.1
	j.payload = {"initiator": initiator_id}
	var act := NpcActionDef.new()
	act.action_id = &"chat"
	act.anim_tag = &"listen"
	act.duration_range = Vector2(1.0e6, 1.0e6) # the director ends the conversation
	j.action = act
	post_job(j, _world.now())
	_offers[j.id] = {"initiator": initiator_id, "spot": spot, "serial": n}
	_log("event=chat_offer initiator=%s job=%s" % [initiator_id, j.id])
	return j.id

# ---- polling --------------------------------------------------------------------------------------------------------------------------------

func _poll(world: Node, now: float) -> void:
	_world = world as NpcWorld
	_rng = _world.rng_for(&"social", &"director")
	if gatherings_enabled:
		_poll_gatherings(now)
	if audiences_enabled:
		_poll_audiences()
	_poll_offers_and_conversations(now)

func _poll_gatherings(now: float) -> void:
	for st in _world.get_stations():
		if not st.tags.has("social"):
			continue
		var id := st.station_id
		var g: Dictionary = _gather.get(id, {"started": false, "end": 0.0, "cooldown_until": 0.0, "members": []})
		_gather[id] = g
		var offer_id := StringName("gather:%s" % id)
		var offer := board.get_job(offer_id)
		if offer == null:
			if now >= float(g["cooldown_until"]):
				var j := NpcJob.new()
				j.id = offer_id
				j.kind = &"gather"
				j.station_id = id
				j.slots = st.capacity()
				j.ttl_s = 0.0
				j.priority = 0.2
				var act := NpcActionDef.new()
				act.action_id = &"gather"
				act.anim_tag = &"talk"
				act.duration_range = Vector2(1.0e6, 1.0e6)
				j.action = act
				post_job(j, now)
				g["started"] = false
			continue
		var members: Array[StringName] = []
		for aid in offer.claimed_by:
			var a := _world.get_agent(aid) as NpcAgent
			if a != null and a.current_job_id() == offer_id and a.phase() == &"work":
				members.append(aid)
		g["members"] = members
		if not g["started"]:
			if members.size() >= 2:
				g["started"] = true
				g["end"] = now + _rng.randf_range(gathering_duration.x, gathering_duration.y)
				_log("event=gathering_started spot=%s members=%s" % [id, ",".join(PackedStringArray(members.map(func(m: StringName) -> String: return String(m))))])
				gathering_started.emit(id, members.duplicate())
		else:
			var reason: StringName = &""
			if members.size() < 2:
				reason = &"members"
			elif now >= float(g["end"]):
				reason = &"timer"
			if reason != &"":
				board.clear(offer_id) # members are released with the job
				g["started"] = false
				g["cooldown_until"] = now + gather_cooldown_s
				_log("event=gathering_ended spot=%s reason=%s" % [id, reason])
				gathering_ended.emit(id, reason)

func _poll_audiences() -> void:
	for st in _world.get_stations():
		if not st.tags.has("performer"):
			continue
		var occ := _world.get_agent(st.occupant(0)) as NpcAgent
		var performing := occ != null and occ.phase() == &"work" and occ.current_job() != null and occ.current_job().station_id == st.station_id
		var have := _audiences.has(st.station_id)
		if performing and not have:
			_open_audience(st)
		elif not performing and have:
			_close_audience(st.station_id)

func _open_audience(seat: NpcStation) -> void:
	var parent := seat.get_parent()
	var spots: Array[NpcStation] = []
	var jobs: Array[StringName] = []
	var offset := _rng.randf() * TAU
	for k in listen_spots:
		var ang := offset + TAU * float(k) / float(listen_spots)
		var spot := NpcStation.new()
		spot.station_id = StringName("listen:%s:%d:spot" % [seat.station_id, k])
		spot.kind = &"listen_spot"
		spot.position = seat.position + Vector3(cos(ang), 0, sin(ang)) * listen_radius
		var dir := seat.position - spot.position
		spot.facing_deg = rad_to_deg(atan2(-dir.x, -dir.z)) # -Z toward the performer
		spot.approach_offset = Vector3.ZERO
		spot.anim_tag = &"listen"
		parent.add_child(spot)
		var look := Marker3D.new()
		look.name = "look_at"
		look.position = dir + Vector3(0, 1.3, 0)
		spot.add_child(look)
		spot.ik_targets[&"look_at"] = NodePath("look_at")
		spots.append(spot)
		var j := NpcJob.new()
		j.id = StringName("listen:%s:%d" % [seat.station_id, k])
		j.kind = &"listen"
		j.station_id = spot.station_id
		j.priority = 0.3
		j.ttl_s = 0.0
		var act := NpcActionDef.new()
		act.action_id = &"listen"
		act.anim_tag = &"listen"
		act.duration_range = Vector2(20.0, 40.0)
		j.action = act
		post_job(j, _world.now())
		jobs.append(j.id)
	_audiences[seat.station_id] = {"spots": spots, "jobs": jobs}
	_log("event=audience_open seat=%s spots=%d" % [seat.station_id, listen_spots])

func _close_audience(seat_id: StringName) -> void:
	var au: Dictionary = _audiences[seat_id]
	for jid in au["jobs"]:
		board.clear(jid) # listeners are released with their jobs
	for s in au["spots"]:
		if is_instance_valid(s):
			s.queue_free()
	_audiences.erase(seat_id)
	_log("event=audience_closed seat=%s" % seat_id)

func _poll_offers_and_conversations(now: float) -> void:
	# offers: start a conversation when the partner works at the spot; drop offers whose initiator moved on
	for oid in _offers.keys():
		var o: Dictionary = _offers[oid]
		var job := board.get_job(oid)
		var ini := _world.get_agent(o["initiator"]) as NpcAgent
		var still_offering := ini != null and ini.current_job() != null and ini.current_job().kind == &"ambient_chat_offer"
		if job == null or not still_offering:
			if job != null:
				board.clear(oid)
			_free_offer(oid)
			continue
		if job.claimed_by.size() == 1 and not o.get("conv", false):
			var partner := _world.get_agent(job.claimed_by[0]) as NpcAgent
			if partner != null and partner.current_job_id() == oid and partner.phase() == &"work":
				_start_conversation(oid, ini, partner, now)
	# running conversations
	for c in _convs.duplicate():
		var ini := _world.get_agent(c["a"]) as NpcAgent
		var par := _world.get_agent(c["b"]) as NpcAgent
		var alive: bool = ini != null and par != null and ini.current_job() != null and ini.current_job().kind == &"ambient_chat_offer" and par.current_job_id() == c["offer"]
		if not alive:
			_end_conversation(c, &"aborted")
		elif now >= float(c["end"]):
			_end_conversation(c, &"done")
		elif now >= float(c["turn"]):
			c["speaker"] = c["b"] if c["speaker"] == c["a"] else c["a"]
			c["turn"] = now + _rng.randf_range(speak_turn_s.x, speak_turn_s.y)
			_play_turn(c, ini, par)
	# autonomous offers by idling agents (per-second chance, agents in sorted order)
	if chat_chance > 0.0:
		for id in _world.agent_ids():
			var a := _world.get_agent(id) as NpcAgent
			if a.current_job() == null or not NpcAmbient.is_ambient(a.current_job()) or a.current_job().kind == &"ambient_chat_offer" or a.phase() != &"work":
				continue
			if now < float(_chat_cooldown.get(id, 0.0)):
				continue
			if _rng.randf() < chat_chance / poll_hz:
				offer_chat(id)

func _start_conversation(offer_id: StringName, ini: NpcAgent, par: NpcAgent, now: float) -> void:
	var o: Dictionary = _offers[offer_id]
	board.get_job(offer_id).ttl_s = 0.0 # a claimed offer no longer expires: the director ends the conversation
	var c := {"offer": offer_id, "a": ini.agent_id, "b": par.agent_id, "end": now + _rng.randf_range(conversation_duration.x, conversation_duration.y), "turn": now + _rng.randf_range(speak_turn_s.x, speak_turn_s.y), "speaker": ini.agent_id}
	_convs.append(c)
	ini.executor.ensure_remaining(float(c["end"]) - now + 2.0) # the initiator stays for the whole conversation
	o["conv"] = true
	if ini.ik:
		ini.ik.set_look_at(par.look_anchor())
	if par.ik:
		par.ik.set_look_at(ini.look_anchor())
	_play_turn(c, ini, par)
	_log("event=conversation_started a=%s b=%s offer=%s" % [ini.agent_id, par.agent_id, offer_id])
	conversation_started.emit(ini.agent_id, par.agent_id)

func _play_turn(c: Dictionary, ini: NpcAgent, par: NpcAgent) -> void:
	var a_speaks: bool = c["speaker"] == c["a"]
	if ini.anim:
		ini.anim.play(&"talk" if a_speaks else &"listen")
	if par.anim:
		par.anim.play(&"listen" if a_speaks else &"talk")

func _end_conversation(c: Dictionary, result: StringName) -> void:
	_convs.erase(c)
	var ini := _world.get_agent(c["a"]) as NpcAgent
	var par := _world.get_agent(c["b"]) as NpcAgent
	for a in [ini, par]:
		if a != null and a.ik:
			a.ik.set_look_at(null)
	if par != null and par.current_job_id() == c["offer"]:
		par.complete_job(&"done")
	board.clear(c["offer"])
	if ini != null and ini.current_job() != null and ini.current_job().kind == &"ambient_chat_offer":
		ini.complete_job(&"done")
	_chat_cooldown[c["a"]] = _world.now() + chat_cooldown_s
	_chat_cooldown[c["b"]] = _world.now() + chat_cooldown_s
	_free_offer(c["offer"])
	_log("event=conversation_ended a=%s b=%s result=%s" % [c["a"], c["b"], result])
	conversation_ended.emit(c["a"], c["b"])

func _free_offer(oid: StringName) -> void:
	if not _offers.has(oid):
		return
	var spot: NpcStation = _offers[oid]["spot"]
	if is_instance_valid(spot):
		spot.queue_free()
	_offers.erase(oid)

func _log(msg: String) -> void:
	_world.decision_log.write_line("[social] T=%06d %s" % [_world.tick_count, msg])
