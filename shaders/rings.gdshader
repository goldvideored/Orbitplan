// Кольца гиганта: плоский квадрат, лишнее отбрасывается. Пиксельные полосы.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

global uniform vec3 sun_dir;
global uniform float sun_level;

uniform float inner = 0.58;   // внутренний радиус в долях внешнего

float h1(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 1.0 || r < inner) {
		discard;
	}
	float q = floor(r * 140.0);
	float dens = h1(q) * 0.6 + 0.4;
	if (h1(floor(r * 22.0) + 3.0) > 0.8) {
		dens *= 0.25;   // щели между кольцами
	}
	vec3 c = mix(vec3(0.7, 0.6, 0.5), vec3(0.9, 0.85, 0.75), h1(q + 7.0));
	ALBEDO = c * (0.75 * sun_level + 0.05);
	ALPHA = dens * 0.8;
}
