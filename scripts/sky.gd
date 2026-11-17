extends RefCounted
## Небесная механика звёздной системы: гигант в центре, 5 лун на круговых орбитах.
## У каждой луны своя система координат: луна в начале, оси вращаются вместе с ней (сутки).
## Считается одинаково на сервере (солнечные панели) и клиентах (картинка, полёты).

const D = preload("res://scripts/defs.gd")


## Положение луны pl в неподвижной системе гиганта.
static func planet_pos(pl: int, t: float) -> Vector3:
	var a: float = D.PLANETS[pl].a
	var phi: float = float(D.PLANETS[pl].phase) + sqrt(D.GIANT_MU / (a * a * a)) * t
	return Vector3(cos(phi), 0.0, sin(phi)) * a


static func planet_vel(pl: int, t: float) -> Vector3:
	var a: float = D.PLANETS[pl].a
	var n := sqrt(D.GIANT_MU / (a * a * a))
	var phi: float = float(D.PLANETS[pl].phase) + n * t
	return Vector3(-sin(phi), 0.0, cos(phi)) * a * n


static func period(pl: int) -> float:
	var a: float = D.PLANETS[pl].a
	return TAU * sqrt(a * a * a / D.GIANT_MU)


static func soi(pl: int) -> float:
	return float(D.PLANETS[pl].a) * D.SOI_FRAC


## Поворот «неподвижная система -> система луны»: local = frame * (inertial - planet_pos).
static func frame(pl: int, t: float) -> Basis:
	var theta := TAU * t / D.DAY_LENGTH + pl * 1.3
	return Basis(Vector3.UP, -theta) * Basis(Vector3.RIGHT, deg_to_rad(D.AXIS_TILT))


static func to_local(pl: int, t: float, inertial: Vector3) -> Vector3:
	return frame(pl, t) * (inertial - planet_pos(pl, t))


static func to_inertial(pl: int, t: float, local: Vector3) -> Vector3:
	return planet_pos(pl, t) + frame(pl, t).transposed() * local


## Небо над луной pl: солнце, гигант, затмение, фаза гиганта, где остальные луны.
static func state(t: float, pl: int = D.HOME_PLANET) -> Dictionary:
	var f := frame(pl, t)
	var sun: Vector3 = (f * D.SUN_DIR).normalized()
	var me := planet_pos(pl, t)
	var giant_rel := f * (-me)
	var gdir := giant_rel.normalized()
	var ang_r := asin(clampf(D.GIANT_R / me.length(), 0.0, 1.0))
	var sun_level := smoothstep(ang_r * 0.92, ang_r * 1.08, sun.angle_to(gdir))
	var phase := (1.0 - sun.dot(gdir)) * 0.5
	var others: Array = []
	for j in D.PLANETS.size():
		if j != pl:
			others.append([j, f * (planet_pos(j, t) - me)])
	return {"frame": f, "sun": sun, "sun_level": sun_level,
		"giant_rel": giant_rel, "gdir": gdir, "phase": phase, "others": others}


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
