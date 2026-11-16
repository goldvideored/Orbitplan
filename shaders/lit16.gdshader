// Освещение с 16 ступенями: 16 — полное солнце, 0 — абсолютная темнота.
// Источники: солнце (до 16), отражённый свет газового гиганта (до 4), фонарик (до 12).
// Планета в центре координат, поэтому нормаль сферы = normalize(позиция).
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec3 sun_dir;      // направление НА солнце
global uniform float sun_level;   // 0..1 (меньше 1 во время затмения)
global uniform vec3 giant_dir;    // направление НА гигант
global uniform float giant_level; // 0..1 — фаза гиганта (доля освещённого диска)
global uniform vec3 flash_pos;
global uniform vec3 flash_dir;
global uniform float flash_on;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;

const float LEVELS = 16.0;
const float GIANT_MAX = 4.0 / 16.0;
const float FLASH_MAX = 12.0 / 16.0;
const float FLASH_RANGE = 28.0;
const vec3 GIANT_TINT = vec3(1.0, 0.7, 0.45);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 up = normalize(wpos);

	// солнце: поверхность + сама планета заслоняет (ночная сторона)
	float s = max(dot(n, sun_dir), 0.0) * smoothstep(-0.03, 0.03, dot(up, sun_dir)) * sun_level;
	// гигант светит отражённым светом
	float g = max(dot(n, giant_dir), 0.0) * smoothstep(-0.03, 0.03, dot(up, giant_dir)) * giant_level * GIANT_MAX;
	// фонарик: конус + затухание по расстоянию
	vec3 to = wpos - flash_pos;
	float d = max(length(to), 0.001);
	vec3 td = to / d;
	float f = flash_on * smoothstep(0.86, 0.94, dot(td, flash_dir))
		* clamp(1.0 - d / FLASH_RANGE, 0.0, 1.0) * max(dot(n, -td), 0.0) * FLASH_MAX;

	float light = s + g + f;
	float level = clamp(floor(light * LEVELS + 0.5), 0.0, LEVELS);
	vec3 tint = light > 0.0001 ? (vec3(s + f) + GIANT_TINT * g) / light : vec3(1.0);

	vec3 base = albedo.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	ALBEDO = base * tint * (level / LEVELS);
}
