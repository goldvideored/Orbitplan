// Общее для всех шейдеров: свет на 16 ступеней и хэши для пиксельных узоров.
// Подключается через #include.

global uniform vec3 sun_dir;      // направление НА солнце
global uniform float sun_level;   // 0..1 (меньше 1 во время затмения)
global uniform vec3 giant_dir;    // направление НА гигант
global uniform float giant_level; // 0..1 — фаза гиганта
global uniform vec3 flash_pos;
global uniform vec3 flash_dir;
global uniform float flash_on;
global uniform float space_mode;  // 1 — открытый космос: планеты под ногами нет, тень от неё не считаем
global uniform float land_on;     // посадочный фонарь корабля (широкий конус вниз)
global uniform vec3 land_pos;
global uniform vec3 land_dir;
// лампы и свечение построек: текстура N×1, в каждом пикселе (x, y, z, w);
// w > 0 — лампа радиусом w, w < 0 — слабое свечение постройки радиусом -w
global uniform sampler2D lamp_tex;
global uniform int lamp_count;

const float LEVELS = 16.0;
const float GIANT_MAX = 4.0 / 16.0;
const float FLASH_MAX = 12.0 / 16.0;
const float FLASH_RANGE = 28.0;
const vec3 GIANT_TINT = vec3(1.0, 0.7, 0.45);
const vec3 LAMP_TINT = vec3(1.0, 0.85, 0.6);
const float LAMP_MAX = 12.0 / 16.0;
const float GLOW_MAX = 3.0 / 16.0;
const float PX = 8.0;             // пикселей на метр (16 на клетку)

// хэши без sin — стабильны на больших координатах
float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Освещённость с квантованием на 16 уровней: 0 — абсолютная темнота.
// Планета в центре координат, поэтому нормаль сферы = normalize(wpos).
vec3 light16(vec3 base, vec3 wpos, vec3 n) {
	if (space_mode > 0.5) {
		// в космосе: только солнце + слабая подсветка (звёзды, гигант), чтобы силуэт был виден
		float sp = max(dot(n, sun_dir), 0.0) * sun_level;
		float lv = clamp(floor(sp * LEVELS + 0.5), 2.0, LEVELS);
		return base * (lv / LEVELS);
	}
	vec3 up = normalize(wpos);
	float s = max(dot(n, sun_dir), 0.0) * smoothstep(-0.03, 0.03, dot(up, sun_dir)) * sun_level;
	float g = max(dot(n, giant_dir), 0.0) * smoothstep(-0.03, 0.03, dot(up, giant_dir)) * giant_level * GIANT_MAX;
	vec3 to = wpos - flash_pos;
	float d = max(length(to), 0.001);
	vec3 td = to / d;
	float f = flash_on * smoothstep(0.86, 0.94, dot(td, flash_dir))
		* clamp(1.0 - d / FLASH_RANGE, 0.0, 1.0) * max(dot(n, -td), 0.0) * FLASH_MAX;
	vec3 tl = wpos - land_pos;
	float dl = max(length(tl), 0.001);
	vec3 tdl = tl / dl;
	float lnd = land_on * smoothstep(0.55, 0.75, dot(tdl, land_dir))
		* clamp(1.0 - dl / 45.0, 0.0, 1.0) * max(dot(n, -tdl), 0.0) * (14.0 / 16.0);
	f += lnd;
	// лампы и свечение построек (тёплый свет)
	float lp = 0.0;
	for (int i = 0; i < lamp_count; i++) {
		vec4 L = texelFetch(lamp_tex, ivec2(i, 0), 0);
		float rad = abs(L.w);
		vec3 dv = L.xyz - wpos;
		float dist = length(dv);
		if (dist < rad && dist > 0.001) {
			float k = (L.w > 0.0 ? LAMP_MAX : GLOW_MAX) * (1.0 - dist / rad);
			lp += k * (0.35 + 0.65 * max(dot(n, dv / dist), 0.0));
		}
	}
	float light = s + g + f + lp;
	float level = clamp(floor(light * LEVELS + 0.5), 0.0, LEVELS);
	vec3 tint = light > 0.0001 ? (vec3(s + f) + GIANT_TINT * g + LAMP_TINT * lp) / light : vec3(1.0);
	return base * tint * (level / LEVELS);
}
