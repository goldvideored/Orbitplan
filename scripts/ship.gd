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


func setup(w, id: int, model: Node3D, fuel_units: float, planet_n: int) -> void:
	world = w
	pn = planet_n
	ship_id = id
	fuel = fuel_units
	add_child(model)
	flame = model.get_meta("flame")
	cam = Camera3D.new()
	cam.fov = 75
	cam.near = 0.1
	cam.far = 15000
	add_child(cam)
	cam.top_level = true   # камера не крутится вместе с кораблём


func mass() -> float:
	return D.SCOUT_DRY + fuel * D.FUEL_UNIT_MASS


## Сколько ещё можно разогнаться (формула Циолковского).
func dv() -> float:
	return D.SCOUT_VE * log(mass() / D.SCOUT_DRY)


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

	thrusting = Input.is_key_pressed(KEY_SPACE) and fuel > 0.0
	if thrusting:
		vel += global_transform.basis.y.normalized() * (D.SCOUT_THRUST / mass()) * dt
		# расход массы: тяга / скорость истечения
		fuel = maxf(0.0, fuel - D.SCOUT_THRUST / D.SCOUT_VE * dt / D.FUEL_UNIT_MASS)
		landed = false

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
