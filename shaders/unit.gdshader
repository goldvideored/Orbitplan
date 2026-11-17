// Юниты: модель из деталей с цветом вершин. Альфа цвета вершины — роль детали:
//   0.0 — краска команды (цвет из INSTANCE_CUSTOM.rgb), 0.7 — светится сама, 1.0 — обычный металл.
// INSTANCE_CUSTOM.a — прочность 0..1 (повреждённые темнеют).
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/light16.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 opos;
varying vec3 onrm;
varying vec4 inst;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	opos = VERTEX;
	onrm = NORMAL;
	inst = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (COLOR.a < 0.35) {
		base = inst.rgb;   // краска команды
	}
	// мелкие пиксельные панели, как на постройках
	vec3 an = abs(onrm);
	vec3 op = opos * PX * 2.0;
	vec2 uv = (an.x > an.y && an.x > an.z) ? op.zy : ((an.y > an.z) ? op.xz : op.xy);
	vec2 px = floor(uv);
	vec2 cell = floor(px / 4.0);
	vec2 inp = px - cell * 4.0;
	base *= 0.9 + 0.12 * hash2(cell + 3.0);
	if (inp.x == 0.0 || inp.y == 0.0) {
		base *= 0.8;
	}
	base *= mix(0.4, 1.0, clamp(inst.a, 0.0, 1.0));
	vec3 lit = light16(base, wpos, normalize(wnrm));
	if (COLOR.a > 0.55 && COLOR.a < 0.85) {
		lit = COLOR.rgb;   // огни, визоры — видны и в темноте
	}
	ALBEDO = lit;
}
