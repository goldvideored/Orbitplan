extends RefCounted
## Настройки игрока: язык, полноэкранный режим, чувствительность мыши. Хранятся в user://settings.cfg.

const I18n = preload("res://scripts/i18n.gd")
const PATH := "user://settings.cfg"

static var fullscreen := false
static var sens := 1.0   # множитель чувствительности мыши


static func load_all() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		I18n.lang = String(cf.get_value("main", "lang", "ru"))
		fullscreen = bool(cf.get_value("main", "fullscreen", false))
		sens = float(cf.get_value("main", "sens", 1.0))
	apply()


static func save_all() -> void:
	var cf := ConfigFile.new()
	cf.set_value("main", "lang", I18n.lang)
	cf.set_value("main", "fullscreen", fullscreen)
	cf.set_value("main", "sens", sens)
	cf.save(PATH)


static func apply() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
