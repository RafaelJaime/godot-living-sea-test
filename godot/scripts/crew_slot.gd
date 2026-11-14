extends Marker3D
## One crew member. The marker is positioned from NORMALIZED ship coordinates once the ship is
## normalized, so it keeps making sense when the final ship GLB replaces the placeholder.
## Tweak norm_u / norm_v / facing_deg in the editor.

@export var character_name := "Papi_Fuego"
@export var final_path := "res://assets/characters/papi_fuego.glb"
@export var placeholder_path := "res://assets/placeholder/Papi_Fuego.glb"
@export var target_height := 1.85
## Height used for the placeholder only (0 = same as target_height); lets seated/odd placeholders look sane.
@export var placeholder_target_height := 0.0
## 0 = stern, 1 = bow (fraction of ship length).
@export_range(0.0, 1.0) var norm_u := 0.5
## -1 = port rail, +1 = starboard rail (fraction of half beam).
@export_range(-1.0, 1.0) var norm_v := 0.0
## Fallback deck height above the waterline, as a fraction of ship length.
@export var deck_height_frac := 0.12
## Snap to the deck mesh with a downward raycast (disabled for seated poses).
@export var snap_to_deck := true
## Raycast hits further than this (m) from the fallback deck height are ignored (rigging, wheel...).
@export var snap_tolerance := 1.2
## Seated on a procedural barrel of this height (0 = none); the barrel is built under the character.
@export var barrel_height := 0.0
## Vertical offset applied only to the placeholder (e.g. seated pose with feet origin).
@export var placeholder_y_offset := 0.0
## Facing in the ship frame: 0 = bow, +90 = port, -90 = starboard, 180 = stern.
@export var facing_deg := 0.0
## Yaw (deg) that turns the model's native front to the ship's bow direction (-Z).
@export var final_model_yaw_deg := -90.0
@export var placeholder_model_yaw_deg := 90.0
@export var ship_loader_path := NodePath("../../Model")

var visual: Node3D
var _anim_player: AnimationPlayer
var _sway_t := randf() * 10.0
var _is_placeholder := false
var position_x_hint := 0.0
var position_z_hint := 0.0

func setup(ship_length: float, ship_beam: float, snap_y_func: Callable) -> void:
	var path := final_path if ModelUtil.file_present(final_path) else placeholder_path
	_is_placeholder = path == placeholder_path
	var inst := ModelUtil.load_glb(path)
	if inst == null and path == final_path:
		path = placeholder_path
		_is_placeholder = true
		inst = ModelUtil.load_glb(path)
	if inst == null:
		push_warning("No model for " + character_name)
		return
	var x := norm_v * ship_beam * 0.5
	var z := lerpf(ship_length * 0.5, -ship_length * 0.5, norm_u)
	var y := deck_height_frac * ship_length
	position_x_hint = x
	position_z_hint = z
	if snap_to_deck:
		var hit: Variant = snap_y_func.call(x, z, y)
		if hit != null and absf(float(hit) - y) <= snap_tolerance:
			y = float(hit)
	if barrel_height > 0.0:
		_make_barrels(y)
		y += barrel_height
	if _is_placeholder:
		y += placeholder_y_offset
	position = Vector3(x, y, z)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var raw := inst as Node3D
	var holder := Node3D.new()
	visual.add_child(holder)
	holder.add_child(raw)
	_fit(holder, placeholder_target_height if (_is_placeholder and placeholder_target_height > 0.0) else target_height)
	var yaw := deg_to_rad(facing_deg + (placeholder_model_yaw_deg if _is_placeholder else final_model_yaw_deg))
	visual.rotation.y = yaw
	_setup_animation(inst)
	print("[crew] ", character_name, " <- ", path, " at ", position)

## Scale so the character reaches target_height, feet at y=0 and centered on XZ.
func _fit(holder: Node3D, height: float) -> void:
	var box := ModelUtil.local_aabb(holder)
	var s := height / maxf(box.size.y, 0.001)
	var c := box.get_center()
	holder.scale = Vector3(s, s, s)
	holder.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)

func _setup_animation(root: Node) -> void:
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim_player = players[0] as AnimationPlayer
	var chosen := ""
	for a in _anim_player.get_animation_list():
		if a == "RESET":
			continue
		if "idle" in a.to_lower():
			chosen = a
			break
		if chosen == "":
			chosen = a
	if chosen == "":
		return
	var anim := _anim_player.get_animation(chosen)
	anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(chosen)
	_anim_player.seek(randf() * maxf(anim.length, 0.01), true)
	print("[crew] ", character_name, " playing animation '", chosen, "'")

func _process(delta: float) -> void:
	# Procedural breathing/sway only when the model has no animation of its own.
	if visual == null or _anim_player != null:
		return
	_sway_t += delta
	visual.rotation.z = sin(_sway_t * 0.9) * 0.012
	visual.scale = Vector3(1.0, 1.0 + sin(_sway_t * 1.6) * 0.006, 1.0)

## Two simple barrels (parented to the marker's parent so they do not inherit the seat offset).
func _make_barrels(deck_y: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.26, 0.13)
	mat.roughness = 0.9
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.15, 0.12, 0.1)
	for i in 2:
		var h := barrel_height if i == 0 else barrel_height * 0.9
		var b := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.34; m.bottom_radius = 0.34; m.height = h; m.radial_segments = 14
		b.mesh = m
		b.material_override = mat
		var r := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.36; rm.bottom_radius = 0.36; rm.height = 0.06; rm.radial_segments = 14
		r.mesh = rm
		r.material_override = band
		r.position.y = h * 0.25
		b.add_child(r)
		var r2 := r.duplicate() as MeshInstance3D
		r2.position.y = -h * 0.25
		b.add_child(r2)
		var off := Vector3(0.0, 0.0, 0.0) if i == 0 else Vector3(0.75, 0.0, 0.35)
		b.position = Vector3(position_x_hint, deck_y + h * 0.5, position_z_hint) + off
		get_parent().add_child(b)
