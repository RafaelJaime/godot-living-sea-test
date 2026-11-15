extends Node3D
## Rotating lighthouse beam: an additive prism that sweeps around at night (and in storms), attached to a lamp by islands.gd.
## Beam visibility follows WorldState (night / storm), so daytime lighthouses just look like towers.

@export var length := 700.0
@export var rpm := 9.0
var _beam: MeshInstance3D
var _mat: ShaderMaterial

## Soft volumetric cone: additive, brightest on the axis (fresnel-like falloff toward the silhouette), fading with distance from the lamp,
## depth-tested so sails and hulls in front of it hide it (it never paints over them).
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform float intensity = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.66);
varying float along;
void vertex() { along = UV.x; }
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.2);
	float fade = pow(1.0 - along, 1.8) * smoothstep(0.0, 0.02, along);
	ALBEDO = tint * intensity * core * fade * 0.55;
	ALPHA = 1.0;
}
"""

func _ready() -> void:
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	# Open cone along -Z: 20 sides x 24 rings, radius 0.8 m at the lamp growing to ~20 m at the far end.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 20
	var rings := 24
	var rad_far := 20.0
	for r in rings:
		var t0 := float(r) / rings
		var t1 := float(r + 1) / rings
		var z0 := -length * t0 * t0 # denser rings near the lamp
		var z1 := -length * t1 * t1
		var r0 := 0.8 + (rad_far - 0.8) * t0 * t0
		var r1 := 0.8 + (rad_far - 0.8) * t1 * t1
		for k in sides:
			var a0 := float(k) / sides * TAU
			var a1 := float(k + 1) / sides * TAU
			var n0 := Vector3(cos(a0), sin(a0), 0.0)
			var n1 := Vector3(cos(a1), sin(a1), 0.0)
			var v := [
				[Vector3(n0.x * r0, n0.y * r0, z0), n0, t0 * t0], [Vector3(n1.x * r0, n1.y * r0, z0), n1, t0 * t0],
				[Vector3(n0.x * r1, n0.y * r1, z1), n0, t1 * t1], [Vector3(n1.x * r1, n1.y * r1, z1), n1, t1 * t1],
			]
			for idx in [0, 1, 2, 1, 3, 2]:
				st.set_normal(v[idx][1])
				st.set_uv(Vector2(v[idx][2], 0.0))
				st.add_vertex(v[idx][0])
	_beam = MeshInstance3D.new()
	_beam.mesh = st.commit()
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = length
	add_child(_beam)
	rotation.y = randf() * TAU
	add_to_group("lighthouse_beam")

func _process(delta: float) -> void:
	var w := WorldState
	var on := maxf(w.night, w.storm * 0.6 * (1.0 - w.daylight * 0.5))
	_beam.visible = on > 0.05
	_mat.set_shader_parameter("intensity", clampf(on, 0.0, 1.0))
	rotation.y += delta * TAU * rpm / 60.0

func is_on() -> bool:
	return _beam != null and _beam.visible

## Beam heading in degrees (for the angular-rate check: rpm * 6 degrees per second).
func beam_yaw_deg() -> float:
	return fposmod(rad_to_deg(global_rotation.y), 360.0)
