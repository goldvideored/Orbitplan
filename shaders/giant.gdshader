// Газовый гигант: полосы облаков + освещение солнцем (видно фазы, как у Луны).
shader_type spatial;
render_mode unshaded;

global uniform vec3 sun_dir;

varying vec3 n_obj;
varying vec3 n_w;

void vertex() {
	n_obj = NORMAL;
	n_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float lat = n_obj.y;
	float wave = sin(atan(n_obj.z, n_obj.x) * 3.0 + lat * 9.0) * 0.08;
	float b1 = sin((lat + wave) * 22.0) * 0.5 + 0.5;
	float b2 = sin((lat - wave) * 57.0 + 1.3) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.80, 0.50, 0.28), vec3(0.96, 0.82, 0.62), b1 * 0.65) * (0.85 + 0.15 * b2);
	float l = max(dot(normalize(n_w), sun_dir), 0.0);
	ALBEDO = c * (l * 0.97 + 0.015);
}
