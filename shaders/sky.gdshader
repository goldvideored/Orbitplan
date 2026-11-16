// Звёздное небо в пиксель-арте: огромная сфера изнутри. Звёзды и туманности.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

varying vec3 dir;

float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// грубый шум для туманностей (по пиксельной сетке)
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir);
	float lat = asin(clamp(d.y, -1.0, 1.0));
	float lon = atan(d.z, d.x);
	vec2 q = floor(vec2(lon / TAU * 1400.0, lat / PI * 700.0));
	vec3 c = vec3(0.0);
	// туманности — очень тусклые, крупными пикселями
	float neb = vnoise(q / 60.0) * vnoise(q / 23.0 + 5.0);
	c += mix(vec3(0.05, 0.02, 0.09), vec3(0.02, 0.05, 0.1), vnoise(q / 90.0)) * smoothstep(0.25, 0.6, neb);
	// звёзды
	float s = h2(q);
	if (s > 0.9965) {
		float b = h2(q + 17.0);
		vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), h2(q + 3.0));
		c = tint * (0.4 + 0.6 * b);
	}
	ALBEDO = c;
}
