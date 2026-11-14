extends Node
## World-anchored wake: a 1024^2 foam field (float16) in a 320 m window that follows the ship in whole-texel steps,
## updated by a ping-pong pair of SubViewports (advect + decay + stamp, see wake_update.gdshader). Window origins are
## tracked in accumulated world coordinates, so a world rebase does not disturb it. The ocean shader samples it.

@export var ship_path := NodePath("../Ship")
@export var size := 320.0
var resolution := 1024 # from Quality.wake_resolution

var _ship: Node3D
var _vp: Array[SubViewport] = []
var _mat: Array[ShaderMaterial] = []
var _cur := 0
var _origin_w := Vector2.INF # window origin in world coordinates (doubles via floats in GDScript)
var _time := 0.0
var _accum := 0.0

func _ready() -> void:
	process_priority = 150
	resolution = Quality.wake_resolution
	_ship = get_node(ship_path)
	var sh := load("res://shaders/wake_update.gdshader") as Shader
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(resolution, resolution)
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(resolution, resolution)
		var m := ShaderMaterial.new()
		m.shader = sh
		rect.material = m
		vp.add_child(rect)
		add_child(vp)
		_vp.append(vp)
		_mat.append(m)

func _process(delta: float) -> void:
	if Waves.ocean == null or delta <= 0.0:
		return
	_time += delta
	if Quality.wake_updates_per_second > 0.0:
		_accum += delta
		if _accum < 1.0 / Quality.wake_updates_per_second:
			return
		delta = _accum
		_accum = 0.0
	var ship_l := Vector2(_ship.global_position.x, _ship.global_position.z)
	var ship_w := ship_l + Vector2(Waves.offset_x, Waves.offset_z)
	var texel := size / float(resolution)
	var new_origin := Vector2(snappedf(ship_w.x - size * 0.5, texel * 8.0), snappedf(ship_w.y - size * 0.5, texel * 8.0))
	if _origin_w.x == INF:
		_origin_w = new_origin
	var delta_uv := (new_origin - _origin_w) / size
	var prev_i := _cur
	var next_i := 1 - _cur
	var m := _mat[next_i]
	m.set_shader_parameter("prev", _vp[prev_i].get_texture())
	m.set_shader_parameter("delta_uv", delta_uv)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("dt", delta)
	m.set_shader_parameter("ship_uv", (ship_w - new_origin) / size)
	var fwd: Vector2 = _ship.get("forward") if _ship.get("forward") != null else Vector2(0, -1)
	m.set_shader_parameter("fwd", fwd)
	var spd: float = _ship.get("current_speed") if _ship.get("current_speed") != null else 6.0
	m.set_shader_parameter("speed", spd)
	var hl := 0.46 * 39.8
	var hb := 4.4
	m.set_shader_parameter("half_len", hl)
	m.set_shader_parameter("half_beam", hb)
	m.set_shader_parameter("seed_t", _time)
	_vp[next_i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_origin_w = new_origin
	_cur = next_i
	var origin_l := _origin_w - Vector2(Waves.offset_x, Waves.offset_z)
	Waves.ocean.set_wake(_vp[next_i].get_texture(), origin_l, size)
