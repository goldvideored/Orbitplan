// Орбита луны в виде системы: лента её цвета с разрывом вокруг самой луны,
// чтобы полоса не протыкала шар насквозь.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 hole = vec3(0.0, 1e9, 0.0);   // где сейчас луна (мировые координаты)
uniform float hole_r = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (distance(wp, hole) < hole_r) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
}
