// Постройки, юниты, персонажи: свет на 16 уровней + пиксельные узоры.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/light16.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform int pattern = 1;   // 0 гладко, 1 металл с панелями, 2 лента конвейера, 3 труба с водой

const float BELT_SPEED = 4.75;   // м/с — как едут предметы по ленте
const float PIPE_SPEED = 9.5;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 opos;
varying vec3 onrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	if (pattern > 0) {
		// развёртка по главной оси грани — квадратные пиксели на коробках
		vec3 an = abs(onrm);
		vec3 op = opos * PX;
		vec2 uv = (an.x > an.y && an.x > an.z) ? op.zy : ((an.y > an.z) ? op.xz : op.xy);
		vec2 px = floor(uv);
		float h = hash2(px);
		if (pattern == 1) {
			// металлические панели 6×6 пикселей: швы, заклёпки, разный оттенок
			vec2 cell = floor(px / 6.0);
			vec2 inp = px - cell * 6.0;
			base *= 0.9 + 0.12 * hash2(cell + 5.0);
			if (inp.x == 0.0 || inp.y == 0.0) {
				base *= 0.7;
			} else if (inp.x == 1.0 && inp.y == 1.0) {
				base *= 1.25;
			}
			base *= 0.96 + 0.06 * h;
		} else if (pattern == 2) {
			// резиновая лента: поперечные полосы едут вдоль оси X
			float s = mod(floor(op.x - TIME * BELT_SPEED * PX), 4.0);
			base *= (s < 1.0) ? 0.55 : (0.9 + 0.1 * h);
		} else if (pattern == 3) {
			// труба: по ней бегут светлые пиксели воды
			float flow = hash2(vec2(floor(op.x - TIME * PIPE_SPEED * PX), floor(op.z)));
			base = mix(base, vec3(0.45, 0.75, 1.0), step(0.82, flow));
			base *= 0.92 + 0.08 * h;
		}
	}
	ALBEDO = light16(base, wpos, normalize(wnrm));
}
