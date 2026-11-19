// Атмосфера большой планеты: светящаяся дымка по краю диска (снаружи) и у горизонта (с поверхности).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 col : source_color = vec4(1.0, 0.85, 0.45, 0.6);

void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = col.rgb * pow(f, 2.2) * col.a;
}
