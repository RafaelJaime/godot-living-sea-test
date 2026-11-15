shader_type canvas_item;
render_mode blend_disabled;
// One step of the world-anchored wake field (ping-pong). R = foam 0..1, G = centre-line turbulence 0..1 (decay ~1/s),
// B = signed Kelvin ridge height in metres (clamped +-0.5, decay ~0.6/s).
uniform sampler2D prev : filter_linear, repeat_disable;
uniform vec2 delta_uv;     // (origin_now - origin_prev) / size
uniform float size;        // window size (m)
uniform float dt;
uniform vec2 ship_uv;      // ship position in the current window (0..1)
uniform vec2 fwd;          // ship forward, world (x, z)
uniform float speed;       // surge speed relative to the water (m/s)
uniform vec2 vdir = vec2(0.0, -1.0); // direction of travel through the water (differs from fwd by the leeway)
uniform float froude = 0.265;        // U / sqrt(g L); the stamps were tuned at U = 5 m/s (0.265)
uniform float heel = 0.0;            // -1..1, + = starboard side down (the leeward side stamps stronger and wider)
uniform float half_len;
uniform float half_beam;
uniform float decay = 0.26;     // 1/s
uniform float arm_slope = 0.354; // tan(19.5 deg): Kelvin arms
uniform float seed_t;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 pw = (UV - ship_uv) * size;               // metres relative to the ship
	vec2 right = vec2(-fwd.y, fwd.x);              // ship starboard (world x,z)
	float a = dot(pw, fwd);                        // along the ship (+ = ahead)
	float d = dot(pw, right);                      // across (+ = starboard)
	// Foam drifts outward from the ship's track: this turns the two stamped corner points into the Kelvin arms.
	float lat = sign(d) * arm_slope * speed * smoothstep(1.2, 3.0, abs(d)) * smoothstep(-2.0, 6.0, -a) * 0.8;
	vec2 vel = right * lat;
	vec2 suv = UV + delta_uv - vel * dt / size;
	vec4 pv = texture(prev, suv);
	float f = pv.r;
	float g = pv.g;
	float b = pv.b;
	// light diffusion
	float px = 1.0 / float(textureSize(prev, 0).x);
	float nb = 0.25 * (texture(prev, suv + vec2(px, 0.0)).r + texture(prev, suv - vec2(px, 0.0)).r + texture(prev, suv + vec2(0.0, px)).r + texture(prev, suv - vec2(0.0, px)).r);
	f = mix(f, nb, 1.0 - exp(-3.82 * dt)); // frame-rate independent (0.12 at the fixed 30 Hz step)
	f *= exp(-decay * dt * (1.0 + 2.0 * (1.0 - clamp(f * 2.0, 0.0, 1.0)))); // thin foam breaks up faster
	vec2 q = pw * 0.7 + vec2(seed_t * 0.4, 0.0);
	vec2 qi = floor(q); vec2 qf = fract(q); qf = qf * qf * (3.0 - 2.0 * qf);
	float n = mix(mix(hash(qi), hash(qi + vec2(1, 0)), qf.x), mix(hash(qi + vec2(0, 1)), hash(qi + vec2(1, 1)), qf.x), qf.y); // smooth value noise: strands, not confetti
	float sp = clamp(froude / 0.265, 0.0, 1.5);
	// stamps (ship frame): hull sides, bow wave, stern turbulence, arm origins just behind the quarters
	// heel: the side that goes down pushes more water (wider, stronger); the windward side lifts out
	float lee = clamp(heel * sign(d), -1.0, 1.0);          // + on the side that is down
	float hb = max(half_beam * (1.0 + 0.35 * lee), 0.1);
	float heel_gain = 1.0 + 0.5 * lee;
	// leeway: the turbulent wake trails along the actual track, not along the heading
	float a_t = dot(pw, vdir);
	float d_t = dot(pw, vec2(-vdir.y, vdir.x));
	float e = length(vec2(d / hb, a / max(half_len, 0.1)));
	float side = smoothstep(0.92, 1.0, e) * (1.0 - smoothstep(1.0, 1.28, e)) * sp * heel_gain * (0.25 + 0.75 * smoothstep(-0.3, 0.9, a / half_len));
	float bow = exp(-pow((a - half_len * 0.95) / 2.2, 2.0)) * exp(-pow(d / (hb * 0.9), 2.0)) * sp * sp;
	float stern = exp(-pow((a_t + half_len * 0.92) / 3.2, 2.0)) * exp(-pow(d_t / (half_beam * 0.5), 2.0)) * sp * 0.6;
	float arms = exp(-pow((a_t + half_len * 0.55) / 2.5, 2.0)) * (exp(-pow((abs(d_t) - half_beam * 0.95) / 0.9, 2.0))) * sp * 0.8;
	float stamp = (side * 0.9 + bow * 1.2 + stern * 1.0 + arms) * (0.35 + 0.9 * n * n);
	f = min(1.0, f + stamp * dt * 2.7);
	// G: turbulence along the track just behind the stern, narrower than the foam, dies in about a second
	float turb = exp(-pow(d_t / max(half_beam * 0.35, 0.1), 2.0)) * exp(-pow((a_t + half_len * 0.95) / 2.5, 2.0)) * sp;
	g = clamp(g * exp(-1.0 * dt) + turb * dt * 4.0, 0.0, 1.0);
	// B: alternating-sign ridges are stamped at the arm origins; the arm advection carries them outward as Kelvin crests
	b = clamp(b * exp(-0.6 * dt) + arms * sin(seed_t * 5.0) * dt * 12.0, -0.5, 0.5);
	COLOR = vec4(f, g, b, 1.0);
}
