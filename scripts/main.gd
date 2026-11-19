extends Node
## Главное меню: название сверху по центру, панель выбора слева, на фоне — война на луне (menu_bg.gd).
## Пункты: локальная игра (в разработке), локальный мультиплеер (хост / подключение),
## список серверов (в разработке), креатив, выход.

const MenuBg = preload("res://scripts/menu_bg.gd")

var menu: CanvasLayer
var bg: Node3D
var main_box: VBoxContainer
var mp_box: VBoxContainer
var stub_box: VBoxContainer
var stub_title: Label
var stub_text: Label
var ip_edit: LineEdit
var port_edit: LineEdit
var status_lbl: Label


func _ready() -> void:
	if Net.dedicated:
		return
	bg = MenuBg.new()
	add_child(bg)
	_build_menu()
	Net.status.connect(func(t: String): status_lbl.text = t)
	Net.game_started.connect(_on_game_started)


func _on_game_started() -> void:
	menu.hide()
	if is_instance_valid(bg):
		bg.queue_free()   # фон больше не нужен: камера и сцена — у мира


func _btn_style(col: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _button(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.06, 0.08, 0.13, 0.82), Color(0.35, 0.6, 1.0, 0.35)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.12, 0.18, 0.3, 0.92), Color(0.45, 0.75, 1.0, 0.9)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.2, 0.3, 0.5, 0.95), Color(0.6, 0.85, 1.0, 1.0)))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _label(text: String, size: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


func _build_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)

	# лёгкое затемнение слева, чтобы панель читалась на фоне звёзд
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)

	# название — сверху по центру
	var title := _label("ORBITPLAN", 84, Color(0.9, 0.95, 1.0))
	title.add_theme_constant_override("outline_size", 14)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 36
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	var sub := _label("командная стратегия на лунах газового гиганта", 18, Color(0.6, 0.75, 1.0))
	sub.anchor_left = 0.0
	sub.anchor_right = 1.0
	sub.offset_top = 140
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(sub)

	# панель выбора — слева от центра
	var holder := Control.new()
	holder.anchor_left = 0.2
	holder.anchor_right = 0.2
	holder.anchor_top = 0.5
	holder.anchor_bottom = 0.5
	holder.offset_left = -10
	holder.offset_top = -170
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(holder)

	main_box = VBoxContainer.new()
	main_box.custom_minimum_size = Vector2(360, 0)
	main_box.add_theme_constant_override("separation", 10)
	holder.add_child(main_box)
	_button("Локальная игра", main_box, _on_local)
	_button("Локальный мультиплеер", main_box, _on_multiplayer)
	_button("Список серверов", main_box, _on_servers)
	_button("Креатив", main_box, _on_creative)
	_button("Выход", main_box, _on_quit)

	# локальный мультиплеер: создать игру или подключиться по адресу
	mp_box = VBoxContainer.new()
	mp_box.custom_minimum_size = Vector2(360, 0)
	mp_box.add_theme_constant_override("separation", 10)
	mp_box.visible = false
	holder.add_child(mp_box)
	mp_box.add_child(_label("Локальный мультиплеер", 26))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP сервера"
	ip_edit.text = "127.0.0.1"
	ip_edit.add_theme_font_size_override("font_size", 18)
	mp_box.add_child(ip_edit)
	port_edit = LineEdit.new()
	port_edit.placeholder_text = "Порт"
	port_edit.text = str(Net.DEFAULT_PORT)
	port_edit.add_theme_font_size_override("font_size", 18)
	mp_box.add_child(port_edit)
	_button("Создать игру (хост)", mp_box, _on_host)
	_button("Подключиться", mp_box, _on_join)
	_button("Назад", mp_box, _on_back)

	# заглушка «в разработке»
	stub_box = VBoxContainer.new()
	stub_box.custom_minimum_size = Vector2(360, 0)
	stub_box.add_theme_constant_override("separation", 12)
	stub_box.visible = false
	holder.add_child(stub_box)
	stub_title = _label("", 26)
	stub_box.add_child(stub_title)
	var tag := _label("В РАЗРАБОТКЕ", 16, Color(1.0, 0.8, 0.3))
	stub_box.add_child(tag)
	stub_text = _label("", 16, Color(0.8, 0.85, 0.9))
	stub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stub_text.custom_minimum_size = Vector2(360, 0)
	stub_box.add_child(stub_text)
	_button("Назад", stub_box, _on_back)

	status_lbl = _label("", 15, Color(1.0, 0.85, 0.5))
	status_lbl.anchor_left = 0.0
	status_lbl.anchor_right = 1.0
	status_lbl.anchor_top = 1.0
	status_lbl.anchor_bottom = 1.0
	status_lbl.offset_top = -48
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(status_lbl)


func _on_local() -> void:
	_show_stub("Локальная игра", "Одиночная игра против ботов — в разработке.\nПока можно играть в локальный мультиплеер или креатив.")


func _on_servers() -> void:
	_show_stub("Список серверов", "Поиск серверов — в разработке.\nПодключиться к серверу по адресу можно через «Локальный мультиплеер».")


func _on_multiplayer() -> void:
	_show(mp_box)


func _on_back() -> void:
	_show(main_box)


func _on_creative() -> void:
	Net.start_offline(true)   # без сервера: порт не открывается, к игре никто не подключится


func _on_host() -> void:
	Net.host(_port(), false)


func _on_join() -> void:
	Net.join(ip_edit.text.strip_edges(), _port())


func _on_quit() -> void:
	get_tree().quit()


func _show(box: Control) -> void:
	for b in [main_box, mp_box, stub_box]:
		(b as Control).visible = b == box
	status_lbl.text = ""


func _show_stub(title: String, text: String) -> void:
	stub_title.text = title
	stub_text.text = text
	_show(stub_box)


func _port() -> int:
	var p := int(port_edit.text) if port_edit else 0
	return p if p > 0 else Net.DEFAULT_PORT
