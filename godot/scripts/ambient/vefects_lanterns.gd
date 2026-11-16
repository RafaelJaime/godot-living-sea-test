extends Node
## Adds the Vefects candle flame to every lit (non-window) ship lantern and removes it when the lantern goes out. Created by
## ambient_director.gd only when the pack is installed; the lantern anchors, glow and light are not touched.

const FLAME_SCALE := 3.0 # the pack's flame is a 5 cm candle; the ship's lantern cage is about 0.5 m

func _ready() -> void:
	if ShipLights.has_signal("lantern_changed"):
		ShipLights.lantern_changed.connect(_on_changed)
	for _i in 6:
		await get_tree().process_frame
	for l in get_tree().get_nodes_in_group("ship_lantern"):
		if l.lit:
			_attach(l)

func _on_changed(id: String, lit: bool) -> void:
	for l in get_tree().get_nodes_in_group("ship_lantern"):
		if l.id == id:
			if lit:
				_attach(l)
			else:
				_detach(l)

func _attach(l: Node) -> void:
	if l.is_window or l.has_node("VefectsFlame"):
		return
	var f := OptionalVfx.spawn(OptionalVfx.CANDLE_FLAME)
	if f == null:
		return
	f.name = "VefectsFlame"
	l.add_child(f)
	(f as Node3D).position = l.glow_offset + Vector3(0, -0.12, 0)
	(f as Node3D).scale = Vector3.ONE * FLAME_SCALE

func _detach(l: Node) -> void:
	var f := l.get_node_or_null("VefectsFlame")
	if f:
		f.queue_free()
