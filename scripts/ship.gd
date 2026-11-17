extends Node3D
## Корабль под управлением игрока. Физика считается у пилота (как ходьба персонажа),
## сервер получает положение и раздаёт остальным.
## Полёт по «сферам влияния», как в KSP: внутри сферы луны корабль летит в её системе
## координат (луна в начале), за границей — в системе гиганта (гигант в начале).
## Начало координат корабля — низ (опоры), нос смотрит вдоль локальной +Y.

const D = preload("res://scripts/defs.gd")
const SkyCalc = preload("res://scripts/sky.gd")

var world                     # World — для поверхности планеты и событий
var ship_id := 0
var vel := Vector3.ZERO
var fuel := 0.0              # единиц топлива He-3
var landed := true
var thrusting := false
var crashed := false
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.35
var cam_dist := 16.0
var flame: Node3D
var cell_hint := -1
var pn := -1                 # луна, в сфере влияния которой летим; -1 — открытый космос
var throttle := 0.0          # дроссель 0..1 (Shift/Ctrl, Z — полный, X — ноль)
var sas_mode := 0            # автопилот ориентации: 0 выкл, 1 по движению, 2 против, 3 нормаль,
                             # 4 антинормаль, 5 радиально наружу, 6 радиально внутрь
var power := 0.0             # тяга сейчас, 0..1
var kind := 0                # тип корабля (D.SHIP_KINDS): 0 разведчик, 1 транспорт
var beam: Node3D             # видимый луч посадочного фонаря
var auto_retro_done := false # автопилот «против движения» уже включён на этом снижении


func setup(w, id: int, model: Node3D, fuel_units: float, planet_n: int, ship_kind := 0) -> void:
	world = w
	kind = ship_kind
	pn = planet_n
	ship_id = id
	fuel = fuel_units
	add_child(model)
	flame = model.get_meta("flame")
	beam = model.get_meta("beam")
	cam = Camera3D.new()
	cam.fov = 75
	cam.near = 0.1
	cam.far = 15000
	add_child(cam)
	cam.top_level = true   # камера не крутится вместе с кораблём


func mass() -> float:
	return float(D.SHIP_KINDS[kind].dry) + fuel * D.FUEL_UNIT_MASS


## Сколько ещё можно разогнаться (формула Циолковского).
func dv() -> float:
	return D.SCOUT_VE * log(mass() / float(D.SHIP_KINDS[kind].dry))


## Гравитационный параметр и радиус тела, вокруг которого летим сейчас.
func body_mu() -> float:
	return D.SHIP_MU if pn >= 0 else D.GIANT_MU


func body_r() -> float:
	return D.PLANET_R if pn >= 0 else D.GIANT_R


func altitude() -> float:
	return global_position.length() - body_r()


## Апоцентр и перицентр (высоты над поверхностью) по текущей скорости. Пустой массив — орбиты нет.
func orbit() -> Array:
	var mu := body_mu()
	var r := global_position
	var energy := vel.length_squared() / 2.0 - mu / r.length()
	if energy >= 0.0:
		return []
	var a := -mu / (2.0 * energy)
	var h := r.cross(vel).length()
	var ecc := sqrt(maxf(0.0, 1.0 + 2.0 * energy * h * h / (mu * mu)))
	return [a * (1.0 + ecc) - body_r(), a * (1.0 - ecc) - body_r()]


## Подробно об орбите: где апоцентр и перицентр и через сколько секунд мы там будем.
func orbit_info() -> Dictionary:
	var mu := body_mu()
	var r := global_position
	var v := vel
	var rl := r.length()
	var energy := v.length_squared() / 2.0 - mu / rl
	if energy >= 0.0 or landed:
		return {}
	var a := -mu / (2.0 * energy)
	var evec := (r * (v.length_squared() - mu / rl) - v * r.dot(v)) / mu
	var ecc := evec.length()
	var pe_dir := evec / ecc if ecc > 0.0001 else r / rl
	var cos_nu := clampf(pe_dir.dot(r / rl), -1.0, 1.0)
	var nu := acos(cos_nu)
	if r.dot(v) < 0.0:
		nu = TAU - nu
	var e_an := 2.0 * atan(sqrt((1.0 - ecc) / (1.0 + ecc)) * tan(nu / 2.0))
	var m_an := fposmod(e_an - ecc * sin(e_an), TAU)
	var n := sqrt(mu / (a * a * a))
	return {
		"ap_pos": -pe_dir * a * (1.0 + ecc), "pe_pos": pe_dir * a * (1.0 - ecc),
		"t_pe": (TAU - m_an) / n, "t_ap": fposmod(PI - m_an, TAU) / n, "ecc": ecc,
	}


## Куда держать нос в текущем режиме автопилота.
func sas_target() -> Vector3:
	var r := global_position.normalized()
	var v := vel
	var h := global_position.cross(vel)
	match sas_mode:
		1:
			return v.normalized() if v.length() > 0.3 else Vector3.ZERO
		2:
			return -v.normalized() if v.length() > 0.3 else Vector3.ZERO
		3:
			return h.normalized() if h.length() > 0.01 else Vector3.ZERO
		4:
			return -h.normalized() if h.length() > 0.01 else Vector3.ZERO
		5:
			return r
		6:
			return -r
	return Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if world.map_mode != 0:
		return   # на карте мышь и колесо управляют картой
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= mm.relative.x * 0.004
		cam_pitch = clampf(cam_pitch + mm.relative.y * 0.004, -1.2, 1.4)
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(6.0, cam_dist - 2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(400.0, cam_dist * 1.15 + 1.0)


func _physics_process(dt: float) -> void:
	if crashed:
		return
	# повороты в осях корабля: W/S — тангаж, A/D — рыскание, Q/E — крен
	var rate: float = D.SHIP_TURN * dt
	var manual := false
	for key in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_Q, KEY_E]:
		if Input.is_key_pressed(key):
			manual = true
	if not manual and sas_mode > 0:
		# автопилот: доворачиваем нос к нужному направлению
		var target := sas_target()
		var nose_dir := global_transform.basis.y.normalized()
		if target != Vector3.ZERO:
			var ang := nose_dir.angle_to(target)
			if ang > 0.002:
				var axis := nose_dir.cross(target)
				if axis.length() < 0.000001:
					axis = global_transform.basis.x
				global_transform.basis = Basis(axis.normalized(), minf(ang, rate)) * global_transform.basis
	if Input.is_key_pressed(KEY_W):
		rotate_object_local(Vector3.RIGHT, -rate)
	if Input.is_key_pressed(KEY_S):
		rotate_object_local(Vector3.RIGHT, rate)
	if Input.is_key_pressed(KEY_A):
		rotate_object_local(Vector3.BACK, rate)
	if Input.is_key_pressed(KEY_D):
		rotate_object_local(Vector3.BACK, -rate)
	if Input.is_key_pressed(KEY_Q):
		rotate_object_local(Vector3.UP, rate)
	if Input.is_key_pressed(KEY_E):
		rotate_object_local(Vector3.UP, -rate)

	# дроссель: Shift — больше, Ctrl — меньше, Z — полный, X — ноль; Space — полная тяга, пока держишь
	if Input.is_key_pressed(KEY_SHIFT):
		throttle = minf(1.0, throttle + D.THROTTLE_RATE * dt)
	if Input.is_key_pressed(KEY_CTRL):
		throttle = maxf(0.0, throttle - D.THROTTLE_RATE * dt)
	if Input.is_key_pressed(KEY_Z):
		throttle = 1.0
	if Input.is_key_pressed(KEY_X):
		throttle = 0.0
	power = 1.0 if Input.is_key_pressed(KEY_SPACE) else throttle
	thrusting = power > 0.001 and fuel > 0.0
	if thrusting:
		var f: float = float(D.SHIP_KINDS[kind].thrust) * power
		vel += global_transform.basis.y.normalized() * (f / mass()) * dt
		# расход массы: тяга / скорость истечения
		fuel = maxf(0.0, fuel - f / D.SCOUT_VE * dt / D.FUEL_UNIT_MASS)
		landed = false
	flame.scale = Vector3(1, maxf(0.2, power), 1)

	if not landed:
		var r := global_position.length()
		vel -= global_position.normalized() * (body_mu() / (r * r)) * dt
		global_position += vel * dt
		if pn < 0:
			_space_step()
			flame.visible = thrusting
			return
		if global_position.length() > SkyCalc.soi(pn):
			_leave_soi()
			flame.visible = thrusting
			return
		cell_hint = world.planet.walk(cell_hint, global_position.normalized())
		var ground: float = world.planet.top_r(cell_hint) + 0.05
		if global_position.length() < ground:
			var impact := vel.length()
			global_position = global_position.normalized() * ground
			vel = Vector3.ZERO
			if impact > D.SHIP_CRASH_SPEED:
				crashed = true
				world.on_ship_crash(self)
				return
			landed = true
			if sas_mode == 2:
				sas_mode = 0   # сели — автопилот посадки больше не нужен
		# снижаемся у поверхности — автопилот сам разворачивает «против движения»
		var alt := altitude()
		if alt < D.AUTO_RETRO_ALT and vel.dot(global_position.normalized()) < -1.0 and not auto_retro_done:
			auto_retro_done = true
			sas_mode = 2
			world.on_auto_retro()
		elif alt > D.AUTO_RETRO_ALT + 30.0:
			auto_retro_done = false
	flame.visible = thrusting


## Вылетели за сферу влияния луны: переходим в систему гиганта.
func _leave_soi() -> void:
	var t: float = world.world_time
	var ft := SkyCalc.frame(pn, t).transposed()
	global_position = SkyCalc.planet_pos(pn, t) + ft * global_position
	vel = SkyCalc.planet_vel(pn, t) + ft * vel
	global_transform.basis = ft * global_transform.basis
	pn = -1
	world.on_ship_soi(-1)


## Открытый космос: упали в гигант — крушение; вошли в сферу луны — переходим в её систему.
func _space_step() -> void:
	if global_position.length() < D.GIANT_R:
		crashed = true
		world.on_ship_crash(self)
		return
	var t: float = world.world_time
	for j in D.PLANETS.size():
		var d := global_position - SkyCalc.planet_pos(j, t)
		if d.length() < SkyCalc.soi(j):
			var f := SkyCalc.frame(j, t)
			global_position = f * d
			vel = f * (vel - SkyCalc.planet_vel(j, t))
			global_transform.basis = f * global_transform.basis
			pn = j
			cell_hint = -1
			world.on_ship_soi(j)
			return


func _process(_dt: float) -> void:
	# камера летает вокруг корабля в осях «над поверхностью»
	var up := global_position.normalized()
	var helper := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var t1 := up.cross(helper).normalized()
	var t2 := up.cross(t1)
	var flat := (t1 * cos(cam_yaw) + t2 * sin(cam_yaw)) * cos(cam_pitch)
	var center := global_position + up * 2.0
	cam.global_position = center + (flat + up * sin(cam_pitch)) * cam_dist
	cam.look_at(center, up)
