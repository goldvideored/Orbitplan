extends Control
## Круговое меню построек (как колесо оружия в GTA).
## Держишь Z — меню открыто. Движение мыши выбирает сектор, колесо листает подтипы
## внутри сектора. Отпустил Z — выбор применён.

const D = preload("res://scripts/defs.gd")
const T = preload("res://scripts/i18n.gd")

const R_OUT := 230.0
const R_IN := 95.0
const DEAD_ZONE := 35.0

var is_open := false
var sectors: Array = []     # [[название, [типы]], ...]
var sub: Array = []         # выбранный подтип в каждом секторе
var hovered := -1
var sel_vec := Vector2.ZERO
var info_func: Callable     # тип -> Array строк (описание, цена, энергия...)
var name_func: Callable     # тип -> подпись в секторе (если не задано — название постройки)
var center_hint := T.t("колесо — подтип")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# по умолчанию — меню построек; другое меню задаётся через configure() до добавления в сцену
	if sectors.is_empty():
		for cat in D.CATEGORIES:
			sectors.append(cat)
		sectors.append([T.t("Бластер"), [D.WEAPON]])
	for i in sectors.size():
		sub.append(0)
	visible = false


func configure(secs: Array, names: Callable, hint: String) -> void:
	sectors = secs.duplicate()
	name_func = names
	center_hint = hint


func open(current_type: int) -> void:
	is_open = true
	visible = true
	sel_vec = Vector2.ZERO
	hovered = -1
	# подсветить сектор текущей постройки
	for i in sectors.size():
		var types: Array = sectors[i][1]
		var k := types.find(current_type)
		if k >= 0:
			sub[i] = k
	queue_redraw()


## Закрыть меню. Возвращает выбранный тип или null, если ничего не выбрано.
func close():
	is_open = false
	visible = false
	if hovered < 0:
		return null
	return current_type_of(hovered)


func current_type_of(i: int) -> int:
	var types: Array = sectors[i][1]
	return types[sub[i] % types.size()]


func on_mouse_motion(rel: Vector2) -> void:
	sel_vec += rel
	if sel_vec.length() > R_OUT:
		sel_vec = sel_vec.normalized() * R_OUT
	if sel_vec.length() < DEAD_ZONE:
		hovered = -1
	else:
		var n := sectors.size()
		var ang := fposmod(sel_vec.angle() + PI / 2.0, TAU)
		hovered = int(round(ang / (TAU / n))) % n
	queue_redraw()


func on_scroll(step: int) -> void:
	if hovered < 0:
		return
	var types: Array = sectors[hovered][1]
	sub[hovered] = posmod(sub[hovered] + step, types.size())
	queue_redraw()


func _draw() -> void:
	if not is_open:
		return
	var font := ThemeDB.fallback_font
	var c := size / 2.0
	var n := sectors.size()
	var step := TAU / n

	for i in n:
		var mid := -PI / 2.0 + step * i
		var a0 := mid - step / 2.0 + 0.02
		var a1 := mid + step / 2.0 - 0.02
		var pts := PackedVector2Array()
		var segs := 20
		for s in segs + 1:
			var a := lerpf(a0, a1, float(s) / segs)
			pts.append(c + Vector2(cos(a), sin(a)) * R_OUT)
		for s in segs + 1:
			var a := lerpf(a1, a0, float(s) / segs)
			pts.append(c + Vector2(cos(a), sin(a)) * R_IN)
		var col := Color(0.25, 0.55, 1.0, 0.8) if i == hovered else Color(0.05, 0.06, 0.1, 0.7)
		draw_colored_polygon(pts, col)

		# подпись сектора: группа и текущий подтип
		var lp := c + Vector2(cos(mid), sin(mid)) * (R_IN + R_OUT) / 2.0
		var types: Array = sectors[i][1]
		var t := current_type_of(i)
		var label_txt := ""
		if name_func.is_valid():
			label_txt = String(name_func.call(t))
		else:
			label_txt = T.t("Бластер") if t == D.WEAPON else T.t(String(D.NAMES[t]))
		draw_string(font, lp + Vector2(-80, -8), T.t(String(sectors[i][0])), HORIZONTAL_ALIGNMENT_CENTER, 160, 15,
				Color(1, 1, 1, 0.7))
		draw_string(font, lp + Vector2(-80, 12), label_txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 17, Color.WHITE)
		if types.size() > 1:
			draw_string(font, lp + Vector2(-80, 30), "%d / %d" % [sub[i] % types.size() + 1, types.size()],
					HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(1, 1, 1, 0.55))

	# центр: подсказка
	draw_circle(c, R_IN - 6, Color(0, 0, 0, 0.6))
	var hint := T.t("двигай мышь") if hovered < 0 else center_hint
	draw_string(font, c + Vector2(-80, 6), hint, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(1, 1, 1, 0.8))

	# подробности выбранного под колесом
	if hovered >= 0 and info_func.is_valid():
		var lines: Array = info_func.call(current_type_of(hovered))
		var y := c.y + R_OUT + 30
		var w := 900.0
		draw_rect(Rect2(c.x - w / 2.0, y - 24, w, 26 * lines.size() + 14), Color(0, 0, 0, 0.65))
		for k in lines.size():
			var fs := 20 if k == 0 else 16
			draw_string(font, Vector2(c.x - w / 2.0, y + k * 26), String(lines[k]), HORIZONTAL_ALIGNMENT_CENTER,
					w, fs, Color.WHITE if k == 0 else Color(0.85, 0.9, 1.0))
