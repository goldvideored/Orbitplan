extends Node3D
## Фон главного меню: справа — планета, на которой идёт война (две стороны занимают по 40% поверхности,
## между ними — нейтральная полоса, где дерутся юниты и рвутся снаряды); слева внизу — маленькая планета
## с площадкой, с которой взлетает разведчик, облетает большую планету и садится обратно.

const D = preload("res://scripts/defs.gd")
const Planet = preload("res://scripts/planet.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const MOON_SHADER = preload("res://shaders/moon_far.gdshader")
const UNIT_SHADER = preload("res://shaders/unit.gdshader")
const World = preload("res://scripts/world.gd")
const Icons = preload("res://scripts/icons.gd")

const CAM_DIST := 300.0
const FOV := 50.0
const TARGET := 0.4          # доля планеты у каждой стороны
const UNIT_COUNTS := [24, 10, 3]      # танки, дроны, мехи у каждой стороны
const UNIT_SPEED := [4.0, 11.0, 2.2]  # м/с
const UNIT_HP := [3, 1, 14]
const UNIT_RANGE := [18.0, 0.0, 28.0]
const MAX_BUILDINGS := 170
# что строится внутри территории (повторы — чаще)
const BUILD_POOL := [D.SOLAR, D.SOLAR, D.SMELTER, D.CRUSHER, D.COAL_PLANT, D.TURRET, D.TURRET, D.TURRET2,
	D.WALL, D.WALL, D.LAMP, D.POWER_POLE, D.ASSEMBLER, D.BATTERY, D.CHIP_FACTORY, D.AA_GUN, D.REPAIR,
	D.MELTER, D.CENTRIFUGE, D.TURRET3, D.NUCLEAR, D.LAUNCH_PAD, D.LOADER, D.UNIT_REPAIR, D.FUEL_SYNTH]
const ROCKET_CYCLE := 26.0   # с: стоит на площадке + полёт
const ROCKET_WAIT := 4.0
const ROCKET_SCALE := 3.0    # ракета крупнее настоящей, чтобы её было видно

var planet: Planet
var pnode: Node3D            # всё, что на большой планете (вращается вместе с ней)
var cam: Camera3D
var axis := Vector3(1.0, 0.25, 0.0).normalized()   # ось «синие — красные»
var own := PackedInt32Array()   # чья клетка: -1 ничья, 0 синие, 1 красные
var frontier: Array = [[], []]
var owned: Array = [[], []]   # клетки каждой стороны (для спавна)
var counts := [0, 0]
var mm_plates: MultiMesh
var world: World               # игровой мир без сети — рисует постройки и юнитов как в игре
var mm_kind: Array = []       # мультимеши танков, дронов, мехов
var bld_count := 0
var asm_ids: Array = []
var turret_acc := 0.0
var units: Array = []         # {team, kind, dir, target, hp, dead, cell, face}
var beams: Array = []         # [from, to, team, до какого времени]
var shells: Array = []        # {a, b, t, team}
var mm_shells: MultiMesh
var beam_mesh: ImmediateMesh
var booms: Array = []         # пул вспышек
var boom_i := 0
var fight_acc := 0.0
var shell_acc := 0.0
var now := 0.0

# ракета
var moon_c := Vector3.ZERO
var moon_r := 40.0
var pad := Vector3.ZERO
var pad_up := Vector3.UP
var rocket: Node3D
var flame: MeshInstance3D
var path: Curve3D
var path_len := 1.0
var rocket_t := 0.0
var last_size := Vector2.ZERO


func _ready() -> void:
	_set_globals()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.025)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.27, 0.35)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -_sun_dir(), Vector3.UP)
	sun.light_energy = 1.3

	cam = Camera3D.new()
	cam.fov = FOV
	cam.far = 8000.0
	cam.position = Vector3(0, 0, CAM_DIST)
	add_child(cam)
	cam.current = true
	_frame_camera()

	_build_stars()
	_build_planet()
	_build_moon_and_rocket()


func _set_globals() -> void:
	RenderingServer.global_shader_parameter_set("sun_dir", _sun_dir())
	RenderingServer.global_shader_parameter_set("sun_level", 1.0)
	RenderingServer.global_shader_parameter_set("giant_dir", Vector3(-0.3, 0.8, -0.5).normalized())
	RenderingServer.global_shader_parameter_set("giant_level", 0.6)
	RenderingServer.global_shader_parameter_set("flash_on", 0.0)
	RenderingServer.global_shader_parameter_set("land_on", 0.0)
	RenderingServer.global_shader_parameter_set("space_mode", 0.0)
	RenderingServer.global_shader_parameter_set("lamp_count", 0)


func _sun_dir() -> Vector3:
	return Vector3(0.35, 0.45, 0.82).normalized()   # спереди-сверху-справа: видимая сторона освещена


## Камера смотрит на центр большой планеты, а сдвигом кадра планета уезжает в правую часть экрана.
func _frame_camera() -> void:
	var sz := get_viewport().get_visible_rect().size
	last_size = sz
	var f := (sz.y * 0.5) / tan(deg_to_rad(FOV * 0.5))
	cam.h_offset = -(0.25 * sz.x) * CAM_DIST / f
	cam.v_offset = (0.03 * sz.y) * CAM_DIST / f


func _build_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 700
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 5.0
	mm.mesh = bm
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var s := rng.randf_range(0.4, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), d * 4000.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.88, 1.0)
	mi.material_override = m
	add_child(mi)


func _unshaded(col: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _shaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m


func _vc_material(unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _mm(mesh: Mesh, count: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = count
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	pnode.add_child(mi)
	return mm


func _up_basis(up: Vector3, s: Vector3) -> Basis:
	var h := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var x := up.cross(h).normalized()
	var z := x.cross(up)
	return Basis(x * s.x, up * s.y, z * s.z)


# ---------------------------------------------------------------------
# Большая планета и война. Постройки и юниты рисует тот же код, что в игре (world.gd):
# создаём мир без сети и без обработки кадров и зовём его функции отрисовки.
# ---------------------------------------------------------------------

func _build_planet() -> void:
	planet = Planet.new()
	planet.generate(20260)
	pnode = Node3D.new()
	add_child(pnode)
	var built: Array = planet.build_mesh()
	var terrain := MeshInstance3D.new()
	terrain.mesh = built[0]
	var tmat := ShaderMaterial.new()
	tmat.shader = TERRAIN_SHADER
	terrain.material_override = tmat
	pnode.add_child(terrain)

	# мир-витрина: только отрисовка
	world = World.new()
	add_child(world)
	world.set_process(false)
	world.set_process_unhandled_input(false)
	world.planet = planet
	world.local_root = pnode
	world.my_pn = 0
	world.icon_atlas = Icons.build_atlas()
	world.sky_state = {"sun": _sun_dir()}
	var umat := ShaderMaterial.new()
	umat.shader = UNIT_SHADER
	world.mm_units = world._make_mm(world._tank_mesh(umat), 128, false)
	world.mm_drones = world._make_mm(world._drone_mesh(umat), 64, false)
	world.mm_mechs = world._make_mm(world._mech_mesh(umat), 16, false)
	mm_kind = [world.mm_units, world.mm_drones, world.mm_mechs]

	var n := planet.count()
	own.resize(n)
	own.fill(-1)
	var plate := CylinderMesh.new()
	plate.top_radius = 1.0
	plate.bottom_radius = 1.0
	plate.height = 0.03
	plate.radial_segments = 6
	plate.rings = 1
	mm_plates = _mm(plate, n, _vc_material(false))
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for c in n:
		mm_plates.set_instance_transform(c, zero)

	var sb := SphereMesh.new()
	sb.radius = 0.6
	sb.height = 1.2
	sb.radial_segments = 6
	sb.rings = 3
	mm_shells = _mm(sb, 32, _vc_material(true))

	beam_mesh = ImmediateMesh.new()
	var bmi := MeshInstance3D.new()
	bmi.mesh = beam_mesh
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bmi.material_override = bm
	pnode.add_child(bmi)

	for i in 24:
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 8
		s.rings = 4
		b.mesh = s
		b.material_override = _unshaded(Color(1.0, 0.6, 0.2), 0.8)
		b.visible = false
		pnode.add_child(b)
		booms.append({"n": b, "t": 0.0, "r": 3.0})

	# ядра сторон, вокруг — стартовые 15%; дальше территория и базы дорастают у тебя на глазах
	var starts := [planet.nearest_cell(axis), planet.nearest_cell(-axis)]
	for t in 2:
		_claim(starts[t], t)
		var r := planet.rings(int(starts[t]), 3)
		for x in r:
			_claim(int(x), t)
		_place(D.CORE, int(starts[t]), 0, t, true)
	while counts[0] < n * 0.15 or counts[1] < n * 0.15:
		for t in 2:
			_grow(t)
	for t in 2:
		for k in 3:
			for i in UNIT_COUNTS[k]:
				units.append({"team": t, "kind": k, "dir": Vector3.ZERO, "target": Vector3.ZERO,
					"hp": 1, "dead": 0.0, "cell": -1, "face": Vector3.ZERO})
	for u in units:
		_respawn(u)


func _claim(c: int, t: int) -> void:
	if own[c] == t:
		return
	if own[c] >= 0:
		counts[own[c]] -= 1
	own[c] = t
	counts[t] += 1
	owned[t].append(c)
	frontier[t].append(c)
	var up: Vector3 = planet.dirs[c]
	var col: Color = D.TEAM_COLORS[t]
	mm_plates.set_instance_transform(c, Transform3D(_up_basis(up, Vector3(0.95, 1, 0.95)), planet.top_pos(c) + up * 0.015))
	mm_plates.set_instance_color(c, col.darkened(0.55))
	if bld_count < MAX_BUILDINGS and randf() < 0.045:
		_try_build(c, t)


## Свободно ли место под постройку стороны t (все клетки её, не заняты, не скалы).
func _fits(type: int, cell: int, dir: int, t: int) -> Array:
	var foot: Array = world._footprint(type, cell, dir)
	if foot.size() != world._size_of(type):
		return []
	for x in foot:
		if own[x] != t or world.grid.has(world._k(0, x)) or planet.level[x] >= D.MAX_LEVEL:
			return []
	return foot


func _place(type: int, cell: int, dir: int, t: int, main := false) -> int:
	var id: int = world._new_id()
	world._add_building({"id": id, "type": type, "team": t, "cell": cell, "dir": dir, "pn": 0,
		"bt": 1.0 if type == D.CORE else 0.0, "main": main, "ukind": randi() % 3})
	bld_count += 1
	if type == D.ASSEMBLER:
		asm_ids.append(id)
	return id


## Что строить на новой клетке: на руде — бур, у края — оборона, внутри — производство и энергия.
func _try_build(c: int, t: int) -> void:
	var nb: PackedInt32Array = planet.nbrs[c]
	var dir := randi() % nb.size()
	var type: int = BUILD_POOL[randi() % BUILD_POOL.size()]
	if planet.ore[c] != D.I_NONE:
		type = [D.DRILL, D.DRILL, D.DRILL2, D.DRILL3][randi() % 4]
	var foot := _fits(type, c, dir, t)
	if foot.is_empty():
		return
	if world._is_drill(type) and int(world._drill_ore(foot)[0]) == D.I_NONE:
		return
	_place(type, c, dir, t)
	if world._is_drill(type):
		_belt_from(foot, t)
	elif type == D.WALL:
		_wall_line(c, t)


## Конвейер от бура: несколько клеток примерно по прямой.
func _belt_from(foot: Array, t: int) -> void:
	var start := -1
	for f in foot:
		var nb: PackedInt32Array = planet.nbrs[f]
		for x in nb:
			if not foot.has(x) and own[x] == t and not world.grid.has(world._k(0, x)):
				start = x
				break
		if start != -1:
			break
	if start == -1:
		return
	var heading := (planet.dirs[start] - planet.dirs[foot[0]]).normalized()
	var cur := start
	for k in randi_range(3, 7):
		var nb: PackedInt32Array = planet.nbrs[cur]
		var best := -1
		var bd := 0.2
		for i in nb.size():
			var x: int = nb[i]
			if own[x] != t or world.grid.has(world._k(0, x)) or planet.level[x] >= D.MAX_LEVEL:
				continue
			var dd := (planet.dirs[x] - planet.dirs[cur]).normalized().dot(heading)
			if dd > bd:
				bd = dd
				best = i
		if best == -1:
			return
		_place(D.CONVEYOR, cur, best, t)
		heading = (planet.dirs[nb[best]] - planet.dirs[cur]).normalized()
		cur = nb[best]


## Забор — сразу несколько секций в ряд.
func _wall_line(c: int, t: int) -> void:
	var cur := c
	var prev := -1
	for k in randi_range(2, 5):
		var nb: PackedInt32Array = planet.nbrs[cur]
		var nxt := -1
		for x in nb:
			if x != prev and own[x] == t and not world.grid.has(world._k(0, x)) and planet.level[x] < D.MAX_LEVEL:
				nxt = x
				break
		if nxt == -1:
			return
		_place(D.WALL, nxt, 0, t)
		prev = cur
		cur = nxt


## Сторона t занимает одну соседнюю свободную клетку от своей границы.
func _grow(t: int) -> void:
	var fr: Array = frontier[t]
	for _try in 6:
		if fr.is_empty():
			return
		var i := randi() % fr.size()
		var c: int = fr[i]
		var open_nb: Array = []
		var nb: PackedInt32Array = planet.nbrs[c]
		for x in nb:
			if own[x] == -1:
				open_nb.append(x)
		if open_nb.is_empty():
			fr[i] = fr[fr.size() - 1]
			fr.pop_back()
			continue
		_claim(open_nb[randi() % open_nb.size()], t)
		return


func _rand_own_dir(t: int) -> Vector3:
	var o: Array = owned[t]
	return planet.dirs[o[randi() % o.size()]]


## Цель юнита — нейтральная полоса между сторонами, ближе к своему краю.
func _band_target(t: int) -> Vector3:
	var sgn := 1.0 if t == 0 else -1.0
	var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	d = (d - axis * d.dot(axis)).normalized()
	return (d + axis * sgn * randf_range(-0.05, 0.3)).normalized()


func _respawn(u: Dictionary) -> void:
	var t: int = u.team
	var d := _rand_own_dir(t)
	var fr: Array = frontier[t]
	if not fr.is_empty() and randf() < 0.6:
		d = planet.dirs[fr[randi() % fr.size()]]
	u.dir = d
	u.cell = planet.walk(-1, d)
	u.target = _band_target(t)
	u.hp = UNIT_HP[int(u.kind)]
	u.dead = 0.0


func _boom(at: Vector3, r: float) -> void:
	var b: Dictionary = booms[boom_i]
	boom_i = (boom_i + 1) % booms.size()
	b.t = 0.0
	b.r = r
	var n: MeshInstance3D = b.n
	n.position = at
	n.visible = true


func _upos(u: Dictionary) -> Vector3:
	var d: Vector3 = u.dir
	var lift := D.DRONE_ALT if int(u.kind) == 1 else 0.0
	return d * (planet.top_r(int(u.cell)) + 0.3 + lift)


func _process(delta: float) -> void:
	now += delta
	if get_viewport().get_visible_rect().size != last_size:
		_frame_camera()
	pnode.rotate(axis, delta * 0.03)
	_war_step(delta)
	_buildings_step(delta)
	_rocket_step(delta)


## Стройка, анимации, сборщики и башни турелей — функциями игрового мира.
func _buildings_step(dt: float) -> void:
	for id in world.building_set.keys():
		if not world.buildings.has(id):
			continue
		var b: Dictionary = world.buildings[id]
		if float(b.bt) >= 0.999:
			b.bt = 1.0
			world.building_set.erase(id)
			world._on_build_state(b)
	# сборщики по кругу собирают юнитов: рука с лазером, юнит растёт на площадке
	for id in asm_ids:
		if not world.buildings.has(id) or world._busy(world.buildings[id]):
			continue
		var e: Array = world.asm_prog.get(id, [0.0, randi() % 3])
		var p: float = float(e[0]) + dt / 8.0
		if p >= 1.0:
			p = 0.0
			e[1] = randi() % 3
		world.asm_prog[id] = [p, e[1]]
	world._update_construction(dt)
	# турели смотрят на ближайшего врага и стреляют
	turret_acc += dt
	var fire := turret_acc >= 0.25
	if fire:
		turret_acc = 0.0
	for id in world.turret_nodes.keys():
		if not world.buildings.has(id):
			continue
		var b: Dictionary = world.buildings[id]
		if world._busy(b):
			continue
		var tp: Vector3 = planet.top_pos(int(b.cell))
		var best = null
		var bd := 45.0
		for u in units:
			if int(u.team) == int(b.team) or float(u.dead) > 0.0:
				continue
			var dd := tp.distance_to(_upos(u))
			if dd < bd:
				bd = dd
				best = u
		if best == null:
			continue
		var to := _upos(best)
		world.turret_aim[id] = pnode.global_transform.basis * (to - tp).normalized()
		if fire and randf() < 0.5:
			beams.append([tp + tp.normalized() * 1.2, to, int(b.team), now + 0.08])
			best.hp = int(best.hp) - 1
			if int(best.hp) <= 0:
				_kill(best)
	world._update_turrets(dt)


func _kill(u: Dictionary) -> void:
	u.dead = 3.0
	_boom(_upos(u), 4.0 if int(u.kind) == 2 else 2.5)


func _war_step(dt: float) -> void:
	var n := planet.count()
	for t in 2:
		if counts[t] < n * TARGET:
			for k in 4:
				_grow(t)
	# юниты: танки и мехи идут к полосе и стреляют, дроны ищут цель и таранят её
	var cnt := [0, 0, 0]
	for u in units:
		var kind: int = u.kind
		if float(u.dead) > 0.0:
			u.dead = float(u.dead) - dt
			if float(u.dead) <= 0.0:
				_respawn(u)
			continue
		var d: Vector3 = u.dir
		var tg: Vector3 = u.target
		if kind == 1:
			var prey = _nearest_enemy(u, 40.0)
			if prey != null:
				tg = Vector3(prey.dir)
				if _upos(u).distance_to(_upos(prey)) < 3.0:
					prey.hp = int(prey.hp) - 4
					if int(prey.hp) <= 0:
						_kill(prey)
					_kill(u)
					continue
		var ang := d.angle_to(tg)
		var step: float = float(UNIT_SPEED[kind]) * dt / D.PLANET_R
		if ang < 0.02:
			u.target = _band_target(int(u.team))
		else:
			d = d.slerp(tg, minf(1.0, step / ang)).normalized()
			u.dir = d
			u.cell = planet.walk(int(u.cell), d)
		var f := (tg - d * tg.dot(d))
		if f.length() > 0.001:
			u.face = f.normalized()
		var face: Vector3 = u.face
		var bas := Basis(face.cross(d), d, -face) if face.length() > 0.5 else _up_basis(d, Vector3.ONE)
		var mm: MultiMesh = mm_kind[kind]
		var c: int = cnt[kind]
		if c < mm.instance_count:
			mm.set_instance_transform(c, Transform3D(bas, _upos(u) - d * 0.3))
			var col: Color = D.TEAM_COLORS[int(u.team)]
			# a >= 0.5 — юнит идёт: в шейдере шагают ноги, бегут траки
			mm.set_instance_custom_data(c, Color(col.r, col.g, col.b, 0.5 + 0.49 * clampf(float(u.hp) / float(UNIT_HP[kind]), 0.3, 1.0)))
			cnt[kind] = c + 1
	for k in 3:
		(mm_kind[k] as MultiMesh).visible_instance_count = cnt[k]
	fight_acc += dt
	if fight_acc >= 0.2:
		fight_acc = 0.0
		for u in units:
			var kind: int = u.kind
			if float(u.dead) > 0.0 or kind == 1 or randf() < 0.4:
				continue
			var best = _nearest_enemy(u, UNIT_RANGE[kind])
			if best == null:
				continue
			var from := _upos(u) + Vector3(u.dir) * (1.6 if kind == 2 else 0.6)
			beams.append([from, _upos(best), int(u.team), now + 0.09])
			best.hp = int(best.hp) - (3 if kind == 2 else 1)
			if int(best.hp) <= 0:
				_kill(best)
	# артиллерия: снаряды навесом из глубины своей территории в полосу у врага
	shell_acc += dt
	if shell_acc >= 0.7 and shells.size() < 30:
		shell_acc = 0.0
		var t := randi() % 2
		shells.append({"a": _rand_own_dir(t), "b": _band_target(1 - t), "t": 0.0, "team": t})
	var si := 0
	for s in shells:
		s.t = float(s.t) + dt / 2.5
	shells = shells.filter(func(sh): return float(sh.t) < 1.0 or _shell_land(sh))
	for s in shells:
		var k: float = s.t
		var a: Vector3 = s.a
		var p := a.slerp(s.b, k).normalized() * (D.PLANET_R + 1.0 + 35.0 * sin(PI * k))
		mm_shells.set_instance_transform(si, Transform3D(Basis.IDENTITY, p))
		mm_shells.set_instance_color(si, D.TEAM_COLORS[int(s.team)].lightened(0.5))
		si += 1
	mm_shells.visible_instance_count = si
	# лучи выстрелов
	beam_mesh.clear_surfaces()
	beams = beams.filter(func(bm): return float(bm[3]) > now)
	if not beams.is_empty():
		beam_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for b in beams:
			var col: Color = D.TEAM_COLORS[int(b[2])].lightened(0.5)
			beam_mesh.surface_set_color(col)
			beam_mesh.surface_add_vertex(b[0])
			beam_mesh.surface_set_color(col)
			beam_mesh.surface_add_vertex(b[1])
		beam_mesh.surface_end()
	# вспышки
	for b in booms:
		var n3: MeshInstance3D = b.n
		if not n3.visible:
			continue
		b.t = float(b.t) + dt
		var k2: float = float(b.t) / 0.6
		if k2 >= 1.0:
			n3.visible = false
			continue
		n3.scale = Vector3.ONE * float(b.r) * (0.3 + k2)
		var bmat: StandardMaterial3D = n3.material_override
		var bc := bmat.albedo_color
		bc.a = 0.85 * (1.0 - k2)
		bmat.albedo_color = bc


func _nearest_enemy(u: Dictionary, rng: float):
	var best = null
	var bd := rng
	var p := _upos(u)
	for o in units:
		if int(o.team) == int(u.team) or float(o.dead) > 0.0:
			continue
		var dd := p.distance_to(_upos(o))
		if dd < bd:
			bd = dd
			best = o
	return best


## Снаряд долетел: взрыв. Возвращает false, чтобы фильтр его убрал.
func _shell_land(s: Dictionary) -> bool:
	_boom(Vector3(s.b) * (D.PLANET_R + 1.0), 4.5)
	return false


# ---------------------------------------------------------------------
# Маленькая планета слева и ракета-разведчик
# ---------------------------------------------------------------------

func _build_moon_and_rocket() -> void:
	var sz := get_viewport().get_visible_rect().size
	moon_c = cam.project_position(Vector2(sz.x * 0.07, sz.y * 1.02), CAM_DIST + 40.0)
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = moon_r
	sm.height = moon_r * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	moon.mesh = sm
	var mmat := ShaderMaterial.new()
	mmat.shader = MOON_SHADER
	moon.material_override = mmat
	moon.position = moon_c
	add_child(moon)
	# площадка — сверху-справа на маленькой планете
	pad_up = Vector3(0.45, 1.0, 0.25).normalized()
	pad = moon_c + pad_up * moon_r
	var pn := Node3D.new()
	pn.transform = Transform3D(_up_basis(pad_up, Vector3.ONE), pad)
	add_child(pn)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(9, 0.6, 9)
	deck.mesh = dm
	deck.material_override = _shaded(Color(0.32, 0.32, 0.36))
	deck.position = Vector3(0, 0.3, 0)
	pn.add_child(deck)
	for c in [Vector3(4, 0.7, 4), Vector3(-4, 0.7, 4), Vector3(4, 0.7, -4), Vector3(-4, 0.7, -4)]:
		var l := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3.ONE * 0.6
		l.mesh = lm
		l.material_override = _unshaded(Color(1.0, 0.3, 0.2))
		l.position = c
		pn.add_child(l)
	var tower := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.8, 14, 0.8)
	tower.mesh = tm
	tower.material_override = _shaded(Color(0.75, 0.35, 0.15))
	tower.position = Vector3(3.6, 7, 3.6)
	pn.add_child(tower)

	rocket = _make_rocket()
	add_child(rocket)
	_build_path()


func _make_rocket() -> Node3D:
	var r := Node3D.new()
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * ROCKET_SCALE
	r.add_child(inner)
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.7
	bm.bottom_radius = 0.7
	bm.height = 3.0
	body.mesh = bm
	body.position = Vector3(0, 2.1, 0)
	body.material_override = _shaded(Color(0.88, 0.88, 0.9))
	inner.add_child(body)
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.7
	nm.height = 1.3
	nose.mesh = nm
	nose.position = Vector3(0, 4.25, 0)
	nose.material_override = _shaded(D.TEAM_COLORS[0])
	inner.add_child(nose)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.4, 0.4, 0.1)
	win.mesh = wm
	win.position = Vector3(0, 3.0, 0.68)
	win.material_override = _unshaded(Color(0.4, 0.85, 1.0))
	inner.add_child(win)
	for i in 3:
		var a := TAU * i / 3.0
		var fin := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.08, 1.0, 0.6)
		fin.mesh = fm
		fin.position = Vector3(cos(a) * 0.85, 1.0, sin(a) * 0.85)
		fin.rotation.y = -a
		fin.material_override = _shaded(Color(0.25, 0.25, 0.28))
		inner.add_child(fin)
	flame = MeshInstance3D.new()
	var flm := CylinderMesh.new()
	flm.top_radius = 0.45
	flm.bottom_radius = 0.0
	flm.height = 2.4
	flame.mesh = flm
	flame.position = Vector3(0, -0.6, 0)
	flame.material_override = _unshaded(Color(1.0, 0.6, 0.2))
	inner.add_child(flame)
	return r


## Маршрут: вертикальный взлёт с площадки, виток вокруг большой планеты, возвращение и посадка.
func _build_path() -> void:
	var pts: Array = []
	pts.append(pad)
	pts.append(pad + pad_up * 15.0)
	pts.append(pad + pad_up * 55.0 + (-pad).normalized() * 25.0)
	# виток по наклонённой окружности вокруг большой планеты
	var r := 150.0
	var e1 := (pad + pad_up * 60.0).normalized()
	var e2 := e1.cross(Vector3(0.2, 0.3, 1.0).normalized()).normalized()
	e1 = e2.cross(e1.cross(e2)).normalized()
	for k in 9:
		var a := TAU * (k + 0.5) / 9.0
		pts.append((e1 * cos(a) + e2 * sin(a)) * r)
	pts.append(pad + pad_up * 60.0 + (-pad).normalized() * 10.0)
	pts.append(pad + pad_up * 18.0)
	pts.append(pad + pad_up * 3.0)
	pts.append(pad)
	path = Curve3D.new()
	path.bake_interval = 1.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var tg := Vector3.ZERO
		if i > 0 and i < pts.size() - 1:
			tg = (Vector3(pts[i + 1]) - Vector3(pts[i - 1])) / 6.0
		path.add_point(p, -tg, tg)
	path_len = path.get_baked_length()


func _rocket_step(dt: float) -> void:
	rocket_t = fmod(rocket_t + dt, ROCKET_CYCLE)
	if rocket_t < ROCKET_WAIT:
		rocket.transform = Transform3D(_up_basis(pad_up, Vector3.ONE), pad)
		flame.visible = false
		return
	var u := (rocket_t - ROCKET_WAIT) / (ROCKET_CYCLE - ROCKET_WAIT)
	var off := path_len * (u - sin(TAU * u) / TAU)   # плавный разгон и плавное торможение у площадки
	var p := path.sample_baked(off)
	var ahead := path.sample_baked(minf(off + 2.0, path_len))
	var vel := ahead - p
	var nose := vel.normalized() if vel.length() > 0.01 else pad_up
	var dpad := p.distance_to(pad)
	if u > 0.5:
		# заход на посадку: разворот хвостом вниз, тормозит двигателем
		nose = pad_up.slerp(nose, clampf((dpad - 25.0) / 60.0, 0.0, 1.0))
	else:
		nose = pad_up.slerp(nose, clampf((dpad - 10.0) / 40.0, 0.0, 1.0))
	rocket.transform = Transform3D(_up_basis(nose, Vector3.ONE), p)
	flame.visible = true
	flame.scale = Vector3(1.0, randf_range(0.7, 1.3), 1.0)
