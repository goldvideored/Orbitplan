// Навбол (авиагоризонт), как в KSP и самолётах: в центре — куда смотрит нос.
// Голубое — над горизонтом, коричневое — под ним; линии тангажа каждые 10°, курса — каждые 30°.
shader_type canvas_item;

uniform vec3 nose = vec3(0.0, 1.0, 0.0);       // нос корабля (мировое направление)
uniform vec3 right_v = vec3(1.0, 0.0, 0.0);    // что справа на экране
uniform vec3 up_screen = vec3(0.0, 0.0, -1.0); // что сверху на экране
uniform vec3 up_world = vec3(0.0, 1.0, 0.0);   // «верх» — от центра планеты (или гиганта)
uniform vec3 north = vec3(0.0, 0.0, -1.0);     // «север» — ось вращения луны

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r2 = dot(p, p);
	if (r2 > 1.0) {
		discard;
	}
	float z = sqrt(1.0 - r2);
	vec3 d = normalize(nose * z + right_v * p.x + up_screen * p.y);
	float el = dot(d, up_world);
	float elev = degrees(asin(clamp(el, -1.0, 1.0)));
	vec3 col = el > 0.0 ? vec3(0.22, 0.45, 0.8) : vec3(0.55, 0.33, 0.18);
	float f = abs(fract(elev / 10.0 + 0.5) - 0.5) * 10.0;
	if (f < 0.35) {
		col = mix(col, vec3(1.0), 0.45);
	}
	vec3 east = normalize(cross(north, up_world));
	vec3 hz = d - up_world * el;
	float az = degrees(atan(dot(hz, east), dot(hz, north)));
	float g = abs(fract(az / 30.0 + 0.5) - 0.5) * 30.0;
	if (g < 0.45 && abs(elev) < 80.0) {
		col = mix(col, vec3(1.0), 0.3);
	}
	if (abs(elev) < 0.7) {
		col = vec3(1.0);   // горизонт
	}
	col *= 0.55 + 0.45 * z;
	COLOR = vec4(col, 1.0);
}
