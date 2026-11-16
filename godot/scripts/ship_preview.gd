@tool
extends Node3D
## Editor-only rest-pose preview of the ship (no simulation, nothing runs in the game: the node frees itself at runtime).
## - Sails: the deployed `*_down` meshes are shown and the furled / duplicate ones are hidden, the same rule PinnaceRig applies at startup. The visibility
##   changes are applied when the scene enters the editor tree and reverted when it leaves, so they are never saved into ship.tscn.
## - Flags: two flat rectangles streaming aft from the stern staff and the main masthead (the cloth simulation of flag.gd is not run in the editor).
## - Lights: warm glow spheres at the two stern lanterns and glow panes on the cabin windows, taken from the constants of ship_lights_builder.gd.
## Everything the preview adds is created in code without an owner, so it is not saved either.
const LIGHTS_BUILDER := "res://scripts/ship_lights_builder.gd"
const FLAG_TEXTURE := "res://assets/ship/flag_ceuta.png"
const FLAGS := [
	{"tip": Vector3(0.06, 13.46, 19.1), "length": 3.7, "height": 2.3, "drop": 0.25},     # stern staff (flag.gd defaults)
	{"tip": Vector3(0.0, 29.0, 2.4), "length": 2.9, "height": 1.55, "drop": 0.4},        # main masthead (FlagMain exports)
]

var _hidden: Array[MeshInstance3D] = []
var _extras: Array[Node] = []

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_apply.call_deferred()

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	for mi in _hidden:
		if is_instance_valid(mi):
			mi.visible = true
	_hidden.clear()
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()

func _apply() -> void:
	if not is_inside_tree() or not _hidden.is_empty() or not _extras.is_empty():
		return
	var model := get_node_or_null("../Model")
	if model != null:
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		var names := {}
		for n in meshes:
			names[String(n.name).to_lower()] = true
		for n in meshes:
			var mi := n as MeshInstance3D
			var low := String(mi.name).to_lower()
			# furled variants and the rigging copies that have a deployed `_down` twin stay hidden (PinnaceRig does the same)
			if mi.visible and (low.ends_with("_top") or (not low.ends_with("_down") and names.has(low + "_down"))):
				mi.visible = false
				_hidden.append(mi)
	for f in FLAGS:
		_add_flag(f)
	_add_lights()
	print("[preview] rest pose: ", _hidden.size(), " furled meshes hidden, ", _extras.size(), " preview nodes added")

func _add(n: Node3D) -> void:
	add_child(n) # no owner: never saved
	_extras.append(n)

func _add_flag(f: Dictionary) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(f["length"], f["height"])
	var mi := MeshInstance3D.new()
	mi.name = "FlagPreview"
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.85, 0.2, 0.2)
	if ResourceLoader.exists(FLAG_TEXTURE):
		m.albedo_texture = load(FLAG_TEXTURE)
		m.albedo_color = Color.WHITE
	mi.material_override = m
	var tip: Vector3 = f["tip"]
	mi.position = tip + Vector3(0.07, -float(f["drop"]) - float(f["height"]) * 0.5, float(f["length"]) * 0.5)
	mi.rotation_degrees = Vector3(0, 90, 0) # the quad lies in the YZ plane, hoist at the staff, fly aft (+z)
	_add(mi)

func _add_lights() -> void:
	var consts := (load(LIGHTS_BUILDER) as GDScript).get_script_constant_map()
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.7, 0.3)
	for d in consts.get("LAMPS", []):
		var mi := MeshInstance3D.new()
		mi.name = "LampPreview"
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		mi.mesh = sm
		mi.material_override = glow
		mi.position = d["pos"]
		_add(mi)
	var rake := deg_to_rad(float(consts.get("WINDOW_RAKE_DEG", 17.9)))
	for w in consts.get("WINDOWS", []):
		var pane := MeshInstance3D.new()
		pane.name = "WindowPreview"
		var q := QuadMesh.new()
		q.size = w["size"]
		pane.mesh = q
		pane.material_override = glow
		pane.position = w["pos"]
		pane.rotation = Vector3(rake, 0, 0)
		_add(pane)
