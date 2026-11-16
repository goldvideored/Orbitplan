// Поверхность планеты в пиксель-арте: реголит, скалы, слоистые стенки террас и руды.
// UV  — координаты в плоскости клетки (метры), у стенок UV.y — радиус (слои идут вокруг планеты).
// UV2.x — уровень высоты, UV2.y — вид грани * 16 + (руда + 1).
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/light16.gdshaderinc"

const vec3 LEVEL_COL[5] = vec3[5](
	vec3(0.22, 0.22, 0.29),   // низина
	vec3(0.33, 0.31, 0.35),
	vec3(0.43, 0.39, 0.39),
	vec3(0.53, 0.47, 0.41),
	vec3(0.70, 0.68, 0.66)    // скалы
);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 px = floor(UV * PX);
	float h = hash2(px);
	int lv = clamp(int(UV2.x + 0.5), 0, 4);
	int code = int(UV2.y + 0.5);
	int kind = code / 16;          // 0 верх клетки, 1 рамка, 2 стенка
	int ore = code % 16 - 1;       // -1 — нет руды

	vec3 base = LEVEL_COL[lv];
	vec3 col = base * (0.86 + 0.14 * h);                 // зерно реголита
	if (hash2(px * 1.7 + 3.1) > 0.94) {
		col *= 0.72;                                     // камешки
	}
	if (lv == 4 && hash2(floor(px / 3.0) + 9.0) > 0.85) {
		col *= 0.8;                                      // трещины в скалах
	}
	vec3 glow = vec3(0.0);

	if (kind == 2) {
		// стенка террасы: горизонтальные слои породы
		float band = floor(UV.y * PX / 2.0);
		col = base * 0.6 * (0.8 + 0.3 * hash2(vec2(band, 7.0))) * (0.9 + 0.1 * h);
	} else if (ore >= 0) {
		float cl = hash2(floor(px / 2.0) + 11.0);        // комки 2×2 пикселя
		if (ore == 0) {          // уголь: чёрные комки с блёстками
			if (cl > 0.4) col = (h > 0.9) ? vec3(0.38) : vec3(0.07, 0.07, 0.08);
		} else if (ore == 1) {   // медь: оранжевые зёрна + прозелень
			if (cl > 0.45) col = (h > 0.85) ? vec3(1.0, 0.72, 0.42) : vec3(0.8, 0.45, 0.2);
			if (h < 0.06) col = vec3(0.3, 0.7, 0.55);
		} else if (ore == 2) {   // железо: ржавые комья
			if (cl > 0.42) col = (h > 0.85) ? vec3(0.78, 0.42, 0.26) : vec3(0.52, 0.24, 0.15);
		} else if (ore == 3) {   // лёд: голубой с трещинами
			col = vec3(0.68, 0.84, 0.95) * (0.9 + 0.1 * h);
			if (cl < 0.18) col = vec3(0.48, 0.68, 0.9);
			if (h > 0.93) col = vec3(0.95, 1.0, 1.0);
		} else if (ore == 4) {   // кварцевый песок с кристаллами
			col = vec3(0.84, 0.79, 0.6) * (0.9 + 0.1 * h);
			if (cl > 0.72) col = (h > 0.6) ? vec3(1.0, 1.0, 0.96) : vec3(0.92, 0.92, 0.85);
		} else if (ore == 5) {   // свинец: серо-синие блоки
			if (cl > 0.48) col = (h > 0.8) ? vec3(0.62, 0.64, 0.78) : vec3(0.38, 0.4, 0.52);
		} else if (ore == 6) {   // уран: зелёные кристаллы, светятся
			if (cl > 0.5) {
				col = vec3(0.22, 0.6, 0.18);
				if (h > 0.55) glow = vec3(0.12, 0.45, 0.08);
			}
		} else if (ore == 7) {   // гелий-3: фиолетовые искры, светятся
			if (h > 0.84) {
				col = vec3(0.75, 0.45, 0.95);
				glow = vec3(0.22, 0.08, 0.32);
			}
		}
	}
	if (kind == 1) {
		col *= 0.6;              // тёмная рамка — граница клетки
	}
	ALBEDO = light16(col, wpos, normalize(wnrm)) + glow;
}
