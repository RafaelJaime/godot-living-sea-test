extends Node3D
## Rotating lighthouse beam: an additive prism that sweeps around at night (and in storms), attached to a lamp by islands.gd.
## Beam visibility follows WorldState (night / storm), so daytime lighthouses just look like towers.

@export var length := 700.0
@export var rpm := 9.0
var _beam: MeshInstance3D
var _mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_fog = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two crossing quads (vertical + horizontal fan) so the beam reads from any angle; alpha fades to the far end.
	for ax in [Vector3.UP, Vector3.RIGHT]:
		var a0: Vector3 = ax * 0.8
		var a1: Vector3 = ax * 14.0
		var near := Color(1.0, 0.92, 0.65, 0.3)
		var far := Color(1.0, 0.92, 0.65, 0.0)
		var pts := [[-a0, near, 0.0], [a0, near, 0.0], [-a1, far, length], [a1, far, length]]
		var vs: Array = []
		for q in pts:
			vs.append([q[0] + Vector3(0, 0, -q[2]), q[1]])
		for idx in [0, 1, 2, 1, 3, 2]:
			st.set_color(vs[idx][1])
			st.add_vertex(vs[idx][0])
	_beam = MeshInstance3D.new()
	_beam.mesh = st.commit()
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = length
	add_child(_beam)
	rotation.y = randf() * TAU

func _process(delta: float) -> void:
	var w := WorldState
	var on := maxf(w.night, w.storm * 0.6 * (1.0 - w.daylight * 0.5))
	_beam.visible = on > 0.05
	_mat.albedo_color = Color(1, 1, 1, clampf(on, 0.0, 1.0))
	rotation.y += delta * TAU * rpm / 60.0
