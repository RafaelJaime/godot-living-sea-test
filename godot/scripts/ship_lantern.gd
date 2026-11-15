class_name ShipLantern
extends Node3D
## One lantern / lamp / lit window on the ship. OFF by default; a crew member lights it through ShipLights.light(id).
## Ignition animation: the flame grows and the light fades in; flicker is cheap value noise.

@export var id := "lantern"
## Where an NPC must stand (ship-pivot space, on the deck) to tend this lantern, and the yaw (deg, 0 = bow, +90 = port) it faces it from.
@export var stand_local := Vector3.ZERO
@export var stand_facing_deg := 0.0
@export var light_color := Color(1.0, 0.72, 0.38)
@export var light_energy := 1.8
@export var light_range := 14.0
@export var casts_shadow := false
@export var light_offset := Vector3.ZERO ## OmniLight offset from this node (windows: the light sits outside, behind the glass line)
@export var is_window := false      ## cabin windows: no flame, additive glow panes laid over the real window glass + a soft light behind them
@export var glow_box := Vector3(0.50, 0.72, 0.60) ## lamp: additive shell (m) just outside the lantern's real dark glass panes
@export var glow_offset := Vector3(0.0, -0.08, 0.0) ## shell centre relative to the anchor (anchor = cage vertex centroid)
@export var halo_size := 1.3        ## lamp: soft billboard halo diameter (m)
@export var ignite_time := 2.4
@export var fade_out_time := 1.2

signal lit_changed(lantern_id: String, lit: bool)

var lit := false
var _level := 0.0 ## 0..1 animated brightness
var _target := 0.0
var _light: OmniLight3D
var _glow: MeshInstance3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _panes: Array[MeshInstance3D] = []
var _pane_defs: Array = [] ## {xform: Transform3D, size: Vector2} in this node's space, filled by add_pane() before add_child
var _mat: StandardMaterial3D
var _phase := randf() * 100.0

## Windows: one glow pane over a real window (xform relative to this node, size in metres).
func add_pane(xform: Transform3D, size: Vector2) -> void:
	_pane_defs.append({"xform": xform, "size": size})

func _ready() -> void:
	add_to_group("ship_lantern")
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD # additive overlay: invisible when black, no glb change
	_mat.albedo_color = Color.BLACK
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_fog = true
	if is_window:
		var wg := Gradient.new() # brighter in the middle, darker at the frame: reads as lit glass, not a flat quad
		wg.colors = PackedColorArray([Color(1, 1, 1), Color(0.35, 0.3, 0.28)])
		var wt := GradientTexture2D.new()
		wt.gradient = wg
		wt.fill = GradientTexture2D.FILL_RADIAL
		wt.fill_from = Vector2(0.5, 0.5)
		wt.fill_to = Vector2(1.0, 0.85)
		wt.width = 64
		wt.height = 64
		_mat.albedo_texture = wt
		for d in _pane_defs:
			var m := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = d["size"]
			m.mesh = q
			m.transform = d["xform"]
			m.material_override = _mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.visible = false
			add_child(m)
			_panes.append(m)
	else:
		_glow = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = glow_box
		_glow.mesh = bm
		_glow.position = glow_offset
		_glow.material_override = _mat
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow.visible = false
		add_child(_glow)
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_halo_mat.albedo_texture = gt
		_halo_mat.albedo_color = Color.BLACK
		_halo_mat.disable_fog = true
		_halo = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(halo_size, halo_size)
		_halo.mesh = qm
		_halo.position = glow_offset
		_halo.material_override = _halo_mat
		_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_halo.visible = false
		add_child(_halo)
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = light_range
	_light.omni_attenuation = 1.6
	_light.light_energy = 0.0
	_light.shadow_enabled = casts_shadow
	_light.visible = false
	_light.position = light_offset
	add_child(_light)

## World position of the lantern and of the spot where an NPC must stand.
func world_position() -> Vector3:
	return global_position

func stand_world() -> Vector3:
	return get_parent().global_transform * stand_local if get_parent() is Node3D else stand_local

func light_up() -> void:
	if lit and _target >= 1.0:
		return
	lit = true
	_target = 1.0
	lit_changed.emit(id, true)

func extinguish() -> void:
	if not lit:
		return
	lit = false
	_target = 0.0
	lit_changed.emit(id, false)

func _process(delta: float) -> void:
	var speed := 1.0 / (ignite_time if _target > _level else fade_out_time)
	_level = move_toward(_level, _target, speed * delta)
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	var flick := 1.0 + 0.10 * sin(t * 13.0) * sin(t * 5.3) + 0.06 * sin(t * 31.0 + 1.0)
	var e := smoothstep(0.0, 1.0, _level)
	var on := e > 0.01
	_light.visible = on
	_light.light_energy = light_energy * e * flick
	var k := (1.0 if is_window else 0.45) * e * flick
	_mat.albedo_color = Color(light_color.r * k, light_color.g * k * 0.95, light_color.b * k * 0.8, 1.0)
	for p in _panes:
		p.visible = on
	if _glow:
		_glow.visible = on
		_halo.visible = on
		var h := 0.28 * e * (0.85 + 0.15 * flick)
		_halo_mat.albedo_color = Color(light_color.r * h, light_color.g * h * 0.9, light_color.b * h * 0.7, 1.0)
