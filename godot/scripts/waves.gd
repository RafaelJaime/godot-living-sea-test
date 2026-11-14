extends Node
## Single source of truth for the ocean waves (Gerstner sum).
## The same maths runs on the GPU (ocean.gdshader) and on the CPU (height_at / displacement_at).
## Coordinates passed to the CPU functions are LOCAL (post world-rebase) coordinates; the
## accumulated rebase shift lives in offset_x / offset_z (doubles) and is folded into the
## per-wave phase so nothing ever loses precision, even after hours of sailing.

const G := 9.81
const WAVE_COUNT := 6

## dir_deg: travel direction in the XZ plane (0 = +X, 90 = +Z). length: wavelength (m).
## steep: Gerstner steepness Q (sum should stay < 1 to avoid loops).
var wave_defs: Array[Dictionary] = [
	{"dir_deg": 200.0, "length": 78.0, "steep": 0.085},
	{"dir_deg": 232.0, "length": 46.0, "steep": 0.075},
	{"dir_deg": 168.0, "length": 29.0, "steep": 0.065},
	{"dir_deg": 255.0, "length": 17.0, "steep": 0.055},
	{"dir_deg": 120.0, "length": 9.5, "steep": 0.045},
	{"dir_deg": 215.0, "length": 5.2, "steep": 0.035},
]
## Global multiplier on all steepnesses (sea state).
var sea_state := 1.0:
	set(v):
		sea_state = v
		_rebuild()

var time := 0.0
var offset_x := 0.0 ## accumulated world shift (doubles)
var offset_z := 0.0

var _dirs := PackedVector2Array()
var _k := PackedFloat32Array()
var _q := PackedFloat32Array()
var _omega := PackedFloat64Array()
var _phase := PackedFloat32Array()
var _vec4 := PackedVector4Array()

func _ready() -> void:
	process_priority = -100
	_rebuild()
	_update_phases()

func _rebuild() -> void:
	_dirs.resize(WAVE_COUNT); _k.resize(WAVE_COUNT); _q.resize(WAVE_COUNT)
	_omega.resize(WAVE_COUNT); _phase.resize(WAVE_COUNT); _vec4.resize(WAVE_COUNT)
	for i in WAVE_COUNT:
		var w := wave_defs[i]
		var a := deg_to_rad(float(w["dir_deg"]))
		_dirs[i] = Vector2(cos(a), sin(a))
		_k[i] = TAU / float(w["length"])
		_q[i] = float(w["steep"]) * sea_state
		_omega[i] = sqrt(G * _k[i])
		_vec4[i] = Vector4(_dirs[i].x, _dirs[i].y, _k[i], _q[i])

func _process(delta: float) -> void:
	time += delta
	_update_phases()

func _update_phases() -> void:
	for i in WAVE_COUNT:
		var d := _dirs[i]
		var p := _omega[i] * time - _k[i] * (d.x * offset_x + d.y * offset_z)
		_phase[i] = fposmod(p, TAU)

## Called when the world origin is shifted: `shift` is how far the world content was moved back.
func add_world_shift(shift_x: float, shift_z: float) -> void:
	offset_x += shift_x
	offset_z += shift_z
	_update_phases()

func push_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("wave_data", _vec4)
	mat.set_shader_parameter("wave_phase", _phase)
	mat.set_shader_parameter("tile_offset", Vector2(fposmod(offset_x, 1000.0), fposmod(offset_z, 1000.0)))
	mat.set_shader_parameter("detail_scroll", Vector2(fposmod(time * 0.011, 1.0), fposmod(time * 0.007, 1.0)))

## Gerstner displacement of the grid point whose rest position is (x, z).
func displacement_at(x: float, z: float) -> Vector3:
	var d := Vector3.ZERO
	for i in WAVE_COUNT:
		var dir := _dirs[i]
		var k := _k[i]
		var f := k * (dir.x * x + dir.y * z) - _phase[i]
		var a := _q[i] / k
		var c := cos(f)
		d.x += dir.x * a * c
		d.z += dir.y * a * c
		d.y += a * sin(f)
	return d

## Surface height at world column (x, z): inverts the horizontal displacement by fixed-point iteration.
func height_at(x: float, z: float) -> float:
	var px := x
	var pz := z
	for _i in 3:
		var d := displacement_at(px, pz)
		px = x - d.x
		pz = z - d.z
	return displacement_at(px, pz).y
