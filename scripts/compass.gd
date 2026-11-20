extends Control
const T = preload("res://scripts/i18n.gd")
## Компас корабля: лента курса со сторонами света, тангаж и направление полёта.
## Курс считается от «севера» — оси вращения луны (в космосе — от оси орбит гиганта).

const STEP := 4.0          # пикселей на градус
const WIDTH := 640.0
const LETTERS := {0: "С", 45: "СВ", 90: "В", 135: "ЮВ", 180: "Ю", 225: "ЮЗ", 270: "З", 315: "СЗ"}

var heading := 0.0         # куда смотрит нос, градусы 0..360
var pitch := 0.0           # угол носа над горизонтом, -90..90
var pro_heading := 0.0     # куда летим
var pro_pitch := 0.0
var has_pro := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# по центру сверху
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = 10.0
	offset_bottom = 100.0


func set_data(h: float, p: float, ph: float, pp: float, show_pro: bool) -> void:
	heading = fposmod(h, 360.0)
	pitch = p
	pro_heading = fposmod(ph, 360.0)
	pro_pitch = pp
	has_pro = show_pro
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cx := WIDTH / 2.0
	draw_rect(Rect2(0, 0, WIDTH, 44), Color(0, 0, 0, 0.55))
	var half := WIDTH / 2.0 / STEP
	var start := int(floor(heading - half))
	var end := int(ceil(heading + half))
	for deg in range(start, end + 1):
		var d := posmod(deg, 360)
		var x := cx + (deg - heading) * STEP
		if d % 45 == 0:
			draw_line(Vector2(x, 0), Vector2(x, 16), Color.WHITE, 2.0)
			var txt: String = LETTERS[d]
			draw_string(font, Vector2(x - 20, 36), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 16,
					Color(1, 0.85, 0.3) if d == 0 else Color.WHITE)
		elif d % 15 == 0:
			draw_line(Vector2(x, 0), Vector2(x, 11), Color(1, 1, 1, 0.8), 1.5)
			draw_string(font, Vector2(x - 20, 34), str(d), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(1, 1, 1, 0.6))
		elif d % 5 == 0:
			draw_line(Vector2(x, 0), Vector2(x, 6), Color(1, 1, 1, 0.5), 1.0)
	# направление полёта — зелёный кружок (или стрелка у края)
	if has_pro:
		var diff := wrapf(pro_heading - heading, -180.0, 180.0)
		var px := cx + diff * STEP
		var green := Color(0.35, 1.0, 0.4)
		if px < 8.0 or px > WIDTH - 8.0:
			var ex := 10.0 if px < 8.0 else WIDTH - 10.0
			var sgn := -1.0 if px < 8.0 else 1.0
			draw_colored_polygon(PackedVector2Array([Vector2(ex + sgn * 8, 22), Vector2(ex, 14), Vector2(ex, 30)]), green)
		else:
			draw_arc(Vector2(px, 22), 7, 0, TAU, 16, green, 2.0)
			draw_line(Vector2(px, 15), Vector2(px, 10), green, 2.0)
	# метка носа
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 8, 44), Vector2(cx + 8, 44), Vector2(cx, 34)]),
			Color(1, 0.85, 0.3))
	var info := T.t("Курс %03d°    Тангаж %+d°") % [int(round(heading)) % 360, int(round(pitch))]
	if has_pro:
		info += T.t("    Полёт %03d° / %+d°") % [int(round(pro_heading)) % 360, int(round(pro_pitch))]
	draw_rect(Rect2(cx - 220, 50, 440, 26), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(cx - 220, 69), info, HORIZONTAL_ALIGNMENT_CENTER, 440, 16, Color.WHITE)
