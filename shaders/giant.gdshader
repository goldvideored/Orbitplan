// Газовый гигант в пиксель-арте: полосы, вихри, штормовое пятно, фазы от солнца (16 ступеней).
shader_type spatial;
render_mode unshaded;

global uniform vec3 sun_dir;

const vec3 BANDS[5] = vec3[5](
	vec3(0.80, 0.52, 0.30), vec3(0.95, 0.80, 0.60), vec3(0.70, 0.42, 0.25),
	vec3(0.88, 0.66, 0.45), vec3(0.60, 0.36, 0.22)
);

varying vec3 n_obj;
varying vec3 n_w;

float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	n_obj = NORMAL;
	n_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(n_obj);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.z, n.x);
	// пиксельная сетка 192×96
	vec2 q = floor(vec2(lon / TAU * 192.0, lat / PI * 96.0));
	// полосы с завихрениями
	float wob = sin(q.x * 0.13 + q.y * 0.5) * 1.6 + sin(q.x * 0.31 - q.y * 0.2) * 0.8;
	int bi = int(mod(floor((q.y + wob) / 4.0), 5.0));
	vec3 c = BANDS[bi] * (0.92 + 0.08 * h2(q));
	// большое штормовое пятно
	vec2 spot = vec2((q.x - 40.0) / 9.0, (q.y + 14.0) / 4.5);
	float sd = dot(spot, spot);
	if (sd < 1.0) {
		c = mix(vec3(0.75, 0.3, 0.18), vec3(0.95, 0.55, 0.35), step(0.45, sd));
	}
	// освещение солнцем, тоже 16 ступеней
	float l = max(dot(normalize(n_w), sun_dir), 0.0);
	l = floor(l * 16.0 + 0.5) / 16.0;
	ALBEDO = c * max(l, 0.02);
}
