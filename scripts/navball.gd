extends Control
## Навбол внизу экрана: шар-авиагоризонт + маркеры (по движению, против движения,
## нормаль, антинормаль, радиально наружу/внутрь), автопилот ориентации и дроссель.

const NavShader = preload("res://shaders/navball.gdshader")


## Слой поверх шара: маркеры рисует сам навбол.
class Overlay extends Control:
	var nb
	func _draw() -> void:
		nb.draw_over(self)

const R := 105.0
const SAS_NAMES := ["выкл", "по движению", "против движения", "нормаль", "антинормаль",
	"радиально наружу", "радиально внутрь"]

var ball: ColorRect
var overlay: Overlay
var mat: ShaderMaterial
var nose := Vector3.UP
var right_v := Vector3.RIGHT
var up_screen := Vector3.FORWARD
var markers: Array = []        # [[направление, вид], ...]
var sas_mode := 0
var throttle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -R - 150
	offset_right = R + 150
	offset_top = -2 * R - 70
	offset_bottom = -6
	ball = ColorRect.new()
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball.position = Vector2(150, 0)
	ball.size = Vector2(2 * R, 2 * R)
	mat = ShaderMaterial.new()
	mat.shader = NavShader
	ball.material = mat
	add_child(ball)
	overlay = Overlay.new()
	overlay.nb = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)


func set_data(n: Vector3, r: Vector3, us: Vector3, up_w: Vector3, north: Vector3, marks: Array,
		sas: int, thr: float) -> void:
	nose = n
	right_v = r
	up_screen = us
	markers = marks
	sas_mode = sas
	throttle = thr
	mat.set_shader_parameter("nose", n)
	mat.set_shader_parameter("right_v", r)
	mat.set_shader_parameter("up_screen", us)
	mat.set_shader_parameter("up_world", up_w)
	mat.set_shader_parameter("north", north)
	overlay.queue_redraw()


func draw_over(c: Control) -> void:
	var font := ThemeDB.fallback_font
	var center := Vector2(150 + R, R)
	c.draw_arc(center, R, 0, TAU, 64, Color(0.1, 0.1, 0.12), 4.0)
	# маркеры
	for m in markers:
		var d: Vector3 = m[0]
		if d.length() < 0.001:
			continue
		d = d.normalized()
		if d.dot(nose) < 0.0:
			continue   # на обратной стороне шара
		var p := center + Vector2(d.dot(right_v), -d.dot(up_screen)) * R
		_marker(c, p, String(m[1]))
	# нос корабля — жёлтая «птичка»
	var y := Color(1.0, 0.85, 0.2)
	c.draw_line(center + Vector2(-22, 0), center + Vector2(-8, 0), y, 3.0)
	c.draw_line(center + Vector2(8, 0), center + Vector2(22, 0), y, 3.0)
	c.draw_line(center + Vector2(-8, 0), center + Vector2(0, 7), y, 3.0)
	c.draw_line(center + Vector2(8, 0), center + Vector2(0, 7), y, 3.0)
	# дроссель — полоска слева
	var bar := Rect2(118, 10, 16, 2 * R - 20)
	c.draw_rect(bar, Color(0, 0, 0, 0.6))
	var hgt := bar.size.y * throttle
	c.draw_rect(Rect2(bar.position.x, bar.end.y - hgt, bar.size.x, hgt), Color(1.0, 0.55, 0.2))
	c.draw_string(font, Vector2(60, bar.end.y + 2), "Тяга %d%%" % int(throttle * 100.0),
			HORIZONTAL_ALIGNMENT_CENTER, 90, 14, Color.WHITE)
	# автопилот ориентации: клавиши 1–7
	var x0 := 2.0 * R + 160.0
	c.draw_string(font, Vector2(x0, 14), "Автопилот:", HORIZONTAL_ALIGNMENT_LEFT, 150, 14, Color(1, 1, 1, 0.7))
	for i in SAS_NAMES.size():
		var on := i == sas_mode
		c.draw_string(font, Vector2(x0, 34 + i * 20), "%d  %s" % [i + 1, SAS_NAMES[i]],
				HORIZONTAL_ALIGNMENT_LEFT, 160, 14, Color(0.4, 1.0, 0.5) if on else Color(1, 1, 1, 0.6))


func _marker(c: Control, p: Vector2, kind: String) -> void:
	var green := Color(0.4, 1.0, 0.4)
	var purple := Color(0.85, 0.4, 1.0)
	var cyan := Color(0.3, 0.85, 1.0)
	match kind:
		"pro":
			c.draw_arc(p, 9, 0, TAU, 20, green, 2.5)
			c.draw_line(p + Vector2(0, -9), p + Vector2(0, -15), green, 2.5)
			c.draw_line(p + Vector2(-9, 0), p + Vector2(-15, 0), green, 2.5)
			c.draw_line(p + Vector2(9, 0), p + Vector2(15, 0), green, 2.5)
		"retro":
			c.draw_arc(p, 9, 0, TAU, 20, green, 2.5)
			c.draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), green, 2.5)
			c.draw_line(p + Vector2(6, -6), p + Vector2(-6, 6), green, 2.5)
		"normal":
			c.draw_polyline(PackedVector2Array([p + Vector2(0, -10), p + Vector2(9, 7), p + Vector2(-9, 7),
				p + Vector2(0, -10)]), purple, 2.5)
		"anti":
			c.draw_polyline(PackedVector2Array([p + Vector2(0, 10), p + Vector2(9, -7), p + Vector2(-9, -7),
				p + Vector2(0, 10)]), purple, 2.5)
		"out":
			c.draw_arc(p, 8, 0, TAU, 20, cyan, 2.5)
			for a in 4:
				var v := Vector2.RIGHT.rotated(TAU * a / 4.0 + PI / 4.0)
				c.draw_line(p + v * 8, p + v * 14, cyan, 2.5)
		"in":
			c.draw_arc(p, 8, 0, TAU, 20, cyan, 2.5)
			for a in 4:
				var v := Vector2.RIGHT.rotated(TAU * a / 4.0 + PI / 4.0)
				c.draw_line(p + v * 3, p + v * 8, cyan, 2.5)
