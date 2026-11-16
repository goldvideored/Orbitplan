extends RefCounted
## Небесная механика: где солнце и гигант в момент времени t.
## Считается одинаково на сервере (для солнечных панелей) и на клиентах (для картинки).
## Система отсчёта привязана к планете (как в KSP): планета вращается вокруг
## наклонённой оси и летит по орбите вокруг гиганта, поэтому для нас движутся небесные тела.

const D = preload("res://scripts/defs.gd")


static func state(t: float) -> Dictionary:
	var theta := TAU * t / D.DAY_LENGTH
	var phi := TAU * t / D.ORBIT_PERIOD
	var frame := Basis(Vector3.UP, -theta) * Basis(Vector3.RIGHT, deg_to_rad(D.AXIS_TILT))
	var sun: Vector3 = (frame * D.SUN_DIR).normalized()
	var orbit_pos := Vector3(cos(phi), 0.0, sin(phi)) * D.GIANT_DIST
	var giant_rel := frame * (-orbit_pos)
	var gdir := giant_rel.normalized()
	# затмение: диск гиганта закрывает солнце
	var ang_r := asin(D.GIANT_R / D.GIANT_DIST)
	var sun_level := smoothstep(ang_r * 0.92, ang_r * 1.08, sun.angle_to(gdir))
	# фаза гиганта: доля видимого диска, освещённая солнцем
	var phase := (1.0 - sun.dot(gdir)) * 0.5
	return {"frame": frame, "sun": sun, "sun_level": sun_level,
		"giant_rel": giant_rel, "gdir": gdir, "phase": phase}


## Уровень света 0..16 на ровной поверхности с нормалью up (без фонарика).
static func level_at(up: Vector3, st: Dictionary) -> int:
	var sun: Vector3 = st.sun
	var gdir: Vector3 = st.gdir
	var sd := up.dot(sun)
	var gd := up.dot(gdir)
	var s: float = maxf(sd, 0.0) * smoothstep(-0.03, 0.03, sd) * float(st.sun_level)
	var g: float = maxf(gd, 0.0) * smoothstep(-0.03, 0.03, gd) * float(st.phase) \
			* float(D.GIANT_MAX_LEVEL) / float(D.LIGHT_LEVELS)
	return clampi(floori((s + g) * D.LIGHT_LEVELS + 0.5), 0, D.LIGHT_LEVELS)
