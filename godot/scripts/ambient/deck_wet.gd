extends Node
## Wet deck: reads `WorldState.deck_wetness` and darkens / glosses the ship's deck material (`ship_pinnace_deck`) with a wet clear coat.
## Materials are duplicated per surface once at start. Created by ambient_director.gd. Test aid: `--deck-wet=<0..1>` forces the value.

var _mats: Array[StandardMaterial3D] = []
var _dry: Array[Dictionary] = []
var _acc := 0.0
var _last := -1.0

func _ready() -> void:
	# Wait for the ship model to be instanced (ship_loader builds it after _ready).
	for _i in 10:
		await get_tree().process_frame
	var ship := get_tree().root.get_node_or_null("Main/Ship")
	if ship == null:
		return
	for mi in ship.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as StandardMaterial3D
			if src != null and src.resource_name.to_lower().contains("deck"):
				var dup := src.duplicate() as StandardMaterial3D
				m.set_surface_override_material(i, dup)
				_mats.append(dup)
				_dry.append({"rough": dup.roughness, "albedo": dup.albedo_color})
	print("[deck_wet] ", _mats.size(), " deck material surface(s)")

func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.25 or _mats.is_empty():
		return
	_acc = 0.0
	var w: float = WorldState.deck_wetness
	if absf(w - _last) < 0.004:
		return
	_last = w
	for i in _mats.size():
		var m := _mats[i]
		var d: Dictionary = _dry[i]
		m.roughness = lerpf(float(d["rough"]), 0.28, w)
		m.albedo_color = (d["albedo"] as Color) * lerpf(1.0, 0.72, w)
		m.clearcoat_enabled = w > 0.02
		m.clearcoat = 0.85 * w
		m.clearcoat_roughness = 0.12
