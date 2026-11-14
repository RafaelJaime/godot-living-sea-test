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
@export var is_window := false      ## cabin window glow: no flame, a flat emissive quad + a soft inner light
@export var glass_size := 0.28
@export var ignite_time := 2.4
@export var fade_out_time := 1.2

signal lit_changed(lantern_id: String, lit: bool)

var lit := false
var _level := 0.0 ## 0..1 animated brightness
var _target := 0.0
var _light: OmniLight3D
var _glass: MeshInstance3D
var _flame: MeshInstance3D
var _mat: StandardMaterial3D
var _phase := randf() * 100.0

func _ready() -> void:
	add_to_group("ship_lantern")
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.2, 0.15, 0.08)
	_mat.emission_enabled = true
	_mat.emission = light_color
	_mat.emission_energy_multiplier = 0.0
	_mat.roughness = 0.4
	_glass = MeshInstance3D.new()
	if is_window:
		var q := QuadMesh.new()
		q.size = Vector2(glass_size, glass_size * 1.25)
		_glass.mesh = q
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var sm := SphereMesh.new()
		sm.radius = glass_size * 0.5
		sm.height = glass_size
		sm.radial_segments = 10
		sm.rings = 6
		_glass.mesh = sm
		_flame = MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = glass_size * 0.2
		fm.height = glass_size * 0.5
		fm.radial_segments = 8
		fm.rings = 4
		_flame.mesh = fm
		_flame.material_override = _mat
		_flame.scale = Vector3.ZERO
		add_child(_flame)
	_glass.material_override = _mat
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = light_range
	_light.omni_attenuation = 1.6
	_light.light_energy = 0.0
	_light.shadow_enabled = casts_shadow
	_light.visible = false
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
	_light.visible = e > 0.01
	_light.light_energy = light_energy * e * flick
	_mat.emission_energy_multiplier = 3.0 * e * flick
	if _flame:
		var g := e * (0.7 + 0.3 * flick)
		_flame.scale = Vector3(g, g * 1.4, g)
