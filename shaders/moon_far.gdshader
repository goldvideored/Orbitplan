// Далёкая луна (в небе или на карте): серый шар, освещённый солнцем, 16 ступеней.
shader_type spatial;
render_mode unshaded;

global uniform vec3 sun_dir;

uniform vec4 albedo : source_color = vec4(0.55, 0.53, 0.58, 1.0);

varying vec3 n_w;

void vertex() {
	n_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float l = max(dot(normalize(n_w), sun_dir), 0.0);
	l = floor(l * 16.0 + 0.5) / 16.0;
	ALBEDO = albedo.rgb * max(l, 0.03);
}
