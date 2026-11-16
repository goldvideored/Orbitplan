// Значки предметов на лентах: квадрат всегда смотрит в камеру, картинка из атласа.
// Ячейка атласа приходит в INSTANCE_CUSTOM.xy (столбец, строка).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : filter_nearest;
uniform vec2 grid = vec2(8.0, 3.0);

varying vec2 cell;

void vertex() {
	// билборд: оставляем позицию экземпляра, поворот берём у камеры
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	cell = INSTANCE_CUSTOM.xy;
}

void fragment() {
	vec2 uv = (cell + vec2(UV.x, UV.y)) / grid;
	vec4 t = texture(atlas, uv);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb;
}
