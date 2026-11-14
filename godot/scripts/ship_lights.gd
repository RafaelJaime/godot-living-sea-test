extends Node
## Autoload "ShipLights": registry and API for the ship's lanterns (see README "Integration API for NPCs").
## Lanterns are OFF by default; NPC behaviour (walking to the stand point, the ignition gesture) belongs to the crew code.
##   ShipLights.get_lanterns() -> [{id, position, interaction_point, facing_deg, lit}]
##   ShipLights.light(id) / extinguish(id) / is_lit(id)
##   signals: lighting_needed(ids)  at dusk (WorldState.daylight low), extinguish_suggested(ids) at dawn
## Test aid: --auto-light[=delay_s] lights every lantern (staggered) that long after lighting_needed.

signal lighting_needed(ids: Array)
signal extinguish_suggested(ids: Array)
signal lantern_changed(id: String, lit: bool)

const DUSK_DAYLIGHT := 0.30
const DAWN_DAYLIGHT := 0.50

var _announced_dusk := false
var _auto_delay := -1.0
var _auto_timer := -1.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--auto-light":
			_auto_delay = 3.0
		elif a.begins_with("--auto-light="):
			_auto_delay = float(a.get_slice("=", 1))

func _lanterns() -> Array[ShipLantern]:
	var out: Array[ShipLantern] = []
	for n in get_tree().get_nodes_in_group("ship_lantern"):
		out.append(n as ShipLantern)
	return out

func _find(id: String) -> ShipLantern:
	for l in _lanterns():
		if l.id == id:
			return l
	return null

func get_lanterns() -> Array:
	var out := []
	for l in _lanterns():
		out.append({"id": l.id, "position": l.world_position(), "interaction_point": l.stand_world(),
			"facing_deg": l.stand_facing_deg, "lit": l.lit, "is_window": l.is_window})
	return out

func is_lit(id: String) -> bool:
	var l := _find(id)
	return l != null and l.lit

func light(id: String) -> bool:
	var l := _find(id)
	if l == null:
		return false
	if not l.lit_changed.is_connected(_on_changed):
		l.lit_changed.connect(_on_changed)
	l.light_up()
	return true

func extinguish(id: String) -> bool:
	var l := _find(id)
	if l == null:
		return false
	if not l.lit_changed.is_connected(_on_changed):
		l.lit_changed.connect(_on_changed)
	l.extinguish()
	return true

func _on_changed(id: String, lit: bool) -> void:
	lantern_changed.emit(id, lit)

func _process(delta: float) -> void:
	var day: float = WorldState.daylight
	if day < DUSK_DAYLIGHT and not _announced_dusk:
		_announced_dusk = true
		var ids := []
		for l in _lanterns():
			if not l.lit:
				ids.append(l.id)
		if not ids.is_empty():
			lighting_needed.emit(ids)
		if _auto_delay >= 0.0:
			_auto_timer = _auto_delay
	elif day > DAWN_DAYLIGHT and _announced_dusk:
		_announced_dusk = false
		var ids2 := []
		for l in _lanterns():
			if l.lit:
				ids2.append(l.id)
		if not ids2.is_empty():
			extinguish_suggested.emit(ids2)
		if _auto_delay >= 0.0:
			for i in ids2:
				extinguish(i)
	if _auto_timer >= 0.0:
		_auto_timer -= delta
		if _auto_timer < 0.0:
			_auto_timer = -1.0
			var k := 0
			for l in _lanterns():
				if not l.lit:
					get_tree().create_timer(0.8 * float(k)).timeout.connect(light.bind(l.id))
					k += 1
