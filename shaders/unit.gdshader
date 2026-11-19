// Юниты: модель из деталей с цветом вершин. Альфа цвета вершины — роль детали:
//   0.0 — краска команды (цвет из INSTANCE_CUSTOM.rgb), 0.7 — светится сама, 1.0 — обычный металл.
// INSTANCE_CUSTOM.a — прочность и движение: a < 0.5 — стоит, прочность = a / 0.49;
//                                           a >= 0.5 — едет/идёт, прочность = (a - 0.5) / 0.49.
// CUSTOM0 — анимация детали: xyz — точка вращения, w — вид:
//   1..8 — нога паука (шарнир у корпуса), 10 — винт дрона, 11 — корпус дрона (покачивается),
//   20 — гусеница (бегут траки), 30 — корпус (покачивается при ходьбе).
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/light16.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 opos;
varying vec3 onrm;
varying vec4 inst;
varying float vkind;
varying float vmove;

void vertex() {
	float a = INSTANCE_CUSTOM.a;
	float moving = step(0.5, a);
	float ph = float(INSTANCE_ID) * 1.37;
	float kind = CUSTOM0.w;
	vec3 piv = CUSTOM0.xyz;
	vec3 v = VERTEX;
	opos = VERTEX;
	if (kind > 0.5 && kind < 8.5) {
		// нога паука: две группы ног ходят по очереди (как у настоящих пауков)
		float k = kind - 1.0;
		float side = step(4.0, k);
		float group = mod(mod(k, 4.0) + side, 2.0);
		float phase = TIME * 7.0 + ph + group * PI;
		vec3 d = v - piv;
		float sw = sin(phase) * 0.32 * moving;
		float c = cos(sw);
		float s = sin(sw);
		d = vec3(c * d.x + s * d.z, d.y, -s * d.x + c * d.z);
		d.y += max(0.0, cos(phase)) * 0.35 * moving * clamp(length(d.xz) / 1.6, 0.0, 1.0);
		v = piv + d;
	} else if (kind > 9.5 && kind < 11.5) {
		// дрон парит; винты крутятся
		if (kind < 10.5) {
			vec3 d = v - piv;
			float r = TIME * 40.0 + ph;
			float c = cos(r);
			float s = sin(r);
			v = piv + vec3(c * d.x + s * d.z, d.y, -s * d.x + c * d.z);
		}
		v.y += sin(TIME * 3.0 + ph) * 0.06;
	} else if (kind > 29.5) {
		v.y += abs(sin(TIME * 7.0 + ph)) * 0.06 * moving;   // корпус пружинит в такт шагам
	}
	if (kind > 19.5 && kind < 20.5) {
		v.y += sin(TIME * 30.0 + ph) * 0.006 * moving;      // гусеницы дрожат
	}
	VERTEX = v;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	onrm = NORMAL;
	inst = INSTANCE_CUSTOM;
	vkind = kind;
	vmove = moving;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (COLOR.a < 0.35) {
		base = inst.rgb;   // краска команды
	}
	// мелкие пиксельные панели, как на постройках; у гусениц панели бегут — траки
	vec3 an = abs(onrm);
	vec3 op = opos * PX * 2.0;
	if (vkind > 19.5 && vkind < 20.5) {
		op.z += TIME * 30.0 * vmove;
	}
	vec2 uv = (an.x > an.y && an.x > an.z) ? op.zy : ((an.y > an.z) ? op.xz : op.xy);
	vec2 px = floor(uv);
	vec2 cell = floor(px / 4.0);
	vec2 inp = px - cell * 4.0;
	base *= 0.9 + 0.12 * hash2(cell + 3.0);
	if (inp.x == 0.0 || inp.y == 0.0) {
		base *= 0.8;
	}
	float hp = clamp((inst.a - 0.5 * vmove) / 0.49, 0.0, 1.0);
	base *= mix(0.4, 1.0, hp);
	vec3 lit = light16(base, wpos, normalize(wnrm));
	if (COLOR.a > 0.55 && COLOR.a < 0.85) {
		lit = COLOR.rgb;   // огни, визоры, фары — видны и в темноте
	}
	ALBEDO = lit;
}
