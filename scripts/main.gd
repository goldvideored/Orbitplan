extends Node
## Главное меню: хост / подключение.

var menu: CanvasLayer
var ip_edit: LineEdit
var port_edit: LineEdit
var status_lbl: Label


func _ready() -> void:
	if Net.dedicated:
		return
	_build_menu()
	Net.status.connect(func(t: String): status_lbl.text = t)
	Net.game_started.connect(func(): menu.hide())


func _build_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "ORBITPLAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "прототип — этап 1"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	box.add_child(sub)

	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP сервера"
	ip_edit.text = "127.0.0.1"
	box.add_child(ip_edit)

	port_edit = LineEdit.new()
	port_edit.placeholder_text = "Порт"
	port_edit.text = str(Net.DEFAULT_PORT)
	box.add_child(port_edit)

	var host_btn := Button.new()
	host_btn.text = "Создать игру (хост)"
	host_btn.pressed.connect(func(): Net.host(_port()))
	box.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "Подключиться"
	join_btn.pressed.connect(func(): Net.join(ip_edit.text.strip_edges(), _port()))
	box.add_child(join_btn)

	status_lbl = Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(status_lbl)


func _port() -> int:
	var p := int(port_edit.text)
	return p if p > 0 else Net.DEFAULT_PORT
