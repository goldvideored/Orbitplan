extends Node3D
## Игровой мир: одна круглая планета.
## На сервере: симуляция (буры, конвейеры, сборщики, турели, юниты, персонажи).
## На клиенте: отрисовка, камера, ввод. Хост делает и то и другое.

const D = preload("res://scripts/defs.gd")
const Planet = preload("res://scripts/planet.gd")
const Player = preload("res://scripts/player.gd")
const SkyCalc = preload("res://scripts/sky.gd")
const RadialMenu = preload("res://scripts/radial_menu.gd")
const Icons = preload("res://scripts/icons.gd")
const Ship = preload("res://scripts/ship.gd")
const Compass = preload("res://scripts/compass.gd")
const Navball = preload("res://scripts/navball.gd")
const MOON_SHADER = preload("res://shaders/moon_far.gdshader")
const UNIT_SHADER = preload("res://shaders/unit.gdshader")
# роль детали юнита — альфа цвета вершины (см. unit.gdshader)
const PAINT := 0.0    # краска команды
const GLOW := 0.7     # светится сама
const METAL := 1.0
const IN_SHIP := -2   # «что в руке» = сидит в корабле (аватар прячем)
const ICON_SHADER = preload("res://shaders/icon.gdshader")
const SUIT_COLOR := Color(0.88, 0.88, 0.9)
const FAR_VIEW := 90.0   # дальше этого (м от камеры) игроки рисуются стрелками
const LIT_SHADER = preload("res://shaders/lit16.gdshader")
const GIANT_SHADER = preload("res://shaders/giant.gdshader")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const RINGS_SHADER = preload("res://shaders/rings.gdshader")
const SKY_SHADER = preload("res://shaders/sky.gdshader")
const ORBIT_SHADER = preload("res://shaders/orbit.gdshader")
const ATMO_SHADER = preload("res://shaders/atmo.gdshader")
const NO_CELL := -1
# цвета орбит планет на карте (и подписи того же цвета)
const PLANET_COLORS := [Color(1.0, 0.6, 0.3), Color(0.35, 0.8, 1.0), Color(0.45, 1.0, 0.45),
	Color(0.8, 0.5, 1.0), Color(1.0, 0.9, 0.35)]
const CORE_H := 1.1   # высота основания ядра

# состояние постройки -> цвет огонька-индикатора
const ST_IDLE := 0    # ждёт (нет сырья, темно)
const ST_OK := 1      # работает
const ST_SLOW := 2    # работает медленно (мало энергии)
const ST_STOP := 3    # стоит (некуда отдавать, нет энергии, нет воды)
const STATE_COLORS := [Color(0.55, 0.55, 0.6), Color(0.2, 1.0, 0.3), Color(1.0, 0.8, 0.15), Color(1.0, 0.15, 0.1)]
# высота огонька над постройкой (в локальных координатах декора)
const IND_H := {
	D.CORE: 2.4, D.DRILL: 2.15, D.DRILL2: 1.95, D.DRILL3: 3.3, D.SOLAR: 1.5,
	D.COAL_PLANT: 1.4, D.NUCLEAR: 2.4, D.SMELTER: 1.45, D.CRUSHER: 1.5, D.MELTER: 1.55,
	D.CENTRIFUGE: 2.1, D.FUEL_SYNTH: 1.7, D.TURRET: 1.1, D.ASSEMBLER: 1.7,
	D.LOADER: 1.45, D.UNLOADER: 1.2, D.CHIP_FACTORY: 1.45, D.TURRET2: 1.1, D.TURRET3: 1.3,
	D.LAUNCH_PAD: 0.4, D.SPACE_DOCK: 1.5, D.UALLOY_FORGE: 1.9, D.UCHIP_FAB: 1.5, D.UFUEL_REF: 2.2, D.TURRET4: 1.9, D.AA_GUN: 1.25, D.REPAIR: 2.0, D.UNIT_REPAIR: 1.35, D.POWER_POLE: 2.9, D.BATTERY: 1.55,
}

var my_team := 0
var is_server := false
var headless := false
var planet: Planet          # планета, на которой сейчас этот клиент (= planets[my_pn])
var planets: Array = []     # у каждой планеты своя геометрия: размер, рельеф, руды
var aim_r := 84.0           # сервер: радиус планеты для баллистики текущей турели

# --- общее состояние (есть у всех) ---
var grid := {}       # ключ _k(pn, клетка) -> id постройки (у каждой планеты своя сетка)
var my_pn := D.HOME_PLANET   # на какой планете сейчас этот клиент
var buildings := {}  # id -> Dictionary
var storage := [D.START_STORAGE.duplicate(), D.START_STORAGE.duplicate(), {}]   # предмет -> количество (нейтралам не нужен)
var power_stats := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]   # [выработка, спрос] по командам
var base_count := [1, 1, D.PLANETS.size()]   # сколько ядер у каждой команды
var cur_caps: Array = []
var unit_stat: Array = []     # [[танки, дроны, мехи, лимит×3] по командам]
var alert_last := {}          # сервер: когда последний раз тревожили «команда:планета»
var alerts: Array = []        # клиент: [текст, до какого времени показывать]
var alert_marks := {}         # клиент: планета -> до какого времени показывать ⚠ на карте
var alert_labels: Array = []  # метки ⚠ у планет в виде системы      # захваты на моей планете: [id ядра, команда, кто захватывает, прогресс 0..1, прочность 0..1]
var finished := false

# --- только сервер ---
var units: Array = []   # {id, team, dir: Vector3, cell, hp, cd}
var next_id := 1
var next_unit_id := 1
var tick_acc := 0.0
var players := {}       # peer_id -> {team, pos, fwd, hp, dead_t, last_shot}
var power_dirty := true # пересобрать энергосети (после стройки/сноса)
var rovers: Array = []  # {id, team, home, dir, cell, fwd, state, cargo_item, cargo_n, target}
var projectiles: Array = []   # {pos, vel, team, kind (0 пуля, 1 снаряд-свинец, 2 снаряд-уран), dmg, ttl, cell}
var creative := false         # бесконечные ресурсы и боеприпасы
var ships := {}               # id -> {id, team, pad, pos, quat, state (0 стоит, 1 летит), pilot, fuel, thrust}
var next_ship_id := 1
var next_rover_id := 1
var power_root := {}    # id постройки -> id корня её энергосети
var power_has_gen := {} # корень -> есть ли в сети генератор
var building_set := {}  # id построек, которые сейчас строятся или сносятся
var asm_nodes := {}     # клиент: id сборщика -> узел с собираемым юнитом
var asm_prog := {}      # клиент: id сборщика -> [готовность 0..1, тип юнита]
var unit_lights: Array = []   # клиент: фары юнитов [где, куда смотрит]
var rover_lights: Array = []  # клиент: фары курьеров
var sim_n := 0                # сервер: номер тика (для «по ленте недавно что-то ехало»)
var threat_pns := PackedInt32Array()   # клиент: планеты, где сейчас вражеский корабль у нас (баннер тревоги)
var nav_target := -1    # помощник перелёта: планета-цель (-1 — выключен)
var plan := {}          # расчёт перелёта к цели
var plan_traj: MeshInstance3D
var plan_label: Label3D
var death_t := -1.0     # клиент: сколько секунд прошло с гибели (-1 — жив)
var death_pos := Vector3.ZERO
var death_pn := 0
var death_pick := -1    # выбранная база для возрождения
var bstate := {}        # клиент: id -> состояние ST_* (для скорости анимаций)
var anim_nodes := {}    # клиент: id -> корневой узел постройки с анимацией (рука сборщика, вертушка разветвителя)

# --- только клиент ---
var bnodes := {}
var mats := {}
var orbit_cam: Camera3D
var orbit_yaw := 0.0
var orbit_pitch := 0.0
var orbit_dist := 230.0
var ghost: Node3D
var ghost_mat: StandardMaterial3D
var ghost_foot: MeshInstance3D    # контур будущей постройки по клеткам
var ghost_arrow: Node3D           # куда смотрит постройка
var ghost_cover: MeshInstance3D   # зона питания генератора
var ghost_key := ""
var radial: RadialMenu
var inspect_cell := NO_CELL
var inspect_info: Array = []   # постройка под прицелом: [тип, состояние, текст, прочность, прогресс, предметы, команда]
var ui := {}                   # виджеты панели справа
var inspect_acc := 0.0
var help_panel: Control
var state_acc := 0
var sel_type := D.CONVEYOR
var sel_rot := 0
var mm_items: MultiMesh
var viewmodel: Node3D       # рука с предметом от первого лица
var vm_hand: Node3D         # сюда кладётся предмет
var held_type := -999       # какой предмет сейчас в руке у вида от первого лица
var vm_time := 0.0
var self_avatar: Node3D = null   # свой космонавт — виден в виде сверху
var icon_atlas: ImageTexture
var item_radial: RadialMenu    # меню выбора груза для точки выгрузки (держать E)
var unit_radial: RadialMenu    # меню выбора юнита для сборщика (держать E)
var ship_radial: RadialMenu    # меню выбора корабля для площадки (держать E)
var dock_radial: RadialMenu    # куда летит космический курьер (держать E на космопорте)
var couriers := {}             # сервер: команда -> космический курьер
var courier_respawn := [0, 0]
var cur_couriers: Array = []   # клиент: снимок курьеров
var courier_nodes := {}        # клиент: команда -> [модель, метка на карте системы]
var e_menu: RadialMenu = null  # какое меню сейчас открыто по E
var mm_drones: MultiMesh
var mm_mechs: MultiMesh
var mm_umechs: MultiMesh
var mm_sel: MultiMesh          # кольца под выделенными юнитами
var selected := {}             # id выделенных юнитов -> true
var unit_pos := {}             # id своего юнита -> где он сейчас (для выделения)
var sel_box: Control
var sel_start := Vector2.ZERO
var selecting := false
var unit_face := {}            # id юнита -> куда смотрит (по ходу движения)
var lamp_img: Image            # источники света для шейдера (лампы и свечение построек)
var lamp_tex_res: ImageTexture
var lamp_acc := 0.0
var filter_cell := NO_CELL
var cur_rovers: Array = []
var rover_nodes := {}          # id ровера -> Node3D
var turret_nodes := {}         # id турели -> декор с поворотной башней
var turret_aim := {}           # id турели -> куда целится (мировое направление)
var mm_proj: MultiMesh
var proj_pos := PackedVector3Array()
var proj_vel := PackedVector3Array()
var proj_kind := PackedByteArray()
var proj_time := 0.0
var cur_ships: Array = []
var ship_nodes := {}           # id корабля -> модель (чужие и стоящие корабли)
var piloting: Ship = null      # свой корабль, которым управляем
var piloting_id := -1
var ship_send_acc := 0.0

# --- поверхность и космос ---
var local_root: Node3D         # всё, что на поверхности текущей планеты (и её небо)
var space_root: Node3D         # вид звёздной системы: гигант, планеты, орбиты (в космосе и на карте)
var sky_moons: Array = []      # соседние планеты в небе над текущей
var space_moons: Array = []    # планеты в виде системы
var map_mode := 0              # 0 — нет карты, 1 — орбита вокруг планеты, 2 — вся система
var map_cam: Camera3D
var map_zoom := 1.0
var local_traj: MeshInstance3D
var sys_traj: MeshInstance3D
var enc_label: Label3D        # «призрак» планеты-цели в точке встречи
var map_ship_label: Label3D
var sys_ship_label: Label3D
var compass: Compass
var navball: Navball
var ap_labels: Array = []      # метки «Ап»/«Пе»: [у планеты Ап, у планеты Пе, в системе Ап, в системе Пе]
var destruct_armed := 0.0      # до какого момента ждём второе нажатие самоуничтожения
var orbit_ribbons: Array = []  # орбиты планет — ленты, толщина подстраивается под масштаб
var orbit_width := -1.0
var pred := {}                 # прогноз траектории корабля
var pred_acc := 0.0
var mm_units: MultiMesh
var big_msg: Label
var crosshair: Label
var prev_units := PackedFloat32Array()
var cur_units := PackedFloat32Array()
var cur_items := PackedVector3Array()
var cur_item_types := PackedByteArray()
var all_slots: Array = []   # все постройки по порядку + бластер (для колеса мыши)
var cur_players: Array = []
var snap_time := 0.0
var drag_mode := 0   # 0 нет, 1 строим, 2 сносим
var drag_last := NO_CELL
var player: Player = null
var fps_mode := true
var others := {}     # peer_id -> Node3D
var my_hp := D.PLAYER_HP
var send_acc := 0.0
var fire_cd := 0.0
var hover_cell := NO_CELL
var hover_dir := 0
var hover_seed := NO_CELL
var terrain_body: StaticBody3D

# --- небо и свет ---
var world_time: float = D.DAY_LENGTH * 0.25   # старт: у обоих ядер рассвет/закат
var giant_node: MeshInstance3D
var sun_node: MeshInstance3D
var stars_node: Node3D   # сфера звёздного неба
var flash_on := false
var sky_state := {}


func setup(seed_val: int, team: int, server: bool, dedicated: bool, creative_on := false) -> void:
	creative = creative_on
	my_team = team
	is_server = server
	headless = dedicated
	for j in D.PLANETS.size():
		var pl := Planet.new()
		pl.generate(seed_val + j * 7919, j)
		planets.append(pl)
	for cat in D.CATEGORIES:
		all_slots.append_array(cat[1])
	all_slots.append(D.WEAPON)
	if team >= 0:
		my_pn = D.TEAM_HOME[team]
	planet = _pl(my_pn)
	if not headless:
		_build_scene()
	if is_server:
		# главные базы команд — на своих планетах
		for t in 2:
			_add_building({"id": _new_id(), "type": D.CORE, "team": t,
				"cell": _pl(D.TEAM_HOME[t]).core_center[t], "dir": 0, "pn": D.TEAM_HOME[t], "main": true})
		# нейтральная база на каждой планете: ядро + готовая оборона
		for pn in D.PLANETS.size():
			var site: int = _pl(pn).core_center[D.T_NEUTRAL]
			var rings_by := {}   # кольцо -> клетки
			var r := _pl(pn).rings(site, 6)
			for c in r:
				var dist: int = r[c]
				if not rings_by.has(dist):
					rings_by[dist] = []
				rings_by[dist].append(c)
			_add_building({"id": _new_id(), "type": D.CORE, "team": D.T_NEUTRAL, "cell": site, "dir": 0, "pn": pn})
			_place_defense(D.TURRET, rings_by[3], D.NEUTRAL_LASERS, pn)
			_place_defense(D.TURRET2, rings_by[6], D.NEUTRAL_GUNS, pn)


## Расставить count турелей типа type равномерно по клеткам кольца (пропуская занятые места).
func _place_defense(type: int, ring: Array, count: int, pn: int) -> void:
	var n := ring.size()
	if n == 0 or count <= 0:
		return
	for k in count:
		# равные промежутки по кольцу; место занято — пробуем следующую клетку
		var start := k * n / count
		for t in n / count:
			var cell: int = ring[(start + t) % n]
			var foot := _footprint(type, cell, 0, pn)
			var ok := foot.size() == _size_of(type)
			for c in foot:
				if grid.has(_k(pn, c)) or _pl(pn).level[c] >= D.MAX_LEVEL:
					ok = false
			if ok:
				_add_building({"id": _new_id(), "type": type, "team": D.T_NEUTRAL, "cell": cell, "dir": 0, "pn": pn})
				break


# =====================================================================
# Помощники
# =====================================================================

## Ключ клетки с учётом планеты: все 5 планет — клоны одной сетки, поэтому номер клетки один и тот же.
## Геометрия планеты pn (-1 — та, где сейчас клиент).
func _pl(pn: int) -> Planet:
	if pn < 0 or pn >= planets.size():
		return planet
	return planets[pn]


func _k(pn: int, cell: int) -> int:
	return pn * 1048576 + cell


## На какой планете игрок (по последнему отчёту клиента).
func _peer_pn(peer: int) -> int:
	if players.has(peer):
		return int(players[peer].get("pn", D.HOME_PLANET))
	return D.HOME_PLANET


func _new_id() -> int:
	var i := next_id
	next_id += 1
	return i


func _size_of(type: int) -> int:
	return 7 if type == D.CORE else int(D.SIZE.get(type, 1))


## Клетки, которые займёт постройка: 1 клетка, 3 (треугольник), 9 (ромб 3×3), ядро — 7.
func _footprint(type: int, cell: int, dir: int, pn := -1) -> Array:
	var P: Planet = _pl(pn)
	var nb: PackedInt32Array = P.nbrs[cell]
	var k := nb.size()
	if type == D.CORE:
		var core_cells: Array = [cell]
		core_cells.append_array(Array(nb))
		return core_cells
	var size := _size_of(type)
	if size == 3:
		return [cell, nb[posmod(dir, k)], nb[posmod(dir + 1, k)]]
	if size == 9:
		var o: Vector3 = P.dirs[cell]
		var v1: Vector3 = P.dirs[nb[posmod(dir, k)]] - o
		var v2: Vector3 = P.dirs[nb[posmod(dir + 1, k)]] - o
		var rhombus: Array = []
		for a in [-1.0, 0.0, 1.0]:
			for bb in [-1.0, 0.0, 1.0]:
				var p: Vector3 = (o + v1 * float(a) + v2 * float(bb)).normalized()
				var c := P.walk(cell, p)
				if not rhombus.has(c):
					rhombus.append(c)
		return rhombus   # у пятиугольника может выйти меньше 9 — тогда ставить нельзя
	if size == 12:
		var o2: Vector3 = P.dirs[cell]
		var w1: Vector3 = P.dirs[nb[posmod(dir, k)]] - o2
		var w2: Vector3 = P.dirs[nb[posmod(dir + 1, k)]] - o2
		var par: Array = []
		for a in [-1.0, 0.0, 1.0, 2.0]:
			for bb in [-1.0, 0.0, 1.0]:
				var p2: Vector3 = (o2 + w1 * float(a) + w2 * float(bb)).normalized()
				var c2 := P.walk(cell, p2)
				if not par.has(c2):
					par.append(c2)
		return par   # 4 тир — параллелограмм 4×3
	return [cell]


## Какую руду добывает бур на этих клетках: [тип, сколько клеток с ней].
func _drill_ore(cells: Array, pn := -1) -> Array:
	var P: Planet = _pl(pn)
	var cnt := {}
	for c in cells:
		var o: int = P.ore[c]
		if o != D.I_NONE:
			cnt[o] = int(cnt.get(o, 0)) + 1
	var best := D.I_NONE
	var bn := 0
	for o in cnt:
		if int(cnt[o]) > bn:
			bn = cnt[o]
			best = o
	return [best, bn]


func _foot_center(cells: Array, pn := -1) -> Vector3:
	var P: Planet = _pl(pn)
	var d := Vector3.ZERO
	var r := 0.0
	for c in cells:
		d += P.dirs[c]
		r = maxf(r, P.top_r(c))
	return d.normalized() * r


func _arc(a: int, b: int, pn := -1) -> float:
	var P: Planet = _pl(pn)
	return P.dirs[a].angle_to(P.dirs[b]) * P.radius


func _bpos(b: Dictionary) -> Vector3:
	return _pl(int(b.pn)).top_pos(b.cell)


func _out_cell(b: Dictionary) -> int:
	var nb: PackedInt32Array = _pl(int(b.pn)).nbrs[b.cell]
	return nb[int(b.dir) % nb.size()]


func _upos(u: Dictionary) -> Vector3:
	var d: Vector3 = u.dir
	return d * (_pl(int(u.pn)).top_r(u.cell) + 0.3)


## Ядро команды для возрождения: главное, если ещё наше, иначе любое своё.
func _home_core(team: int):
	var any = null
	for b in buildings.values():
		if b.type == D.CORE and b.team == team:
			if b.main:
				return b
			any = b
	return any


func _spawn_pn(team: int) -> int:
	var hc = _home_core(team)
	return int(hc.pn) if hc != null else int(D.TEAM_HOME[maxi(team, 0) % 2])


func _spawn_pos(team: int) -> Vector3:
	var hc = _home_core(team)
	var c: int = _pl(_spawn_pn(team)).spawn_cell[maxi(team, 0) % 2]
	if hc != null:
		# клетка на втором кольце вокруг ядра
		var r := _pl(_spawn_pn(team)).rings(int(hc.cell), 2)
		for x in r:
			if int(r[x]) == 2:
				c = x
				break
	return _pl(_spawn_pn(team)).dirs[c] * (_pl(_spawn_pn(team)).top_r(c) + 1.0)


## Где возродиться: выбранная база (если она ещё наша), иначе ближайшая к месту гибели —
## сначала на той же планете, потом главная, потом любая.
func _respawn_core(o: Dictionary):
	var sc: int = int(o.get("spawn_core", -1))
	if buildings.has(sc) and buildings[sc].type == D.CORE and int(buildings[sc].team) == int(o.team):
		return buildings[sc]
	var best = null
	var best_d := INF
	var opn: int = int(o.get("pn", -1))
	var opos: Vector3 = o.get("pos", Vector3.ZERO)
	for b in buildings.values():
		if b.type != D.CORE or int(b.team) != int(o.team):
			continue
		var d: float = 1.0e6 + (0.0 if b.main else 1.0)
		if int(b.pn) == opn:
			d = _bpos(b).distance_to(opos)
		if d < best_d:
			best_d = d
			best = b
	return best


## Точка возрождения у ядра — клетка на втором кольце вокруг него.
func _spawn_near(core: Dictionary) -> Vector3:
	var c: int = core.cell
	var r := _pl(int(core.pn)).rings(c, 2)
	for x in r:
		if int(r[x]) == 2:
			c = x
			break
	return _pl(int(core.pn)).dirs[c] * (_pl(int(core.pn)).top_r(c) + 1.0)


## Цена модернизации до следующего уровня.
func _upgrade_cost(b: Dictionary) -> Dictionary:
	var out := {}
	var lv: int = int(b.lvl)
	if lv >= D.UPG_MAX:
		return out
	var cost: Dictionary = D.COST[b.type]
	for it in cost:
		if int(it) == D.I_ALLOY:
			continue   # сплав — только на 3 уровень (ниже)
		out[it] = mini(int(cost[it]) * int(D.UPG_COST_MULT[lv]) + (5 if it == D.I_CHIP else 0), D.CORE_CAP)
	if not out.has(D.I_CHIP):
		out[D.I_CHIP] = 5 * lv
	if lv == 2:
		out[D.I_ALLOY] = 10 if _size_of(int(b.type)) == 1 else 20   # до 3 уровня — нужен сплав Pb-U
	return out


@rpc("any_peer", "call_remote", "reliable")
func req_upgrade(cell: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		if _in_reach(peer, cell, _peer_pn(peer)):
			server_upgrade(Net.team_of(peer), cell, _peer_pn(peer))


func server_upgrade(team: int, cell: int, pn: int) -> void:
	if not grid.has(_k(pn, cell)):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if int(b.team) != team or not D.UPGRADABLE.has(int(b.type)) or int(b.lvl) >= D.UPG_MAX or _busy(b):
		return
	var cost := _upgrade_cost(b)
	if not creative:
		var st: Dictionary = storage[team]
		for it in cost:
			if int(st.get(it, 0)) < int(cost[it]):
				return
		for it in cost:
			st[it] = int(st.get(it, 0)) - int(cost[it])
	b.lvl = int(b.lvl) + 1
	for p in Net.ready_peers:
		ev_upgrade.rpc_id(p, b.id, int(b.lvl))
	if not headless:
		_apply_upgrade(b.id, int(b.lvl))


@rpc("authority", "call_remote", "reliable")
func ev_upgrade(id: int, lvl: int) -> void:
	_apply_upgrade(id, lvl)


func _apply_upgrade(id: int, lvl: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	b.lvl = lvl
	if int(b.pn) == my_pn and bnodes.has(id):
		_revis(id)
		_boom(_bpos(b) + _bpos(b).normalized() * 1.5, 1.5, false)


@rpc("any_peer", "call_remote", "reliable")
func req_choose_base(core_id: int) -> void:
	if multiplayer.is_server():
		server_choose_base(multiplayer.get_remote_sender_id(), core_id)


func server_choose_base(pid: int, core_id: int) -> void:
	if not players.has(pid):
		return
	var o: Dictionary = players[pid]
	if o.hp > 0 or int(o.dead_t) <= D.RESPAWN_TICKS - D.CHOOSE_TICKS:
		return   # окно выбора закрыто
	if buildings.has(core_id) and buildings[core_id].type == D.CORE and int(buildings[core_id].team) == int(o.team):
		o["spawn_core"] = core_id


func _is_drill(t: int) -> bool:
	return t == D.DRILL or t == D.DRILL2 or t == D.DRILL3


func _can_afford(team: int, type: int) -> bool:
	if creative:
		return true
	var st: Dictionary = storage[team]
	var cost: Dictionary = D.COST[type]
	for it in cost:
		if int(st.get(it, 0)) < int(cost[it]):
			return false
	return true


func _cost_text(type: int) -> String:
	var parts := PackedStringArray()
	var cost: Dictionary = D.COST[type]
	for it in cost:
		parts.append("%s %d" % [D.ITEM_NAMES[it], cost[it]])
	return ", ".join(parts)


func _can_place(team: int, type: int, cell: int, dir: int, pn: int) -> bool:
	if team < 0 or finished or cell < 0 or cell >= _pl(pn).count():
		return false
	if not D.COST.has(type):
		return false
	var foot := _footprint(type, cell, dir, pn)
	if foot.size() != _size_of(type):
		return false
	for c in foot:
		if grid.has(_k(pn, c)) or _pl(pn).level[c] >= D.MAX_LEVEL:
			return false
	for b in buildings.values():
		if b.type == D.CORE and b.pn == pn and b.team != team and _arc(cell, b.cell, pn) < D.ENEMY_ZONE:
			return false
	if _is_drill(type):
		var dep: int = _drill_ore(foot, pn)[0]
		if dep == D.I_NONE:
			return false
		if type == D.DRILL and D.RARE_ORES.has(dep):
			return false
		if dep == D.I_UNIQUE_ORE and type != D.DRILL3:
			return false   # уникальную материю берёт только Бур III
	return _can_afford(team, type)


# =====================================================================
# Постройки (общая часть)
# =====================================================================

func _add_building(d: Dictionary) -> void:
	var b := {
		"id": int(d.id), "type": int(d.type), "team": int(d.team),
		"cell": int(d.cell), "dir": int(d.dir), "pn": int(d.get("pn", D.HOME_PLANET)),
		"main": bool(d.get("main", false)), "cap_team": -1, "cap": 0,
		"hp": D.HP[int(d.type)], "item": D.I_NONE, "prog": 0.0,
		"store": 0, "timer": 0, "rr": 0,
		"buf": {}, "cur": -1, "out_item": D.I_NONE, "out_n": 0,
		"blocked": false, "water": 0, "wuse": 0, "burn": 0, "wt": 0, "cool": false,
		"pr": 0.0, "pout": 0.0, "out_blocked": false, "filter": int(d.get("filter", D.I_NONE)),
		"ukind": int(d.get("ukind", -1)), "lit": bool(d.get("lit", true)),
		"charge": 0.0, "bflow": 0.0, "lvl": int(d.get("lvl", 1)),
		# стройка: bt — готовность 0..1, decon — идёт снос, by — кто строит/сносит (peer)
		"bt": float(d.get("bt", 1.0)), "decon": bool(d.get("decon", false)), "by": int(d.get("by", 0)),
		"refund_full": false,
	}
	var cells := _footprint(b.type, b.cell, b.dir, b.pn)
	b["cells"] = cells
	# соседние клетки снаружи контура — сюда машина отдаёт продукт
	var outs: Array = []
	for c in cells:
		var nb: PackedInt32Array = _pl(b.pn).nbrs[c]
		for x in nb:
			if not cells.has(x) and not outs.has(x):
				outs.append(x)
	b["outs"] = outs
	if D.RECIPES.has(b.type):
		b["fouts"] = _front_cells(b)   # завод отдаёт продукт только вперёд
	if _is_drill(b.type):
		var info := _drill_ore(cells, b.pn)
		b["ore"] = info[0]
		b["ore_n"] = info[1]
	buildings[b.id] = b
	for c in cells:
		grid[_k(b.pn, c)] = b.id
	power_dirty = true
	if is_server and (b.type == D.LOADER or b.type == D.FUEL_DEPOT):
		_spawn_rover(b)
	next_id = maxi(next_id, b.id + 1)
	if _busy(b):
		building_set[b.id] = true
	if not headless and b.pn == my_pn:
		_vis_add(b)
		_refresh_links(b)


func _remove_building(id: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	for c in b.cells:
		grid.erase(_k(b.pn, c))
	buildings.erase(id)
	power_dirty = true
	if is_server:
		rovers = rovers.filter(func(r): return r.home != id)   # ровер без дома исчезает
	if bnodes.has(id):
		bnodes[id].queue_free()
		bnodes.erase(id)
	turret_nodes.erase(id)
	turret_aim.erase(id)
	building_set.erase(id)
	asm_nodes.erase(id)
	if not headless and b.pn == my_pn:
		_refresh_links(b)


## Постройка ещё строится или уже сносится — не работает.
func _busy(b: Dictionary) -> bool:
	return float(b.bt) < 1.0 or bool(b.decon)


func _bdata(b: Dictionary) -> Dictionary:
	return {"id": b.id, "type": b.type, "team": b.team, "cell": b.cell, "dir": b.dir, "filter": b.filter,
		"pn": b.pn, "main": b.main, "ukind": b.ukind, "lit": b.lit, "bt": b.bt, "decon": b.decon, "by": b.by,
		"lvl": b.lvl}


# =====================================================================
# Сервер: команды игроков
# =====================================================================

## Дотягивается ли игрок до клетки (строить и сносить можно только рядом с собой, не с карты).
func _in_reach(peer: int, cell: int, pn: int) -> bool:
	if not players.has(peer):
		return false
	var pl: Dictionary = players[peer]
	if int(pl.get("pn", -1)) != pn or pl.hp <= 0:
		return false
	return Vector3(pl.pos).distance_to(_pl(pn).top_pos(cell)) <= D.BUILD_REACH + 4.0


func server_place(team: int, type: int, cell: int, dir: int, pn: int, peer := 0) -> void:
	if not D.COST.has(type) or type == D.CORE:
		return
	var nb0: PackedInt32Array = _pl(pn).nbrs[cell]
	dir = posmod(dir, nb0.size())
	if not _can_place(team, type, cell, dir, pn):
		return
	if not creative:
		var st: Dictionary = storage[team]
		var cost: Dictionary = D.COST[type]
		for it in cost:
			st[it] = int(st.get(it, 0)) - int(cost[it])
	var nb: PackedInt32Array = _pl(pn).nbrs[cell]
	var d := {"id": _new_id(), "type": type, "team": team, "cell": cell, "dir": posmod(dir, nb.size()), "pn": pn,
		"bt": 0.0, "by": peer}
	_add_building(d)
	for p in Net.ready_peers:
		ev_add.rpc_id(p, d)


## Снос не мгновенный: постройка разбирается столько же, сколько строилась, ресурсы — в конце.
func server_remove(team: int, cell: int, pn: int, peer := 0) -> void:
	if finished or not grid.has(_k(pn, cell)):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if b.team != team or b.type == D.CORE or b.decon:
		return
	b.refund_full = float(b.bt) < 1.0   # недостроенное — отмена стройки, вернём всё
	b.decon = true
	b.by = peer
	building_set[b.id] = true
	power_dirty = true
	for p in Net.ready_peers:
		ev_build.rpc_id(p, b.id, float(b.bt), true, peer)
	if not headless:
		_on_build_state(b)


## Сервер: шаг стройки или сноса одной постройки.
func _build_tick(b: Dictionary) -> void:
	var step: float = D.TICK / D.build_time(int(b.type))
	if b.decon:
		b.bt = float(b.bt) - step
		if b.bt <= 0.0:
			var st: Dictionary = storage[int(b.team)]
			var cost: Dictionary = D.COST[b.type]
			if not creative and int(b.team) < 2:
				for it in cost:
					var back: int = int(cost[it]) if b.refund_full else int(cost[it]) / 2
					st[it] = mini(int(st.get(it, 0)) + back, D.CORE_CAP)   # не выше лимита склада
			_destroy(b.id)
		return
	b.bt = float(b.bt) + step
	if b.bt >= 1.0:
		b.bt = 1.0
		building_set.erase(b.id)
		power_dirty = true
		for p in Net.ready_peers:
			ev_build.rpc_id(p, b.id, 1.0, false, int(b.by))
		if not headless:
			_on_build_state(b)


func _destroy(id: int, by_damage := false) -> void:
	if by_damage and buildings.has(id):
		var b: Dictionary = buildings[id]
		_alert_team(int(b.team), "Постройка разрушена: %s — %s" % [D.NAMES[b.type], D.PLANETS[int(b.pn)].name],
			int(b.pn), 1)
	_remove_building(id)
	for peer in Net.ready_peers:
		ev_remove.rpc_id(peer, id)


func send_full_sync(peer: int) -> void:
	var list: Array = []
	for b in buildings.values():
		list.append(_bdata(b))
	full_sync.rpc_id(peer, list)
	if finished:
		ev_over.rpc_id(peer, 0 if int(base_count[0]) > 0 else 1)


func server_player_state(peer: int, pos: Vector3, fwd: Vector3, held: int, pn: int) -> void:
	var team: int = Net.team_of(peer)
	if team < 0:
		return
	if not players.has(peer):
		players[peer] = {"team": team, "pos": pos, "fwd": fwd, "hp": D.PLAYER_HP, "dead_t": 0,
			"last_shot": 0, "held": held, "pn": pn}
	var pl: Dictionary = players[peer]
	pl.held = held
	pl["pn"] = clampi(pn, 0, D.PLANETS.size() - 1)
	if pl.hp <= 0:
		return
	pl.pos = pos
	pl.fwd = fwd


## Луч против сферы: расстояние до попадания или -1.
func _ray_sphere(from: Vector3, dir: Vector3, c: Vector3, r: float) -> float:
	var t: float = (c - from).dot(dir)
	if t <= 0.0:
		return -1.0
	if (from + dir * t).distance_to(c) > r:
		return -1.0
	return t


func server_shoot(peer: int, from: Vector3, dir: Vector3) -> void:
	if finished or not players.has(peer):
		return
	var pl: Dictionary = players[peer]
	if pl.hp <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - int(pl.last_shot) < D.GUN_CD_MS:
		return
	pl.last_shot = now
	dir = dir.normalized()
	var spn: int = pl.get("pn", D.HOME_PLANET)

	var best_t: float = D.GUN_RANGE
	var hit_unit = null
	var hit_peer := -1
	for u in units:
		if u.team == pl.team or u.hp <= 0 or u.pn != spn:
			continue
		var t := _ray_sphere(from, dir, _upos(u), 0.5)
		if t > 0.0 and t < best_t:
			best_t = t
			hit_unit = u
			hit_peer = -1
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == pl.team or o.hp <= 0 or int(o.get("pn", D.HOME_PLANET)) != spn:
			continue
		var p: Vector3 = o.pos
		var up := p.normalized()
		for h in [0.5, 1.3]:
			var t := _ray_sphere(from, dir, p + up * h, 0.5)
			if t > 0.0 and t < best_t:
				best_t = t
				hit_unit = null
				hit_peer = pid

	var hit_ship = null
	for sh in ships.values():
		if int(sh.team) == int(pl.team) or int(sh.pn) != spn:
			continue
		var sup: Vector3 = Basis(Quaternion(sh.quat)).y
		for h in [1.2, 2.6, 4.0]:
			var t := _ray_sphere(from, dir, Vector3(sh.pos) + sup * h, 1.1)
			if t > 0.0 and t < best_t:
				best_t = t
				hit_ship = sh
				hit_unit = null
				hit_peer = -1
	var hit_rover = null
	for r in rovers:
		if int(r.team) == int(pl.team) or int(r.pn) != spn:
			continue
		var t := _ray_sphere(from, dir, _rpos(r) + _rpos(r).normalized() * 0.6, 0.9)
		if t > 0.0 and t < best_t:
			best_t = t
			hit_rover = r
			hit_ship = null
			hit_unit = null
			hit_peer = -1
	if hit_rover != null:
		_damage_rover(hit_rover, D.GUN_DMG)
	elif hit_ship != null:
		_damage_ship(hit_ship, D.GUN_DMG)   # ракеты сбиваются и из бластера
	elif hit_unit != null:
		hit_unit.hp -= D.GUN_DMG
	elif hit_peer != -1:
		_damage_player(hit_peer, D.GUN_DMG)

	var end := from + dir * best_t
	for p in Net.ready_peers:
		if p != peer:
			fx_shot.rpc_id(p, from, end, spn)
	if not headless and peer != 1 and spn == my_pn:
		_tracer(from, end)


func _damage_player(pid: int, dmg: int) -> void:
	if not players.has(pid):
		return
	var o: Dictionary = players[pid]
	if o.hp <= 0:
		return
	o.hp -= dmg
	if o.hp <= 0:
		o.hp = 0
		o.dead_t = D.RESPAWN_TICKS
		o["spawn_core"] = -1   # базу можно выбрать в первые 5 с


# =====================================================================
# RPC
# =====================================================================

@rpc("any_peer", "call_remote", "reliable")
func req_place(type: int, cell: int, dir: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		if _in_reach(peer, cell, _peer_pn(peer)):
			server_place(Net.team_of(peer), type, cell, dir, _peer_pn(peer), peer)


@rpc("any_peer", "call_remote", "reliable")
func req_remove(cell: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		if _in_reach(peer, cell, _peer_pn(peer)):
			server_remove(Net.team_of(peer), cell, _peer_pn(peer), peer)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func req_player_state(pos: Vector3, fwd: Vector3, held: int, pn: int) -> void:
	if multiplayer.is_server():
		server_player_state(multiplayer.get_remote_sender_id(), pos, fwd, held, pn)


@rpc("any_peer", "call_remote", "reliable")
func req_shoot(from: Vector3, dir: Vector3) -> void:
	if multiplayer.is_server():
		server_shoot(multiplayer.get_remote_sender_id(), from, dir)


@rpc("authority", "call_remote", "reliable")
func ev_add(d: Dictionary) -> void:
	_add_building(d)


@rpc("authority", "call_remote", "reliable")
func ev_remove(id: int) -> void:
	_remove_building(id)


## Началась/закончилась стройка или снос.
@rpc("authority", "call_remote", "reliable")
func ev_build(id: int, bt: float, decon: bool, by: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	b.bt = bt
	b.decon = decon
	b.by = by
	if _busy(b):
		building_set[id] = true
	else:
		building_set.erase(id)
	power_dirty = true
	_on_build_state(b)


@rpc("authority", "call_remote", "reliable")
func ev_team(ids: PackedInt32Array, team: int) -> void:
	_apply_team(ids, team)


## У построек сменилась команда: обновить данные и перекрасить.
func _apply_team(ids: PackedInt32Array, team: int) -> void:
	for id in ids:
		if not buildings.has(id):
			continue
		var b: Dictionary = buildings[id]
		b.team = team
		if b.pn == my_pn and bnodes.has(id):
			bnodes[id].queue_free()
			bnodes.erase(id)
			turret_nodes.erase(id)
			asm_nodes.erase(id)
			_vis_add(b)


@rpc("authority", "call_remote", "unreliable_ordered")
func caps_snap(caps: Array, counts: Array, ustat: Array) -> void:
	cur_caps = caps
	base_count = counts
	unit_stat = ustat


@rpc("authority", "call_remote", "reliable")
func ev_over(winner: int) -> void:
	_show_over(winner)


@rpc("authority", "call_remote", "reliable")
func ev_respawn(pos: Vector3, pn: int) -> void:
	if player:
		_switch_planet(pn)
		player.teleport(pos)


@rpc("authority", "call_remote", "reliable")
func full_sync(list: Array) -> void:
	for d in list:
		if not buildings.has(int(d.id)):
			_add_building(d)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(u: PackedFloat32Array, it: PackedVector3Array, itt: PackedByteArray, pl: Array,
		st: Array, hp: Array, pw: Array, rv: Array, t: float) -> void:
	_apply_snapshot(u, it, itt, pl, st, hp, pw, rv)
	# часы клиента подтягиваем к серверным
	if absf(world_time - t) > 1.0:
		world_time = t
	else:
		world_time = lerpf(world_time, t, 0.1)


@rpc("any_peer", "call_remote", "reliable")
func req_command(ids: PackedInt32Array, mode: int, point: Vector3, has_point: bool) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		server_command(Net.team_of(peer), _peer_pn(peer), ids, mode, point, has_point)


## Приказ выделенным юнитам: поведение (mode, -1 — не менять) и/или точка охраны.
func server_command(team: int, pn: int, ids: PackedInt32Array, mode: int, point: Vector3, has_point: bool) -> void:
	var want := {}
	for id in ids:
		want[id] = true
	for u in units:
		if u.team != team or u.pn != pn or not want.has(int(u.id)):
			continue
		if mode >= 0:
			u.mode = clampi(mode, 0, 2)
			if mode == D.MODE_GUARD and not has_point:
				u.guard = _upos(u)
		if has_point:
			u.guard = point
			u.mode = D.MODE_GUARD


@rpc("any_peer", "call_remote", "reliable")
func req_lamp(cell: int, all_on_planet: bool) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		server_lamp(Net.team_of(peer), cell, _peer_pn(peer), all_on_planet)


## Включить/выключить лампу (или все свои лампы на планете — режим маскировки).
func server_lamp(team: int, cell: int, pn: int, all_on_planet: bool) -> void:
	if not grid.has(_k(pn, cell)):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if b.type != D.LAMP or b.team != team:
		return
	var lit: bool = not b.lit
	var ids := PackedInt32Array()
	for o in buildings.values():
		if o.type == D.LAMP and o.team == team and o.pn == pn and (all_on_planet or o.id == b.id):
			o.lit = lit
			ids.append(o.id)
	for p in Net.ready_peers:
		ev_lamp.rpc_id(p, ids, lit)
	if not headless:
		_apply_lamp(ids, lit)


@rpc("authority", "call_remote", "reliable")
func ev_lamp(ids: PackedInt32Array, lit: bool) -> void:
	_apply_lamp(ids, lit)


func _apply_lamp(ids: PackedInt32Array, lit: bool) -> void:
	for id in ids:
		if buildings.has(id):
			buildings[id].lit = lit
			var root = bnodes.get(id)
			if root != null and root.has_meta("bulb"):
				var bulb: MeshInstance3D = root.get_meta("bulb")
				bulb.material_override = _mat(Color(1.0, 0.85, 0.55), true) if lit else _pmat(Color(0.25, 0.24, 0.22), 0)
	lamp_acc = 1.0   # пересобрать свет сразу


@rpc("any_peer", "call_remote", "reliable")
func req_set_unit(cell: int, kind: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		server_set_unit(Net.team_of(peer), cell, kind, _peer_pn(peer))


func server_set_unit(team: int, cell: int, kind: int, pn: int) -> void:
	if not grid.has(_k(pn, cell)):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if b.type != D.ASSEMBLER or b.team != team or b.timer > 0:
		return
	b.ukind = clampi(kind, 0, D.UNIT_NAMES.size() - 1)
	b.buf = {}


@rpc("any_peer", "call_remote", "reliable")
func req_pad_action(cell: int, kind: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		server_pad_action(Net.team_of(peer), cell, _peer_pn(peer), kind)


@rpc("any_peer", "call_remote", "reliable")
func req_board(id: int) -> void:
	if multiplayer.is_server():
		server_board(multiplayer.get_remote_sender_id(), id)


@rpc("authority", "call_remote", "reliable")
func ev_board(id: int, pos: Vector3, quat: Quaternion, fuel: float, pn: int, kind: int) -> void:
	_start_piloting(id, pos, quat, fuel, pn, kind)


@rpc("any_peer", "call_remote", "reliable")
func req_ship_load(id: int) -> void:
	if multiplayer.is_server():
		server_ship_load(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func req_ship_unload(id: int) -> void:
	if multiplayer.is_server():
		server_ship_unload(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func req_ship_state(id: int, pos: Vector3, quat: Quaternion, fuel: float, thrust: bool, pn: int) -> void:
	if multiplayer.is_server():
		server_ship_state(multiplayer.get_remote_sender_id(), id, pos, quat, fuel, thrust, pn)


@rpc("any_peer", "call_remote", "reliable")
func req_ship_exit(id: int, pos: Vector3, quat: Quaternion, pn: int) -> void:
	if multiplayer.is_server():
		server_ship_exit(multiplayer.get_remote_sender_id(), id, pos, quat, pn)


@rpc("any_peer", "call_remote", "reliable")
func req_ship_crash(id: int) -> void:
	if multiplayer.is_server():
		server_ship_crash(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func req_set_filter(cell: int, item: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		server_set_filter(Net.team_of(peer), cell, item, _peer_pn(peer))


func server_set_filter(team: int, cell: int, item: int, pn: int) -> void:
	if not grid.has(_k(pn, cell)) or not D.ITEM_NAMES.has(item):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if (b.type != D.UNLOADER and b.type != D.SORTER) or b.team != team:
		return
	b.filter = item
	if b.type == D.UNLOADER:
		b.buf = {}   # старый груз выбрасываем
	for p in Net.ready_peers:
		ev_filter.rpc_id(p, b.id, item)
	if not headless:
		_apply_filter(b.id, item)


@rpc("authority", "call_remote", "reliable")
func ev_filter(id: int, item: int) -> void:
	_apply_filter(id, item)


func _apply_filter(id: int, item: int) -> void:
	if not buildings.has(id):
		return
	buildings[id].filter = item
	var root = bnodes.get(id)
	if root == null or not root.has_meta("filter_sprite"):
		return
	var sp: Sprite3D = root.get_meta("filter_sprite")
	sp.visible = item != D.I_NONE
	if sp.visible:
		var c := Icons.cell_of(item)
		sp.region_rect = Rect2(c.x * Icons.SIZE, c.y * Icons.SIZE, Icons.SIZE, Icons.SIZE)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func req_inspect(cell: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		inspect_reply.rpc_id(peer, cell, _inspect_info(cell, _peer_pn(peer)))


@rpc("authority", "call_remote", "unreliable_ordered")
func inspect_reply(cell: int, info: Array) -> void:
	inspect_cell = cell
	inspect_info = info


## Данные о постройке под прицелом (считает сервер — у него внутренности машин).
func _inspect_info(cell: int, pn: int) -> Array:
	if not grid.has(_k(pn, cell)):
		return []
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	var st: Array = _status(b)
	var t: int = b.type
	var prog := -1.0
	if _busy(b):
		prog = float(b.bt)
	elif D.RECIPES.has(t) and int(b.cur) != -1:
		prog = float(b.prog) / float(D.RECIPES[t][b.cur]["t"])
	elif t == D.ASSEMBLER and int(b.timer) > 0:
		prog = 1.0 - float(b.timer) / float(D.UNIT_STATS[b.ukind].build)
	elif t == D.BATTERY:
		prog = float(b.charge) / D.BATTERY_CAP
	elif t == D.LAUNCH_PAD and int(b.timer) > 0:
		prog = 1.0 - float(b.timer) / float(D.SHIP_KINDS[int(b.get("ship_kind", 0))].build)
	var items := PackedInt32Array()
	for it in b.buf:
		if int(b.buf[it]) > 0:
			items.append(int(it))
			items.append(int(b.buf[it]))
	if int(b.water) > 0 and not b.buf.has(D.I_WATER):
		items.append(D.I_WATER)
		items.append(int(b.water))
	if b.item != D.I_NONE and items.is_empty():
		items.append(int(b.item))
		items.append(1)
	return [t, int(st[0]), String(st[1]), float(b.hp) / float(D.HP[t]), prog, items, int(b.team)]


## [состояние ST_*, короткий текст]
func _status(b: Dictionary) -> Array:
	var t: int = b.type
	if _busy(b):
		return [ST_IDLE, ("снос %d%%" if b.decon else "стройка %d%%") % int(100.0 * float(b.bt))]
	if D.POWER_USE.has(t) and not power_has_gen.has(power_root.get(b.id, b.id)):
		return [ST_STOP, "нет энергии: рядом нет генератора"]
	if t == D.CORE and b.team == D.T_NEUTRAL:
		if b.cap_team >= 0:
			return [ST_SLOW, "нейтральная база, захватывают %s: %d%%" % [D.TEAM_NAMES[b.cap_team],
				int(100.0 * b.cap / D.CAPTURE_TICKS)]]
		var def_n := 0
		for o in buildings.values():
			if o.team == D.T_NEUTRAL and o.pn == b.pn and D.DEFENSE_TYPES.has(o.type) \
					and _bpos(o).distance_to(_bpos(b)) < D.BASE_RADIUS:
				def_n += 1
		return [ST_IDLE, "нейтральная база, оборона: %d турелей — встань у ядра, чтобы захватить" % def_n]
	if t == D.CORE:
		var full := PackedStringArray()
		var st: Dictionary = storage[b.team]
		for it in D.CORE_ACCEPT:
			if int(st.get(it, 0)) >= D.CORE_CAP:
				full.append(D.ITEM_NAMES[it])
		if full.is_empty():
			return [ST_OK, "склад принимает всё переработанное"]
		if int(b.get("burn_t", 0)) > 0:
			return [ST_SLOW, "склад полон, лишнее сжигается: " + ", ".join(full)]
		return [ST_OK, "склад полон: " + ", ".join(full)]
	if t == D.TURRET:
		return [ST_OK, "в строю, лазер %d клеток" % int(round(D.TURRET_RANGE / D.CELL_M))]
	if t == D.LAUNCH_PAD:
		var fuel_in := int(b.buf.get(D.I_FUEL, 0))
		var bk: int = b.get("ship_kind", 0)
		if b.timer > 0:
			return [ST_OK, "сборка: %s %d%%" % [D.SHIP_KINDS[bk].name,
				int(100.0 * (1.0 - float(b.timer) / float(D.SHIP_KINDS[bk].build)))]]
		var sh = _pad_ship(b)
		if sh == null:
			return [ST_IDLE, "корабля нет — держи E: собрать разведчика, транспорт или истребитель"]
		var dv := _ship_dv(float(sh.fuel), int(sh.kind))
		var st_txt: String = "в полёте" if sh.state == 1 else "на площадке"
		var fit: int = int(D.SHIP_KINDS[int(sh.kind)].get("fuel", D.I_FUEL))
		return [ST_OK, "%s %s, топливо %d/%d (Δv %d м/с), на площадке %s: %d" % [
			D.SHIP_KINDS[int(sh.kind)].name, st_txt, int(sh.fuel), int(_ship_tank(sh)), int(dv),
			D.ITEM_NAMES[fit], int(b.buf.get(fit, 0)) if fit != D.I_FUEL else fuel_in]]
	if t == D.SPLITTER or t == D.JUNCTION or t == D.BRIDGE:
		var what: String = D.ITEM_NAMES[b.item] if b.item != D.I_NONE else "пусто"
		if t == D.BRIDGE:
			return [ST_OK, "%s, дальний мост: %s" % [what, "есть" if _bridge_target(b) != null else "нет — выдаёт вперёд"]]
		return [ST_OK, what]
	if t == D.POWER_POLE:
		var root: int = power_root.get(b.id, b.id)
		if power_has_gen.has(root):
			return [ST_OK, "в сети с генератором"]
		return [ST_IDLE, "нет генератора в сети — поставь столбы цепочкой до генератора"]
	if t == D.WALL:
		return [ST_OK, "забор"]
	if t == D.LAMP:
		return [ST_OK, "горит"] if b.lit else [ST_IDLE, "выключена (маскировка)"]
	if t == D.BATTERY:
		var ch := float(b.charge)
		var ctxt := "заряд %d / %d" % [int(ch), int(D.BATTERY_CAP)]
		if float(b.bflow) < -0.001:
			return [ST_SLOW, ctxt + ", отдаёт в сеть"]
		if ch < 1.0:
			return [ST_IDLE, ctxt + " — нет излишка энергии"]
		return [ST_OK, ctxt + (", заряжается" if float(b.bflow) > 0.001 else "")]
	if t == D.REPAIR or t == D.UNIT_REPAIR:
		return _power_state(b, "чинит %s в %d м" % ["постройки" if t == D.REPAIR else "юнитов", int(D.REPAIR_RADIUS)])
	if t == D.AA_GUN:
		var items := 0
		for it in b.buf:
			items += int(b.buf[it])
		var ammo := int(b.get("ammo", 0)) + items / D.AA_ITEMS_PER_SHOT
		var boost: String = ("  вода %d — стрельба ×2" % b.water) if b.water > 0 else "  (подай воду — стрельба ×2)"
		if creative or b.team == D.T_NEUTRAL:
			return [ST_OK, "ПВО, боеприпасы бесконечны"]
		if ammo <= 0:
			return [ST_STOP, "нет снарядов: подай ресурсы (3 на выстрел)"]
		return [ST_OK, "ПВО: снарядов %d%s" % [ammo, boost]]
	if t == D.TURRET2:
		var cu := int(b.buf.get(D.I_COPPER, 0))
		if not creative and b.team != D.T_NEUTRAL and cu <= 0 and int(b.get("ammo", 0)) <= 0:
			return [ST_STOP, "нет меди"]
		return [ST_OK, "медь %d" % cu if not creative else "боеприпасы бесконечны"]
	if t == D.TURRET4:
		var ua := int(b.buf.get(D.I_UALLOY, 0))
		if creative or b.team == D.T_NEUTRAL:
			return [ST_OK, "боеприпасы бесконечны"]
		if ua <= 0 and int(b.get("ammo", 0)) <= 0:
			return [ST_STOP, "нет уникального сплава"]
		return [ST_OK, "уникальный сплав %d (×%d снаряда)" % [ua, D.T4_SHOTS_PER_ITEM]]
	if t == D.TURRET3:
		var lead := int(b.buf.get(D.I_LEAD, 0))
		var ur := int(b.buf.get(D.I_URANIUM, 0))
		if not creative and lead + ur <= 0:
			return [ST_STOP, "нет снарядов (свинец или уран)"]
		return [ST_OK, "снаряды: свинец %d, уран %d" % [lead, ur] if not creative else "боеприпасы бесконечны"]
	if t == D.SORTER and int(b.filter) == D.I_NONE:
		return [ST_IDLE, "груз не выбран — держи E"]
	if t == D.CONVEYOR or t == D.PIPE or t == D.SORTER:
		return [ST_OK, "везёт: " + D.ITEM_NAMES[b.item] if b.item != D.I_NONE else "пусто"]
	if _is_drill(t):
		if b.blocked:
			return [ST_STOP, "некуда отдавать руду"]
		if t == D.DRILL3 and b.water <= 0:
			return [ST_STOP, "нет воды"]
		return _power_state(b, "добывает: " + D.ITEM_NAMES[b.ore])
	if D.RECIPES.has(t):
		if b.out_blocked:
			return [ST_STOP, "некуда отдать продукт"]
		if b.cur == -1:
			return [ST_IDLE, "ждёт сырьё"]
		var rec: Dictionary = D.RECIPES[t][b.cur]
		return _power_state(b, "%s %d%%" % [D.ITEM_NAMES[rec["out"]], int(100.0 * b.prog / float(rec["t"]))])
	if t == D.SOLAR:
		if b.pout <= 0.0:
			return [ST_IDLE, "темно, выработки нет"]
		if b.pout < D.SOLAR_POWER - 0.1:
			return [ST_SLOW, "%d энергии (мало света)" % int(b.pout)]
		return [ST_OK, "%d энергии" % int(b.pout)]
	if t == D.COAL_PLANT:
		if b.pout > 0.0:
			return [ST_OK, "%d энергии, угля %d" % [int(b.pout), int(b.buf.get(D.I_COAL, 0))]]
		return [ST_IDLE, "нет угля"]
	if t == D.NUCLEAR:
		if not b.cool:
			return [ST_STOP, "нет воды для охлаждения"]
		if b.pout > 0.0:
			return [ST_OK, "%d энергии, урана %d" % [int(b.pout), int(b.buf.get(D.I_URANIUM, 0))]]
		return [ST_IDLE, "нет урана"]
	if t == D.ASSEMBLER and int(b.ukind) < 0:
		return [ST_IDLE, "тип юнита не выбран — держи E"]
	if t == D.ASSEMBLER:
		var k: int = b.ukind
		var nm: String = D.UNIT_NAMES[k]
		if b.timer > 0:
			return [ST_OK, "собирает: %s %d%%" % [nm, int(100.0 * (1.0 - float(b.timer) / D.UNIT_STATS[k].build))]]
		if _unit_count(b.team, k) >= _unit_limit(b.team, k):
			return [ST_SLOW, "лимит: %s %d/%d (захвати базы — лимит вырастет)" % [nm, _unit_count(b.team, k), _unit_limit(b.team, k)]]
		return [ST_IDLE, "%s: подай конвейером %s  (E — сменить)" % [nm, _cost_dict_text(D.UNIT_RECIPES[k])]]
	if (t == D.LOADER or t == D.FUEL_DEPOT) and int(b.get("rover_t", 0)) > 0:
		return [ST_STOP, "%s уничтожен — новый через %d с" % ["Заправщик" if t == D.FUEL_DEPOT else "Курьер",
			int(ceil(float(b.rover_t) * D.TICK))]]
	if t == D.SPACE_DOCK:
		return _dock_status(b)
	if t == D.FUEL_DEPOT:
		var fu := int(b.buf.get(D.I_FUEL, 0))
		if fu == 0:
			return [ST_IDLE, "ждёт топливо по трубе"]
		return [ST_OK, "топливо %d/%d" % [fu, D.DEPOT_CAP]]
	if t == D.LOADER:
		var total := 0
		for it in b.buf:
			total += int(b.buf[it])
		var rv := ""
		for r in rovers:
			if r.home == b.id:
				rv = ["ровер дома", "ровер везёт %d × %s" % [r.cargo_n, D.ITEM_NAMES.get(r.cargo_item, "?")],
					"ровер едет назад"][int(r.state)]
		if total == 0:
			return [ST_IDLE, "ждёт груз с конвейеров, " + rv]
		return [ST_OK, "на складе %d/%d, %s" % [total, D.LOADER_CAP, rv]]
	if t == D.UNLOADER:
		if b.filter == D.I_NONE:
			return [ST_IDLE, "груз не выбран — держи E"]
		var have := int(b.buf.get(b.filter, 0))
		if b.out_blocked:
			return [ST_STOP, "некуда отдавать %s (%d)" % [D.ITEM_NAMES[b.filter], have]]
		return [ST_OK, "принимает: %s, внутри %d/%d" % [D.ITEM_NAMES[b.filter], have, D.UNLOADER_CAP]]
	return [ST_OK, ""]


func _power_state(b: Dictionary, txt: String) -> Array:
	if b.pr <= 0.001:
		return [ST_STOP, "нет энергии"]
	if b.pr < 0.99:
		return [ST_SLOW, "%s (энергия %d%%)" % [txt, int(b.pr * 100.0)]]
	return [ST_OK, txt]


## Раз в полсекунды рассылаем цвета индикаторов всех построек.
func _send_states() -> void:
	var ids := PackedInt32Array()
	var sts := PackedByteArray()
	for b in buildings.values():
		ids.append(b.id)
		if BELT_TYPES.has(int(b.type)):
			# лента крутится, только пока по ней недавно что-то ехало
			sts.append(ST_OK if sim_n - int(b.get("flow_t", -100)) < 12 else ST_IDLE)
		else:
			sts.append(int(_status(b)[0]))
	for p in Net.ready_peers:
		states.rpc_id(p, ids, sts)
	if not headless:
		_apply_states(ids, sts)


@rpc("authority", "call_remote", "unreliable_ordered")
func states(ids: PackedInt32Array, sts: PackedByteArray) -> void:
	_apply_states(ids, sts)


func _apply_states(ids: PackedInt32Array, sts: PackedByteArray) -> void:
	for i in ids.size():
		bstate[ids[i]] = sts[i]
		var broot = bnodes.get(ids[i])
		if broot != null and buildings.has(ids[i]) and BELT_TYPES.has(int(buildings[ids[i]].type)):
			_set_belt_run(broot, sts[i] == ST_OK)
		var root = bnodes.get(ids[i])
		if root == null or not root.has_meta("ind"):
			continue
		var ind: MeshInstance3D = root.get_meta("ind")
		ind.material_override = _mat(STATE_COLORS[clampi(sts[i], 0, 3)], true)


func _buf_text(buf: Dictionary) -> String:
	var parts := PackedStringArray()
	for it in buf:
		if int(buf[it]) > 0:
			parts.append("%s %d" % [D.ITEM_NAMES[it], buf[it]])
	return "пусто" if parts.is_empty() else ", ".join(parts)


@rpc("authority", "call_remote", "unreliable")
func fx_shot(from: Vector3, to: Vector3, pn: int) -> void:
	if pn == my_pn:
		_tracer(from, to)


@rpc("authority", "call_remote", "unreliable_ordered")
func turret_aims(ids: PackedInt32Array, dirs: PackedVector3Array) -> void:
	_apply_aims(ids, dirs)


func _apply_aims(ids: PackedInt32Array, dirs: PackedVector3Array) -> void:
	for i in ids.size():
		turret_aim[ids[i]] = dirs[i]


@rpc("authority", "call_remote", "unreliable_ordered")
func ships_snap(sv: Array) -> void:
	cur_ships = sv


@rpc("authority", "call_remote", "unreliable_ordered")
func proj_snap(pp: PackedVector3Array, pv: PackedVector3Array, pk: PackedByteArray) -> void:
	_apply_proj(pp, pv, pk)


func _apply_proj(pp: PackedVector3Array, pv: PackedVector3Array, pk: PackedByteArray) -> void:
	proj_pos = pp
	proj_vel = pv
	proj_kind = pk
	proj_time = 0.0


@rpc("authority", "call_remote", "unreliable")
func fx_beam(from: Vector3, to: Vector3, kind: int, pn: int) -> void:
	if pn != my_pn:
		return
	_tracer(from, to, [Color(1.0, 0.85, 0.3), Color(1.0, 0.25, 0.2), Color(0.6, 0.9, 1.0), Color(0.4, 0.6, 1.0)][clampi(kind, 0, 3)])


@rpc("authority", "call_remote", "unreliable")
func fx_boom(at: Vector3, r: float, uranium: bool, pn: int) -> void:
	if pn == my_pn:
		_boom(at, r, uranium)


# =====================================================================
# Сервер: симуляция
# =====================================================================

func _process(delta: float) -> void:
	world_time += delta
	if is_server and not finished:
		tick_acc += delta
		var steps := 0
		while tick_acc >= D.TICK and steps < 5:
			tick_acc -= D.TICK
			steps += 1
			_sim_tick()
			_send_snapshot()
	if not headless:
		_update_client(delta)


## Энергосети: генератор питает всё в D.POWER_RING кольцах вокруг себя.
## Генераторы и потребители, связанные зонами, образуют одну сеть.
func _rebuild_power() -> void:
	power_dirty = false
	var parent := {}
	for b in buildings.values():
		if _busy(b):
			continue
		if D.GENERATORS.has(b.type) or D.POWER_USE.has(b.type) or b.type == D.POWER_POLE or b.type == D.BATTERY:
			parent[b.id] = b.id
	# генераторы и энергостолбы связывают в одну сеть всё вокруг себя; столбы — цепочкой
	for b in buildings.values():
		if not parent.has(b.id):
			continue
		var ring := 0
		if D.GENERATORS.has(b.type):
			ring = D.POWER_RING
		elif b.type == D.POWER_POLE:
			ring = D.POLE_RING
		else:
			continue
		var covered := {}
		for c in b.cells:
			var r := _pl(int(b.pn)).rings(c, ring)
			for x in r:
				covered[x] = true
		for x in covered:
			if grid.has(_k(b.pn, x)):
				var oid: int = grid[_k(b.pn, x)]
				if parent.has(oid) and buildings[oid].team == b.team:
					_uf_union(parent, b.id, oid)
	power_root.clear()
	power_has_gen.clear()
	for id in parent:
		var root := _uf_find(parent, id)
		power_root[id] = root
		if D.GENERATORS.has(buildings[id].type) or buildings[id].type == D.BATTERY:
			power_has_gen[root] = true   # аккумулятор тоже источник


func _uf_find(parent: Dictionary, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


func _uf_union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra != rb:
		parent[ra] = rb


func _sim_tick() -> void:
	sim_n += 1
	if power_dirty:
		_rebuild_power()
	var skies := {}   # небо каждой планеты считаем один раз за тик
	var prod := [0.0, 0.0]
	var demand := [0.0, 0.0]
	var gprod := {}   # корень сети -> выработка
	var gdem := {}    # корень сети -> спрос
	var list: Array = buildings.values()

	# проход 1: генераторы и спрос на энергию
	for b in list:
		if _busy(b):
			continue
		var t: int = b.type
		var team: int = b.team
		var out := 0.0
		if t == D.SOLAR:
			if not skies.has(b.pn):
				skies[b.pn] = SkyCalc.state(world_time, b.pn)
			var lvl := SkyCalc.level_at(_pl(int(b.pn)).dirs[b.cell], skies[b.pn])
			out = D.SOLAR_POWER * float(lvl) / float(D.LIGHT_LEVELS)
		elif t == D.COAL_PLANT:
			if b.burn <= 0 and _buf_take(b, D.I_COAL, 1):
				b.burn = D.COAL_BURN_TICKS
			if b.burn > 0:
				b.burn -= 1
				out = D.COAL_POWER
		elif t == D.NUCLEAR:
			b.wt += 1
			if b.wt >= D.NUCLEAR_WATER_TICKS:
				b.wt = 0
				b.cool = _buf_take(b, D.I_WATER, 1)
			if b.burn <= 0 and b.cool and _buf_take(b, D.I_URANIUM, 1):
				b.burn = D.NUCLEAR_URANIUM_TICKS
			if b.burn > 0 and b.cool:
				b.burn -= 1
				out = D.NUCLEAR_POWER
		var root: int = power_root.get(b.id, b.id)
		if D.GENERATORS.has(t):
			b.pout = out
			prod[team] += out
			gprod[root] = float(gprod.get(root, 0.0)) + out
		if D.POWER_USE.has(t) and _wants_power(b):
			var pu: float = float(D.POWER_USE[t]) * float(D.UPG_POWER[int(b.lvl) - 1])
			demand[team] += pu
			gdem[root] = float(gdem.get(root, 0.0)) + pu

	# аккумуляторы: излишек сети заряжает их, нехватку они покрывают
	var bats := {}   # корень сети -> аккумуляторы
	var stored := [0.0, 0.0]
	var cap := [0.0, 0.0]
	for b in list:
		if b.type == D.BATTERY and not _busy(b):
			var broot: int = power_root.get(b.id, b.id)
			if not bats.has(broot):
				bats[broot] = []
			bats[broot].append(b)
	for root in bats:
		var surplus: float = float(gprod.get(root, 0.0)) - float(gdem.get(root, 0.0))
		var arr: Array = bats[root]
		var step: float = D.BATTERY_RATE * D.TICK
		if surplus > 0.0:
			var e: float = surplus * D.TICK
			for bt in arr:
				var take: float = minf(minf(D.BATTERY_CAP - float(bt.charge), step), e)
				bt.charge = float(bt.charge) + take
				bt.bflow = take
				e -= take
		else:
			var need: float = -surplus * D.TICK
			var got := 0.0
			for bt in arr:
				var give: float = minf(minf(float(bt.charge), step), need - got)
				bt.charge = float(bt.charge) - give
				bt.bflow = -give
				got += give
			gprod[root] = float(gprod.get(root, 0.0)) + got / D.TICK
		for bt in arr:
			var tm: int = bt.team
			if tm < 2:
				stored[tm] += float(bt.charge)
				cap[tm] += D.BATTERY_CAP

	# в каждой сети: не хватает энергии — все её машины работают медленнее
	var gratio := {}
	for root in gdem:
		gratio[root] = minf(1.0, float(gprod.get(root, 0.0)) / float(gdem[root]))
	for team in 2:
		power_stats[team] = [prod[team], demand[team], stored[team], cap[team]]

	# проход 2: работа (стройка и снос — вместо работы)
	for b in list:
		if not buildings.has(b.id):
			continue
		if _busy(b):
			_build_tick(b)
			continue
		aim_r = _pl(int(b.pn)).radius
		var t: int = b.type
		var r := 1.0
		if D.POWER_USE.has(t):
			var root: int = power_root.get(b.id, b.id)
			r = float(gratio.get(root, 1.0 if power_has_gen.has(root) else 0.0))
			b.pr = r
		if t == D.CORE:
			if int(b.get("burn_t", 0)) > 0:
				b.burn_t = int(b.burn_t) - 1
		elif _is_drill(t):
			_drill_tick(b, r)
		elif t == D.CONVEYOR or t == D.PIPE or t == D.SORTER:
			_belt_tick(b)
		elif D.RECIPES.has(t):
			_factory_tick(b, r * float(D.UPG_SPEED[int(b.lvl) - 1]))
		elif t == D.ASSEMBLER:
			_assembler_tick(b)
		elif t == D.TURRET:
			_turret_tick(b)
		elif t == D.TURRET2:
			_turret2_tick(b)
		elif t == D.TURRET3:
			_turret3_tick(b)
		elif t == D.TURRET4:
			_turret4_tick(b)
		elif t == D.AA_GUN:
			_aa_tick(b)
		elif t == D.SPLITTER or t == D.JUNCTION or t == D.BRIDGE:
			_logistic_tick(b)
		elif t == D.REPAIR or t == D.UNIT_REPAIR:
			_repair_tick(b, r)
		elif t == D.UNLOADER:
			_unloader_tick(b)
		elif t == D.LOADER or t == D.FUEL_DEPOT:
			_depot_tick(b)
		elif t == D.SPACE_DOCK:
			_dock_tick(b)
		elif t == D.LAUNCH_PAD:
			_pad_tick(b)
	_couriers_tick()
	_players_tick()
	_units_tick()
	_rovers_tick()
	_proj_tick()
	_capture_tick()
	state_acc += 1
	if state_acc >= 5:
		state_acc = 0
		_send_states()


# ---------------------------------------------------------------------
# Логистика: точка выгрузки и роверы
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# Корабли: сборка на площадке, заправка, посадка/высадка пилота
# ---------------------------------------------------------------------

func _ship_dv(fuel: float, kind := 0) -> float:
	var dry: float = D.SHIP_KINDS[kind].dry
	return float(D.SHIP_KINDS[kind].get("ve", D.SCOUT_VE)) * log((dry + fuel * D.FUEL_UNIT_MASS) / dry)


func _ship_tank(sh) -> float:
	return float(D.SHIP_KINDS[int(sh.kind)].tank)


func _cargo_used(sh) -> int:
	var n := 0
	for c in sh.cargo:
		n += int(D.UNIT_STATS[int(c[0])].slots)
	return n


func _cost_dict_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for it in cost:
		parts.append("%s %d" % [D.ITEM_NAMES[it], cost[it]])
	return ", ".join(parts)


## Где стоит корабль на площадке: центр контура, поверх основания.
func _pad_spot(b: Dictionary) -> Vector3:
	var c := _foot_center(b.cells, int(b.pn))
	return c + c.normalized() * 0.5


func _pad_ship(b: Dictionary):
	for sh in ships.values():
		if sh.pad == b.id:
			return sh
	return null


func _pad_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		if b.timer == 0:
			var spot := _pad_spot(b)
			var id := next_ship_id
			next_ship_id += 1
			var kind: int = b.get("ship_kind", 0)
			ships[id] = {"id": id, "team": b.team, "pad": b.id, "pos": spot, "pn": b.pn, "kind": kind,
				"quat": Quaternion(_up_basis(spot.normalized())), "state": 0, "pilot": -1, "cargo": [],
				"fuel": float(D.SHIP_KINDS[kind].tank) if creative else 0.0, "thrust": false,
				"hp": int(D.SHIP_HP[kind])}
		return
	# заправка стоящего на площадке корабля: 1 единица за 0.3 с
	var sh = _pad_ship(b)
	if sh == null or sh.state == 1 or float(sh.fuel) >= _ship_tank(sh) - 0.001:
		return
	if creative:
		sh.fuel = _ship_tank(sh)
		return
	b.wt += 1
	if b.wt >= 3:
		b.wt = 0
		if _buf_take(b, int(D.SHIP_KINDS[int(sh.kind)].get("fuel", D.I_FUEL)), 1):   # истребителю — уникальное
			sh.fuel = minf(_ship_tank(sh), float(sh.fuel) + 1.0)


func server_pad_action(team: int, cell: int, pn: int, kind := 0) -> void:
	if not grid.has(_k(pn, cell)):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if b.type != D.LAUNCH_PAD or b.team != team or b.timer > 0 or _pad_ship(b) != null:
		return
	kind = clampi(kind, 0, D.SHIP_KINDS.size() - 1)
	var cost: Dictionary = D.SHIP_COSTS[kind]
	var st: Dictionary = storage[team]
	if not creative:
		for it in cost:
			if int(st.get(it, 0)) < int(cost[it]):
				return
		for it in cost:
			st[it] = int(st[it]) - int(cost[it])
	b["ship_kind"] = kind
	b.timer = int(D.SHIP_KINDS[kind].build)


## Транспорт забирает своих юнитов рядом (сколько влезет мест).
func server_ship_load(peer: int, id: int) -> void:
	if not ships.has(id) or ships[id].pilot != peer:
		return
	var sh: Dictionary = ships[id]
	var cap: int = D.SHIP_KINDS[int(sh.kind)].cargo
	var used := _cargo_used(sh)
	var only: int = int(D.SHIP_KINDS[int(sh.kind)].get("only", -1))
	for u in units:
		if u.team != sh.team or u.pn != sh.pn or u.hp <= 0:
			continue
		if only >= 0 and int(u.kind) != only:
			continue   # истребитель берёт только уникальных мехов
		var slots: int = D.UNIT_STATS[u.kind].slots
		if used + slots > cap or _upos(u).distance_to(sh.pos) > D.LOAD_RADIUS:
			continue
		sh.cargo.append([u.kind, u.hp])
		used += slots
		u.hp = 0
	units = units.filter(func(x): return x.hp > 0)


## Транспорт выгружает юнитов вокруг себя; они охраняют точку высадки.
func server_ship_unload(peer: int, id: int) -> void:
	if not ships.has(id) or ships[id].pilot != peer or int(ships[id].pn) < 0:
		return
	var sh: Dictionary = ships[id]
	if sh.cargo.is_empty():
		return
	var c0 := _pl(int(sh.pn)).nearest_cell(Vector3(sh.pos).normalized())
	var around: Array = []
	var r := _pl(int(sh.pn)).rings(c0, 3)
	for x in r:
		if int(r[x]) >= 2:
			around.append(x)
	var i := 0
	for c in sh.cargo:
		_spawn_unit(sh.team, around[i % around.size()], sh.pn, int(c[0]), int(c[1]))
		i += 1
	sh.cargo = []


func server_board(peer: int, id: int) -> void:
	if not ships.has(id) or not players.has(peer):
		return
	var sh: Dictionary = ships[id]
	var pl: Dictionary = players[peer]
	if sh.pilot != -1 or sh.team != pl.team or pl.hp <= 0:
		return
	if int(pl.get("pn", D.HOME_PLANET)) != sh.pn or Vector3(pl.pos).distance_to(sh.pos) > 7.0:
		return
	sh.pilot = peer
	sh.state = 1
	if peer == 1 and not headless:
		_start_piloting(id, sh.pos, sh.quat, sh.fuel, sh.pn, int(sh.kind))
	else:
		ev_board.rpc_id(peer, id, sh.pos, sh.quat, sh.fuel, sh.pn, int(sh.kind))


func server_ship_state(peer: int, id: int, pos: Vector3, quat: Quaternion, fuel: float, thrust: bool, pn: int) -> void:
	if not ships.has(id) or ships[id].pilot != peer:
		return
	var sh: Dictionary = ships[id]
	var now := Time.get_ticks_msec() / 1000.0
	if pn >= 0 and int(sh.pn) != pn:
		# корабль вошёл в атмосферу планеты — тревога другой команде
		_alert_team(1 - int(sh.team), "⚠ Вражеский %s вошёл в атмосферу: %s" % [
			String(D.SHIP_KINDS[int(sh.kind)].name).to_lower(), D.PLANETS[pn].name], pn, 2)
	var dt_rep := now - float(sh.get("rep_t", now))
	if dt_rep > 0.01 and int(sh.pn) == pn:
		sh["vel"] = (pos - Vector3(sh.pos)) / dt_rep
	sh["rep_t"] = now
	sh.pn = clampi(pn, -1, D.PLANETS.size() - 1)
	sh.pos = pos
	sh.quat = quat
	sh.fuel = clampf(fuel, 0.0, float(sh.fuel))   # заправиться в полёте нельзя
	sh.thrust = thrust
	sh.pad = -1


func server_ship_exit(peer: int, id: int, pos: Vector3, quat: Quaternion, pn: int) -> void:
	if not ships.has(id) or ships[id].pilot != peer:
		return
	var sh: Dictionary = ships[id]
	sh.pn = clampi(pn, 0, D.PLANETS.size() - 1)
	sh.pos = pos
	sh.quat = quat
	sh.pilot = -1
	sh.state = 0
	sh.thrust = false
	# сел на свою свободную площадку — встаёт на неё и снова заправляется
	sh.pad = -1
	for b in buildings.values():
		if b.type == D.LAUNCH_PAD and b.team == sh.team and b.pn == sh.pn and _pad_ship(b) == null \
				and _pad_spot(b).distance_to(pos) < 6.0:
			sh.pad = b.id
			sh.pos = _pad_spot(b)
			break


func server_ship_crash(peer: int, id: int) -> void:
	if ships.has(id) and ships[id].pilot == peer:
		var at: Vector3 = ships[id].pos
		var cpn: int = ships[id].pn
		var skind: int = int(ships[id].kind)
		var steam: int = int(ships[id].team)
		ships.erase(id)
		if skind == 3:
			_blast(at, steam, cpn, D.KAMIKAZE_R, D.KAMIKAZE_DMG)   # камикадзе: врезался или подорван
		_damage_player(peer, 40)
		for p in Net.ready_peers:
			fx_boom.rpc_id(p, at, 6.0, false, cpn)
		if not headless and cpn == my_pn:
			_boom(at, 6.0, false)


func _unloader_tick(b: Dictionary) -> void:
	b.out_blocked = false
	var it: int = b.filter
	if it == D.I_NONE or int(b.buf.get(it, 0)) <= 0:
		return
	if _output(b, it):
		b.buf[it] = int(b.buf[it]) - 1
	else:
		b.out_blocked = true


func _spawn_rover(home: Dictionary) -> void:
	var d: Vector3 = _pl(int(home.pn)).dirs[home.cell]
	rovers.append({"id": next_rover_id, "team": home.team, "home": home.id, "dir": d, "pn": home.pn,
		"cell": home.cell, "fwd": _up_basis(d).x, "state": 0, "hp": D.ROVER_HP,
		"kind": 1 if home.type == D.FUEL_DEPOT else 0,   # 0 — курьер, 1 — заправщик
		"cargo_item": D.I_NONE, "cargo_n": 0, "target": -1})
	next_rover_id += 1


func _rpos(r: Dictionary) -> Vector3:
	var d: Vector3 = r.dir
	return d * _pl(int(r.pn)).top_r(r.cell)


## Куда можно отвезти item: точка выгрузки с этим фильтром, а топливо — ещё и стартовая площадка.
func _find_drop(team: int, item: int, from: Vector3, pn: int) -> int:
	var best := -1
	var bd := INF
	for b in buildings.values():
		if b.team != team or b.pn != pn or _busy(b) or not _drop_ok(b, item):
			continue
		var d: float = from.distance_squared_to(_bpos(b))
		if d < bd:
			bd = d
			best = b.id
	return best


func _drop_ok(b: Dictionary, item: int) -> bool:
	return _drop_room(b, item) > 0


func _drop_room(b: Dictionary, item: int) -> int:
	if b.type == D.UNLOADER and b.filter == item:
		return D.UNLOADER_CAP - int(b.buf.get(item, 0))
	if b.type == D.LAUNCH_PAD and (item == D.I_FUEL or item == D.I_UFUEL):
		return D.PAD_FUEL_CAP - int(b.buf.get(item, 0))
	return 0


## Ближайшая своя точка выгрузки, которая принимает item и где есть место. -1 — нет такой.
func _find_unloader(team: int, item: int, from: Vector3, pn: int) -> int:
	var best := -1
	var bd := INF
	for b in buildings.values():
		if b.type != D.UNLOADER or b.team != team or b.filter != item or b.pn != pn:
			continue
		if int(b.buf.get(item, 0)) >= D.UNLOADER_CAP:
			continue
		var d: float = from.distance_squared_to(_bpos(b))
		if d < bd:
			bd = d
			best = b.id
	return best


## Едем по поверхности к точке. true — приехали.
func _rover_move(r: Dictionary, target: Vector3) -> bool:
	var pos := _rpos(r)
	var dist := pos.distance_to(target)
	if dist <= D.ROVER_REACH:
		return true
	var ud: Vector3 = r.dir
	var tdir := target.normalized()
	var tangent := tdir - ud * ud.dot(tdir)
	if tangent.length() > 0.00001:
		var step: float = minf(D.ROVER_SPEED, dist - D.ROVER_REACH + 0.01)
		r.fwd = tangent.normalized()
		r.dir = (ud + tangent.normalized() * (step / _pl(int(r.pn)).radius)).normalized()
		r.cell = _pl(int(r.pn)).walk(r.cell, r.dir)
	return false


## Ровер: дома грузится (до ROVER_CAP одного груза, у которого есть куда ехать),
## везёт к ближайшей подходящей точке выгрузки, выгружает, возвращается.
func _rovers_tick() -> void:
	for r in rovers:
		if not buildings.has(r.home):
			continue
		var home: Dictionary = buildings[r.home]
		if r.state == 0:
			# дома: выбираем груз, которого больше всего и для которого есть точка выгрузки
			# курьер возит только твёрдое, заправщик — только топливо
			var buf: Dictionary = home.buf
			var best_item := D.I_NONE
			var best_n := 0
			var tanker: bool = int(r.kind) == 1
			for it in buf:
				var n := int(buf[it])
				if tanker != (int(it) == D.I_FUEL) or (not tanker and D.FLUIDS.has(int(it))):
					continue
				if n > best_n and _find_drop(r.team, it, _rpos(r), r.pn) != -1:
					best_n = n
					best_item = it
			if best_item != D.I_NONE:
				var take := mini(best_n, D.TANKER_CAP if tanker else D.ROVER_CAP)
				buf[best_item] = best_n - take
				r.cargo_item = best_item
				r.cargo_n = take
				r.target = _find_drop(r.team, best_item, _rpos(r), r.pn)
				r.state = 1
		elif r.state == 1:
			# везём
			if not buildings.has(r.target) or not _drop_ok(buildings[r.target], r.cargo_item):
				r.target = _find_drop(r.team, r.cargo_item, _rpos(r), r.pn)
				if r.target == -1:
					continue   # некуда — ждём на месте
			var tgt: Dictionary = buildings[r.target]
			if _rover_move(r, _bpos(tgt)):
				var have := int(tgt.buf.get(r.cargo_item, 0))
				var n := mini(_drop_room(tgt, r.cargo_item), r.cargo_n)
				if n > 0:
					tgt.buf[r.cargo_item] = have + n
					r.cargo_n -= n
				if r.cargo_n <= 0:
					r.cargo_item = D.I_NONE
					r.state = 2
				else:
					r.target = _find_drop(r.team, r.cargo_item, _rpos(r), r.pn)   # эта полна — ищем другую
		elif r.state == 2:
			# домой
			if _rover_move(r, _bpos(home)):
				r.state = 0


# ---------------------------------------------------------------------
# Космический курьер: один на команду, сам летает между космопортами.
# В порту: выгружает привезённое, догружает груз с конвейеров, заправляется по трубе.
# Полный бак + 1 мин ожидания — вылет в порт на планете, которую назначил игрок (держи E),
# иначе — обратно, откуда прилетел.
# ---------------------------------------------------------------------

func _any_dock(team: int):
	for b in buildings.values():
		if b.type == D.SPACE_DOCK and int(b.team) == team and not _busy(b):
			return b
	return null


func _dock_on(team: int, pn: int):
	for b in buildings.values():
		if b.type == D.SPACE_DOCK and int(b.team) == team and int(b.pn) == pn and not _busy(b):
			return b
	return null


func _cargo_total(c: Dictionary) -> int:
	var n := 0
	for it in c.cargo:
		n += int(c.cargo[it])
	return n


func _courier_dur(a: int, b: int) -> float:
	if a == b:
		return 30.0
	var r1: float = D.PLANETS[a].a
	var r2: float = D.PLANETS[b].a
	var at := (r1 + r2) * 0.5
	return maxf(40.0, PI * sqrt(at * at * at / D.GIANT_MU) * 0.5 + 16.0)   # вдвое быстрее перелёта по Гоману


func _courier_target(c: Dictionary, d: Dictionary):
	var pn: int = int(d.get("dest_pn", -1))
	if pn < 0 or pn == int(d.pn):
		if buildings.has(int(c.get("prev", -1))):
			pn = int(buildings[int(c.prev)].pn)
		else:
			return null
	if pn == int(d.pn):
		return null
	return _dock_on(int(c.team), pn)


func _courier_lost(team: int, why: String) -> void:
	couriers.erase(team)
	courier_respawn[team] = D.COURIER_RESPAWN_TICKS
	_alert_team(team, "Космический курьер потерян (%s) — новый через 1 мин" % why, -1, 1)


func _couriers_tick() -> void:
	for team in 2:
		if not couriers.has(team):
			if courier_respawn[team] > 0:
				courier_respawn[team] -= 1
				continue
			var nd = _any_dock(team)
			if nd != null:
				couriers[team] = {"team": team, "at": nd.id, "to": -1, "prev": -1, "state": 0, "cargo": {},
					"fuel": 0, "wait": -1, "unload": false, "t0": 0.0, "dur": 0.0,
					"from_pn": nd.pn, "to_pn": nd.pn, "from_cell": nd.cell, "to_cell": nd.cell}
			continue
		var c: Dictionary = couriers[team]
		if int(c.state) == 0:
			if not buildings.has(int(c.at)):
				_courier_lost(team, "космопорт разрушен")
				continue
			var d: Dictionary = buildings[int(c.at)]
			if int(d.team) != team:
				_courier_lost(team, "космопорт захвачен")
				continue
			var recv: Dictionary = d.get("recv", {})
			d["recv"] = recv
			if bool(c.unload):
				# выгрузка: по 5 за тик в приёмный склад порта
				var rtot := 0
				for it in recv:
					rtot += int(recv[it])
				var k := 5
				for it in c.cargo.keys():
					while k > 0 and rtot < D.DOCK_RECV_CAP and int(c.cargo[it]) > 0:
						c.cargo[it] = int(c.cargo[it]) - 1
						recv[it] = int(recv.get(it, 0)) + 1
						rtot += 1
						k -= 1
					if int(c.cargo[it]) <= 0:
						c.cargo.erase(it)
				if c.cargo.is_empty():
					c.unload = false
			else:
				# погрузка: по 5 за тик с конвейерного склада порта
				var k2 := 5
				for it in d.buf.keys():
					if int(it) == D.I_FUEL:
						continue
					while k2 > 0 and _cargo_total(c) < D.COURIER_CARGO and int(d.buf[it]) > 0:
						d.buf[it] = int(d.buf[it]) - 1
						c.cargo[it] = int(c.cargo.get(it, 0)) + 1
						k2 -= 1
			# заправка по трубе
			if int(c.fuel) < D.COURIER_FUEL and _buf_take(d, D.I_FUEL, 1):
				c.fuel = int(c.fuel) + 1
			if int(c.fuel) >= D.COURIER_FUEL and not bool(c.unload):
				if int(c.wait) < 0:
					c.wait = D.COURIER_WAIT_TICKS
				c.wait = int(c.wait) - 1
				if int(c.wait) <= 0:
					var tgt = _courier_target(c, d)
					if tgt == null:
						c.wait = 0   # лететь некуда — ждёт назначения
					else:
						c.fuel = 0
						c.state = 1
						c.prev = d.id
						c.to = tgt.id
						c.from_pn = d.pn
						c.to_pn = tgt.pn
						c.from_cell = d.cell
						c.to_cell = tgt.cell
						c.t0 = world_time
						c.dur = _courier_dur(int(d.pn), int(tgt.pn))
						c.wait = -1
		else:
			if world_time < float(c.t0) + float(c.dur):
				continue
			var dst = buildings.get(int(c.to))
			if dst == null or int(dst.team) != team or dst.type != D.SPACE_DOCK:
				_courier_lost(team, "порт назначения разрушен")
				continue
			c.state = 0
			c.at = int(c.to)
			c.unload = true
			c.wait = -1


## Порт выдаёт привезённое на конвейеры вокруг (по 1 за тик).
func _dock_tick(b: Dictionary) -> void:
	var recv: Dictionary = b.get("recv", {})
	for it in recv.keys():
		if int(recv[it]) <= 0:
			recv.erase(it)
			continue
		if _output(b, int(it)):
			recv[it] = int(recv[it]) - 1
			return


func _dock_status(b: Dictionary) -> Array:
	var dest: int = int(b.get("dest_pn", -1))
	var dtxt: String = "цель: " + (String(D.PLANETS[dest].name) if dest >= 0 and dest != int(b.pn) else "обратно, откуда прилетел") + " (держи E)"
	var recv: Dictionary = b.get("recv", {})
	var rtot := 0
	for it in recv:
		rtot += int(recv[it])
	var rtxt := ("  · принято %d, выдаёт на конвейеры" % rtot) if rtot > 0 else ""
	if not couriers.has(int(b.team)):
		return [ST_IDLE, "курьер появится через %d с, %s" % [int(ceil(courier_respawn[int(b.team)] * D.TICK)), dtxt]]
	var c: Dictionary = couriers[int(b.team)]
	if int(c.state) == 1:
		var left := float(c.t0) + float(c.dur) - world_time
		return [ST_OK, "курьер летит на %s, прилёт через %d с, %s%s" % [D.PLANETS[int(c.to_pn)].name, int(left), dtxt, rtxt]]
	if int(c.at) != int(b.id):
		var opn: int = int(buildings[int(c.at)].pn) if buildings.has(int(c.at)) else 0
		return [ST_IDLE, "курьер в другом порту (%s), %s%s" % [D.PLANETS[opn].name, dtxt, rtxt]]
	if bool(c.unload):
		return [ST_OK, "курьер выгружается: осталось %d%s" % [_cargo_total(c), rtxt]]
	if int(c.fuel) < D.COURIER_FUEL:
		return [ST_IDLE, "курьер здесь: топливо %d/%d (подай по трубе), груз %d/%d, %s%s" % [int(c.fuel), D.COURIER_FUEL,
			_cargo_total(c), D.COURIER_CARGO, dtxt, rtxt]]
	if _courier_target(c, b) == null:
		return [ST_SLOW, "курьер заправлен, но лететь некуда — нужен свой космопорт на другой планете, %s" % dtxt]
	return [ST_OK, "курьер заправлен, груз %d/%d, вылет через %d с, %s%s" % [_cargo_total(c), D.COURIER_CARGO,
		int(ceil(maxf(float(c.wait), 0.0) * D.TICK)), dtxt, rtxt]]


@rpc("any_peer", "call_remote", "reliable")
func req_set_dest(cell: int, pn: int) -> void:
	if multiplayer.is_server():
		var peer := multiplayer.get_remote_sender_id()
		server_set_dest(Net.team_of(peer), cell, pn, _peer_pn(peer))


func server_set_dest(team: int, cell: int, dest: int, pn: int) -> void:
	if not grid.has(_k(pn, cell)):
		return
	var b: Dictionary = buildings[grid[_k(pn, cell)]]
	if b.type != D.SPACE_DOCK or int(b.team) != team:
		return
	b["dest_pn"] = clampi(dest, -1, D.PLANETS.size() - 1)


func _planet_name(j) -> String:
	return String(D.PLANETS[int(j)].name)


func _dock_info(j) -> Array:
	return [String(D.PLANETS[int(j)].name), "Космический курьер полетит сюда (нужен свой космопорт на этой планете)"]


@rpc("authority", "call_remote", "unreliable_ordered")
func courier_snap(cv: Array) -> void:
	cur_couriers = cv


## Клиент: курьер стоит в порту, взлетает/садится у планеты, а между планетами — метка на карте системы.
func _update_couriers() -> void:
	var seen := {}
	for e in cur_couriers:
		var team: int = e[0]
		seen[team] = true
		if not courier_nodes.has(team):
			var nm := _make_ship(team, 1)
			local_root.add_child(nm)
			var nl := _marker_label("◆ курьер", D.TEAM_COLORS[team])
			space_root.add_child(nl)
			courier_nodes[team] = [nm, nl]
		var model: Node3D = courier_nodes[team][0]
		var lbl: Label3D = courier_nodes[team][1]
		var state: int = e[1]
		var flame: Node3D = model.get_meta("flame")
		var asc := 8.0
		if state == 0:
			var at_pn: int = e[3]
			var at_cell: int = e[2]
			model.visible = at_pn == my_pn
			flame.visible = false
			if model.visible:
				var up: Vector3 = planet.dirs[at_cell]
				model.transform = Transform3D(_up_basis(up).scaled(Vector3.ONE * 0.8), planet.top_pos(at_cell) + up * 0.55)
			lbl.position = SkyCalc.planet_pos(at_pn, world_time) + Vector3.UP * D.planet_r(at_pn) * 2.0
			continue
		var fpn: int = e[4]
		var tpn: int = e[5]
		var fcell: int = e[6]
		var tcell: int = e[7]
		var t0: float = e[8]
		var dur: float = e[9]
		var u := world_time - t0
		model.visible = false
		var hgt := -1.0
		var cell := fcell
		if u < asc and fpn == my_pn:
			hgt = 0.55 + 160.0 * pow(u / asc, 2.0)
		elif u > dur - asc and tpn == my_pn:
			hgt = 0.55 + 160.0 * pow(maxf(dur - u, 0.0) / asc, 2.0)
			cell = tcell
		if hgt >= 0.0:
			var up: Vector3 = planet.dirs[cell]
			model.visible = true
			flame.visible = true
			model.transform = Transform3D(_up_basis(up).scaled(Vector3.ONE * 0.8), planet.top_pos(cell) + up * hgt)
		# карта системы: по дуге от планеты отправления к планете прибытия
		var pf := SkyCalc.planet_pos(fpn, t0 + asc)
		var pt := SkyCalc.planet_pos(tpn, t0 + dur - asc)
		var k := clampf((u - asc) / maxf(dur - 2.0 * asc, 1.0), 0.0, 1.0)
		var s := k * k * (3.0 - 2.0 * k)
		var a0 := atan2(pf.z, pf.x)
		var da := fposmod(atan2(pt.z, pt.x) - a0, TAU)
		var rr := lerpf(pf.length(), pt.length(), s)
		lbl.position = Vector3(cos(a0 + da * s), 0.0, sin(a0 + da * s)) * rr + Vector3.UP * 80.0
	for team in courier_nodes.keys():
		if not seen.has(team):
			for nd in courier_nodes[team]:
				(nd as Node).queue_free()
			courier_nodes.erase(team)


## Курьер/заправщик подбит: взрыв, через минуту база выпустит новый.
func _damage_rover(r: Dictionary, dmg: int) -> void:
	if bool(r.get("dead", false)):
		return
	r.hp = int(r.get("hp", D.ROVER_HP)) - dmg
	if int(r.hp) > 0:
		return
	r["dead"] = true
	var at := _rpos(r) + _rpos(r).normalized() * 0.6
	rovers.erase(r)
	if buildings.has(r.home):
		buildings[r.home]["rover_t"] = D.ROVER_RESPAWN_TICKS
		_alert_team(int(r.team), "%s уничтожен — новый через 1 мин" % ("Заправщик" if int(r.kind) == 1 else "Курьер"),
			int(r.pn), 1)
	for p in Net.ready_peers:
		fx_boom.rpc_id(p, at, 2.5, false, int(r.pn))
	if not headless and int(r.pn) == my_pn:
		_boom(at, 2.5, false)


## База курьера: если его уничтожили — отсчёт до нового.
func _depot_tick(b: Dictionary) -> void:
	if int(b.get("rover_t", 0)) <= 0:
		return
	b.rover_t = int(b.rover_t) - 1
	if b.rover_t <= 0:
		_spawn_rover(b)


func _buf_take(b: Dictionary, item: int, n: int) -> bool:
	var buf: Dictionary = b.buf
	if int(buf.get(item, 0)) >= n:
		buf[item] = int(buf[item]) - n
		return true
	return false


func _wants_power(b: Dictionary) -> bool:
	var t: int = b.type
	if t == D.DRILL2:
		return not b.blocked
	if t == D.DRILL3:
		return not b.blocked and b.water > 0
	if D.RECIPES.has(t):
		return b.cur != -1
	if t == D.REPAIR or t == D.UNIT_REPAIR:
		return true
	return false


func _drill_tick(b: Dictionary, r: float) -> void:
	var t: int = b.type
	var ore: int = b.ore
	if b.blocked:
		# выход забит — пробуем выгрузить готовую руду
		if _output(b, int(D.ORE_PRODUCT.get(ore, ore))):
			b.blocked = false
			b.prog = 0.0
		return
	if t == D.DRILL3 and b.water <= 0:
		return
	b.prog += r
	# скорость пропорциональна доле рудных клеток под буром
	var need: float = float(D.DRILL_TICKS[t]) * float(b.cells.size()) / float(maxi(int(b.ore_n), 1))
	if D.RARE_ORES.has(ore):
		need /= D.RARE_SPEED   # редкие породы добываются в 5 раз медленнее
	if b.prog >= need:
		if t == D.DRILL3:
			b.wuse += 1
			if b.wuse >= D.DRILL3_WATER_PER:
				b.wuse = 0
				b.water -= 1
		if _output(b, int(D.ORE_PRODUCT.get(ore, ore))):
			b.prog = 0.0
		else:
			b.blocked = true


func _belt_tick(b: Dictionary) -> void:
	if b.item == D.I_NONE:
		return
	var speed: float = D.PIPE_SPEED if b.type == D.PIPE else D.CONVEYOR_SPEED
	b.prog = minf(b.prog + speed, 1.0)
	if b.prog >= 1.0 and _push(_out_cell(b), b.id, b.team, b.item, b.pn):
		b.item = D.I_NONE
		b.prog = 0.0


func _factory_tick(b: Dictionary, r: float) -> void:
	var recs: Array = D.RECIPES[b.type]
	b.out_blocked = false
	if b.out_n > 0:
		if _output(b, b.out_item):
			b.out_n -= 1
		else:
			b.out_blocked = true
		if b.out_n > 0:
			return   # ждём, пока выгрузим готовое
	if b.cur == -1:
		for i in recs.size():
			var cand: Dictionary = recs[i]
			var ins: Dictionary = cand["in"]
			if _has_inputs(b, ins):
				for it in ins:
					b.buf[it] = int(b.buf[it]) - int(ins[it])
				b.cur = i
				b.prog = 0.0
				break
	if b.cur != -1:
		var rec: Dictionary = recs[b.cur]
		b.prog += r
		if b.prog >= float(rec["t"]):
			b.out_item = rec["out"]
			b.out_n = rec["n"]
			b.cur = -1
			b.prog = 0.0


func _has_inputs(b: Dictionary, ins: Dictionary) -> bool:
	var buf: Dictionary = b.buf
	for it in ins:
		if int(buf.get(it, 0)) < int(ins[it]):
			return false
	return true


## Выдать 1 предмет в любую клетку вокруг контура (по кругу). true — если кто-то взял.
func _output(b: Dictionary, item: int) -> bool:
	var outs: Array = b.get("fouts", b.outs)
	var k := outs.size()
	for i in k:
		var idx: int = (b.rr + i) % k
		if _push(outs[idx], b.id, b.team, item, b.pn):
			b.rr = (idx + 1) % k
			return true
	return false


## Может ли постройка o принять предмет (не конвейер и не ядро).
func _accepts(o: Dictionary, item: int) -> bool:
	var t: int = o.type
	var buf: Dictionary = o.buf
	if D.RECIPES.has(t):
		for rec in D.RECIPES[t]:
			if rec["in"].has(item):
				return int(buf.get(item, 0)) < D.BUFFER_CAP
		return false
	if t == D.COAL_PLANT:
		return item == D.I_COAL and int(buf.get(item, 0)) < D.BUFFER_CAP
	if t == D.NUCLEAR:
		if item == D.I_URANIUM:
			return int(buf.get(item, 0)) < D.NUCLEAR_URANIUM_CAP
		if item == D.I_WATER:
			return int(buf.get(item, 0)) < D.NUCLEAR_WATER_CAP
		return false
	if t == D.DRILL3:
		return item == D.I_WATER and o.water < D.BUFFER_CAP
	if t == D.ASSEMBLER:
		if int(o.ukind) < 0:
			return false   # тип не выбран — ничего не берёт
		var need: Dictionary = D.UNIT_RECIPES[o.ukind]
		return need.has(item) and int(buf.get(item, 0)) < int(need[item]) * 2
	if t == D.LAUNCH_PAD:
		return (item == D.I_FUEL or item == D.I_UFUEL) and int(buf.get(item, 0)) < D.PAD_FUEL_CAP
	if t == D.AA_GUN:
		if item == D.I_WATER:
			return o.water < D.AA_WATER_CAP
		var total := 0
		for it in buf:
			total += int(buf[it])
		return total < D.AA_AMMO_CAP
	if t == D.TURRET2:
		return item == D.I_COPPER and int(buf.get(item, 0)) < D.T2_AMMO_CAP
	if t == D.TURRET4:
		return item == D.I_UALLOY and int(buf.get(item, 0)) < D.T4_AMMO_CAP
	if t == D.TURRET3:
		if item != D.I_LEAD and item != D.I_URANIUM:
			return false
		return int(buf.get(D.I_LEAD, 0)) + int(buf.get(D.I_URANIUM, 0)) < D.T3_AMMO_CAP
	if t == D.FUEL_DEPOT:
		return item == D.I_FUEL and int(buf.get(item, 0)) < D.DEPOT_CAP
	if t == D.SPACE_DOCK:
		if item == D.I_FUEL:
			return int(buf.get(item, 0)) < D.COURIER_FUEL * 2
		if D.FLUIDS.has(item):
			return false
		var tot := 0
		for it in buf:
			if int(it) != D.I_FUEL:
				tot += int(buf[it])
		return tot < D.DOCK_CAP
	if t == D.LOADER:
		if D.FLUIDS.has(item):
			return false
		var total := 0
		for it in buf:
			total += int(buf[it])
		return total < D.LOADER_CAP
	return false


## Положить предмет в клетку cell от постройки src_id. true — если взяли.
func _push(cell: int, src_id: int, team: int, item: int, pn: int) -> bool:
	if not grid.has(_k(pn, cell)):
		return false
	var o: Dictionary = buildings[grid[_k(pn, cell)]]
	if o.team != team or _busy(o):
		return false
	var t: int = o.type
	if t == D.SPLITTER or t == D.JUNCTION or t == D.BRIDGE:
		# берут и твёрдое, и воду — совмещены с трубами
		if o.item != D.I_NONE:
			return false
		if t == D.BRIDGE and int(grid.get(_k(pn, _out_cell(o)), -1)) == src_id:
			return false
		if t == D.JUNCTION:
			var jout := _junction_out(o, src_id, pn)
			if jout < 0:
				return false
			o["jout"] = jout
		o.item = item
		o.prog = 0.0
		o["src"] = src_id
		o["flow_t"] = sim_n
		return true
	if t == D.CONVEYOR or t == D.PIPE or t == D.SORTER:
		# вода и топливо — только в трубы, всё твёрдое — только на конвейеры
		if D.FLUIDS.has(item) != (t == D.PIPE):
			return false
		if t == D.SORTER and item != int(o.filter):
			return false   # сортировщик берёт только выбранный груз
		# лента, которая смотрит в источник, у него ничего не берёт
		if o.item != D.I_NONE or int(grid.get(_k(pn, _out_cell(o)), -1)) == src_id:
			return false
		o.item = item
		o.prog = 0.0
		o["flow_t"] = sim_n
		return true
	if t == D.CORE:
		# сырую руду ядро не принимает — только переработанное
		if not D.CORE_ACCEPT.has(item):
			return false
		var st: Dictionary = storage[team]
		if int(st.get(item, 0)) >= D.CORE_CAP:
			o["burn_t"] = 10   # склад полон — лишнее сжигается, лента не встаёт
			return true
		st[item] = int(st.get(item, 0)) + 1
		return true
	if not _accepts(o, item):
		return false
	if t == D.DRILL3 or (t == D.AA_GUN and item == D.I_WATER):
		o.water += 1
	else:
		var buf: Dictionary = o.buf
		buf[item] = int(buf.get(item, 0)) + 1
	return true


## Ближайшая вражеская цель в радиусе: юнит, игрок или (для артиллерии) постройка.
## Возвращает {pos, unit, pid, bld} или пустой словарь.
func _find_target(team: int, from: Vector3, rng: float, with_buildings: bool, pn: int) -> Dictionary:
	var best := {}
	var bd := rng
	for u in units:
		if u.team == team or u.hp <= 0 or u.pn != pn:
			continue
		var p := _upos(u)
		var d := from.distance_to(p)
		if d < bd:
			bd = d
			best = {"pos": p, "unit": u, "pid": -1, "bld": null}
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == team or o.hp <= 0 or int(o.get("pn", D.HOME_PLANET)) != pn:
			continue
		var pp: Vector3 = o.pos
		var p := pp + pp.normalized() * 0.9
		var d := from.distance_to(p)
		if d < bd:
			bd = d
			best = {"pos": p, "unit": null, "pid": pid, "bld": null}
	for r in rovers:
		if int(r.team) == team or int(r.pn) != pn:
			continue
		var rp := _rpos(r) + _rpos(r).normalized() * 0.6
		var d := from.distance_to(rp)
		if d < bd:
			bd = d
			best = {"pos": rp, "unit": null, "pid": -1, "bld": null, "rover": r}
	if with_buildings:
		for b in buildings.values():
			if b.team == team or b.pn != pn:
				continue
			var p := _bpos(b)
			var d := from.distance_to(p)
			if d < bd:
				bd = d
				best = {"pos": p, "unit": null, "pid": -1, "bld": b}
	return best


func _hit_target(tgt: Dictionary, dmg: int) -> void:
	if tgt.get("rover") != null:
		_damage_rover(tgt.rover, dmg)
	elif tgt.unit != null:
		tgt.unit.hp -= dmg
	elif tgt.pid != -1:
		_damage_player(tgt.pid, dmg)
	elif tgt.bld != null and buildings.has(tgt.bld.id):
		_damage_building(tgt.bld, dmg)


## Откуда стреляет турель (над центром её контура).
func _muzzle(b: Dictionary, h: float) -> Vector3:
	var c := _foot_center(b.cells, int(b.pn))
	return c + c.normalized() * h


## I — лазер: мгновенное попадание, без энергии и боеприпасов.
func _turret_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	var from := _muzzle(b, 0.8)
	var tgt := _find_target(b.team, from, D.TURRET_RANGE, false, b.pn)
	if tgt.is_empty():
		return
	_hit_target(tgt, D.TURRET_DMG)
	b.timer = D.TURRET_CD
	b["aim"] = (Vector3(tgt.pos) - from).normalized()
	_fx_beam(from, tgt.pos, 1, b.pn)


## II — пулемёт: пули с баллистикой, 1 свинец = несколько пуль.
func _turret2_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	if not creative and b.team != D.T_NEUTRAL and int(b.get("ammo", 0)) <= 0:
		if not _buf_take(b, D.I_COPPER, 1):
			return
		b["ammo"] = D.T2_SHOTS_PER_COPPER
	var from := _muzzle(b, 1.3)
	var tgt := _find_target(b.team, from, D.T2_RANGE, false, b.pn)
	if tgt.is_empty():
		return
	var vel := _aim(from, tgt.pos, D.T2_SPEED, 1.0)
	if vel == Vector3.ZERO:
		return
	b["aim"] = vel.normalized()
	_spawn_proj(from, vel, b.team, 0, D.T2_DMG, 1.2, b.cell, b.pn)
	if not creative and b.team != D.T_NEUTRAL:
		b["ammo"] = int(b.ammo) - 1
	b.timer = D.T2_CD


## III — артиллерия: навесной снаряд со взрывом. Уран — с облучением.
func _turret3_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	var has_u := int(b.buf.get(D.I_URANIUM, 0)) > 0
	var has_pb := int(b.buf.get(D.I_LEAD, 0)) > 0
	if not creative and b.team != D.T_NEUTRAL and not has_u and not has_pb:
		return
	var from := _muzzle(b, 2.5)
	var tgt := _find_target(b.team, from, D.T3_RANGE, true, b.pn)
	if tgt.is_empty():
		return
	var vel := _aim(from, tgt.pos, D.T3_SPEED, 6.0, true)
	if vel == Vector3.ZERO:
		return
	var kind := 2 if has_u else 1
	if not creative:
		_buf_take(b, D.I_URANIUM if has_u else D.I_LEAD, 1)
	b["aim"] = vel.normalized()
	_spawn_proj(from, vel, b.team, kind, D.T3_DMG, 7.0, b.cell, b.pn)
	b.timer = D.T3_CD


## Ближайшая цель любого вида (наземная, летающая, игрок, корабль, курьер, постройка) — с ссылкой,
## чтобы самонаводящийся снаряд мог за ней следить.
func _find_any_target(team: int, from: Vector3, rng: float, pn: int) -> Dictionary:
	var best := {}
	var bd := rng
	for u in units:
		if u.team == team or u.hp <= 0 or u.pn != pn:
			continue
		var d := from.distance_to(_tpos({"k": "unit", "ref": u}))
		if d < bd:
			bd = d
			best = {"k": "unit", "ref": u}
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == team or o.hp <= 0 or int(o.get("pn", -9)) != pn:
			continue
		var d := from.distance_to(Vector3(o.pos))
		if d < bd:
			bd = d
			best = {"k": "pid", "ref": pid}
	for sh in ships.values():
		if int(sh.team) == team or int(sh.pn) != pn:
			continue
		var d := from.distance_to(Vector3(sh.pos))
		if d < bd:
			bd = d
			best = {"k": "ship", "ref": int(sh.id)}
	for r in rovers:
		if int(r.team) == team or int(r.pn) != pn:
			continue
		var d := from.distance_to(_rpos(r))
		if d < bd:
			bd = d
			best = {"k": "rover", "ref": r}
	if best.is_empty():
		for b in buildings.values():
			if b.team == team or b.pn != pn or b.team == D.T_NEUTRAL and team == D.T_NEUTRAL:
				continue
			var d := from.distance_to(_bpos(b))
			if d < bd:
				bd = d
				best = {"k": "bld", "ref": int(b.id)}
	return best


## Где сейчас цель (null — её больше нет).
func _tpos(t: Dictionary):
	match String(t.k):
		"unit":
			var u: Dictionary = t.ref
			if int(u.hp) <= 0:
				return null
			var p := _upos(u)
			return p + p.normalized() * (D.DRONE_ALT if int(u.kind) == D.U_DRONE else 0.8)
		"pid":
			if not players.has(t.ref) or int(players[t.ref].hp) <= 0:
				return null
			var pp: Vector3 = players[t.ref].pos
			return pp + pp.normalized() * 0.9
		"ship":
			if not ships.has(t.ref):
				return null
			var sp: Vector3 = ships[t.ref].pos
			return sp + Basis(Quaternion(ships[t.ref].quat)).y * 2.0
		"rover":
			var r: Dictionary = t.ref
			if bool(r.get("dead", false)):
				return null
			return _rpos(r) + _rpos(r).normalized() * 0.6
		"bld":
			if not buildings.has(t.ref):
				return null
			var bp := _bpos(buildings[t.ref])
			return bp + bp.normalized() * 1.0
	return null


func _damage_tgt(t: Dictionary, dmg: int) -> void:
	match String(t.k):
		"unit":
			t.ref.hp = int(t.ref.hp) - dmg
		"pid":
			_damage_player(int(t.ref), dmg)
		"ship":
			if ships.has(t.ref):
				_damage_ship(ships[t.ref], dmg)
		"rover":
			_damage_rover(t.ref, dmg)
		"bld":
			if buildings.has(t.ref):
				_damage_building(buildings[t.ref], dmg)


## Уникальная пушка: навесной выстрел по любой цели, снаряд дальше наводится сам.
func _turret4_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	var free_ammo: bool = creative or b.team == D.T_NEUTRAL
	if not free_ammo and int(b.get("ammo", 0)) <= 0:
		if not _buf_take(b, D.I_UALLOY, 1):
			return
		b["ammo"] = D.T4_SHOTS_PER_ITEM
	var from := _muzzle(b, 3.0)
	var tgt := _find_any_target(b.team, from, D.T3_RANGE, b.pn)
	if tgt.is_empty():
		return
	var tp = _tpos(tgt)
	if tp == null:
		return
	var up := from.normalized()
	var dir: Vector3 = (Vector3(tp) - from).normalized()
	var vel := (dir + up * 0.9).normalized() * D.T4_SPEED   # вверх дугой, дальше наведётся
	b["aim"] = vel.normalized()
	_spawn_proj(from, vel, b.team, 5, D.T4_DMG, 9.0, b.cell, b.pn)
	projectiles[projectiles.size() - 1]["tgt"] = tgt
	if not free_ammo:
		b["ammo"] = int(b.ammo) - 1
	b.timer = D.T4_CD


# ---------------------------------------------------------------------
# Разветвитель, перекрёсток, мост; ремонт
# ---------------------------------------------------------------------

func _logistic_tick(b: Dictionary) -> void:
	if b.item == D.I_NONE:
		return
	var t: int = b.type
	if t == D.SPLITTER:
		# по кругу во все соседние клетки, кроме той постройки, откуда пришло
		var nb: PackedInt32Array = _pl(int(b.pn)).nbrs[b.cell]
		var k := nb.size()
		for i in k:
			var idx: int = (b.rr + i) % k
			if int(grid.get(_k(b.pn, nb[idx]), -1)) == int(b.get("src", -2)):
				continue
			if _push(nb[idx], b.id, b.team, b.item, b.pn):
				b.rr = (idx + 1) % k
				b.item = D.I_NONE
				return
	elif t == D.JUNCTION:
		if _push(int(b.get("jout", -1)), b.id, b.team, b.item, b.pn):
			b.item = D.I_NONE
	elif t == D.BRIDGE:
		var far = _bridge_target(b)
		if far != null:
			if far.item == D.I_NONE:
				far.item = b.item
				far.prog = 0.0
				far["src"] = b.id
				b.item = D.I_NONE
		elif _push(_out_cell(b), b.id, b.team, b.item, b.pn):
			b.item = D.I_NONE


## Следующий свой мост по направлению моста (до BRIDGE_RANGE клеток).
func _bridge_target(b: Dictionary):
	var heading: Vector3 = _pl(int(b.pn)).dirs[_out_cell(b)] - _pl(int(b.pn)).dirs[b.cell]
	var c: int = b.cell
	for i in D.BRIDGE_RANGE:
		c = _pl(int(b.pn))._step(c, heading)
		var id := int(grid.get(_k(b.pn, c), -1))
		if id != -1 and id != b.id:
			var o: Dictionary = buildings[id]
			if o.type == D.BRIDGE and o.team == b.team:
				return o
	return null


## Перекрёсток: куда выпустить груз — в клетку напротив той, откуда он пришёл.
func _junction_out(o: Dictionary, src_id: int, pn: int) -> int:
	var nb: PackedInt32Array = _pl(pn).nbrs[o.cell]
	var k := nb.size()
	for d in k:
		if int(grid.get(_k(pn, nb[d]), -1)) == src_id:
			return nb[(d + k / 2) % k]
	return -1


func _repair_tick(b: Dictionary, r: float) -> void:
	if r <= 0.001:
		return
	var c := _bpos(b)
	if b.type == D.REPAIR:
		var rate := int(ceil(D.REPAIR_RATE * r))
		for o in buildings.values():
			if o.team != b.team or o.pn != b.pn or o.id == b.id:
				continue
			var mx: int = D.HP[o.type]
			if o.hp < mx and _bpos(o).distance_to(c) < D.REPAIR_RADIUS:
				o.hp = mini(mx, o.hp + rate)
	else:
		var rate := int(ceil(D.UNIT_REPAIR_RATE * r))
		for u in units:
			if u.team != b.team or u.pn != b.pn or u.hp <= 0:
				continue
			var mx: int = D.UNIT_STATS[u.kind].hp
			if u.hp < mx and _upos(u).distance_to(c) < D.REPAIR_RADIUS:
				u.hp = mini(mx, u.hp + rate)


## Ближайшая вражеская летающая цель: дрон или корабль в полёте. {pos, vel} или пустой словарь.
func _find_air_target(team: int, from: Vector3, rng: float, pn: int) -> Dictionary:
	var best := {}
	var bd := rng
	for u in units:
		if u.team == team or u.hp <= 0 or u.pn != pn or u.kind != D.U_DRONE:
			continue
		var p := _upos(u)
		p += p.normalized() * D.DRONE_ALT
		var d := from.distance_to(p)
		if d < bd:
			bd = d
			best = {"pos": p, "vel": u.get("vel", Vector3.ZERO)}
	for sh in ships.values():
		if sh.team == team or int(sh.pn) != pn or int(sh.state) != 1:
			continue
		var d := from.distance_to(sh.pos)
		if d < bd:
			bd = d
			best = {"pos": Vector3(sh.pos), "vel": sh.get("vel", Vector3.ZERO)}
	return best


## ПВО: стреляет с упреждением зенитными снарядами. Снаряды — любой ресурс, уран облучает.
## Вода ускоряет стрельбу вдвое.
func _aa_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	var from := _muzzle(b, 1.6)
	var tgt := _find_air_target(b.team, from, D.AA_RANGE, b.pn)
	if tgt.is_empty():
		return
	var free_ammo: bool = creative or b.team == D.T_NEUTRAL
	if not free_ammo and int(b.get("ammo", 0)) <= 0:
		# заряжаем: уран в приоритете, иначе что есть
		var total := 0
		for k in b.buf:
			total += int(b.buf[k])
		if total < D.AA_ITEMS_PER_SHOT:
			return
		var need: int = D.AA_ITEMS_PER_SHOT
		var had_u := false
		var order: Array = [D.I_URANIUM]
		for k in b.buf:
			if int(k) != D.I_URANIUM:
				order.append(k)
		for k in order:
			while need > 0 and int(b.buf.get(k, 0)) > 0:
				_buf_take(b, int(k), 1)
				need -= 1
				if int(k) == D.I_URANIUM:
					had_u = true
		b["ammo"] = 1
		b["ammo_u"] = had_u
	var uranium := bool(b.get("ammo_u", false)) if not free_ammo else int(b.buf.get(D.I_URANIUM, 0)) > 0
	# упреждение: где будет цель, пока летит снаряд (два уточнения)
	var p: Vector3 = tgt.pos
	var v: Vector3 = tgt.vel
	var aim_at := p
	for i in 2:
		aim_at = p + v * (from.distance_to(aim_at) / D.AA_SPEED)
	var vel := _aim(from, aim_at, D.AA_SPEED, 2.0)
	if vel == Vector3.ZERO:
		return
	b["aim"] = vel.normalized()
	_spawn_proj(from, vel, b.team, 4 if uranium else 3, D.AA_DMG, 2.0, b.cell, b.pn)
	if not free_ammo:
		b["ammo"] = int(b.ammo) - 1
	var cd: int = D.AA_CD
	if b.water > 0:
		cd = D.AA_CD_WATER
		b.wuse += 1
		if b.wuse >= D.AA_WATER_PER:
			b.wuse = 0
			b.water -= 1
	b.timer = cd


## Зенитный снаряд рядом с вражеской летающей целью?
func _flak_near(pr: Dictionary, at: Vector3) -> bool:
	for u in units:
		if u.team == pr.team or u.hp <= 0 or u.pn != pr.pn or u.kind != D.U_DRONE:
			continue
		var p := _upos(u)
		if at.distance_to(p + p.normalized() * D.DRONE_ALT) < D.AA_FUSE:
			return true
	for sh in ships.values():
		if sh.team != pr.team and int(sh.pn) == pr.pn and int(sh.state) == 1 \
				and at.distance_to(sh.pos) < D.AA_FUSE + 1.5:
			return true
	return false


## Разрыв зенитного снаряда: осколки бьют только летающих (дроны, корабли).
func _explode_flak(at: Vector3, team: int, uranium: bool, pn: int) -> void:
	var r: float = D.AA_SPLASH
	for u in units:
		if u.team == team or u.hp <= 0 or u.pn != pn or u.kind != D.U_DRONE:
			continue
		var p := _upos(u)
		var d := at.distance_to(p + p.normalized() * D.DRONE_ALT)
		if d < r:
			u.hp -= int(D.AA_DMG * lerpf(1.0, 0.3, d / r))
			if uranium:
				u.poison = D.POISON_TICKS
	for sh in ships.values():
		if sh.team == team or int(sh.pn) != pn or int(sh.state) != 1:
			continue
		var d := at.distance_to(sh.pos)
		if d < r + 1.5:
			_damage_ship(sh, int(D.AA_DMG * lerpf(1.0, 0.3, clampf(d / r, 0.0, 1.0))) + (5 if uranium else 0))
	for p in Net.ready_peers:
		fx_boom.rpc_id(p, at, r, uranium, pn)
	if not headless and pn == my_pn:
		_boom(at, r, uranium)


## Урон кораблю. Сбит — для пилота это крушение.
func _damage_ship(sh: Dictionary, dmg: int) -> void:
	if bool(sh.get("down", false)):
		return
	sh.hp = int(sh.get("hp", 1)) - dmg
	if sh.hp > 0:
		return
	sh["down"] = true
	var pilot: int = sh.pilot
	if pilot == 1 and not headless:
		if piloting_id == int(sh.id):
			on_ship_crash(piloting)
	elif pilot != -1 and Net.ready_peers.has(pilot):
		ev_ship_down.rpc_id(pilot, int(sh.id))
	else:
		ships.erase(sh.id)


@rpc("authority", "call_remote", "reliable")
func ev_ship_down(id: int) -> void:
	if piloting_id == id and piloting:
		on_ship_crash(piloting)


## Подбор угла возвышения: снаряд летит с гравитацией к центру планеты, планета круглая,
## поэтому прогоняем траекторию численно и ищем угол с наименьшим промахом.
## Возвращает вектор начальной скорости или Vector3.ZERO, если не достать.
func _aim(from: Vector3, target: Vector3, speed: float, tmax: float, high := false) -> Vector3:
	var up := from.normalized()
	var h := target - from
	h = h - up * h.dot(up)
	if h.length() < 0.001:
		return Vector3.ZERO
	h = h.normalized()
	if high:
		return _aim_high(from, h, up, target, speed, tmax)
	var direct := (target - from).normalized()
	var th0 := asin(clampf(direct.dot(up), -1.0, 1.0))
	var lo := th0 - 0.3
	var hi := minf(th0 + 1.2, 1.5)
	var best_th := th0
	var best_d := INF
	for i in 25:
		var th := lerpf(lo, hi, float(i) / 24.0)
		var d := _miss(from, h, up, th, speed, target, tmax)
		if d < best_d:
			best_d = d
			best_th = th
	var step := (hi - lo) / 24.0
	for k in 6:
		step *= 0.5
		for th in [best_th - step, best_th + step]:
			var d := _miss(from, h, up, th, speed, target, tmax)
			if d < best_d:
				best_d = d
				best_th = th
	if best_d > 2.0:
		return Vector3.ZERO
	return (h * cos(best_th) + up * sin(best_th)) * speed


## Навесная стрельба: перебираем углы сверху вниз, первый подходящий — самая высокая дуга.
func _aim_high(from: Vector3, h: Vector3, up: Vector3, target: Vector3, speed: float, tmax: float) -> Vector3:
	var lo := -0.3
	var hi := 1.45
	var n := 36
	var best_th := 0.0
	var best_d := INF
	for i in range(n, -1, -1):
		var th := lerpf(lo, hi, float(i) / n)
		var d := _miss(from, h, up, th, speed, target, tmax, false)
		if d < 3.0:
			best_th = th
			best_d = d
			break
	if best_d == INF:
		return Vector3.ZERO
	var step := (hi - lo) / n
	for k in 6:
		step *= 0.5
		for th in [best_th - step, best_th + step]:
			var d := _miss(from, h, up, th, speed, target, tmax, false)
			if d < best_d:
				best_d = d
				best_th = th
	if best_d > 2.0:
		return Vector3.ZERO
	return (h * cos(best_th) + up * sin(best_th)) * speed


## Насколько близко пройдёт снаряд от цели при угле th.
## early — прекращать, когда снаряд начал удаляться (для прямой наводки; навесом он сначала уходит вверх).
func _miss(from: Vector3, h: Vector3, up: Vector3, th: float, speed: float, target: Vector3, tmax: float,
		early := true) -> float:
	var p := from
	var v := (h * cos(th) + up * sin(th)) * speed
	var t := 0.0
	var best := INF
	while t < tmax:
		v -= p.normalized() * D.PROJ_G * D.PROJ_DT
		p += v * D.PROJ_DT
		t += D.PROJ_DT
		var d := p.distance_to(target)
		if d < best:
			best = d
		elif early and d > best + 5.0:
			break   # уже удаляемся
		if p.length() < aim_r - 1.0:
			break   # ушёл под землю
	return best


func _spawn_proj(from: Vector3, vel: Vector3, team: int, kind: int, dmg: int, ttl: float, cell: int, pn: int) -> void:
	projectiles.append({"pos": from, "vel": vel, "team": team, "kind": kind, "dmg": dmg,
		"ttl": ttl, "cell": _pl(pn).walk(cell, from.normalized()), "pn": pn})


## Полёт снарядов: несколько шагов физики за тик, пули бьют при касании, снаряды взрываются о землю.
func _proj_tick() -> void:
	var steps := int(round(D.TICK / D.PROJ_DT))
	for pr in projectiles:
		var alive := true
		for s_i in steps:
			var a: Vector3 = pr.pos
			var v: Vector3 = pr.vel
			if int(pr.kind) == 6:
				if _missile_near(pr, a):
					_blast(a, pr.team, pr.pn, D.JET_MISSILE_R, int(pr.dmg))
					alive = false
					break
			elif int(pr.kind) == 5:
				# самонаводящийся: поворачивает к цели, у цели — прямое попадание и взрыв
				var tp = _tpos(pr.tgt) if pr.has("tgt") else null
				if tp != null:
					var to_t: Vector3 = Vector3(tp) - a
					if to_t.length() < 2.0:
						_damage_tgt(pr.tgt, int(pr.dmg))
						_explode(a, pr.team, false, pr.pn)
						alive = false
						break
					var want := to_t.normalized() * D.T4_SPEED * 1.3
					v = v.lerp(want, minf(1.0, 2.5 * D.PROJ_DT))
				else:
					v -= a.normalized() * D.PROJ_G * D.PROJ_DT
			else:
				v -= a.normalized() * D.PROJ_G * D.PROJ_DT
			var b := a + v * D.PROJ_DT
			pr.vel = v
			pr.pos = b
			pr.ttl -= D.PROJ_DT
			if pr.kind == 0 and _bullet_hit(pr, a, b):
				alive = false
				break
			if (pr.kind == 3 or pr.kind == 4) and _flak_near(pr, b):
				_explode_flak(b, pr.team, pr.kind == 4, pr.pn)
				alive = false
				break
			pr.cell = _pl(int(pr.pn)).walk(pr.cell, b.normalized())
			if b.length() < _pl(int(pr.pn)).top_r(pr.cell):
				if pr.kind == 3 or pr.kind == 4:
					_explode_flak(b, pr.team, pr.kind == 4, pr.pn)
				elif pr.kind == 6:
					_blast(b, pr.team, pr.pn, D.JET_MISSILE_R, int(pr.dmg))
				elif pr.kind != 0:
					_explode(b, pr.team, pr.kind == 2, pr.pn)
				alive = false
				break
		if alive and pr.ttl <= 0.0:
			if pr.kind == 6:
				_blast(pr.pos, pr.team, pr.pn, D.JET_MISSILE_R, int(pr.dmg))
			elif pr.kind >= 3 and pr.kind <= 4:
				_explode_flak(pr.pos, pr.team, pr.kind == 4, pr.pn)
			elif pr.kind != 0:
				_explode(pr.pos, pr.team, pr.kind == 2, pr.pn)
			alive = false
		pr["dead"] = not alive
	projectiles = projectiles.filter(func(x): return not x.dead)


## Пуля задела врага на отрезке a→b?
func _bullet_hit(pr: Dictionary, a: Vector3, b: Vector3) -> bool:
	for u in units:
		if u.team == pr.team or u.hp <= 0 or u.pn != pr.pn:
			continue
		if _seg_dist(a, b, _upos(u)) < 0.5:
			u.hp -= pr.dmg
			return true
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == pr.team or o.hp <= 0 or int(o.get("pn", D.HOME_PLANET)) != pr.pn:
			continue
		var pp: Vector3 = o.pos
		var c := pp + pp.normalized() * 0.9
		if _seg_dist(a, b, c) < 0.6:
			_damage_player(pid, pr.dmg)
			return true
	return false


func _seg_dist(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return (a + ab * t).distance_to(c)


## Взрыв: урон врагам в радиусе (в центре 100%, к краю 20%). Уран — облучение на 2 с.
func _explode(at: Vector3, team: int, uranium: bool, pn: int) -> void:
	var r: float = D.T3_SPLASH
	for u in units:
		if u.team == team or u.hp <= 0 or u.pn != pn:
			continue
		var d := at.distance_to(_upos(u))
		if d < r:
			u.hp -= int(D.T3_DMG * lerpf(1.0, 0.2, d / r))
			if uranium:
				u.poison = D.POISON_TICKS
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == team or o.hp <= 0 or int(o.get("pn", D.HOME_PLANET)) != pn:
			continue
		var d := at.distance_to(o.pos)
		if d < r:
			_damage_player(pid, int(D.T3_DMG * lerpf(1.0, 0.2, d / r)))
			if uranium:
				o["poison"] = D.POISON_TICKS
	for b in buildings.values():
		if b.team == team or b.pn != pn or not buildings.has(b.id):
			continue
		var d := at.distance_to(_bpos(b))
		if d < r:
			_damage_building(b, int(D.T3_DMG * lerpf(1.0, 0.2, d / r)))
			if finished:
				break
	for p in Net.ready_peers:
		fx_boom.rpc_id(p, at, r, uranium, pn)
	if not headless and pn == my_pn:
		_boom(at, r, uranium)


func _fx_beam(from: Vector3, to: Vector3, kind: int, pn: int) -> void:
	for p in Net.ready_peers:
		fx_beam.rpc_id(p, from, to, kind, pn)
	if not headless and pn == my_pn:
		_tracer(from, to, [Color(1.0, 0.85, 0.3), Color(1.0, 0.25, 0.2), Color(0.6, 0.9, 1.0), Color(0.4, 0.6, 1.0)][clampi(kind, 0, 3)])


func _unit_count(team: int, kind: int) -> int:
	var n := 0
	for u in units:
		if u.team == team and u.kind == kind and u.hp > 0:
			n += 1
	return n


## Лимит юнитов типа kind = лимит на ядро × сколько ядер у команды.
func _unit_limit(team: int, kind: int) -> int:
	var cores := 0
	for b in buildings.values():
		if b.type == D.CORE and b.team == team:
			cores += 1
	return int(D.UNIT_LIMIT[kind]) * maxi(cores, 1)


## Сборщик: копит рецепт выбранного юнита, собирает, если команда не упёрлась в лимит.
## Сборщик: пока тип юнита не выбран — стоит. Ресурсы — только с конвейеров (не со склада базы), и в креативе тоже.
func _assembler_tick(b: Dictionary) -> void:
	var k: int = b.ukind
	if b.timer > 0:
		b.timer = maxi(0, int(b.timer) - int(b.lvl))   # модернизация — собирает быстрее
		if b.timer == 0:
			_spawn_unit(b.team, _bay_cell(b), b.pn, k)
		return
	if k < 0 or _unit_count(b.team, k) >= _unit_limit(b.team, k):
		return
	var need: Dictionary = D.UNIT_RECIPES[k]
	if not _has_inputs(b, need):
		return
	for it in need:
		b.buf[it] = int(b.buf[it]) - int(need[it])
	b.timer = int(D.UNIT_STATS[k].build)


## Клетки перед постройкой (со стороны, куда она повёрнута) — туда завод выдаёт продукт.
func _front_cells(b: Dictionary) -> Array:
	var nb: PackedInt32Array = _pl(int(b.pn)).nbrs[b.cell]
	var toward: int = nb[int(b.dir) % nb.size()]
	var c := _foot_center(b.cells, int(b.pn))
	var up := c.normalized()
	var f := _pl(int(b.pn)).top_pos(toward) - _pl(int(b.pn)).top_pos(b.cell)
	f = (f - up * f.dot(up)).normalized()
	var res: Array = []
	for x in b.outs:
		var v := _pl(int(b.pn)).top_pos(x) - c
		if (v - up * v.dot(up)).normalized().dot(f) > 0.55:
			res.append(x)
	if res.is_empty():
		res.append(_bay_cell(b))
	return res


## Площадка сборки юнита — клетка рядом со сборщиком, со стороны, куда он смотрит.
func _bay_cell(b: Dictionary) -> int:
	var nb: PackedInt32Array = _pl(int(b.pn)).nbrs[b.cell]
	var toward: int = nb[int(b.dir) % nb.size()]
	var c := _foot_center(b.cells, int(b.pn))
	var up := c.normalized()
	var f := _pl(int(b.pn)).top_pos(toward) - _pl(int(b.pn)).top_pos(b.cell)
	f = (f - up * f.dot(up)).normalized()
	var best: int = b.cell
	var best_d := -INF
	for x in b.outs:
		var v := _pl(int(b.pn)).top_pos(x) - c
		var d := (v - up * v.dot(up)).normalized().dot(f)
		if d > best_d:
			best_d = d
			best = x
	return best


func _spawn_unit(team: int, cell: int, pn: int, kind := 0, hp := -1) -> void:
	var d: Vector3 = _pl(pn).dirs[cell]
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.01
	d = (d + jitter).normalized()
	var full: int = D.UNIT_STATS[kind].hp
	units.append({"id": next_unit_id, "team": team, "dir": d, "cell": cell, "hp": hp if hp > 0 else full,
		"cd": 0, "poison": 0, "pn": pn, "kind": kind, "mode": D.MODE_GUARD,
		"guard": d * _pl(pn).top_r(cell)})
	next_unit_id += 1


func _players_tick() -> void:
	for pid in players.keys():
		if Net.team_of(pid) < 0:
			players.erase(pid)   # игрок вышел
			continue
		var o: Dictionary = players[pid]
		if o.hp > 0:
			if int(o.get("poison", 0)) > 0:
				o.poison -= 1
				_damage_player(pid, D.POISON_DMG)
			# жгучие клетки малых планет
			var opn: int = int(o.get("pn", -1))
			if opn >= 0 and int(o.get("held", 0)) != IN_SHIP:
				var P: Planet = _pl(opn)
				var oc: int = P.walk(int(o.get("cell", -1)), Vector3(o.pos).normalized())
				o["cell"] = oc
				o["hz"] = int(o.get("hz", 0)) + 1
				if P.hazard.size() > oc and P.hazard[oc] == 1 and int(o.hz) % 5 == 0 \
						and Vector3(o.pos).length() < P.top_r(oc) + 1.2:
					_damage_player(pid, D.HAZARD_DMG)
			continue
		o.dead_t -= 1
		if o.dead_t <= 0:
			o.hp = D.PLAYER_HP
			var rc = _respawn_core(o)
			if rc != null:
				o.pos = _spawn_near(rc)
				o["pn"] = int(rc.pn)
			else:
				o.pos = _spawn_pos(o.team)
				o["pn"] = _spawn_pn(o.team)
			if pid == 1 and not headless:
				if player:
					_switch_planet(int(o.pn))
					player.teleport(o.pos)
			elif Net.ready_peers.has(pid):
				ev_respawn.rpc_id(pid, o.pos, int(o.pn))


## Юниты. Поведение: агрессия — ищет врагов по всей планете; охрана — бьёт врагов возле точки охраны
## и возвращается к ней; стоять — не двигается, стреляет в радиусе оружия.
## Дрон-камикадзе таранит цель и снимает четверть её максимальной прочности.
func _units_tick() -> void:
	for u in units:
		if int(u.get("poison", 0)) > 0:
			u.poison -= 1
			u.hp -= D.POISON_DMG   # облучение ураном
		if u.hp <= 0:
			continue
		if u.cd > 0:
			u.cd -= 1
		var st: Dictionary = D.UNIT_STATS[u.kind]
		var mode: int = u.mode
		var upos := _upos(u)
		u["vel"] = (upos - u.get("last", upos)) / D.TICK   # для упреждения ПВО
		u["last"] = upos
		var guard: Vector3 = u.guard
		# радиус, в котором юнит ищет врагов
		var look: float = st.aggro
		if mode == D.MODE_HOLD:
			look = st.range if u.kind != D.U_DRONE else st.aggro * 0.5
		var target_unit = null
		var target_player := -1
		var best: float = look
		var tpos := Vector3.ZERO
		for o in units:
			if o.hp <= 0 or o.id == u.id or o.pn != u.pn:
				continue
			var op := _upos(o)
			var d: float = upos.distance_to(op)
			if o.team != u.team:
				if d < best and (mode != D.MODE_GUARD or op.distance_to(guard) < D.GUARD_RADIUS + st.range):
					best = d
					target_unit = o
					tpos = op
			elif d < 0.6 and d > 0.001:
				# чтобы свои не слипались в одну точку
				var away: Vector3 = (u.dir - o.dir)
				u.dir = (u.dir + away.normalized() * 0.002).normalized()
		for pid in players:
			var pl: Dictionary = players[pid]
			if pl.team == u.team or pl.hp <= 0 or int(pl.get("pn", D.HOME_PLANET)) != u.pn:
				continue
			var pp: Vector3 = pl.pos
			var d: float = upos.distance_to(pp)
			if d < best and (mode != D.MODE_GUARD or pp.distance_to(guard) < D.GUARD_RADIUS + st.range):
				best = d
				target_unit = null
				target_player = pid
				tpos = pp

		var reach: float = st.range
		var target_b = null
		if target_player == -1 and target_unit == null:
			if mode == D.MODE_AGGRO:
				target_b = _nearest_enemy_building(upos, u.team, u.pn)
			else:
				var nb = _nearest_enemy_building(upos, u.team, u.pn)
				var lim: float = D.GUARD_RADIUS if mode == D.MODE_GUARD else st.range
				var anchor := guard if mode == D.MODE_GUARD else upos
				if nb != null and _bpos(nb).distance_to(anchor) < lim + 2.0:
					target_b = nb
			if target_b == null:
				# врагов рядом нет: охрана возвращается к точке, остальные стоят
				if mode == D.MODE_GUARD and upos.distance_to(guard) > 2.0:
					_unit_step(u, guard, st.speed, 1.5)
				continue
			tpos = _bpos(target_b)
			reach = st.range + (2.2 if target_b.type == D.CORE else 0.6)

		var dist: float = upos.distance_to(tpos)
		if dist > reach:
			if mode != D.MODE_HOLD:
				_unit_step(u, tpos, st.speed, reach)
		elif u.kind == D.U_DRONE:
			# таран: четверть максимальной прочности цели, дрон погибает
			if target_player != -1:
				_damage_player(target_player, int(D.PLAYER_HP * D.KAMIKAZE_FRAC))
			elif target_unit != null:
				target_unit.hp -= int(float(D.UNIT_STATS[target_unit.kind].hp) * D.KAMIKAZE_FRAC)
			else:
				_damage_building(target_b, int(float(D.HP[target_b.type]) * D.KAMIKAZE_FRAC))
			u.hp = 0
			for p in Net.ready_peers:
				fx_boom.rpc_id(p, upos, 3.0, false, u.pn)
			if not headless and u.pn == my_pn:
				_boom(upos, 3.0, false)
			if finished:
				return
		elif u.cd == 0:
			u.cd = st.cd
			var dmg: int = st.dmg
			if target_player != -1:
				_damage_player(target_player, dmg)
			elif target_unit != null:
				target_unit.hp -= dmg
			else:
				_damage_building(target_b, dmg)
			_fx_beam(upos, tpos, 2, u.pn)
			if finished:
				return
	units = units.filter(func(x): return x.hp > 0)


## Шаг юнита по поверхности к точке (останавливается на расстоянии reach).
## Наземный юнит упирается во вражеский забор: тогда не идёт, а ломает его.
func _unit_step(u: Dictionary, tpos: Vector3, speed: float, reach: float) -> void:
	var ud: Vector3 = u.dir
	var dist := _upos(u).distance_to(tpos)
	var tdir := tpos.normalized()
	var tangent := tdir - ud * ud.dot(tdir)
	if tangent.length() > 0.00001:
		var step: float = minf(speed, dist - reach + 0.01)
		if step > 0.0:
			var nd := (ud + tangent.normalized() * (step / _pl(int(u.pn)).radius)).normalized()
			var nc := _pl(int(u.pn)).walk(u.cell, nd)
			if u.kind != D.U_DRONE and nc != u.cell:
				var wid := int(grid.get(_k(u.pn, nc), -1))
				if wid != -1 and buildings[wid].type == D.WALL and buildings[wid].team != u.team:
					if u.cd == 0:
						var st: Dictionary = D.UNIT_STATS[u.kind]
						u.cd = maxi(int(st.cd), 3)
						_damage_building(buildings[wid], maxi(int(st.dmg), 4))
					return
			u.dir = nd
			u.cell = nc


func _nearest_enemy_building(from: Vector3, team: int, pn: int):
	var best = null
	var bd := INF
	for b in buildings.values():
		if b.team == team or b.pn != pn:
			continue
		var d: float = from.distance_squared_to(_bpos(b))
		if d < bd:
			bd = d
			best = b
	return best


func _damage_building(b: Dictionary, dmg: int) -> void:
	b.hp -= dmg
	if b.hp > 0:
		return
	if b.type == D.CORE:
		# разрушенное ядро не исчезает: база становится нейтральной, её можно захватить
		if b.team != D.T_NEUTRAL:
			b.hp = int(D.HP[D.CORE] * D.NEUTRALIZED_HP)
			_set_core_team(b, D.T_NEUTRAL)
		else:
			b.hp = 1
	else:
		_destroy(b.id, true)


## Тревога игрокам команды (тревоги о разрушениях — не чаще раза в ALERT_COOLDOWN на планету).
func _alert_team(team: int, text: String, pn: int, kind: int) -> void:
	if team < 0 or team > 1:
		return
	if kind == 1:
		var key := "%d:%d" % [team, pn]
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(alert_last.get(key, -100.0)) < D.ALERT_COOLDOWN:
			return
		alert_last[key] = now
	for p in Net.ready_peers:
		if Net.team_of(p) == team:
			ev_alert.rpc_id(p, text, pn, kind)
	if not headless and my_team == team:
		_on_alert(text, pn, kind)


@rpc("authority", "call_remote", "reliable")
func ev_alert(text: String, pn: int, kind: int) -> void:
	_on_alert(text, pn, kind)


## Показать тревогу: строка в HUD на 6 с и метка ⚠ у планеты на карте на 30 с.
func _on_alert(text: String, pn: int, kind: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	alerts.append([text, now + 6.0])
	if kind == 2:
		ui.banner_until = now + 8.0
		ui.banner_msg = "⚠ ВНИМАНИЕ! " + text.trim_prefix("⚠ ")
	if alerts.size() > 4:
		alerts.pop_front()
	if pn >= 0:
		alert_marks[pn] = now + 30.0


## Ядро сменило хозяина: постройки прежнего хозяина вокруг базы переходят вместе с ним.
func _set_core_team(core: Dictionary, team: int) -> void:
	var old: int = core.team
	var ids := PackedInt32Array()
	var gone: Array = []
	var center := _bpos(core)
	for b in buildings.values():
		if b.pn != core.pn or b.team != old:
			continue
		if b.id == core.id or _bpos(b).distance_to(center) < D.BASE_RADIUS:
			# нейтральная оборона при захвате исчезает, остальное переходит новому хозяину
			if old == D.T_NEUTRAL and b.id != core.id and D.DEFENSE_TYPES.has(b.type):
				gone.append(b)
				continue
			b.team = team
			ids.append(b.id)
	for b in gone:
		var at := _bpos(b)
		_destroy(b.id)
		for p in Net.ready_peers:
			fx_boom.rpc_id(p, at, 3.0, false, core.pn)
		if not headless and core.pn == my_pn:
			_boom(at, 3.0, false)
	core.cap = 0
	core.cap_team = -1
	for r in rovers:
		if buildings.has(r.home) and buildings[r.home].team != r.team:
			r.team = buildings[r.home].team
	power_dirty = true
	for p in Net.ready_peers:
		ev_team.rpc_id(p, ids, team)
	if not headless:
		_apply_team(ids, team)
	_check_victory()


## Команда без единого ядра проигрывает.
func _check_victory() -> void:
	var cnt := [0, 0, 0]
	for b in buildings.values():
		if b.type == D.CORE:
			cnt[b.team] += 1
	base_count = cnt
	if finished:
		return
	for t in 2:
		if cnt[t] == 0:
			finished = true
			var winner := 1 - t
			for p in Net.ready_peers:
				ev_over.rpc_id(p, winner)
			if headless:
				print("[server] Игра окончена, победили: %s" % D.TEAM_NAMES[winner])
			else:
				_show_over(winner)
			return


## Захват нейтральных баз: стоять у ядра, пока рядом нет других команд.
func _capture_tick() -> void:
	for core in buildings.values():
		if core.type != D.CORE or core.team != D.T_NEUTRAL:
			continue
		var c := _bpos(core)
		var present := {}
		for pid in players:
			var o: Dictionary = players[pid]
			if o.hp > 0 and int(o.get("pn", -1)) == core.pn and Vector3(o.pos).distance_to(c) < D.CAPTURE_RADIUS:
				present[int(o.team)] = true
		for u in units:
			if u.hp > 0 and u.pn == core.pn and _upos(u).distance_to(c) < D.CAPTURE_RADIUS:
				present[int(u.team)] = true
		present.erase(D.T_NEUTRAL)
		if present.size() == 1:
			var t: int = present.keys()[0]
			if core.cap_team != t:
				core.cap_team = t
				core.cap = 0
			core.cap += 1
			if core.cap >= D.CAPTURE_TICKS:
				core.hp = maxi(core.hp, int(D.HP[D.CORE] * 0.5))
				_set_core_team(core, t)
		elif present.is_empty() and core.cap > 0:
			core.cap = maxi(0, core.cap - 2)   # ушли — прогресс тает
			if core.cap == 0:
				core.cap_team = -1


## Данные одной планеты для снапшота (кэшируются: игроки на одной планете получают одно и то же).
func _snap_data(pn: int) -> Dictionary:
	var u := PackedFloat32Array()
	for x in units:
		if x.pn != pn:
			continue
		var p := _upos(x)
		u.append(p.x)
		u.append(p.y)
		u.append(p.z)
		u.append(float(x.team))
		u.append(float(x.hp) / float(D.UNIT_STATS[x.kind].hp))
		u.append(float(x.id))
		u.append(float(x.kind))
	var it := PackedVector3Array()
	var itt := PackedByteArray()
	var aim_ids := PackedInt32Array()
	var aim_dirs := PackedVector3Array()
	var asm := PackedInt32Array()   # сборщики за работой: [id, тип юнита, готовность ×1000]...
	for b in buildings.values():
		if b.pn != pn:
			continue
		if (b.type == D.CONVEYOR or b.type == D.PIPE or b.type == D.SORTER) and b.item != D.I_NONE:
			var a := _bpos(b)
			var nxt := _pl(pn).top_pos(_out_cell(b))
			var up: Vector3 = _pl(pn).dirs[b.cell]
			it.append(a + (nxt - a) * (float(b.prog) - 0.5) + up * 0.3)
			itt.append(b.item)
		if b.has("aim"):
			aim_ids.append(b.id)
			aim_dirs.append(b.aim)
		if b.type == D.ASSEMBLER and int(b.timer) > 0:
			var k: int = b.ukind
			asm.append(b.id)
			asm.append(k)
			asm.append(int(1000.0 * (1.0 - float(b.timer) / float(D.UNIT_STATS[k].build))))
	var pl: Array = []
	for pid in players:
		var o: Dictionary = players[pid]
		if int(o.get("pn", D.HOME_PLANET)) == pn:
			pl.append([pid, o.pos, o.fwd, o.team, o.hp, o.held])
	var pp := PackedVector3Array()
	var pv := PackedVector3Array()
	var pk := PackedByteArray()
	for pr in projectiles:
		if pr.pn == pn:
			pp.append(pr.pos)
			pv.append(pr.vel)
			pk.append(pr.kind)
	var rv: Array = []
	for r in rovers:
		if r.pn == pn:
			rv.append([r.id, _rpos(r), r.fwd, r.team, r.cargo_n, r.cargo_item, int(r.get("kind", 0))])
	var caps: Array = []
	for b in buildings.values():
		if b.type == D.CORE and b.pn == pn:
			caps.append([b.id, b.team, b.cap_team, float(b.cap) / D.CAPTURE_TICKS, float(b.hp) / D.HP[D.CORE]])
	return {"u": u, "it": it, "itt": itt, "pl": pl, "rv": rv, "pp": pp, "pv": pv, "pk": pk,
		"aim_ids": aim_ids, "aim_dirs": aim_dirs, "caps": caps, "asm": asm}


func _send_snapshot() -> void:
	# корабли — все (с номером планеты; -1 — в открытом космосе), клиент рисует только свои
	var sv: Array = []
	for sh in ships.values():
		sv.append([sh.id, sh.team, sh.pos, sh.quat, sh.thrust, sh.pilot, sh.state, sh.pn, sh.kind, _cargo_used(sh),
			float(sh.get("hp", 1)) / float(D.SHIP_HP[int(sh.kind)])])
	# сколько юнитов каждого типа у команд и какой лимит: [[кол-во×3, лимит×3], ...]
	var ustat: Array = []
	for t in 2:
		var row: Array = []
		for k in D.UNIT_NAMES.size():
			row.append(_unit_count(t, k))
		for k in D.UNIT_NAMES.size():
			row.append(_unit_limit(t, k))
		ustat.append(row)
	var cv: Array = []
	for c in couriers.values():
		var atb = buildings.get(int(c.at))
		var at_cell: int = int(atb.cell) if atb != null else 0
		var at_pn: int = int(atb.pn) if atb != null else 0
		cv.append([int(c.team), int(c.state), at_cell, at_pn, int(c.from_pn), int(c.to_pn), int(c.from_cell),
			int(c.to_cell), float(c.t0), float(c.dur)])
	# угроза: вражеский корабль в полёте внутри сферы притяжения планеты, где у команды ядро или игрок
	var threat := [[], []]
	for sh in ships.values():
		var spn: int = int(sh.pn)
		if int(sh.state) != 1 or spn < 0:
			continue
		var enemy: int = 1 - int(sh.team)
		if enemy < 0 or enemy > 1 or (threat[enemy] as Array).has(spn):
			continue
		if _team_present(enemy, spn):
			(threat[enemy] as Array).append(spn)
	var cache := {}
	for p in Net.ready_peers:
		var tm: int = Net.team_of(p)
		if tm == 0 or tm == 1:
			threat_snap.rpc_id(p, PackedInt32Array(threat[tm]))
		var pn := _peer_pn(p)
		if not cache.has(pn):
			cache[pn] = _snap_data(pn)
		var sd: Dictionary = cache[pn]
		snapshot.rpc_id(p, sd.u, sd.it, sd.itt, sd.pl, storage, base_count, power_stats, sd.rv, world_time)
		caps_snap.rpc_id(p, sd.caps, base_count, ustat)
		proj_snap.rpc_id(p, sd.pp, sd.pv, sd.pk)
		ships_snap.rpc_id(p, sv)
		if not sd.aim_ids.is_empty():
			turret_aims.rpc_id(p, sd.aim_ids, sd.aim_dirs)
		asm_snap.rpc_id(p, sd.asm)
		courier_snap.rpc_id(p, cv)
	if not headless:
		var sd: Dictionary = cache[my_pn] if cache.has(my_pn) else _snap_data(my_pn)
		_apply_snapshot(sd.u, sd.it, sd.itt, sd.pl, storage, base_count, power_stats, sd.rv)
		cur_caps = sd.caps
		unit_stat = ustat
		if my_team == 0 or my_team == 1:
			threat_pns = PackedInt32Array(threat[my_team])
		cur_couriers = cv
		_apply_proj(sd.pp, sd.pv, sd.pk)
		cur_ships = sv
		_apply_aims(sd.aim_ids, sd.aim_dirs)
		_apply_asm(sd.asm)


@rpc("authority", "call_remote", "unreliable_ordered")
func threat_snap(pns: PackedInt32Array) -> void:
	threat_pns = pns


## Есть ли у команды на планете ядро или живой игрок (тогда вражеский корабль там — угроза).
func _team_present(team: int, pn: int) -> bool:
	for pid in players:
		var o: Dictionary = players[pid]
		if int(o.team) == team and int(o.get("pn", -9)) == pn and int(o.hp) > 0:
			return true
	for b in buildings.values():
		if b.type == D.CORE and int(b.team) == team and int(b.pn) == pn:
			return true
	return false


@rpc("authority", "call_remote", "unreliable_ordered")
func asm_snap(a: PackedInt32Array) -> void:
	_apply_asm(a)


func _apply_asm(a: PackedInt32Array) -> void:
	asm_prog.clear()
	for i in range(0, a.size() - 2, 3):
		asm_prog[a[i]] = [float(a[i + 2]) / 1000.0, a[i + 1]]


# =====================================================================
# Клиент: сцена
# =====================================================================

func _build_scene() -> void:
	local_root = Node3D.new()
	add_child(local_root)
	space_root = Node3D.new()
	space_root.visible = false
	add_child(space_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# ламп нет: весь свет считает шейдер lit16 по положению солнца и гиганта

	# поверхность планеты: меш + коллизия (своя у каждой планеты, пересобирается при перелёте)
	_build_terrain()

	# газовый гигант, вокруг которого мы крутимся, и звёзды
	giant_node = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = D.GIANT_R
	sm.height = D.GIANT_R * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	giant_node.mesh = sm
	var gmat := ShaderMaterial.new()
	gmat.shader = GIANT_SHADER
	giant_node.material_override = gmat
	local_root.add_child(giant_node)
	# кольца: плоский квадрат с шейдером, наклонён относительно экватора гиганта
	var rings := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2.ONE * D.GIANT_R * 2.0 * 2.3
	rings.mesh = rq
	var rmat := ShaderMaterial.new()
	rmat.shader = RINGS_SHADER
	rings.material_override = rmat
	rings.rotation_degrees = Vector3(-90 + 18, 0, 8)
	giant_node.add_child(rings)

	# солнце — маленькая очень яркая точка
	sun_node = MeshInstance3D.new()
	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = D.SUN_VIS_R
	sun_mesh.height = D.SUN_VIS_R * 2.0
	sun_node.mesh = sun_mesh
	var sun_mat := StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1.0, 0.97, 0.88)
	sun_mat.emission_enabled = true
	sun_mat.emission = Color(1.0, 0.95, 0.8)
	sun_mat.emission_energy_multiplier = 8.0
	sun_node.material_override = sun_mat
	add_child(sun_node)

	_build_space()

	# звёздное небо — огромная сфера изнутри
	var sky_mesh := SphereMesh.new()
	sky_mesh.radius = 14000.0
	sky_mesh.height = 28000.0
	sky_mesh.radial_segments = 48
	sky_mesh.rings = 24
	var sky_mi := MeshInstance3D.new()
	sky_mi.mesh = sky_mesh
	var skymat := ShaderMaterial.new()
	skymat.shader = SKY_SHADER
	sky_mi.material_override = skymat
	sky_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars_node = sky_mi
	add_child(sky_mi)

	# руда на лентах
	# предметы на лентах — пиксельные значки, всегда лицом к камере
	mm_items = MultiMesh.new()
	mm_items.transform_format = MultiMesh.TRANSFORM_3D
	mm_items.use_custom_data = true
	mm_items.instance_count = 8192
	mm_items.visible_instance_count = 0
	var iq := QuadMesh.new()
	iq.size = Vector2(0.5, 0.5)
	var imat := ShaderMaterial.new()
	imat.shader = ICON_SHADER
	icon_atlas = Icons.build_atlas()
	imat.set_shader_parameter("atlas", icon_atlas)
	imat.set_shader_parameter("grid", Vector2(Icons.COLS, Icons.ROWS))
	iq.material = imat
	mm_items.mesh = iq
	var items_mmi := MultiMeshInstance3D.new()
	items_mmi.multimesh = mm_items
	local_root.add_child(items_mmi)

	# юниты
	# снаряды: светящиеся шарики, между снапшотами летят сами по баллистике
	mm_proj = MultiMesh.new()
	mm_proj.transform_format = MultiMesh.TRANSFORM_3D
	mm_proj.use_colors = true
	mm_proj.instance_count = 2048
	mm_proj.visible_instance_count = 0
	var psph := SphereMesh.new()
	psph.radius = 0.14
	psph.height = 0.28
	psph.radial_segments = 6
	psph.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	psph.material = pmat
	mm_proj.mesh = psph
	var proj_mmi := MultiMeshInstance3D.new()
	proj_mmi.multimesh = mm_proj
	local_root.add_child(proj_mmi)

	# юниты: модели из деталей, цвет команды и прочность — через данные экземпляра
	var umat := ShaderMaterial.new()
	umat.shader = UNIT_SHADER
	mm_units = _make_mm(_tank_mesh(umat), 4096, false)
	mm_drones = _make_mm(_drone_mesh(umat), 2048, false)
	mm_mechs = _make_mm(_mech_mesh(umat), 512, false)
	mm_umechs = _make_mm(_mech_mesh(umat, true), 256, false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	var sel_mat := StandardMaterial3D.new()
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel_mat.albedo_color = Color(0.4, 1.0, 0.5)
	ring.material = sel_mat
	mm_sel = _make_mm(ring, 2048, false)

	# орбитальная камера
	orbit_cam = Camera3D.new()
	orbit_cam.far = 15000
	add_child(orbit_cam)
	var cd: Vector3 = planet.dirs[planet.core_center[maxi(my_team, 0)]]
	_orbit_look_at(cd)

	# призрак постройки: контур по клеткам + стрелка + зона питания генератора
	ghost = Node3D.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_mat.vertex_color_use_as_albedo = true
	ghost_foot = MeshInstance3D.new()
	ghost_foot.material_override = ghost_mat
	ghost.add_child(ghost_foot)
	ghost_arrow = Node3D.new()
	var ga := MeshInstance3D.new()
	var gam := BoxMesh.new()
	gam.size = Vector3(0.8, 0.2, 0.2)
	ga.mesh = gam
	ga.position = Vector3(0.45, 0.45, 0)
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(1, 1, 1, 0.8)
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ga.material_override = arrow_mat
	ghost_arrow.add_child(ga)
	ghost.add_child(ghost_arrow)
	ghost_cover = MeshInstance3D.new()
	var cover_mat := StandardMaterial3D.new()
	cover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cover_mat.albedo_color = Color(1.0, 0.9, 0.2, 0.18)
	ghost_cover.material_override = cover_mat
	ghost.add_child(ghost_cover)
	local_root.add_child(ghost)

	# интерфейс
	var layer := CanvasLayer.new()
	add_child(layer)
	_build_panel(layer)

	big_msg = Label.new()
	big_msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_msg.add_theme_font_size_override("font_size", 56)
	big_msg.add_theme_constant_override("outline_size", 10)
	big_msg.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(big_msg)

	var hint := Label.new()
	hint.text = "H — управление"
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 16
	hint.offset_top = -34
	hint.offset_right = 400
	hint.offset_bottom = -10
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(hint)
	help_panel = _build_help()
	layer.add_child(help_panel)

	radial = RadialMenu.new()
	radial.info_func = _type_info
	layer.add_child(radial)
	item_radial = RadialMenu.new()
	var item_name := func(it): return D.ITEM_NAMES[it]
	item_radial.configure(D.FILTER_GROUPS, item_name, "колесо — сырьё / продукт")
	item_radial.info_func = func(it): return [D.ITEM_NAMES[it], "Точка выгрузки будет принимать этот груз"]
	layer.add_child(item_radial)
	unit_radial = RadialMenu.new()
	var unit_name := func(k): return D.UNIT_NAMES[k]
	unit_radial.configure([["Мини-танк", [0]], ["Дрон", [1]], ["Мех", [2]], ["Уник. мех", [3]]], unit_name, "отпусти E — выбрать")
	unit_radial.info_func = _unit_info
	layer.add_child(unit_radial)
	ship_radial = RadialMenu.new()
	var ship_name := func(k): return D.SHIP_KINDS[k].name
	ship_radial.configure([["Разведчик", [0]], ["Транспорт", [1]], ["НЛО", [2]], ["Камикадзе", [3]], ["Истребитель F", [4]]],
		ship_name, "отпусти E — собрать")
	ship_radial.info_func = _ship_info
	layer.add_child(ship_radial)
	dock_radial = RadialMenu.new()
	var dsecs: Array = []
	for j in D.PLANETS.size():
		dsecs.append([String(D.PLANETS[j].name), [j]])
	dock_radial.configure(dsecs, _planet_name, "отпусти E — назначить")
	dock_radial.info_func = _dock_info
	layer.add_child(dock_radial)
	sel_box = Control.new()
	sel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sel_box.draw.connect(_draw_sel_box)
	layer.add_child(sel_box)

	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.add_theme_constant_override("outline_size", 4)
	crosshair.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(crosshair)
	compass.visible = false
	layer.add_child(compass)
	navball.visible = false
	layer.add_child(navball)

	# персонаж
	if my_team >= 0:
		player = Player.new()
		player.gmul = float(D.PLANETS[my_pn].get("g", 1.0))
		add_child(player)
		player.teleport(_spawn_pos(my_team))
		_build_viewmodel()
		self_avatar = _make_avatar(my_team)
		_set_fps(true)
	else:
		_set_fps(false)


## Обычные поверхности — шейдер с 16 уровнями света. Светящиеся (glow) — сами светятся в темноте.
var terrain_node: Node3D = null
var terrain_cache := {}   # планета -> [меш, треугольники коллизии]


## Поверхность текущей планеты: меш с оттенком, коллизия, у малых — красные искры над жгучими клетками,
## у большой — атмосфера.
func _build_terrain() -> void:
	if terrain_node != null:
		terrain_node.queue_free()
	terrain_node = Node3D.new()
	local_root.add_child(terrain_node)
	if not terrain_cache.has(my_pn):
		terrain_cache[my_pn] = planet.build_mesh()
	var built: Array = terrain_cache[my_pn]
	var terrain := MeshInstance3D.new()
	terrain.mesh = built[0]
	var tmat := ShaderMaterial.new()
	tmat.shader = TERRAIN_SHADER
	tmat.set_shader_parameter("tint", D.PLANET_TINT[planet.kind])
	terrain.material_override = tmat
	terrain_node.add_child(terrain)
	terrain_body = StaticBody3D.new()
	var tcol := CollisionShape3D.new()
	var tshape := ConcavePolygonShape3D.new()
	tshape.backface_collision = true
	tshape.set_faces(built[1])
	tcol.shape = tshape
	terrain_body.add_child(tcol)
	terrain_node.add_child(terrain_body)
	if planet.kind == 2:
		terrain_node.add_child(_atmo_shell(planet.radius))
	if planet.kind == 1:
		var pts := PackedVector3Array()
		var nrm := PackedVector3Array()
		for c in planet.count():
			if planet.hazard[c] == 1:
				pts.append(planet.top_pos(c) + planet.dirs[c] * 0.1)
				nrm.append(planet.dirs[c])
		if not pts.is_empty():
			var ps := CPUParticles3D.new()
			ps.amount = mini(500, pts.size() * 3)
			ps.lifetime = 2.2
			ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
			ps.emission_points = pts
			ps.emission_normals = nrm
			ps.direction = Vector3(1, 0, 0)
			ps.spread = 25.0
			ps.gravity = Vector3.ZERO
			ps.initial_velocity_min = 0.6
			ps.initial_velocity_max = 1.8
			ps.scale_amount_min = 0.6
			ps.scale_amount_max = 1.2
			var grad := Gradient.new()
			grad.set_color(0, Color(1.0, 0.35, 0.15, 1.0))
			grad.set_color(1, Color(0.8, 0.05, 0.02, 0.0))
			ps.color_ramp = grad
			var qm := QuadMesh.new()
			qm.size = Vector2(0.16, 0.16)
			var pm := StandardMaterial3D.new()
			pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pm.vertex_color_use_as_albedo = true
			pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			qm.material = pm
			ps.mesh = qm
			ps.visibility_aabb = AABB(Vector3.ONE * -planet.radius * 1.5, Vector3.ONE * planet.radius * 3.0)
			terrain_node.add_child(ps)


func _atmo_shell(r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r * 1.14
	sp.height = r * 2.28
	sp.radial_segments = 64
	sp.rings = 32
	mi.mesh = sp
	var m := ShaderMaterial.new()
	m.shader = ATMO_SHADER
	mi.material_override = m
	return mi


## Планеты в небе, вид звёздной системы (гигант, планеты, орбиты, сферы влияния), карта.
func _build_space() -> void:
	for j in D.PLANETS.size():
		var moon_mat := ShaderMaterial.new()
		moon_mat.shader = MOON_SHADER
		var tv: Vector3 = D.PLANET_TINT[D.planet_kind(j)]
		moon_mat.set_shader_parameter("albedo", Color(0.55 * tv.x, 0.53 * tv.y, 0.58 * tv.z))
		var rj := D.planet_r(j)
		# планета в небе над текущей
		var sm := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = rj
		sp.height = rj * 2.0
		sp.radial_segments = 32
		sp.rings = 16
		sm.mesh = sp
		sm.material_override = moon_mat
		local_root.add_child(sm)
		sky_moons.append(sm)
		# планета в виде системы: шар, подпись, круг сферы влияния
		var node := Node3D.new()
		var ball := MeshInstance3D.new()
		ball.mesh = sp
		ball.material_override = moon_mat
		node.add_child(ball)
		var lbl := Label3D.new()
		lbl.text = D.PLANETS[j].name
		lbl.modulate = PLANET_COLORS[j]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.fixed_size = true
		lbl.pixel_size = 0.0012
		lbl.font_size = 22
		lbl.outline_size = 6
		lbl.no_depth_test = true
		lbl.position = Vector3(0, rj * 1.6, 0)
		node.add_child(lbl)
		node.add_child(_circle_mesh(SkyCalc.soi(j), Color(0.5, 0.7, 1.0, 0.5)))
		var warn := _marker_label("⚠ тревога", Color(1.0, 0.3, 0.2))
		warn.position = Vector3(0, -rj * 1.6, 0)
		if D.planet_kind(j) == 2:
			node.add_child(_atmo_shell(rj))
			sm.add_child(_atmo_shell(rj))
		node.add_child(warn)
		alert_labels.append(warn)
		space_root.add_child(node)
		space_moons.append(node)
		# орбита планеты — лента её цвета
		var rib := MeshInstance3D.new()
		var rmat := ShaderMaterial.new()
		rmat.shader = ORBIT_SHADER
		var oc: Color = PLANET_COLORS[j]
		rmat.set_shader_parameter("albedo", Color(oc.r, oc.g, oc.b, 0.8))
		rib.material_override = rmat
		space_root.add_child(rib)
		orbit_ribbons.append(rib)
	# гигант в центре системы
	var giant := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = D.GIANT_R
	gs.height = D.GIANT_R * 2.0
	gs.radial_segments = 64
	gs.rings = 32
	giant.mesh = gs
	var gmat := ShaderMaterial.new()
	gmat.shader = GIANT_SHADER
	giant.material_override = gmat
	space_root.add_child(giant)
	# траектории и метки корабля
	local_traj = MeshInstance3D.new()
	local_root.add_child(local_traj)
	sys_traj = MeshInstance3D.new()
	space_root.add_child(sys_traj)
	enc_label = _marker_label("◯", Color(0.45, 1.0, 0.5))
	space_root.add_child(enc_label)
	map_ship_label = _marker_label("▲ ты", Color(1, 0.9, 0.3))
	local_root.add_child(map_ship_label)
	sys_ship_label = _marker_label("▲ ты", Color(1, 0.9, 0.3))
	space_root.add_child(sys_ship_label)
	plan_traj = MeshInstance3D.new()
	space_root.add_child(plan_traj)
	plan_label = _marker_label("◎ цель", Color(1.0, 0.75, 0.3))
	plan_label.visible = false
	space_root.add_child(plan_label)
	map_cam = Camera3D.new()
	map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_cam.far = 30000
	add_child(map_cam)
	compass = Compass.new()
	navball = Navball.new()
	for i in 4:
		var l := _marker_label("Ап" if i % 2 == 0 else "Пе", Color(0.4, 0.9, 1.0) if i % 2 == 0 else Color(1.0, 0.6, 0.3))
		(local_root if i < 2 else space_root).add_child(l)
		ap_labels.append(l)


## Перестраивает ленты орбит, если толщина заметно поменялась (при зуме карты).
func _set_orbit_width(w: float) -> void:
	if orbit_width > 0.0 and absf(w - orbit_width) / orbit_width < 0.15:
		return
	orbit_width = w
	for j in orbit_ribbons.size():
		var a: float = D.PLANETS[j].a
		var verts := PackedVector3Array()
		var verts2 := PackedVector3Array()   # вертикальная лента: видно, даже если смотришь вдоль плоскости орбит
		for i in 257:
			var ang := TAU * i / 256.0
			var dir := Vector3(cos(ang), 0, sin(ang))
			verts.append(dir * (a - w / 2.0))
			verts.append(dir * (a + w / 2.0))
			verts2.append(dir * a + Vector3.UP * (w / 2.0))
			verts2.append(dir * a - Vector3.UP * (w / 2.0))
		var am := ArrayMesh.new()
		for vv in [verts, verts2]:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = vv
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr)
		orbit_ribbons[j].mesh = am


func _marker_label(txt: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0015
	l.font_size = 22
	l.outline_size = 6
	l.no_depth_test = true
	l.visible = false
	return l


## Окружность в плоскости XZ (орбиты, сферы влияния).
func _circle_mesh(r: float, col: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, m)
	for i in 129:
		var a := TAU * i / 128.0
		im.surface_add_vertex(Vector3(cos(a), 0, sin(a)) * r)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi


func _make_mm(mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = not colors
	mm.instance_count = count
	mm.visible_instance_count = 0
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	local_root.add_child(mmi)
	return mm


# ---------------------------------------------------------------------
# Модели юнитов: детали сливаются в один меш (чтобы рисовать сотнями через MultiMesh)
# ---------------------------------------------------------------------

func _pb(size: Vector3) -> PrimitiveMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _pc(r_top: float, r_bot: float, h: float, segs := 8) -> PrimitiveMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


func _ps(r: float) -> PrimitiveMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 5
	return m


## Деталь: [меш, где стоит, поворот в градусах, цвет (альфа — роль детали)].
func _merge(parts: Array, mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var cust := PackedFloat32Array()   # CUSTOM0: точка вращения + вид анимации (см. unit.gdshader)
	var idx := PackedInt32Array()
	for part in parts:
		var pm: PrimitiveMesh = part[0]
		var xf: Transform3D
		if typeof(part[1]) == TYPE_TRANSFORM3D:
			xf = part[1]
		else:
			var rot: Vector3 = part[2]
			xf = Transform3D(Basis.from_euler(rot * (PI / 180.0)), part[1])
		var col: Color = part[3]
		var akind: float = float(part[4]) if part.size() > 4 else 0.0
		var piv: Vector3 = part[5] if part.size() > 5 else Vector3.ZERO
		var arr := pm.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var base := verts.size()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((xf.basis * nn[i]).normalized())
			cols.append(col)
			cust.append(piv.x)
			cust.append(piv.y)
			cust.append(piv.z)
			cust.append(akind)
		var ii = arr[Mesh.ARRAY_INDEX]
		if ii != null and ii.size() > 0:
			for k in ii:
				idx.append(base + int(k))
		else:
			for k in v.size():
				idx.append(base + k)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_CUSTOM0] = cust
	out[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	am.surface_set_material(0, mat)
	return am


## Деталь-брус между двумя точками (для ног паука): [меш, преобразование, -, цвет, вид, шарнир].
func _seg(a: Vector3, b: Vector3, th: float, col: Color, akind: float, piv: Vector3) -> Array:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var xf := Transform3D(Basis(side, dir.cross(side), dir), (a + b) * 0.5)
	return [_pb(Vector3(th, th, a.distance_to(b))), xf, null, col, akind, piv]


## Мини-танк: корпус на гусеницах (траки бегут), башня цвета команды, ствол, фары. Перёд — -Z.
func _tank_mesh(mat: Material) -> ArrayMesh:
	var dark := Color(0.22, 0.22, 0.24, METAL)
	var steel := Color(0.5, 0.5, 0.53, METAL)
	var team := Color(1, 1, 1, PAINT)
	var lamp := Color(1.0, 0.92, 0.6, GLOW)
	var parts := [
		[_pb(Vector3(0.24, 0.32, 1.3)), Vector3(-0.5, 0.16, 0), Vector3.ZERO, dark, 20],     # гусеницы
		[_pb(Vector3(0.24, 0.32, 1.3)), Vector3(0.5, 0.16, 0), Vector3.ZERO, dark, 20],
		[_pb(Vector3(0.8, 0.3, 1.15)), Vector3(0, 0.36, 0), Vector3.ZERO, steel, 30],         # корпус
		[_pb(Vector3(0.82, 0.06, 0.5)), Vector3(0, 0.53, 0.25), Vector3.ZERO, team, 30],       # полоса
		[_pc(0.28, 0.32, 0.24, 8), Vector3(0, 0.62, 0.05), Vector3.ZERO, team, 30],           # башня
		[_pc(0.05, 0.06, 0.7, 6), Vector3(0, 0.66, -0.42), Vector3(90, 0, 0), dark, 30],      # ствол
		[_pb(Vector3(0.12, 0.07, 0.05)), Vector3(-0.25, 0.4, -0.6), Vector3.ZERO, lamp, 30],  # фары
		[_pb(Vector3(0.12, 0.07, 0.05)), Vector3(0.25, 0.4, -0.6), Vector3.ZERO, lamp, 30],
	]
	return _merge(parts, mat)


## Дрон-камикадзе: корпус цвета команды, крестовина, 4 крутящихся винта, глаз-фара, заряд снизу.
func _drone_mesh(mat: Material) -> ArrayMesh:
	var dark := Color(0.2, 0.2, 0.22, METAL)
	var steel := Color(0.55, 0.55, 0.6, METAL)
	var team := Color(1, 1, 1, PAINT)
	var parts := [
		[_ps(0.22), Vector3.ZERO, Vector3.ZERO, team, 11],
		[_pb(Vector3(1.0, 0.05, 0.07)), Vector3.ZERO, Vector3(0, 45, 0), steel, 11],
		[_pb(Vector3(1.0, 0.05, 0.07)), Vector3.ZERO, Vector3(0, -45, 0), steel, 11],
		[_pb(Vector3(0.12, 0.05, 0.06)), Vector3(0, 0.02, -0.21), Vector3.ZERO, Color(1.0, 0.9, 0.6, GLOW), 11],   # фара
		[_ps(0.1), Vector3(0, -0.2, 0), Vector3.ZERO, Color(1.0, 0.55, 0.15, GLOW), 11],                             # заряд
	]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * 0.35, 0.06, sz * 0.35)
			parts.append([_pc(0.04, 0.04, 0.06, 6), c, Vector3.ZERO, dark, 11])
			parts.append([_pb(Vector3(0.4, 0.015, 0.05)), c + Vector3(0, 0.03, 0), Vector3.ZERO, dark, 10, c])   # лопасти
			parts.append([_pb(Vector3(0.05, 0.015, 0.4)), c + Vector3(0, 0.03, 0), Vector3.ZERO, dark, 10, c])
	return _merge(parts, mat)


## Боевой мех-паук: брюшко и головогрудь цвета команды, кабина с визором и фарами,
## спаренные пушки сверху, 8 суставчатых ног (ходят двумя группами). Перёд — -Z.
func _mech_mesh(mat: Material, alien := false) -> ArrayMesh:
	var dark := Color(0.2, 0.2, 0.22, METAL)
	var steel := Color(0.48, 0.48, 0.52, METAL)
	if alien:
		# уникальный мех: тёмно-фиолетовый инопланетный металл с синими светящимися полосами
		dark = Color(0.14, 0.1, 0.2, METAL)
		steel = Color(0.28, 0.22, 0.4, METAL)
	var team := Color(1, 1, 1, PAINT)
	var lamp := Color(1.0, 0.92, 0.6, GLOW)
	var parts := [
		[_ps(0.85), Vector3(0, 1.55, 0.75), Vector3.ZERO, team, 30],                         # брюшко
		[_pb(Vector3(1.2, 0.55, 1.2)), Vector3(0, 1.45, -0.35), Vector3.ZERO, steel, 30],     # головогрудь
		[_pb(Vector3(1.0, 0.12, 1.0)), Vector3(0, 1.76, -0.35), Vector3.ZERO, team, 30],      # панцирь
		[_pb(Vector3(0.6, 0.35, 0.45)), Vector3(0, 1.5, -1.05), Vector3.ZERO, steel, 30],     # кабина
		[_pb(Vector3(0.5, 0.1, 0.04)), Vector3(0, 1.58, -1.28), Vector3.ZERO, Color(1.0, 0.4, 0.25, GLOW), 30],  # визор
		[_pb(Vector3(0.1, 0.08, 0.04)), Vector3(-0.22, 1.38, -1.28), Vector3.ZERO, lamp, 30],  # фары
		[_pb(Vector3(0.1, 0.08, 0.04)), Vector3(0.22, 1.38, -1.28), Vector3.ZERO, lamp, 30],
		[_pb(Vector3(0.7, 0.25, 0.5)), Vector3(0, 1.95, -0.3), Vector3.ZERO, dark, 30],       # турель
	]
	for sx in [-1.0, 1.0]:
		parts.append([_pc(0.08, 0.09, 1.1, 6), Vector3(sx * 0.18, 1.98, -0.95), Vector3(90, 0, 0), dark, 30])   # стволы
		parts.append([_pb(Vector3(0.1, 0.1, 0.04)), Vector3(sx * 0.18, 1.98, -1.52), Vector3.ZERO,
			Color(1.0, 0.5, 0.2, GLOW), 30])
	# ноги: шарнир у корпуса -> колено высоко над корпусом -> стопа далеко в стороне
	var zs := [-0.85, -0.35, 0.15, 0.65]
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		for i in 4:
			var leg := float(side * 4 + i + 1)
			var hip := Vector3(sx * 0.55, 1.4, float(zs[i]) - 0.2)
			var spread := float(zs[i]) * 1.6
			var knee := Vector3(sx * 1.45, 2.25, hip.z + spread * 0.5)
			var foot := Vector3(sx * 2.25, 0.0, hip.z + spread)
			parts.append(_seg(hip, knee, 0.16, steel, leg, hip))
			parts.append(_seg(knee, foot, 0.12, dark, leg, hip))
			parts.append([_ps(0.11), knee, Vector3.ZERO, team, leg, hip])   # колено
			if alien:
				parts.append(_seg(knee + Vector3(0, 0.1, 0), foot.lerp(knee, 0.5) + Vector3(0, 0.1, 0), 0.05,
					Color(0.3, 0.6, 1.0, GLOW), leg, hip))   # синяя полоса по ноге
	if alien:
		for z in [-0.7, -0.3, 0.1, 0.5]:
			parts.append([_pb(Vector3(1.05, 0.04, 0.06)), Vector3(0, 1.83, z), Vector3.ZERO, Color(0.3, 0.6, 1.0, GLOW), 30])
		parts.append([_ps(0.3), Vector3(0, 2.3, 0.75), Vector3.ZERO, Color(0.4, 0.95, 1.0, GLOW), 30])   # кристалл материи
	return _merge(parts, mat)


func _mat(color: Color, glow := false) -> Material:
	var key := "%s|%s" % [color, glow]
	if mats.has(key):
		return mats[key]
	var m: Material
	if glow:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = color
		sm.emission_enabled = true
		sm.emission = color
		sm.emission_energy_multiplier = 1.5
		m = sm
	else:
		var sh := ShaderMaterial.new()
		sh.shader = LIT_SHADER
		sh.set_shader_parameter("albedo", color)
		m = sh
	mats[key] = m
	return m


## Материал с пиксельным узором: 0 гладко, 1 металл, 2 лента конвейера, 3 труба с водой.
func _pmat(color: Color, pattern: int) -> Material:
	var key := "p%d|%s" % [pattern, color]
	if mats.has(key):
		return mats[key]
	var sh := ShaderMaterial.new()
	sh.shader = LIT_SHADER
	sh.set_shader_parameter("albedo", color)
	sh.set_shader_parameter("pattern", pattern)
	mats[key] = sh
	return sh


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = _mat(color, glow)
	parent.add_child(m)
	return m


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, color: Color, segs := 16) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	m.mesh = cm
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


## Ставит узел на верх клетки: локальная Y — нормаль, локальная X — в сторону соседа.
func _orient(n: Node3D, cell: int, toward: int) -> void:
	var o := planet.top_pos(cell)
	var up: Vector3 = planet.dirs[cell]
	var f := planet.top_pos(toward) - o
	f = (f - up * f.dot(up)).normalized()
	n.transform = Transform3D(Basis(f, up, f.cross(up)), o)


func _vis_add(b: Dictionary) -> void:
	var root := Node3D.new()   # в мировых координатах
	var n := Node3D.new()      # декор, повёрнут по клетке
	root.add_child(n)
	var col: Color = D.TEAM_COLORS[b.team]
	var t: int = b.type
	var cells: Array = b.cells
	var multi := cells.size() > 1
	var base_h := CORE_H if t == D.CORE else 0.45
	var mi: MeshInstance3D = null
	if multi:
		# основание — призмы точно по контуру клеток
		var pr: Array = planet.prism(cells, base_h, 0.94, col.darkened(0.55), col.darkened(0.3))
		mi = MeshInstance3D.new()
		mi.mesh = pr[0]
		mi.material_override = _vc_mat()
		root.add_child(mi)
		var pbody := StaticBody3D.new()
		var pcol := CollisionShape3D.new()
		var pshape := ConcavePolygonShape3D.new()
		pshape.backface_collision = true
		pshape.set_faces(pr[1])
		pcol.shape = pshape
		pbody.add_child(pcol)
		root.add_child(pbody)
	if t == D.CORE:
		_cyl(n, 0.9, 0.5, Vector3(0, 0.25, 0), col.darkened(0.2), 6)
		var crystal := Node3D.new()
		crystal.position = Vector3(0, 1.3, 0)
		n.add_child(crystal)
		_box(crystal, Vector3(1.1, 1.6, 1.1), Vector3.ZERO, col, true)
		_anim(n, crystal, "spin", 0.4, 1.0, true)
		_anim(n, crystal, "bob", 0.1, 1.0, true)
		var orbit := Node3D.new()
		orbit.position = Vector3(0, 1.3, 0)
		n.add_child(orbit)
		for k in 3:
			var a := TAU * k / 3.0
			_box(orbit, Vector3(0.18, 0.18, 0.18), Vector3(cos(a) * 1.1, 0.4 * sin(a * 2.0), sin(a) * 1.1), col.lightened(0.3), true)
		_anim(n, orbit, "spin", -1.2, 1.0, true)
		var fire := Node3D.new()   # склад полон — лишнее горит
		fire.position = Vector3(0, 0.55, 0)
		n.add_child(fire)
		for k in 4:
			var a := TAU * k / 4.0
			_box(fire, Vector3(0.2, 0.35, 0.2), Vector3(cos(a) * 0.7, 0, sin(a) * 0.7), Color(1.0, 0.45, 0.1), true)
		_anim(n, fire, "burn", 0.3, 6.0, true)
	else:
		_vis_shape(n, t, col)
	if D.RECIPES.has(t):
		# выход продукта — лоток спереди со стрелкой
		_box(n, Vector3(0.22, 0.3, 0.5), Vector3(0.74, 0.22, 0), Color(0.25, 0.25, 0.28))
		var arr := _box(n, Vector3(0.12, 0.05, 0.3), Vector3(0.86, 0.4, 0), Color(1.0, 0.8, 0.2), true)
		_anim(n, arr, "pulse", 0.3, 2.0, true)
	if D.UPGRADABLE.has(t):
		for i in int(b.get("lvl", 1)) - 1:
			_box(n, Vector3(0.26, 0.07, 0.12), Vector3(-0.6, 0.95 + 0.14 * i, 0.6), Color(1.0, 0.8, 0.2), true)
	if n.has_meta("bulb"):
		root.set_meta("bulb", n.get_meta("bulb"))
		if not bool(b.get("lit", true)):
			var bl: MeshInstance3D = n.get_meta("bulb")
			bl.material_override = _pmat(Color(0.25, 0.24, 0.22), 0)
	if IND_H.has(t):
		var ind := MeshInstance3D.new()
		var im := SphereMesh.new()
		im.radius = 0.13
		im.height = 0.26
		im.radial_segments = 8
		im.rings = 4
		ind.mesh = im
		ind.position = Vector3(0, IND_H[t], 0)
		ind.material_override = _mat(STATE_COLORS[ST_IDLE], true)
		n.add_child(ind)
		root.set_meta("ind", ind)
	if n.has_meta("pitch"):
		turret_nodes[b.id] = n
	if t == D.UNLOADER or t == D.SORTER:
		var sp := Sprite3D.new()
		sp.texture = icon_atlas
		sp.region_enabled = true
		sp.region_rect = Rect2(0, 0, Icons.SIZE, Icons.SIZE)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.pixel_size = 0.07
		sp.shaded = false
		sp.position = Vector3(0, 1.9 if t == D.UNLOADER else 1.2, 0)
		sp.visible = false
		n.add_child(sp)
		root.set_meta("filter_sprite", sp)
	# твёрдое тело для одноклеточных (по конвейерам и трубам ходим; у забора — свои секции)
	if not multi and t != D.CONVEYOR and t != D.PIPE and t != D.WALL and t != D.SORTER:
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 2.8, 1.2) if t == D.POWER_POLE else Vector3(1.2, 1.3, 1.2)
		shape_node.shape = shape
		shape_node.position.y = shape.size.y / 2.0
		body.add_child(shape_node)
		n.add_child(body)
	local_root.add_child(root)

	var nb: PackedInt32Array = planet.nbrs[b.cell]
	var toward: int = nb[int(b.dir) % nb.size()]
	if multi:
		# декор — в центре контура, поверх основания, крупнее
		var center := _foot_center(cells, int(b.pn))
		var up := center.normalized()
		var f := planet.top_pos(toward) - planet.top_pos(b.cell)
		f = (f - up * f.dot(up)).normalized()
		n.transform = Transform3D(Basis(f, up, f.cross(up)), center + up * base_h)
		if t != D.CORE:
			n.scale = Vector3.ONE * (1.6 if cells.size() == 3 else (2.4 if cells.size() == 9 else 2.9))
	else:
		_orient(n, b.cell, toward)
	bnodes[b.id] = root
	_vis_links(n, root, b)
	if n.has_meta("arm") or n.has_meta("spin") or n.has_meta("anim"):
		anim_nodes[b.id] = root
	root.set_meta("deco", n)
	root.set_meta("deco_xf", n.transform)
	root.set_meta("deco_h", _deco_height(n))
	root.set_meta("anchor", planet.top_pos(b.cell))
	if mi != null:
		root.set_meta("prism", mi)
	if _busy(b):
		_apply_build_vis(b)
	if b.filter != D.I_NONE:
		_apply_filter(b.id, b.filter)


# ---------------------------------------------------------------------
# Соединения: конвейеры и трубы стыкуются с соседями, заборы — в сплошную стену, столбы — проводами
# ---------------------------------------------------------------------

const LINK_TYPES := [D.CONVEYOR, D.SORTER, D.PIPE, D.WALL, D.POWER_POLE, D.SPLITTER, D.JUNCTION, D.BRIDGE]
const BELT_TYPES := [D.CONVEYOR, D.SORTER, D.PIPE, D.SPLITTER, D.JUNCTION, D.BRIDGE]


## Выдаёт ли постройка o продукт именно в клетку cell (завод — только вперёд).
func _feeds(o: Dictionary, cell: int, pipe: bool) -> bool:
	if not _is_producer(o, pipe):
		return false
	return not o.has("fouts") or (o.fouts as Array).has(cell)


## Постройка сама выдаёт продукт в соседние клетки (к ней пристыкуется лента).
func _is_producer(o: Dictionary, pipe: bool) -> bool:
	var t: int = o.type
	if pipe:
		return t == D.MELTER
	return _is_drill(t) or (D.RECIPES.has(t) and t != D.MELTER) or t == D.UNLOADER


## Направление на соседнюю клетку в локальных координатах декора (в плоскости клетки) и расстояние до неё.
func _local_dir(n: Node3D, from_cell: int, to_cell: int) -> Array:
	var w := planet.top_pos(to_cell) - planet.top_pos(from_cell)
	var l := n.transform.basis.inverse() * w
	l.y = 0.0
	return [l.normalized(), w.length()]


## Узел, повёрнутый так, что его +X смотрит вдоль v (v — в плоскости XZ).
func _seg_node(n: Node3D, v: Vector3) -> Node3D:
	var seg := Node3D.new()
	seg.rotation.y = atan2(-v.z, v.x)
	n.add_child(seg)
	return seg


func _vis_links(n: Node3D, root: Node3D, b: Dictionary) -> void:
	var t: int = b.type
	if not LINK_TYPES.has(t):
		return
	var pn: int = b.pn
	var cell: int = b.cell
	var nb: PackedInt32Array = planet.nbrs[cell]
	var col: Color = D.TEAM_COLORS[b.team]
	if t == D.CONVEYOR or t == D.PIPE or t == D.SORTER:
		var out := _local_dir(n, cell, _out_cell(b))
		var half: float = float(out[1]) * 0.5
		var feeders: Array = []
		for x in nb:
			if x == _out_cell(b) or not grid.has(_k(pn, x)):
				continue
			var o: Dictionary = buildings[grid[_k(pn, x)]]
			if (o.type == t or (t != D.PIPE and (o.type == D.CONVEYOR or o.type == D.SORTER))) and _out_cell(o) == cell:
				feeders.append(x)
			elif o.type == D.SPLITTER or o.type == D.JUNCTION or o.type == D.BRIDGE:
				feeders.append(x)
			elif _feeds(o, cell, t == D.PIPE):
				feeders.append(x)
		# лента заходит внутрь машины, в которую смотрит, — без зазора у стенки
		var oc := _out_cell(b)
		var into := 0.0
		if grid.has(_k(pn, oc)) and not BELT_TYPES.has(int(buildings[grid[_k(pn, oc)]].type)):
			into = 0.35
			_intake(n, out[0], half, t == D.PIPE)
		_belt_half(n, out[0], half + into, false, t == D.PIPE, col)
		if feeders.is_empty():
			_belt_half(n, -Vector3(out[0]), half, true, t == D.PIPE, col)   # начало ленты — прямой кусок
		for x in feeders:
			var fd := _local_dir(n, cell, x)
			var ext := 0.0 if BELT_TYPES.has(int(buildings[grid[_k(pn, x)]].type)) else 0.35
			_belt_half(n, fd[0], float(fd[1]) * 0.5 + ext, true, t == D.PIPE, col)
			if ext > 0.0:
				_intake(n, fd[0], float(fd[1]) * 0.5, t == D.PIPE)
		if t == D.SORTER:
			# арка сортировщика над лентой, на ней — значок выбранного груза
			var arch := _seg_node(n, out[0])
			for sz in [-0.4, 0.4]:
				_box(arch, Vector3(0.08, 0.75, 0.08), Vector3(0, 0.45, sz), Color(0.85, 0.7, 0.15))
			_box(arch, Vector3(0.12, 0.1, 0.9), Vector3(0, 0.85, 0), Color(0.85, 0.7, 0.15))
		if t == D.CONVEYOR or t == D.SORTER:
			# стык в центре: барабан-ролик под лентой и стрелка направления
			_cyl(n, 0.36, 0.07, Vector3(0, 0.135, 0), Color(0.16, 0.16, 0.18), 8).material_override = \
					_pmat(Color(0.2, 0.2, 0.22), 2)
			var arrow := _seg_node(n, out[0])
			for sgn in [1.0, -1.0]:
				var wing := _box(arrow, Vector3(0.22, 0.03, 0.06), Vector3(0.14, 0.18, 0.06 * sgn), col, true)
				wing.rotation = Vector3(0.0, 0.6 * sgn, 0.0)
		else:
			_box(n, Vector3(0.42, 0.42, 0.42), Vector3(0, 0.3, 0), Color(0.42, 0.45, 0.5)).material_override = \
					_pmat(Color(0.42, 0.45, 0.5), 1)
	elif t == D.SPLITTER or t == D.JUNCTION or t == D.BRIDGE:
		_vis_logistic(n, root, b)
	elif t == D.WALL:
		var stone := _pmat(Color(0.45, 0.45, 0.48), 1)
		var post := _cyl(n, 0.45, 2.7, Vector3(0, 1.35, 0), Color(0.4, 0.4, 0.43), 6)
		post.material_override = stone
		_cyl(n, 0.5, 0.12, Vector3(0, 2.76, 0), col.darkened(0.3), 6)
		var body := StaticBody3D.new()
		n.add_child(body)
		var pcs := CollisionShape3D.new()
		var pshape := CylinderShape3D.new()
		pshape.radius = 0.5
		pshape.height = 3.0
		pcs.shape = pshape
		pcs.position.y = 1.5
		body.add_child(pcs)
		for x in nb:
			if not grid.has(_k(pn, x)):
				continue
			var o: Dictionary = buildings[grid[_k(pn, x)]]
			if o.type != D.WALL and not D.DEFENSE_TYPES.has(o.type):
				continue
			var ld := _local_dir(n, cell, x)
			var hl: float = float(ld[1]) * 0.5 + 0.02
			var seg := _seg_node(n, ld[0])
			var panel := _box(seg, Vector3(hl, 2.2, 0.5), Vector3(hl * 0.5, 1.1, 0), Color(0.4, 0.4, 0.43))
			panel.material_override = stone
			_box(seg, Vector3(hl, 0.1, 0.56), Vector3(hl * 0.5, 2.25, 0), col.darkened(0.3))
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(hl, 3.0, 0.6)
			cs.shape = bs
			cs.position = Vector3(hl * 0.5, 1.5, 0)
			cs.rotation.y = seg.rotation.y
			cs.position = seg.transform * cs.position
			body.add_child(cs)
	elif t == D.POWER_POLE:
		var wood := Color(0.5, 0.45, 0.35)
		_cyl(n, 0.08, 2.6, Vector3(0, 1.3, 0), wood)
		_box(n, Vector3(0.9, 0.08, 0.08), Vector3(0, 2.4, 0), wood)
		var pl := _box(n, Vector3(0.14, 0.14, 0.14), Vector3(0, 2.65, 0), Color(1.0, 0.85, 0.3), true)
		_anim(n, pl, "blink", 1.0, 0.7, true)
		# провода — к двум ближайшим столбам своей команды, поставленным раньше
		var near: Array = []
		var r := planet.rings(cell, D.POLE_RING)
		for x in r:
			if x == cell or not grid.has(_k(pn, x)):
				continue
			var o: Dictionary = buildings[grid[_k(pn, x)]]
			if o.type == D.POWER_POLE and o.team == b.team and o.id < b.id:
				near.append([int(r[x]), x])
		near.sort_custom(func(a, c): return a[0] < c[0])
		for i in mini(2, near.size()):
			_wire(root, cell, int(near[i][1]))


## Приёмный короб там, где лента входит в машину или выходит из неё.
func _intake(n: Node3D, v: Vector3, at: float, pipe: bool) -> void:
	var seg := _seg_node(n, v)
	if pipe:
		_box(seg, Vector3(0.12, 0.42, 0.42), Vector3(at, 0.3, 0), Color(0.45, 0.48, 0.52))
		return
	_box(seg, Vector3(0.14, 0.42, 0.86), Vector3(at, 0.21, 0), Color(0.3, 0.3, 0.33)).material_override = \
			_pmat(Color(0.3, 0.3, 0.33), 1)
	for sz in [-0.3, -0.1, 0.1, 0.3]:
		_box(seg, Vector3(0.16, 0.08, 0.1), Vector3(at, 0.36, sz), Color(0.9, 0.75, 0.15) if sz < 0.0 or sz > 0.2 \
				else Color(0.1, 0.1, 0.1))


## Разветвитель, перекрёсток, мост: ступица + стыки лент/труб ко всем соседям-лентам.
func _vis_logistic(n: Node3D, root: Node3D, b: Dictionary) -> void:
	var t: int = b.type
	var pn: int = b.pn
	var cell: int = b.cell
	var col: Color = D.TEAM_COLORS[b.team]
	var nb: PackedInt32Array = planet.nbrs[cell]
	var steel := _pmat(Color(0.5, 0.5, 0.55), 1)
	var hazard := Color(0.9, 0.75, 0.15)
	if t != D.BRIDGE:
		for x in nb:
			if not grid.has(_k(pn, x)):
				continue
			var o: Dictionary = buildings[grid[_k(pn, x)]]
			var ot: int = o.type
			if not BELT_TYPES.has(ot) and not _feeds(o, cell, false) and not _feeds(o, cell, true):
				continue
			var ld := _local_dir(n, cell, x)
			var inward: bool = (ot == D.CONVEYOR or ot == D.PIPE or ot == D.SORTER) and _out_cell(o) == cell
			if not BELT_TYPES.has(ot):
				inward = true
			_belt_half(n, ld[0], float(ld[1]) * 0.5, inward, ot == D.PIPE or (ot == D.MELTER), col)
	if t == D.SPLITTER:
		# ступица с вращающимся распределителем
		_cyl(n, 0.62, 0.22, Vector3(0, 0.11, 0), Color(0.3, 0.3, 0.33), 8).material_override = steel
		_cyl(n, 0.66, 0.05, Vector3(0, 0.23, 0), hazard, 8)
		var spin := Node3D.new()
		spin.position = Vector3(0, 0.27, 0)
		n.add_child(spin)
		_cyl(spin, 0.2, 0.1, Vector3.ZERO, Color(0.25, 0.25, 0.28), 8)
		for a in 3:
			var vane := Node3D.new()
			vane.rotation.y = TAU * a / 3.0
			spin.add_child(vane)
			_box(vane, Vector3(0.42, 0.08, 0.08), Vector3(0.3, 0, 0), Color(0.75, 0.75, 0.8))
			_box(vane, Vector3(0.08, 0.1, 0.1), Vector3(0.5, 0, 0), col, true)
		n.set_meta("spin", spin)
	elif t == D.JUNCTION:
		# крестовина: нижний проход и мостик над ним, рамка с жёлто-чёрной разметкой
		_box(n, Vector3(1.0, 0.2, 1.0), Vector3(0, 0.1, 0), Color(0.3, 0.3, 0.33)).material_override = steel
		for k in 4:
			var c := Vector3(0.45 if k % 2 == 0 else -0.45, 0.25, 0.45 if k < 2 else -0.45)
			_box(n, Vector3(0.14, 0.1, 0.14), c, hazard)
		_box(n, Vector3(1.0, 0.05, 0.5), Vector3(0, 0.23, 0), Color.WHITE).material_override = \
				_pmat(Color(0.2, 0.2, 0.22), 2)
		var top := Node3D.new()
		top.position = Vector3(0, 0.42, 0)
		top.rotation.y = PI / 2.0
		n.add_child(top)
		_box(top, Vector3(1.0, 0.05, 0.5), Vector3.ZERO, Color.WHITE).material_override = _pmat(Color(0.2, 0.2, 0.22), 2)
		for sz in [-0.3, 0.3]:
			_box(top, Vector3(1.0, 0.12, 0.06), Vector3(0, 0.03, sz), Color(0.58, 0.56, 0.5))
			_box(n, Vector3(0.08, 0.4, 0.08), Vector3(sz, 0.2, sz), Color(0.4, 0.4, 0.44))
			_box(n, Vector3(0.08, 0.4, 0.08), Vector3(sz, 0.2, -sz), Color(0.4, 0.4, 0.44))
	else:
		# мост: въездной пандус сзади, опора, площадка наверху; есть дальний мост — пролёт-ферма до него
		var out := _local_dir(n, cell, _out_cell(b))
		var fwd: Vector3 = out[0]
		var half: float = float(out[1]) * 0.5
		var ramp := _seg_node(n, fwd)
		var ang := atan2(0.95, half)
		var rp := Node3D.new()
		rp.position = Vector3(-half * 0.5, 0.55, 0)
		rp.rotation.z = ang
		ramp.add_child(rp)
		var rl := sqrt(half * half + 0.95 * 0.95)
		_box(rp, Vector3(rl, 0.05, 0.6), Vector3.ZERO, Color.WHITE).material_override = _pmat(Color(0.2, 0.2, 0.22), 2)
		for sz in [-0.34, 0.34]:
			_box(rp, Vector3(rl, 0.14, 0.07), Vector3(0, 0.02, sz), Color(0.58, 0.56, 0.5))
		for sz in [-0.3, 0.3]:
			_box(ramp, Vector3(0.12, 1.1, 0.12), Vector3(0.1, 0.55, sz), Color(0.4, 0.4, 0.45)).material_override = steel
		_box(ramp, Vector3(0.6, 0.14, 0.8), Vector3(0.15, 1.1, 0), Color(0.32, 0.32, 0.36)).material_override = steel
		_box(ramp, Vector3(0.62, 0.04, 0.5), Vector3(0.15, 1.19, 0), col, true)
		var tgt = _bridge_target(b)
		if tgt == null:
			_belt_half(n, fwd, half, false, false, col)   # дальнего моста нет — выдаёт вперёд
		else:
			_span(root, b, tgt, col)


## Пролёт моста: лента по воздуху между площадками двух мостов.
func _span(root: Node3D, a: Dictionary, c: Dictionary, col: Color) -> void:
	var pa := planet.top_pos(a.cell) + planet.dirs[a.cell] * 1.2
	var pc := planet.top_pos(c.cell) + planet.dirs[c.cell] * 1.2
	var d := pc - pa
	var dir := d.normalized()
	var up := ((pa + pc) * 0.5).normalized()
	var side := up.cross(dir).normalized()
	var bas := Basis(dir, side.cross(dir), side)   # +X — вдоль пролёта
	var holder := Node3D.new()
	holder.transform = Transform3D(bas, (pa + pc) * 0.5)
	root.add_child(holder)
	var ln := d.length()
	_box(holder, Vector3(ln, 0.05, 0.5), Vector3.ZERO, Color.WHITE).material_override = _pmat(Color(0.2, 0.2, 0.22), 2)
	for sz in [-0.3, 0.3]:
		_box(holder, Vector3(ln, 0.08, 0.06), Vector3(0, -0.06, sz), Color(0.5, 0.5, 0.55))
		_box(holder, Vector3(ln, 0.05, 0.05), Vector3(0, 0.28, sz), col.darkened(0.2))
	var k := int(ln / 0.8)
	for i in k:
		var x := -ln * 0.5 + (i + 0.5) * ln / k
		for sz in [-0.3, 0.3]:
			_box(holder, Vector3(0.04, 0.34, 0.04), Vector3(x, 0.11, sz), Color(0.5, 0.5, 0.55))


## Половина ленты/трубы: от центра клетки до края в сторону v. inward — груз едет к центру.
func _belt_half(n: Node3D, v: Vector3, length: float, inward: bool, pipe: bool, col: Color) -> void:
	var seg := _seg_node(n, -v if inward else v)   # +X узла — направление движения груза
	var cx := -length * 0.5 if inward else length * 0.5
	var ln := length + 0.04
	if pipe:
		var tube := _box(seg, Vector3(ln, 0.26, 0.26), Vector3(cx, 0.3, 0), Color(0.3, 0.38, 0.5))
		tube.material_override = _pmat(Color(0.25, 0.4, 0.6), 3)
		var fx := cx * 2.0 - 0.06 if not inward else cx * 2.0 + 0.06
		_box(seg, Vector3(0.06, 0.34, 0.34), Vector3(fx, 0.3, 0), Color(0.45, 0.48, 0.52))   # фланец у края
		_box(seg, Vector3(0.08, 0.3, 0.08), Vector3(cx, 0.12, 0), Color(0.35, 0.36, 0.4))      # опора
		return
	# резиновое полотно с бегущими поперечными полосами
	_box(seg, Vector3(ln, 0.05, 0.6), Vector3(cx, 0.15, 0), Color.WHITE).material_override = \
			_pmat(Color(0.2, 0.2, 0.22), 2)
	# станина и борта
	_box(seg, Vector3(ln, 0.1, 0.5), Vector3(cx, 0.06, 0), Color(0.3, 0.3, 0.33)).material_override = \
			_pmat(Color(0.3, 0.3, 0.33), 1)
	for sz in [-0.34, 0.34]:
		_box(seg, Vector3(ln, 0.16, 0.07), Vector3(cx, 0.15, sz), Color(0.55, 0.55, 0.6)).material_override = \
				_pmat(Color(0.58, 0.56, 0.5), 1)
	# ролики на краях бортов и полоса цвета команды по борту
	var ex := cx * 2.0
	for sz in [-0.34, 0.34]:
		_box(seg, Vector3(0.1, 0.1, 0.09), Vector3(ex, 0.08, sz), Color(0.25, 0.25, 0.27))
		_box(seg, Vector3(ln * 0.6, 0.03, 0.075), Vector3(cx, 0.235, sz), col.darkened(0.2))


## Провод между верхушками двух столбов, с провисанием.
func _wire(root: Node3D, a_cell: int, b_cell: int) -> void:
	var a := planet.top_pos(a_cell) + planet.dirs[a_cell] * 2.45
	var c := planet.top_pos(b_cell) + planet.dirs[b_cell] * 2.45
	var up := ((a + c) * 0.5).normalized()
	var sag := a.distance_to(c) * 0.06
	var pts: Array = []
	for i in 7:
		var k := i / 6.0
		pts.append(a.lerp(c, k) - up * sag * 4.0 * k * (1.0 - k))
	var m := _mat(Color(0.12, 0.12, 0.13))
	for i in 6:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, p0.distance_to(p1))
		seg.mesh = bm
		seg.material_override = m
		var dir := (p1 - p0).normalized()
		var side := up.cross(dir)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		seg.transform = Transform3D(Basis(side, dir.cross(side), dir), (p0 + p1) * 0.5)
		root.add_child(seg)


## После стройки/сноса перерисовать соседей, чьё соединение могло измениться.
func _refresh_links(b: Dictionary) -> void:
	var pn: int = b.pn
	var ids := {}
	for c in b.cells:
		var nb: PackedInt32Array = planet.nbrs[c]
		for x in nb:
			var id: int = grid.get(_k(pn, x), -1)
			if id != -1 and id != b.id and LINK_TYPES.has(int(buildings[id].type)):
				ids[id] = true
	if b.type == D.BRIDGE:
		var rb := planet.rings(b.cell, D.BRIDGE_RANGE + 1)
		for x in rb:
			var id: int = grid.get(_k(pn, x), -1)
			if id != -1 and id != b.id and int(buildings[id].type) == D.BRIDGE:
				ids[id] = true
	if b.type == D.POWER_POLE:
		var r := planet.rings(b.cell, D.POLE_RING)
		for x in r:
			var id: int = grid.get(_k(pn, x), -1)
			if id != -1 and id != b.id and int(buildings[id].type) == D.POWER_POLE:
				ids[id] = true
	for id in ids:
		_revis(id)


func _revis(id: int) -> void:
	if not bnodes.has(id) or not buildings.has(id):
		return
	bnodes[id].queue_free()
	bnodes.erase(id)
	turret_nodes.erase(id)
	asm_nodes.erase(id)
	_vis_add(buildings[id])


## Лента/труба: полосы бегут, только когда по ней что-то едет.
func _set_belt_run(root: Node3D, on: bool) -> void:
	if root.has_meta("belt_on") and bool(root.get_meta("belt_on")) == on:
		return
	root.set_meta("belt_on", on)
	if not root.has_meta("belt_meshes"):
		var found: Array = []
		var stack: Array = [root]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			for ch in nd.get_children():
				stack.append(ch)
				if ch is MeshInstance3D:
					var sm := (ch as MeshInstance3D).material_override as ShaderMaterial
					if sm != null:
						var pt = sm.get_shader_parameter("pattern")
						if pt != null and (int(pt) == 2 or int(pt) == 3):
							found.append(ch)
		root.set_meta("belt_meshes", found)
	for mi in root.get_meta("belt_meshes"):
		if is_instance_valid(mi):
			(mi as MeshInstance3D).set_instance_shader_parameter("belt_on", 1.0 if on else 0.0)


## Высота декора (по мешам) в его локальных координатах.
func _deco_height(n: Node3D) -> float:
	var h := 0.3
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		for ch in node.get_children():
			if ch is Node3D:
				var cxf: Transform3D = xf * (ch as Node3D).transform
				if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
					var bb: AABB = cxf * (ch as MeshInstance3D).mesh.get_aabb()
					h = maxf(h, bb.end.y)
				stack.append([ch, cxf])
	return h


# ---------------------------------------------------------------------
# Анимация стройки и сноса: постройка растёт из земли внутри светящегося каркаса,
# к ней тянется луч от строителя. Снос — то же самое в обратную сторону (оранжевым).
# ---------------------------------------------------------------------

func _glow_mat(col: Color, alpha: float) -> Material:
	var key := "glow|%s|%s" % [col, alpha]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	mats[key] = m
	return m


## Каркас стройки: стойки по углам, рамка сверху и сканирующая плита (meta "plate").
func _make_cage(parent: Node3D, xf: Transform3D, w: float, h: float, col: Color) -> Node3D:
	var cage := Node3D.new()
	cage.transform = xf
	parent.add_child(cage)
	var edge := _glow_mat(col, 0.85)
	for c in [Vector2(w, w), Vector2(-w, w), Vector2(w, -w), Vector2(-w, -w)]:
		var post := _box(cage, Vector3(0.05, h, 0.05), Vector3(c.x, h * 0.5, c.y), col)
		post.material_override = edge
	for k in [Vector3(0, h, w), Vector3(0, h, -w), Vector3(0, 0.02, w), Vector3(0, 0.02, -w)]:
		_box(cage, Vector3(w * 2.0, 0.05, 0.05), k, col).material_override = edge
	for k in [Vector3(w, h, 0), Vector3(-w, h, 0), Vector3(w, 0.02, 0), Vector3(-w, 0.02, 0)]:
		_box(cage, Vector3(0.05, 0.05, w * 2.0), k, col).material_override = edge
	var plate := _box(cage, Vector3(w * 2.0, 0.04, w * 2.0), Vector3.ZERO, col)
	plate.material_override = _glow_mat(col, 0.35)
	cage.set_meta("plate", plate)
	cage.set_meta("h", h)
	return cage


func _apply_build_vis(b: Dictionary) -> void:
	var root: Node3D = bnodes.get(b.id)
	if root == null or not root.has_meta("deco"):
		return
	var n: Node3D = root.get_meta("deco")
	var xf: Transform3D = root.get_meta("deco_xf")
	var busy := _busy(b)
	var p := clampf(_shown_bt(b), 0.0, 1.0) if busy else 1.0
	var ps := maxf(p, 0.03)
	n.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, ps, 1.0)), xf.origin)
	if root.has_meta("prism"):
		var pm: MeshInstance3D = root.get_meta("prism")
		var a: Vector3 = root.get_meta("anchor")
		var up := a.normalized()
		var k := ps - 1.0
		var bs := Basis(Vector3(1, 0, 0) + up * up.x * k, Vector3(0, 1, 0) + up * up.y * k,
			Vector3(0, 0, 1) + up * up.z * k)
		pm.transform = Transform3D(bs, a - bs * a)
	var cage: Node3D = root.get_meta("cage") if root.has_meta("cage") else null
	if not busy:
		if cage != null:
			cage.queue_free()
			root.remove_meta("cage")
		if root.has_meta("beam"):
			(root.get_meta("beam") as Node3D).queue_free()
			root.remove_meta("beam")
		return
	if cage == null:
		var col: Color = Color(1.0, 0.55, 0.15) if b.decon else D.TEAM_COLORS[b.team].lightened(0.3)
		cage = _make_cage(root, xf, 0.8, float(root.get_meta("deco_h")), col)
		root.set_meta("cage", cage)
	var plate: Node3D = cage.get_meta("plate")
	plate.position.y = float(cage.get_meta("h")) * p
	_update_beam(root, b, cage.transform * plate.position)


## Готовность для показа: клиент досчитывает сам, на хосте — сглаживаем между тиками.
func _shown_bt(b: Dictionary) -> float:
	var bt := float(b.bt)
	if is_server:
		var step: float = (tick_acc / D.TICK) * D.TICK / D.build_time(int(b.type))
		bt += -step if b.decon else step
	return bt


## Луч от руки строителя к сканирующей плите — мерцает, как сварка.
func _update_beam(root: Node3D, b: Dictionary, target: Vector3) -> void:
	var from = null
	var by: int = b.by
	if by != 0 and by == multiplayer.get_unique_id():
		if player != null and not player.dead and piloting == null:
			from = vm_hand.global_position if fps_mode and vm_hand != null else \
					player.global_position + player.global_position.normalized() * 1.2
	elif others.has(by):
		var o: Node3D = others[by]
		if o.visible:
			from = o.global_position + o.global_position.normalized() * 1.2
	if from == null or Vector3(from).distance_to(target) > 40.0:
		_laser_off(root, "beam")
		return
	var col: Color = Color(1.0, 0.55, 0.15) if b.decon else D.TEAM_COLORS[b.team].lightened(0.4)
	var jitter := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	_laser(root, "beam", from, target + jitter, col)


## Лазерный луч: яркая сердцевина + полупрозрачное свечение + искры в точке попадания.
## holder — узел в мировых координатах (без поворота), key — имя луча в его meta.
func _laser(holder: Node3D, key: String, from: Vector3, to: Vector3, col: Color) -> void:
	var ln: Node3D = holder.get_meta(key) if holder.has_meta(key) else null
	if ln == null:
		ln = Node3D.new()
		holder.add_child(ln)
		holder.set_meta(key, ln)
		var core := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.035, 0.035, 1.0)
		core.mesh = cm
		core.material_override = _mat(col.lerp(Color.WHITE, 0.6), true)
		ln.add_child(core)
		var glow := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.13, 0.13, 1.0)
		glow.mesh = gm
		glow.material_override = _glow_mat(col, 0.3)
		ln.add_child(glow)
		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 6
		sm.rings = 3
		spark.mesh = sm
		spark.material_override = _mat(col.lerp(Color.WHITE, 0.4), true)
		ln.add_child(spark)
		for k in 4:
			var bit := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.04, 0.04)
			bit.mesh = bm
			bit.material_override = _mat(Color(1.0, 0.85, 0.4), true)
			ln.add_child(bit)
	ln.visible = true
	var d := to - from
	var dist := maxf(d.length(), 0.01)
	var dir := d / dist
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var flick := randf_range(0.7, 1.3)
	var bas := Basis(side * flick, dir.cross(side) * flick, dir * dist)
	var mid := (from + to) * 0.5
	(ln.get_child(0) as Node3D).transform = Transform3D(bas, mid)
	(ln.get_child(1) as Node3D).transform = Transform3D(bas, mid)
	(ln.get_child(2) as Node3D).transform = Transform3D(Basis.from_scale(Vector3.ONE * randf_range(0.5, 1.4)), to)
	var up := to.normalized()
	for k in 4:
		var rnd := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		(ln.get_child(3 + k) as Node3D).position = to + (rnd + up) * randf_range(0.1, 0.45)


func _laser_off(holder: Node3D, key: String) -> void:
	if holder.has_meta(key):
		(holder.get_meta(key) as Node3D).visible = false


## Стройка/снос начались или закончились — пересобрать каркас.
func _on_build_state(b: Dictionary) -> void:
	if headless or b.pn != my_pn or not bnodes.has(b.id):
		return
	var root: Node3D = bnodes[b.id]
	if root.has_meta("cage"):
		(root.get_meta("cage") as Node3D).queue_free()
		root.remove_meta("cage")
	if root.has_meta("beam"):
		(root.get_meta("beam") as Node3D).queue_free()
		root.remove_meta("beam")
	_apply_build_vis(b)
	lamp_acc = 1.0


## Каждый кадр: идёт стройка/снос и сборка юнитов в сборщиках.
func _update_construction(delta: float) -> void:
	for id in building_set.keys():
		if not buildings.has(id):
			building_set.erase(id)
			continue
		var b: Dictionary = buildings[id]
		if not is_server:
			var step: float = delta / D.build_time(int(b.type))
			if b.decon:
				b.bt = maxf(float(b.bt) - step, 0.0)
			else:
				b.bt = minf(float(b.bt) + step, 0.999)   # готовность подтвердит сервер
		if b.pn == my_pn:
			_apply_build_vis(b)
	_update_assembly()


## Юнит собирается на площадке рядом со сборщиком: растёт снизу вверх в каркасе,
## робот-рука на крыше сборщика водит по нему лазером.
func _update_assembly() -> void:
	for id in asm_nodes.keys():
		var hv = asm_nodes[id]
		if not is_instance_valid(hv):
			asm_nodes.erase(id)
		elif not asm_prog.has(id) or not bnodes.has(id):
			(hv as Node3D).queue_free()
			asm_nodes.erase(id)
	var meshes := [mm_units.mesh, mm_drones.mesh, mm_mechs.mesh, mm_umechs.mesh]
	for id in asm_prog:
		if not bnodes.has(id) or not buildings.has(id):
			continue
		var b: Dictionary = buildings[id]
		var e: Array = asm_prog[id]
		var p := clampf(float(e[0]), 0.0, 1.0)
		var kind := clampi(int(e[1]), 0, 3)
		var root: Node3D = bnodes[id]
		var holder: Node3D = asm_nodes.get(id)
		if holder != null and int(holder.get_meta("kind")) != kind:
			holder.queue_free()
			holder = null
		if holder == null:
			var bay := _bay_cell(b)
			var up: Vector3 = planet.dirs[bay]
			var away := planet.top_pos(bay) - _foot_center(b.cells, int(b.pn))
			away = (away - up * away.dot(up)).normalized()
			holder = Node3D.new()
			holder.transform = Transform3D(Basis(up.cross(-away), up, -away).orthonormalized(), planet.top_pos(bay))
			holder.set_meta("kind", kind)
			root.add_child(holder)
			# площадка сборки: плита с разметкой
			_cyl(holder, 0.85, 0.06, Vector3(0, 0.03, 0), Color(0.3, 0.3, 0.33), 6)
			_cyl(holder, 0.9, 0.03, Vector3(0, 0.07, 0), Color(0.9, 0.75, 0.15), 6)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.instance_count = 1
			mm.mesh = meshes[kind]
			var col: Color = D.TEAM_COLORS[b.team]
			mm.set_instance_custom_data(0, Color(col.r, col.g, col.b, 0.49))   # стоит, целый
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			holder.add_child(mmi)
			holder.set_meta("mm", mm)
			var ch := 2.8 if kind >= D.U_MECH else 1.1
			var cw := 2.4 if kind >= D.U_MECH else 0.7
			var cage := _make_cage(holder, Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), cw, ch,
				D.TEAM_COLORS[b.team].lightened(0.3))
			holder.set_meta("cage", cage)
			asm_nodes[id] = holder
		var mmh: MultiMesh = holder.get_meta("mm")
		var lift := D.DRONE_ALT * 0.5 if kind == D.U_DRONE else 0.0
		mmh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(1.0, maxf(p, 0.03), 1.0)),
			Vector3(0, 0.08 + lift * p, 0)))
		var cg: Node3D = holder.get_meta("cage")
		var plate: Node3D = cg.get_meta("plate")
		plate.position.y = float(cg.get_meta("h")) * p
	_update_anim()


## Деталь декора по описанию из _anim. Скорость зависит от того, работает ли постройка.
func _run_anim(n: Node3D, b: Dictionary, id: int) -> void:
	var dt := get_process_delta_time()
	var st: int = bstate.get(id, ST_OK)
	var act: float = 0.0 if _busy(b) else [0.0, 1.0, 0.5, 0.0][clampi(st, 0, 3)]
	for spec in n.get_meta("anim"):
		var node: Node3D = spec.n
		if not is_instance_valid(node):
			continue
		var a: float = 1.0 if (bool(spec.always) and not _busy(b)) else act
		var v: float = spec.v
		var w: float = spec.w
		var base: Vector3 = spec.base
		spec.ph = float(spec.ph) + dt * w * TAU * a
		var ph: float = spec.ph
		match String(spec.k):
			"spin":
				var r := node.rotation
				if spec.ax == "x":
					r.x += dt * v * a
				elif spec.ax == "z":
					r.z += dt * v * a
				else:
					r.y += dt * v * a
				node.rotation = r
			"bob":
				node.position = base + Vector3(0, sin(ph) * v, 0)
			"slide":
				node.position = base + Vector3(0, 0, sin(ph) * v)
			"swing":
				node.rotation = base + Vector3(0, sin(ph) * v, 0)
			"pulse":
				node.scale = base * (1.0 + v * sin(ph))
			"blink":
				node.visible = a > 0.0 and fmod(ph / TAU, 1.0) < 0.55
			"burn":
				node.visible = st == ST_SLOW
				node.scale = Vector3.ONE * (1.0 + v * sin(ph))
			"charge":
				# деления заряда: заряжается — бегут снизу вверх, отдаёт — мигают, пусто — гаснут
				var lvl := int(v)
				if st == ST_IDLE or _busy(b):
					node.visible = false
				elif st == ST_SLOW:
					node.visible = fmod(ph / TAU * 2.0, 1.0) < 0.6
				else:
					node.visible = int(fmod(ph / TAU * 1.5, 1.0) * 5.0) >= lvl
			"smoke":
				node.visible = a > 0.0
				var cnt := node.get_child_count()
				for i in cnt:
					var puff: Node3D = node.get_child(i)
					var k := fmod(ph / TAU + float(i) / cnt, 1.0)
					puff.position = Vector3(sin(k * 5.0 + i) * 0.12, k * v, cos(k * 4.0 + i) * 0.12)
					puff.scale = Vector3.ONE * (0.5 + k * 1.3) * (1.0 - k * 0.6)
			"sun":
				var sun: Vector3 = sky_state.get("sun", Vector3.ZERO)
				var par := node.get_parent() as Node3D
				var up := par.global_transform.basis.y.normalized()
				var tgt := up
				if sun.dot(up) > 0.05:
					tgt = (up * 0.35 + sun.normalized()).normalized()
				var lt := (par.global_transform.basis.inverse() * tgt).normalized()
				var cur := node.transform.basis.y.normalized()
				var nt := cur.slerp(lt, minf(1.0, dt * 2.0)).normalized()
				var x := Vector3.RIGHT - nt * nt.x
				if x.length() < 0.01:
					x = Vector3.FORWARD
				x = x.normalized()
				node.transform = Transform3D(Basis(x, nt, x.cross(nt)), node.position)


## Анимации построек: рука сборщика (работает — лазер по собираемому юниту), вертушка разветвителя.
func _update_anim() -> void:
	var tm := Time.get_ticks_msec() / 1000.0
	for id in anim_nodes.keys():
		var rv = anim_nodes[id]
		if not is_instance_valid(rv) or not buildings.has(id):
			anim_nodes.erase(id)
			continue
		var root: Node3D = rv
		var n: Node3D = root.get_meta("deco")
		var b: Dictionary = buildings[id]
		if n.has_meta("anim"):
			_run_anim(n, b, id)
		if n.has_meta("spin"):
			var busy_spin: bool = not _busy(b) and int(b.item) != D.I_NONE
			(n.get_meta("spin") as Node3D).rotation.y = tm * (6.0 if busy_spin else 1.5)
			continue
		if not n.has_meta("arm"):
			continue
		var arm: Array = n.get_meta("arm")
		var yaw: Node3D = arm[0]
		var sh: Node3D = arm[1]
		var el: Node3D = arm[2]
		var tip: Node3D = arm[3]
		var working := asm_prog.has(id) and asm_nodes.has(id) and not _busy(b)
		var ph := float(id) * 1.7
		if working:
			var holder: Node3D = asm_nodes[id]
			var e: Array = asm_prog[id]
			var p := clampf(float(e[0]), 0.0, 1.0)
			var cg: Node3D = holder.get_meta("cage")
			var hgt: float = float(cg.get_meta("h")) * p
			# куда тянуться: на площадку, в текущую высоту сборки
			var aim := holder.global_transform * Vector3(sin(tm * 2.3 + ph) * 0.35, 0.1 + hgt, cos(tm * 1.7 + ph) * 0.35)
			var lv := n.global_transform.affine_inverse() * aim - yaw.position
			yaw.rotation.y = lerp_angle(yaw.rotation.y, atan2(-lv.z, lv.x), 0.2)
			sh.rotation.z = 0.35 + 0.15 * sin(tm * 3.1 + ph)
			el.rotation.z = -0.9 + 0.2 * sin(tm * 2.2 + ph)
			_laser(root, "arm_laser", tip.global_position, aim, Color(1.0, 0.3, 0.2))
		else:
			yaw.rotation.y = lerp_angle(yaw.rotation.y, 0.6 * sin(tm * 0.4 + ph), 0.05)
			sh.rotation.z = 0.9 + 0.08 * sin(tm * 0.7 + ph)
			el.rotation.z = -1.7 + 0.08 * sin(tm * 0.9 + ph)
			_laser_off(root, "arm_laser")


## Добавить анимацию детали декора. kind: spin (вращение по оси ax), bob (вверх-вниз), slide (вперёд-назад),
## pulse (дышит размером), blink (мигает), swing (качается по Y), sun (панель за солнцем), smoke (дым).
## v — скорость/размах, w — частота; always — анимировать даже когда постройка простаивает.
func _anim(n: Node3D, node: Node3D, kind: String, v: float, w := 1.0, always := false, ax := "y") -> void:
	var list: Array = n.get_meta("anim") if n.has_meta("anim") else []
	var base: Vector3 = node.rotation
	if kind == "bob" or kind == "slide" or kind == "smoke":
		base = node.position
	elif kind == "pulse":
		base = node.scale
	list.append({"n": node, "k": kind, "v": v, "w": w, "always": always, "ax": ax, "base": base,
		"ph": randf() * TAU})
	n.set_meta("anim", list)


## Брус между двумя точками (в координатах parent).
func _beam(parent: Node3D, a: Vector3, b: Vector3, th: float, col: Color) -> MeshInstance3D:
	var m := _box(parent, Vector3(th, th, maxf(a.distance_to(b), 0.01)), (a + b) * 0.5, col)
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	m.transform = Transform3D(Basis(side, dir.cross(side), dir), (a + b) * 0.5)
	return m


## Буровая штанга с коронкой: узел, внизу которого — конус бура (вращать и двигать узел целиком).
func _drill_bit(n: Node3D, length: float, r: float, col: Color) -> Node3D:
	var bit := Node3D.new()
	n.add_child(bit)
	_cyl(bit, r, length, Vector3(0, length * 0.5 + 0.2, 0), Color(0.5, 0.5, 0.55), 6)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 2.4
	cm.bottom_radius = 0.01
	cm.height = 0.32
	cm.radial_segments = 6
	cone.mesh = cm
	cone.position = Vector3(0, 0.1, 0)
	cone.material_override = _pmat(col, 1)
	bit.add_child(cone)
	for k in 3:
		var a := TAU * k / 3.0
		_box(bit, Vector3(0.05, 0.25, 0.05), Vector3(cos(a) * r * 1.6, 0.2, sin(a) * r * 1.6), col.darkened(0.3))
	return bit


## Кучка выбранной породы у бура.
func _debris(n: Node3D, r: float) -> void:
	for k in 5:
		var a := TAU * k / 5.0 + 0.4
		var sz := 0.08 + 0.05 * (k % 3)
		var rock := _box(n, Vector3(sz, sz, sz), Vector3(cos(a) * r, sz * 0.5, sin(a) * r), Color(0.35, 0.32, 0.3))
		rock.rotation = Vector3(0, a, 0)


## Дым из трубы: несколько клубов, поднимаются и тают.
func _smoke(n: Node3D, at: Vector3, col: Color) -> void:
	var sm := Node3D.new()
	sm.position = at
	n.add_child(sm)
	for k in 5:
		var puff := _box(sm, Vector3(0.22, 0.22, 0.22), Vector3.ZERO, col)
		puff.material_override = _glow_mat(col, 0.45)
	_anim(n, sm, "smoke", 1.2, 0.6)


## 4 тир: инопланетный стиль — тёмно-фиолетовый металл, синие светящиеся полосы, парящий кристалл материи.
func _vis_tier4(n: Node3D, t: int, col: Color) -> void:
	var hull := Color(0.2, 0.15, 0.3)
	var hull2 := Color(0.3, 0.24, 0.42)
	var blue := Color(0.35, 0.65, 1.0)
	if t == D.TURRET4:
		_cyl(n, 0.75, 0.45, Vector3(0, 0.22, 0), hull, 8).material_override = _pmat(hull, 1)
		_cyl(n, 0.78, 0.04, Vector3(0, 0.4, 0), blue, 8).material_override = _mat(blue, true)
		var pitch := _turret_head(n, Vector3(0, 0.75, 0), Vector3(0.1, 0.25, 0))
		var head: Node3D = n.get_meta("head")
		_box(head, Vector3(0.8, 0.5, 0.75), Vector3.ZERO, hull2).material_override = _pmat(hull2, 1)
		_box(head, Vector3(0.82, 0.05, 0.77), Vector3(0, 0.12, 0), blue, true)
		for sz in [-0.22, 0.22]:
			_box(pitch, Vector3(1.0, 0.24, 0.24), Vector3(0.45, 0, sz), hull)   # ракетные блоки
			for k in 3:
				_box(pitch, Vector3(0.05, 0.06, 0.06), Vector3(0.96, -0.06 + 0.06 * k, sz), blue, true)
		pitch.rotation_degrees = Vector3(0, 0, 30)
		return
	# завод: корпус с синими поясами, сверху — кольцо и парящий кристалл материи
	_box(n, Vector3(1.35, 0.9, 1.1), Vector3(0, 0.45, 0), hull).material_override = _pmat(hull, 1)
	for y in [0.25, 0.6]:
		_box(n, Vector3(1.37, 0.05, 1.12), Vector3(0, y, 0), blue, true)
	var ring := Node3D.new()
	ring.position = Vector3(0, 1.25, 0)
	n.add_child(ring)
	for k in 6:
		var a := TAU * k / 6.0
		_box(ring, Vector3(0.12, 0.08, 0.12), Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), blue, true)
	_anim(n, ring, "spin", 1.6)
	var crys := Node3D.new()
	crys.position = Vector3(0, 1.3, 0)
	n.add_child(crys)
	var cc := Color(0.4, 0.95, 1.0)
	if t == D.UCHIP_FAB:
		cc = Color(0.45, 0.8, 1.0)
	elif t == D.UFUEL_REF:
		cc = Color(0.55, 0.6, 1.0)
	_box(crys, Vector3(0.28, 0.42, 0.28), Vector3.ZERO, cc, true).rotation = Vector3(0.6, 0, 0.6)
	_anim(n, crys, "spin", 2.2)
	_anim(n, crys, "bob", 0.12, 1.5)
	_anim(n, crys, "pulse", 0.15, 3.0)
	if t == D.UCHIP_FAB:
		for i in 3:
			for j in 2:
				var sq := _box(n, Vector3(0.18, 0.03, 0.18), Vector3(-0.35 + 0.35 * i, 0.91, -0.2 + 0.4 * j), blue, true)
				_anim(n, sq, "blink", 1.0, 1.0 + 0.3 * i + 0.2 * j)
	elif t == D.UFUEL_REF:
		for sx in [-0.45, 0.45]:
			_cyl(n, 0.2, 1.4, Vector3(sx, 0.7, 0.35), hull2, 10).material_override = _pmat(hull2, 1)
			_cyl(n, 0.21, 0.05, Vector3(sx, 1.2, 0.35), blue, 10).material_override = _mat(blue, true)
	else:
		var melt := _box(n, Vector3(0.5, 0.12, 0.5), Vector3(0.3, 0.95, -0.2), Color(0.4, 0.75, 1.0), true)
		_anim(n, melt, "pulse", 0.12, 2.5)


## Поворотная часть турели: head крутится вокруг вертикали, pitch внутри неё поднимает ствол.
## Ствол строится вдоль локальной +X внутри pitch. Возвращает pitch.
func _turret_head(n: Node3D, head_pos: Vector3, pitch_pos: Vector3) -> Node3D:
	var head := Node3D.new()
	head.position = head_pos
	n.add_child(head)
	var pitch := Node3D.new()
	pitch.position = pitch_pos
	head.add_child(pitch)
	n.set_meta("head", head)
	n.set_meta("pitch", pitch)
	return pitch


## Простые формы построек. Светящиеся детали видны и в полной темноте.
func _vis_shape(n: Node3D, t: int, col: Color) -> void:
	var dark := col.darkened(0.45)
	var metal := Color(0.6, 0.6, 0.65)
	if LINK_TYPES.has(t):
		pass   # форма зависит от соседей — строит _vis_links
	elif t == D.DRILL:
		# бур I — тренога: три ноги, лебёдка на вершине, вращающийся бур ходит вверх-вниз
		var wood := Color(0.55, 0.42, 0.28)
		var apex := Vector3(0, 1.75, 0)
		for k in 3:
			var a := TAU * k / 3.0 + 0.3
			_beam(n, Vector3(cos(a) * 0.7, 0.0, sin(a) * 0.7), apex, 0.09, wood)
		_box(n, Vector3(0.36, 0.26, 0.3), apex + Vector3(0, 0.05, 0), dark).material_override = _pmat(dark, 1)
		var wheel := Node3D.new()
		wheel.position = apex + Vector3(0, 0.05, 0.2)
		n.add_child(wheel)
		_box(wheel, Vector3(0.36, 0.06, 0.04), Vector3.ZERO, Color(0.8, 0.55, 0.25))
		_box(wheel, Vector3(0.06, 0.36, 0.04), Vector3.ZERO, Color(0.8, 0.55, 0.25))
		_anim(n, wheel, "spin", 5.0, 1.0, false, "z")
		var bit := _drill_bit(n, 1.25, 0.07, Color(0.85, 0.6, 0.3))
		bit.position = Vector3(0, 0.25, 0)
		_anim(n, bit, "spin", 9.0)
		_anim(n, bit, "bob", 0.15, 3.0)
		_debris(n, 0.45)
	elif t == D.DRILL2:
		# бур II — на сваях: платформа на четырёх опорах, мотор с приводом, вал уходит в грунт
		for c in [Vector2(0.55, 0.55), Vector2(-0.55, 0.55), Vector2(0.55, -0.55), Vector2(-0.55, -0.55)]:
			_cyl(n, 0.07, 1.0, Vector3(c.x, 0.5, c.y), Color(0.35, 0.36, 0.4), 6)
			_beam(n, Vector3(c.x, 0.1, c.y), Vector3(c.x * 0.2, 0.9, c.y * 0.2), 0.04, Color(0.35, 0.36, 0.4))
		_box(n, Vector3(1.35, 0.1, 1.35), Vector3(0, 1.0, 0), dark).material_override = _pmat(dark, 1)
		for c in [Vector3(0, 1.17, 0.66), Vector3(0, 1.17, -0.66)]:
			_box(n, Vector3(1.35, 0.04, 0.04), c, Color(0.9, 0.75, 0.15))   # перила
		_box(n, Vector3(0.6, 0.5, 0.55), Vector3(0.25, 1.3, 0), metal).material_override = _pmat(metal, 1)
		var drive := Node3D.new()
		drive.position = Vector3(0.25, 1.3, 0.3)
		n.add_child(drive)
		for k in 3:
			var sp := _box(drive, Vector3(0.44, 0.06, 0.05), Vector3.ZERO, Color(0.25, 0.25, 0.28))
			sp.rotation.z = PI * k / 3.0
		_anim(n, drive, "spin", 7.0, 1.0, false, "z")
		var bit := _drill_bit(n, 1.1, 0.09, metal)
		bit.position = Vector3(-0.25, 0.05, 0)
		_anim(n, bit, "spin", 12.0)
		_anim(n, bit, "bob", 0.08, 5.0)
		var lamp := _box(n, Vector3(0.18, 0.12, 0.18), Vector3(0.25, 1.62, 0), Color(1.0, 0.9, 0.3), true)
		_anim(n, lamp, "blink", 1.0, 1.5)
		_debris(n, 0.6)
	elif t == D.DRILL3:
		# бур III — буровая вышка: решётчатая башня, талевый блок ходит вверх-вниз, ротор крутит трубу
		var steel := Color(0.75, 0.3, 0.2)
		_box(n, Vector3(1.45, 0.16, 1.45), Vector3(0, 0.08, 0), dark).material_override = _pmat(dark, 1)
		var top := 2.8
		var bw := 0.6
		var tw := 0.13
		var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		for c in corners:
			_beam(n, Vector3(c.x * bw, 0.16, c.y * bw), Vector3(c.x * tw, top, c.y * tw), 0.06, steel)
		for lv in 5:
			var y0 := 0.16 + (top - 0.16) * lv / 5.0
			var y1 := 0.16 + (top - 0.16) * (lv + 1) / 5.0
			var w0 := lerpf(bw, tw, float(lv) / 5.0)
			var w1 := lerpf(bw, tw, float(lv + 1) / 5.0)
			for k in 4:
				var c0: Vector2 = corners[k]
				var c1: Vector2 = corners[(k + 1) % 4]
				_beam(n, Vector3(c0.x * w0, y0, c0.y * w0), Vector3(c1.x * w1, y1, c1.y * w1), 0.025, steel)
				_beam(n, Vector3(c0.x * w1, y1, c0.y * w1), Vector3(c1.x * w1, y1, c1.y * w1), 0.025, steel)
		_box(n, Vector3(0.36, 0.14, 0.36), Vector3(0, top + 0.07, 0), Color(0.3, 0.3, 0.33))   # кронблок
		var block := Node3D.new()
		block.position = Vector3(0, 1.7, 0)
		n.add_child(block)
		_box(block, Vector3(0.18, 0.24, 0.14), Vector3.ZERO, Color(0.95, 0.75, 0.15))
		_box(block, Vector3(0.02, 2.0, 0.02), Vector3(-0.05, 1.1, 0), Color(0.15, 0.15, 0.15))   # тросы
		_box(block, Vector3(0.02, 2.0, 0.02), Vector3(0.05, 1.1, 0), Color(0.15, 0.15, 0.15))
		_anim(n, block, "bob", 0.6, 1.2)
		var pipe := Node3D.new()
		pipe.position = Vector3(0, 0.16, 0)
		n.add_child(pipe)
		_cyl(pipe, 0.045, 1.4, Vector3(0, 0.7, 0), Color(0.55, 0.56, 0.6), 6)
		_box(pipe, Vector3(0.34, 0.08, 0.08), Vector3(0, 0.12, 0), Color(0.2, 0.2, 0.22))   # ротор
		_anim(n, pipe, "spin", 6.0)
		_box(n, Vector3(0.45, 0.4, 0.35), Vector3(0.45, 0.36, -0.45), Color(0.85, 0.85, 0.8))   # будка бурильщика
		_cyl(n, 0.2, 0.55, Vector3(-0.45, 0.43, 0.45), Color(0.25, 0.55, 1.0))   # бак воды
		var beacon := _box(n, Vector3(0.1, 0.1, 0.1), Vector3(0, top + 0.2, 0), Color(1.0, 0.2, 0.15), true)
		_anim(n, beacon, "blink", 1.0, 1.0, true)
	elif t == D.SOLAR:
		_cyl(n, 0.08, 0.6, Vector3(0, 0.3, 0), metal)
		var panel := Node3D.new()
		panel.position = Vector3(0, 0.65, 0)
		n.add_child(panel)
		_box(panel, Vector3(1.5, 0.06, 1.5), Vector3.ZERO, Color(0.12, 0.18, 0.4)).material_override = \
				_pmat(Color(0.14, 0.2, 0.45), 1)
		_box(panel, Vector3(1.54, 0.04, 0.05), Vector3(0, 0.01, 0), metal)
		_anim(n, panel, "sun", 1.0, 1.0, true)   # панель поворачивается за солнцем
	elif t == D.COAL_PLANT:
		_box(n, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.5, 0), Color(0.3, 0.28, 0.27)).material_override = \
				_pmat(Color(0.3, 0.28, 0.27), 1)
		_cyl(n, 0.22, 1.4, Vector3(0.35, 1.7, 0.35), Color(0.4, 0.38, 0.36))
		var fire := _box(n, Vector3(0.5, 0.2, 0.1), Vector3(0, 0.5, 0.71), Color(1.0, 0.45, 0.15), true)
		_anim(n, fire, "pulse", 0.25, 9.0)
		_smoke(n, Vector3(0.35, 2.4, 0.35), Color(0.35, 0.33, 0.32))
	elif t == D.NUCLEAR:
		_cyl(n, 0.85, 1.8, Vector3(0, 0.9, 0), Color(0.75, 0.75, 0.72), 6).material_override = \
				_pmat(Color(0.75, 0.75, 0.72), 1)
		_cyl(n, 0.4, 0.15, Vector3(0, 1.85, 0), Color(0.4, 1.0, 0.3))
		var core := _box(n, Vector3(0.3, 0.3, 0.3), Vector3(0, 2.05, 0), Color(0.4, 1.0, 0.3), true)
		_anim(n, core, "spin", 1.5)
		_anim(n, core, "pulse", 0.2, 4.0)
		var ring := Node3D.new()
		ring.position = Vector3(0, 1.2, 0)
		n.add_child(ring)
		for k in 6:
			var a := TAU * k / 6.0
			var pod := _box(ring, Vector3(0.12, 0.12, 0.12), Vector3(cos(a) * 0.9, 0, sin(a) * 0.9), Color(0.4, 1.0, 0.3), true)
			pod.rotation.y = -a
		_anim(n, ring, "spin", 0.8)
		_smoke(n, Vector3(0, 2.3, 0), Color(0.85, 0.88, 0.9))   # пар охлаждения
	elif t == D.SMELTER:
		_box(n, Vector3(1.3, 1.0, 1.3), Vector3(0, 0.5, 0), Color(0.35, 0.3, 0.28)).material_override = \
				_pmat(Color(0.35, 0.3, 0.28), 1)
		var melt := _box(n, Vector3(0.7, 0.2, 0.7), Vector3(0, 1.1, 0), Color(1.0, 0.5, 0.15), true)
		_anim(n, melt, "pulse", 0.12, 3.0)
		_cyl(n, 0.12, 0.6, Vector3(-0.45, 1.3, -0.45), Color(0.3, 0.28, 0.27))
		_smoke(n, Vector3(-0.45, 1.6, -0.45), Color(0.4, 0.36, 0.33))
	elif t == D.CRUSHER:
		_box(n, Vector3(1.3, 0.8, 1.3), Vector3(0, 0.4, 0), Color(0.4, 0.4, 0.42)).material_override = \
				_pmat(Color(0.4, 0.4, 0.42), 1)
		for sx in [0.3, -0.3]:
			var roll := Node3D.new()
			roll.position = Vector3(sx, 0.95, 0)
			n.add_child(roll)
			_cyl(roll, 0.28, 0.9, Vector3.ZERO, metal, 8).rotation = Vector3(PI / 2.0, 0, 0)
			for k in 4:
				var tooth := _box(roll, Vector3(0.62, 0.08, 0.9), Vector3.ZERO, Color(0.35, 0.35, 0.38))
				tooth.rotation.z = PI * k / 4.0
			_anim(n, roll, "spin", 6.0 if sx > 0.0 else -6.0, 1.0, false, "z")
	elif t == D.MELTER:
		_cyl(n, 0.6, 1.0, Vector3(0, 0.5, 0), Color(0.45, 0.5, 0.55)).material_override = _pmat(Color(0.45, 0.5, 0.55), 1)
		_cyl(n, 0.4, 0.15, Vector3(0, 1.05, 0), Color(0.5, 0.8, 1.0))
		for k in 3:
			var bub := _box(n, Vector3(0.12, 0.12, 0.12), Vector3(-0.15 + 0.15 * k, 1.15, 0.1 * (k - 1)),
				Color(0.6, 0.85, 1.0), true)
			_anim(n, bub, "bob", 0.12, 4.0 + k)
		_smoke(n, Vector3(0, 1.3, 0), Color(0.85, 0.9, 1.0))   # пар
	elif t == D.CENTRIFUGE:
		_cyl(n, 0.55, 0.5, Vector3(0, 0.25, 0), Color(0.5, 0.55, 0.5))
		var rotor := Node3D.new()
		rotor.position = Vector3(0, 0.95, 0)
		n.add_child(rotor)
		_cyl(rotor, 0.12, 0.9, Vector3.ZERO, Color(0.4, 0.42, 0.4))
		for k in 4:
			var a := TAU * k / 4.0
			_cyl(rotor, 0.12, 0.7, Vector3(cos(a) * 0.38, 0, sin(a) * 0.38), Color(0.55, 0.6, 0.55))
			_box(rotor, Vector3(0.1, 0.1, 0.1), Vector3(cos(a) * 0.38, 0.4, sin(a) * 0.38), Color(0.45, 1.0, 0.3), true)
		_anim(n, rotor, "spin", 14.0)
		_box(n, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.55, 0), Color(0.45, 1.0, 0.3), true)
	elif t == D.FUEL_SYNTH:
		_box(n, Vector3(1.3, 1.0, 1.3), Vector3(0, 0.5, 0), Color(0.3, 0.25, 0.4)).material_override = \
				_pmat(Color(0.3, 0.25, 0.4), 1)
		for c in [Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]:
			_cyl(n, 0.05, 0.6, Vector3(c.x, 1.3, c.y), Color(0.6, 0.6, 0.65), 6)
		var orb := Node3D.new()
		orb.position = Vector3(0, 1.4, 0)
		n.add_child(orb)
		_box(orb, Vector3(0.4, 0.4, 0.4), Vector3.ZERO, Color(0.85, 0.45, 1.0), true).rotation = Vector3(0.6, 0, 0.6)
		_anim(n, orb, "spin", 2.5)
		_anim(n, orb, "bob", 0.1, 2.0)
		_anim(n, orb, "pulse", 0.15, 5.0)
	elif t == D.LAUNCH_PAD:
		_box(n, Vector3(1.5, 0.08, 1.5), Vector3(0, 0.04, 0), Color(0.3, 0.3, 0.33)).material_override = \
				_pmat(Color(0.3, 0.3, 0.33), 1)
		_box(n, Vector3(1.1, 0.09, 0.08), Vector3(0, 0.05, 0), Color(0.9, 0.75, 0.15))
		_box(n, Vector3(0.08, 0.09, 1.1), Vector3(0, 0.05, 0), Color(0.9, 0.75, 0.15))
		_box(n, Vector3(0.1, 2.2, 0.1), Vector3(0.62, 1.1, 0.62), Color(0.75, 0.35, 0.15))   # башня обслуживания
		var boom := Node3D.new()
		boom.position = Vector3(0.62, 1.7, 0.62)
		n.add_child(boom)
		_box(boom, Vector3(0.45, 0.06, 0.06), Vector3(-0.22, 0, 0), Color(0.75, 0.35, 0.15))
		_anim(n, boom, "swing", 0.5, 0.5)
		for c in [Vector3(0.7, 0.1, -0.7), Vector3(-0.7, 0.1, 0.7), Vector3(-0.7, 0.1, -0.7)]:
			var lt := _box(n, Vector3(0.06, 0.06, 0.06), c, Color(1.0, 0.3, 0.2), true)   # огни
			_anim(n, lt, "blink", 1.0, 1.2, true)
	elif t == D.LOADER:
		_box(n, Vector3(1.45, 0.15, 1.45), Vector3(0, 0.08, 0), Color(0.85, 0.7, 0.15))
		_box(n, Vector3(1.0, 0.5, 1.0), Vector3(0, 0.4, 0), Color(0.35, 0.36, 0.4)).material_override = \
				_pmat(Color(0.35, 0.36, 0.4), 1)
		_box(n, Vector3(0.12, 1.2, 0.12), Vector3(0.55, 0.6, 0.55), Color(0.85, 0.7, 0.15))
		var crane := Node3D.new()
		crane.position = Vector3(0.55, 1.2, 0.55)
		n.add_child(crane)
		_box(crane, Vector3(0.9, 0.12, 0.12), Vector3(-0.4, 0, 0), Color(0.85, 0.7, 0.15))
		var hook := Node3D.new()
		hook.position = Vector3(-0.75, -0.25, 0)
		crane.add_child(hook)
		_box(hook, Vector3(0.02, 0.4, 0.02), Vector3(0, 0.05, 0), Color(0.15, 0.15, 0.15))
		_box(hook, Vector3(0.2, 0.14, 0.2), Vector3(0, -0.18, 0), Color(0.6, 0.45, 0.25))   # ящик на крюке
		_anim(n, crane, "swing", 0.9, 0.6)
		_anim(n, hook, "bob", 0.12, 1.2)
		_box(n, Vector3(0.3, 0.12, 0.12), Vector3(0, 0.66, -0.51), Color(1.0, 0.85, 0.2), true)
	elif t == D.UALLOY_FORGE or t == D.UCHIP_FAB or t == D.UFUEL_REF or t == D.TURRET4:
		_vis_tier4(n, t, col)
	elif t == D.SPACE_DOCK:
		# космопорт: посадочный круг, башня с огнём, бак топлива, ящики груза
		_cyl(n, 0.78, 0.12, Vector3(0, 0.06, 0), Color(0.3, 0.3, 0.34), 8).material_override = _pmat(Color(0.3, 0.3, 0.34), 1)
		_cyl(n, 0.6, 0.02, Vector3(0, 0.13, 0), Color(0.9, 0.75, 0.15), 8)
		_cyl(n, 0.5, 0.03, Vector3(0, 0.14, 0), Color(0.3, 0.3, 0.34), 8)
		_box(n, Vector3(0.1, 1.3, 0.1), Vector3(-0.62, 0.65, -0.62), Color(0.75, 0.35, 0.15))
		var bcn := _box(n, Vector3(0.12, 0.12, 0.12), Vector3(-0.62, 1.35, -0.62), Color(0.4, 0.8, 1.0), true)
		_anim(n, bcn, "blink", 1.0, 1.0, true)
		_cyl(n, 0.16, 0.5, Vector3(0.62, 0.3, -0.55), Color(0.75, 0.4, 1.0), 8)   # бак топлива
		for c in [Vector3(0.6, 0.12, 0.55), Vector3(0.38, 0.12, 0.62), Vector3(0.6, 0.32, 0.55)]:
			_box(n, Vector3(0.2, 0.18, 0.2), c, Color(0.6, 0.45, 0.25))
	elif t == D.FUEL_DEPOT:
		# заправочная станция: бак He-3, колонка со шлангом
		_box(n, Vector3(1.45, 0.15, 1.45), Vector3(0, 0.08, 0), Color(0.55, 0.3, 0.75))
		_cyl(n, 0.45, 1.2, Vector3(-0.2, 0.75, 0.15), Color(0.6, 0.6, 0.65), 12).material_override = \
				_pmat(Color(0.6, 0.6, 0.65), 1)
		_cyl(n, 0.47, 0.1, Vector3(-0.2, 1.0, 0.15), Color(0.75, 0.4, 1.0), 12)
		_box(n, Vector3(0.25, 0.8, 0.25), Vector3(0.5, 0.55, -0.4), Color(0.85, 0.85, 0.8))
		var glow := _box(n, Vector3(0.18, 0.12, 0.05), Vector3(0.5, 0.8, -0.53), Color(0.85, 0.45, 1.0), true)
		_anim(n, glow, "blink", 1.0, 0.8)
	elif t == D.UNLOADER:
		_box(n, Vector3(1.45, 0.15, 1.45), Vector3(0, 0.08, 0), Color(0.2, 0.45, 0.8))
		_box(n, Vector3(0.9, 0.6, 0.9), Vector3(0, 0.45, 0), Color(0.4, 0.42, 0.46)).material_override = \
				_pmat(Color(0.4, 0.42, 0.46), 1)
		var lift := Node3D.new()
		lift.position = Vector3(0, 0.85, 0)
		n.add_child(lift)
		_box(lift, Vector3(0.7, 0.06, 0.7), Vector3.ZERO, Color(0.85, 0.7, 0.15))
		_box(lift, Vector3(0.3, 0.25, 0.3), Vector3(0, 0.15, 0), Color(0.6, 0.45, 0.25))
		_anim(n, lift, "bob", 0.15, 1.0)
		_box(n, Vector3(0.3, 0.12, 0.12), Vector3(0, 0.6, -0.46), Color(0.3, 0.7, 1.0), true)
	elif t == D.CHIP_FACTORY:
		_box(n, Vector3(1.3, 0.9, 1.3), Vector3(0, 0.45, 0), Color(0.15, 0.32, 0.2)).material_override = \
				_pmat(Color(0.15, 0.32, 0.2), 1)
		_box(n, Vector3(0.7, 0.06, 0.7), Vector3(0, 0.93, 0), Color(0.1, 0.2, 0.12))
		var scan := _box(n, Vector3(0.7, 0.05, 0.08), Vector3(0, 0.98, 0), Color(0.3, 1.0, 0.45), true)
		_anim(n, scan, "slide", 0.3, 2.0)   # сканирующая полоса над кристаллом
		var head := Node3D.new()
		head.position = Vector3(0.45, 1.05, 0.45)
		n.add_child(head)
		_box(head, Vector3(0.12, 0.3, 0.12), Vector3.ZERO, Color(0.95, 0.8, 0.3))
		_anim(n, head, "bob", 0.08, 6.0)
	elif t == D.ASSEMBLER:
		# цех: корпус с полосами, на крыше — робот-рука с лазером (поворот, плечо, локоть, излучатель)
		_box(n, Vector3(1.35, 0.75, 1.35), Vector3(0, 0.375, 0), col.darkened(0.3)).material_override = \
				_pmat(col.darkened(0.3), 1)
		_box(n, Vector3(1.4, 0.08, 1.4), Vector3(0, 0.79, 0), Color(0.85, 0.7, 0.15))
		for sx in [-0.45, 0.45]:
			_box(n, Vector3(0.2, 0.06, 1.37), Vector3(sx, 0.5, 0), Color(0.15, 0.15, 0.17))
		var yaw := Node3D.new()
		yaw.position = Vector3(-0.2, 0.83, 0)
		n.add_child(yaw)
		_cyl(yaw, 0.26, 0.2, Vector3(0, 0.1, 0), Color(0.55, 0.56, 0.6), 10).material_override = \
				_pmat(Color(0.55, 0.56, 0.6), 1)
		var sh := Node3D.new()
		sh.position = Vector3(0, 0.28, 0)
		yaw.add_child(sh)
		_box(sh, Vector3(0.24, 0.24, 0.3), Vector3.ZERO, Color(0.9, 0.6, 0.15))   # плечевой сустав
		_box(sh, Vector3(0.75, 0.14, 0.16), Vector3(0.37, 0, 0), Color(0.92, 0.65, 0.18)).material_override = \
				_pmat(Color(0.92, 0.65, 0.18), 1)
		var el := Node3D.new()
		el.position = Vector3(0.75, 0, 0)
		sh.add_child(el)
		_cyl(el, 0.1, 0.24, Vector3.ZERO, Color(0.3, 0.3, 0.33), 8).rotation = Vector3(PI / 2.0, 0, 0)
		_box(el, Vector3(0.6, 0.11, 0.12), Vector3(0.3, 0, 0), Color(0.92, 0.65, 0.18)).material_override = \
				_pmat(Color(0.92, 0.65, 0.18), 1)
		var tip := Node3D.new()
		tip.position = Vector3(0.62, 0, 0)
		el.add_child(tip)
		_box(tip, Vector3(0.14, 0.16, 0.16), Vector3.ZERO, Color(0.25, 0.25, 0.28))
		_box(tip, Vector3(0.05, 0.08, 0.08), Vector3(0.09, 0, 0), Color(1.0, 0.25, 0.2), true)   # линза
		n.set_meta("arm", [yaw, sh, el, tip])
	elif t == D.TURRET:
		_cyl(n, 0.55, 0.6, Vector3(0, 0.3, 0), col.darkened(0.35))
		var pitch := _turret_head(n, Vector3(0, 0.75, 0), Vector3.ZERO)
		_cyl(pitch, 0.22, 0.25, Vector3(0, -0.05, 0), Color(0.6, 0.6, 0.65))
		_box(pitch, Vector3(1.0, 0.2, 0.2), Vector3(0.4, 0, 0), Color(0.75, 0.75, 0.8))
		_box(pitch, Vector3(0.08, 0.12, 0.12), Vector3(0.92, 0, 0), Color(1.0, 0.25, 0.2), true)   # линза лазера
	elif t == D.TURRET2:
		_box(n, Vector3(1.0, 0.5, 1.0), Vector3(0, 0.25, 0), col.darkened(0.35))
		var pitch := _turret_head(n, Vector3(0, 0.68, 0), Vector3(0.1, 0.04, 0))
		var head: Node3D = n.get_meta("head")
		_box(head, Vector3(0.6, 0.35, 0.6), Vector3.ZERO, Color(0.5, 0.52, 0.56))
		_box(head, Vector3(0.1, 0.1, 0.3), Vector3(-0.32, -0.08, 0), Color(0.9, 0.5, 0.22))   # короб с медными патронами
		for sz in [-0.12, 0.12]:
			_box(pitch, Vector3(0.75, 0.08, 0.08), Vector3(0.5, 0, sz), Color(0.25, 0.25, 0.28))
	elif t == D.BATTERY:
		# корпус с банками, светящиеся деления заряда
		_box(n, Vector3(1.2, 0.2, 1.0), Vector3(0, 0.1, 0), Color(0.3, 0.3, 0.33)).material_override = \
				_pmat(Color(0.3, 0.3, 0.33), 1)
		for k in 3:
			var x := -0.38 + 0.38 * k
			_box(n, Vector3(0.3, 1.0, 0.7), Vector3(x, 0.7, 0), Color(0.2, 0.22, 0.26)).material_override = \
					_pmat(Color(0.2, 0.22, 0.26), 1)
			_box(n, Vector3(0.12, 0.08, 0.12), Vector3(x, 1.24, 0.15), Color(0.85, 0.3, 0.2))   # клеммы
			_box(n, Vector3(0.12, 0.08, 0.12), Vector3(x, 1.24, -0.15), Color(0.3, 0.3, 0.33))
			for lv in 4:
				var seg := _box(n, Vector3(0.22, 0.14, 0.04), Vector3(x, 0.35 + lv * 0.2, 0.36), Color(0.3, 1.0, 0.5), true)
				_anim(n, seg, "charge", float(lv), 1.0, true)
	elif t == D.REPAIR:
		_cyl(n, 0.4, 1.6, Vector3(0, 0.8, 0), Color(0.75, 0.75, 0.78)).material_override = _pmat(Color(0.75, 0.75, 0.78), 1)
		var cross := Node3D.new()
		cross.position = Vector3(0, 1.85, 0)
		n.add_child(cross)
		_box(cross, Vector3(0.5, 0.14, 0.14), Vector3.ZERO, Color(0.3, 1.0, 0.4), true)
		_box(cross, Vector3(0.14, 0.5, 0.14), Vector3.ZERO, Color(0.3, 1.0, 0.4), true)
		_anim(n, cross, "spin", 1.5)
		_anim(n, cross, "pulse", 0.12, 3.0)
	elif t == D.UNIT_REPAIR:
		_cyl(n, 0.8, 0.2, Vector3(0, 0.1, 0), Color(0.35, 0.4, 0.45), 6)
		var gantry := Node3D.new()
		n.add_child(gantry)
		_box(gantry, Vector3(0.15, 1.2, 0.15), Vector3(0.6, 0.6, 0), Color(0.6, 0.62, 0.66))
		_box(gantry, Vector3(0.6, 0.12, 0.12), Vector3(0.35, 1.2, 0), Color(0.6, 0.62, 0.66))
		_box(gantry, Vector3(0.2, 0.2, 0.2), Vector3(0.05, 1.1, 0), Color(0.3, 1.0, 0.4), true)
		_anim(n, gantry, "spin", 0.7)
	elif t == D.LAMP:
		_cyl(n, 0.07, 2.0, Vector3(0, 1.0, 0), Color(0.35, 0.35, 0.38))
		_cyl(n, 0.28, 0.08, Vector3(0, 2.05, 0), Color(0.3, 0.3, 0.32))
		var bulb := _box(n, Vector3(0.26, 0.2, 0.26), Vector3(0, 1.92, 0), Color(1.0, 0.85, 0.55), true)
		n.set_meta("bulb", bulb)
	elif t == D.AA_GUN:
		_box(n, Vector3(1.0, 0.45, 1.0), Vector3(0, 0.22, 0), col.darkened(0.35))
		var pitch := _turret_head(n, Vector3(0, 0.62, 0), Vector3(0, 0.15, 0))
		var head: Node3D = n.get_meta("head")
		_cyl(head, 0.35, 0.3, Vector3.ZERO, Color(0.5, 0.52, 0.56))
		for sz in [-0.14, 0.14]:
			_box(pitch, Vector3(1.15, 0.07, 0.07), Vector3(0.55, 0, sz), Color(0.25, 0.25, 0.28))
		_box(pitch, Vector3(0.3, 0.22, 0.42), Vector3(-0.05, 0, 0), Color(0.3, 0.5, 0.85))   # кожух водяного охлаждения
		pitch.rotation_degrees = Vector3(0, 0, 35)
	elif t == D.TURRET3:
		_cyl(n, 0.65, 0.5, Vector3(0, 0.25, 0), col.darkened(0.35))
		var pitch := _turret_head(n, Vector3(0, 0.75, 0), Vector3(0.15, 0.35, 0))
		var head: Node3D = n.get_meta("head")
		_box(head, Vector3(0.8, 0.55, 0.7), Vector3.ZERO, Color(0.45, 0.47, 0.42))
		_box(pitch, Vector3(1.5, 0.16, 0.16), Vector3(0.65, 0, 0), Color(0.3, 0.31, 0.3))
		_box(pitch, Vector3(0.08, 0.18, 0.18), Vector3(1.42, 0, 0), Color(1.0, 0.55, 0.2), true)
		pitch.rotation_degrees = Vector3(0, 0, 25)   # пока цели нет — ствол приподнят
	# метка команды — маленький огонёк, чтобы своё было видно ночью
	if t != D.CONVEYOR and t != D.PIPE and t != D.WALL and t != D.SORTER:
		_box(n, Vector3(0.15, 0.15, 0.15), Vector3(-0.5, 0.15, -0.5), col, true)


func _vc_mat() -> Material:
	if mats.has("vc"):
		return mats["vc"]
	var m := ShaderMaterial.new()
	m.shader = LIT_SHADER
	m.set_shader_parameter("use_vertex_color", true)
	mats["vc"] = m
	return m


# =====================================================================
# Клиент: снапшоты, камера, ввод
# =====================================================================

func _apply_snapshot(u: PackedFloat32Array, it: PackedVector3Array, itt: PackedByteArray, pl: Array,
		st: Array, hp: Array, pw: Array, rv: Array) -> void:
	cur_rovers = rv
	prev_units = cur_units
	cur_units = u
	cur_items = it
	cur_item_types = itt
	power_stats = pw
	cur_players = pl
	snap_time = 0.0
	if not is_server:
		storage = st
		base_count = hp


func _set_fps(on: bool) -> void:
	fps_mode = on and player != null
	if player:
		player.active = fps_mode
	if fps_mode:
		player.cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		if player:
			_orbit_look_at(player.global_position.normalized())
		orbit_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	crosshair.visible = fps_mode


func _orbit_look_at(d: Vector3) -> void:
	orbit_pitch = asin(clampf(d.y, -1.0, 1.0))
	orbit_yaw = atan2(d.x, d.z)


## Базис «смотрим на точку d поверхности» без вырождения у полюсов.
func _update_orbit_cam() -> void:
	orbit_pitch = clampf(orbit_pitch, -1.45, 1.45)
	var d := Vector3(cos(orbit_pitch) * sin(orbit_yaw), sin(orbit_pitch), cos(orbit_pitch) * cos(orbit_yaw))
	orbit_cam.position = d * orbit_dist
	orbit_cam.look_at(Vector3.ZERO, Vector3.UP)


func _update_client(delta: float) -> void:
	if not fps_mode:
		var sp := delta * 0.6 * ((orbit_dist - planet.radius) / 150.0)
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			orbit_pitch += sp
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			orbit_pitch -= sp
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			orbit_yaw -= sp
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			orbit_yaw += sp
		_update_orbit_cam()

	if player:
		# провалился сквозь землю — вернуть на поверхность
		if player.global_position.length() < planet.radius - 2.0:
			player.teleport(_spawn_pos(my_team))
		send_acc += delta
		if send_acc >= 0.05:
			send_acc = 0.0
			var fwd := -player.global_transform.basis.z
			var ppos := player.global_position
			var held := sel_type
			if piloting:
				ppos = piloting.global_position
				held = IN_SHIP
			if is_server:
				server_player_state(1, ppos, fwd, held, my_pn)
			else:
				req_player_state.rpc_id(1, ppos, fwd, held, my_pn)
	if piloting:
		ship_send_acc += delta
		if ship_send_acc >= 0.05:
			ship_send_acc = 0.0
			var q := piloting.global_transform.basis.get_rotation_quaternion()
			if is_server:
				server_ship_state(1, piloting_id, piloting.global_position, q, piloting.fuel, piloting.thrusting, piloting.pn)
			else:
				req_ship_state.rpc_id(1, piloting_id, piloting.global_position, q, piloting.fuel, piloting.thrusting, piloting.pn)
		pred_acc += delta
		if pred_acc >= 0.25:
			pred_acc = 0.0
			pred = _predict()
			_draw_trajectories()
			plan = _plan()
			_draw_plan()
		_update_map_view()
		_update_compass()

	_update_sky()
	_update_flashlight()
	_update_viewmodel(delta)
	_update_self_avatar()
	lamp_acc += delta
	if lamp_acc >= 0.06:
		lamp_acc = 0.0
		_update_lights()
	_update_units()
	_update_items()
	_update_players(delta)
	_update_rovers(delta)
	_update_proj(delta)
	_update_ships(delta)
	_update_turrets(delta)
	_update_construction(delta)
	_update_death(delta)
	_update_couriers()

	# стрельба
	fire_cd -= delta
	if fps_mode and sel_type == D.WEAPON and not player.dead and not finished \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cd <= 0.0:
		fire_cd = D.GUN_CD_MS / 1000.0
		_fire()

	# какая клетка под прицелом и куда будет смотреть постройка
	_update_hover()
	var alive := not (player != null and player.dead)
	ghost.visible = hover_cell != NO_CELL and not finished and my_team >= 0 \
			and sel_type != D.WEAPON and alive and not radial.is_open and not item_radial.is_open \
			and piloting == null and fps_mode
	if ghost.visible:
		_update_ghost()
		var ok := _can_place(my_team, sel_type, hover_cell, hover_dir, my_pn)
		ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)

	# осмотр постройки под прицелом (данные присылает сервер)
	inspect_acc += delta
	if hover_cell != NO_CELL and grid.has(_k(my_pn, hover_cell)) and inspect_acc >= 0.25:
		inspect_acc = 0.0
		if is_server:
			inspect_cell = hover_cell
			inspect_info = _inspect_info(hover_cell, my_pn)
		else:
			req_inspect.rpc_id(1, hover_cell)
	if drag_mode != 0 and hover_cell != NO_CELL and hover_cell != drag_last and alive:
		drag_last = hover_cell
		if drag_mode == 1 and sel_type != D.WEAPON:
			_request_place(hover_cell, hover_dir)
		elif drag_mode == 2:
			_request_remove(hover_cell)

	_update_hud()


## Небесная механика. Система отсчёта привязана к планете (как в KSP):
## планета вращается вокруг наклонённой оси и летит по орбите вокруг гиганта,
## поэтому для нас движутся солнце, гигант и звёзды.
## Видим ли мы систему целиком (в открытом космосе или на карте системы).
func _system_view() -> bool:
	return map_mode == 2 or (piloting != null and piloting.pn < 0)


func _update_sky() -> void:
	var sysv := _system_view()
	local_root.visible = not sysv
	space_root.visible = sysv
	# звёзды «бесконечно далеко»: сфера едет вместе с камерой, иначе её край обрезается дальностью
	var cam_now := get_viewport().get_camera_3d()
	var cam_pos := cam_now.global_position if cam_now else Vector3.ZERO
	stars_node.global_position = cam_pos
	RenderingServer.global_shader_parameter_set("space_mode", 1.0 if sysv else 0.0)
	if sysv:
		# система гиганта: неподвижные оси, солнце в направлении SUN_DIR
		var sun_i: Vector3 = D.SUN_DIR.normalized()
		RenderingServer.global_shader_parameter_set("sun_dir", sun_i)
		RenderingServer.global_shader_parameter_set("sun_level", 1.0)
		RenderingServer.global_shader_parameter_set("giant_level", 0.0)
		sun_node.global_position = cam_pos + sun_i * D.SUN_VIS_DIST
		sun_node.visible = true
		stars_node.basis = Basis.IDENTITY
		var now := Time.get_ticks_msec() / 1000.0
		for j in space_moons.size():
			space_moons[j].position = SkyCalc.planet_pos(j, world_time)
			if j < orbit_ribbons.size():
				var om: ShaderMaterial = orbit_ribbons[j].material_override
				om.set_shader_parameter("hole", space_moons[j].global_position)
				om.set_shader_parameter("hole_r", D.planet_r(j) * 1.6 + orbit_width)
			alert_labels[j].visible = float(alert_marks.get(j, 0.0)) > now
		return
	var st := SkyCalc.state(world_time, my_pn)
	sky_state = st
	var sun: Vector3 = st.sun
	var gdir: Vector3 = st.gdir
	var frame: Basis = st.frame
	var giant_rel: Vector3 = st.giant_rel
	RenderingServer.global_shader_parameter_set("sun_dir", sun)
	RenderingServer.global_shader_parameter_set("sun_level", float(st.sun_level))
	RenderingServer.global_shader_parameter_set("giant_dir", gdir)
	RenderingServer.global_shader_parameter_set("giant_level", float(st.phase))
	giant_node.position = giant_rel
	sun_node.global_position = cam_pos + sun * D.SUN_VIS_DIST
	sun_node.visible = float(st.sun_level) > 0.02
	stars_node.basis = frame
	# соседние планеты в небе
	for j in sky_moons.size():
		sky_moons[j].visible = false
	for o in st.others:
		var m: MeshInstance3D = sky_moons[int(o[0])]
		m.visible = true
		m.position = o[1]


func _update_flashlight() -> void:
	var on := flash_on and player != null and not player.dead and piloting == null
	RenderingServer.global_shader_parameter_set("flash_on", 1.0 if on else 0.0)
	if player:
		RenderingServer.global_shader_parameter_set("flash_pos", player.cam.global_position)
		RenderingServer.global_shader_parameter_set("flash_dir", player.look_dir())
	# посадочный фонарь: сам включается у поверхности
	var land: bool = piloting != null and piloting.pn >= 0 and piloting.altitude() < D.LANDING_LIGHT_ALT
	RenderingServer.global_shader_parameter_set("land_on", 1.0 if land else 0.0)
	if piloting:
		piloting.beam.visible = land
		RenderingServer.global_shader_parameter_set("land_pos", piloting.global_position)
		RenderingServer.global_shader_parameter_set("land_dir", -piloting.global_transform.basis.y.normalized())


## Уровень света 0..16 в точке поверхности (то же, что считает шейдер, без фонарика).
func light_level_at(pos: Vector3) -> int:
	if sky_state.is_empty():
		return 0
	return SkyCalc.level_at(pos.normalized(), sky_state)


## Перестраивает меш призрака, только когда сменилась клетка, тип или поворот.
func _update_ghost() -> void:
	var nb: PackedInt32Array = planet.nbrs[hover_cell]
	_orient(ghost_arrow, hover_cell, nb[hover_dir])
	var key := "%d|%d|%d" % [sel_type, hover_cell, hover_dir]
	if key == ghost_key:
		return
	ghost_key = key
	var foot := _footprint(sel_type, hover_cell, hover_dir)
	var pr: Array = planet.prism(foot, 0.35, 0.96, Color.WHITE, Color.WHITE)
	ghost_foot.mesh = pr[0]
	ghost_cover.visible = D.GENERATORS.has(sel_type) or sel_type == D.POWER_POLE
	if ghost_cover.visible:
		var zone := {}
		var ring: int = D.POLE_RING if sel_type == D.POWER_POLE else D.POWER_RING
		for c in foot:
			var r := planet.rings(c, ring)
			for x in r:
				zone[x] = true
		var cp: Array = planet.prism(zone.keys(), 0.08, 0.9, Color.WHITE, Color.WHITE)
		ghost_cover.mesh = cp[0]


## Юниты: 7 чисел на юнита — x, y, z, команда, прочность 0..1, id, тип.
func _update_units() -> void:
	var a := clampf(snap_time / D.TICK, 0.0, 1.0)
	snap_time += get_process_delta_time()
	var stride := 7
	var n := cur_units.size() / stride
	var can_lerp := prev_units.size() == cur_units.size()
	var counts := [0, 0, 0, 0]
	var mms := [mm_units, mm_drones, mm_mechs, mm_umechs]
	var lifts := [0.0, D.DRONE_ALT, 0.0, 0.0]   # модели стоят на земле, дроны летают
	var ns := 0
	unit_pos.clear()
	unit_lights.clear()
	var seen_ids := {}
	for i in n:
		var j := i * stride
		var p := Vector3(cur_units[j], cur_units[j + 1], cur_units[j + 2])
		if can_lerp:
			p = Vector3(prev_units[j], prev_units[j + 1], prev_units[j + 2]).lerp(p, a)
		var team := int(cur_units[j + 3])
		var hpf := cur_units[j + 4]
		var id := int(cur_units[j + 5])
		var kind := clampi(int(cur_units[j + 6]), 0, 3)
		seen_ids[id] = true
		var up := p.normalized()
		var mm: MultiMesh = mms[kind]
		var c: int = counts[kind]
		if c >= mm.instance_count:
			continue
		var col: Color = D.TEAM_COLORS[team]
		# куда смотрит: по ходу движения (между снапшотами), иначе — как раньше
		var face: Vector3 = unit_face.get(id, Vector3.ZERO)
		if can_lerp:
			var mv := Vector3(cur_units[j], cur_units[j + 1], cur_units[j + 2]) \
					- Vector3(prev_units[j], prev_units[j + 1], prev_units[j + 2])
			mv -= up * mv.dot(up)
			if mv.length() > 0.01:
				face = mv.normalized()
				unit_face[id] = face
		var bas := _up_basis(up)
		face -= up * face.dot(up)
		if face.length() > 0.01:
			var f := face.normalized()
			bas = Basis(f.cross(up), up, -f)
		mm.set_instance_transform(c, Transform3D(bas, p + up * (float(lifts[kind]) - 0.3)))
		var moving := false
		if can_lerp:
			moving = Vector3(cur_units[j], cur_units[j + 1], cur_units[j + 2]).distance_to(
				Vector3(prev_units[j], prev_units[j + 1], prev_units[j + 2])) > 0.02
		mm.set_instance_custom_data(c, Color(col.r, col.g, col.b, clampf(hpf, 0.0, 1.0) * 0.49 + (0.5 if moving else 0.0)))
		if unit_lights.size() < 48 and face.length() > 0.5:
			unit_lights.append([p + up * (float(lifts[kind]) + 0.4), face])
		counts[kind] = c + 1
		if team == my_team:
			unit_pos[id] = p
			if selected.has(id) and ns < mm_sel.instance_count:
				var sc := 2.4 if kind >= D.U_MECH else 0.8
				mm_sel.set_instance_transform(ns, Transform3D(_up_basis(up).scaled(Vector3.ONE * sc), p + up * 0.1))
				ns += 1
	for k in mms.size():
		mms[k].visible_instance_count = counts[k]
	mm_sel.visible_instance_count = ns
	if unit_face.size() > seen_ids.size() + 64:
		for id in unit_face.keys():
			if not seen_ids.has(id):
				unit_face.erase(id)
	# выделенные, которых больше нет, — забываем
	for id in selected.keys():
		if not unit_pos.has(id):
			selected.erase(id)


## Выделение рамкой (или щелчком) в виде сверху: свои юниты на экране внутри прямоугольника.
func _finish_selection(end: Vector2) -> void:
	selecting = false
	sel_box.queue_redraw()
	var r := Rect2(sel_start, end - sel_start).abs()
	selected.clear()
	if r.size.length() < 6.0:
		var best := -1
		var bd := 25.0
		for id in unit_pos:
			var sp := orbit_cam.unproject_position(unit_pos[id])
			if sp.distance_to(end) < bd and not orbit_cam.is_position_behind(unit_pos[id]):
				bd = sp.distance_to(end)
				best = id
		if best != -1:
			selected[best] = true
		return
	for id in unit_pos:
		if orbit_cam.is_position_behind(unit_pos[id]):
			continue
		if r.has_point(orbit_cam.unproject_position(unit_pos[id])):
			selected[id] = true


## Приказ выделенным юнитам.
func _command(mode: int, point := Vector3.ZERO, has_point := false) -> void:
	if selected.is_empty():
		return
	var ids := PackedInt32Array(selected.keys())
	if is_server:
		server_command(my_team, my_pn, ids, mode, point, has_point)
	else:
		req_command.rpc_id(1, ids, mode, point, has_point)


## Точка на поверхности под курсором (вид сверху).
func _mouse_ground() -> Variant:
	var mp := get_viewport().get_mouse_position()
	var from := orbit_cam.project_ray_origin(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + orbit_cam.project_ray_normal(mp) * 2000.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.position


func _update_items() -> void:
	var m := mini(cur_items.size(), mm_items.instance_count)
	for i in m:
		mm_items.set_instance_transform(i, Transform3D(Basis(), cur_items[i] + cur_items[i].normalized() * 0.1))
		var ty := int(cur_item_types[i]) if i < cur_item_types.size() else D.I_COPPER
		var cell := Icons.cell_of(ty)
		mm_items.set_instance_custom_data(i, Color(cell.x, cell.y, 0, 0))
	mm_items.visible_instance_count = m


## Любой базис, у которого Y смотрит вдоль up.
func _up_basis(up: Vector3) -> Basis:
	var helper := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var x := helper.cross(up).normalized()
	return Basis(x, up, x.cross(up))


func _update_hover() -> void:
	hover_cell = NO_CELL
	var c: Camera3D = player.cam if fps_mode else orbit_cam
	var mp: Vector2
	if fps_mode:
		mp = get_viewport().get_visible_rect().size / 2.0
	else:
		mp = get_viewport().get_mouse_position()
	var from := c.project_ray_origin(mp)
	var dir := c.project_ray_normal(mp)
	var length: float = D.BUILD_REACH if fps_mode else 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var hp: Vector3 = hit.position
	hover_cell = planet.walk(hover_seed, hp.normalized())
	hover_seed = hover_cell

	# направление постройки: сосед, который ближе всего к «вперёд» камеры
	var fwd: Vector3 = (-c.global_transform.basis.z) if fps_mode else c.global_transform.basis.y
	var o := planet.top_pos(hover_cell)
	var up: Vector3 = planet.dirs[hover_cell]
	fwd = fwd - up * fwd.dot(up)
	var nb: PackedInt32Array = planet.nbrs[hover_cell]
	var best := 0
	var bd := -INF
	for i in nb.size():
		var v := planet.top_pos(nb[i]) - o
		v = (v - up * v.dot(up)).normalized()
		var d := v.dot(fwd)
		if d > bd:
			bd = d
			best = i
	hover_dir = posmod(best + sel_rot, nb.size())


func _update_players(delta: float) -> void:
	var me := multiplayer.get_unique_id()
	var seen := {}
	var k := minf(1.0, delta * 15.0)
	for e in cur_players:
		var pid: int = e[0]
		var pos: Vector3 = e[1]
		var fwd: Vector3 = e[2]
		var hp: int = e[4]
		if pid == me:
			my_hp = hp
			continue
		seen[pid] = true
		if not others.has(pid):
			var av := _make_avatar(e[3])
			av.position = pos
			others[pid] = av
		var node: Node3D = others[pid]
		node.visible = hp > 0
		var held: int = e[5] if e.size() > 5 else D.WEAPON
		node.visible = hp > 0 and held != IN_SHIP
		if held == IN_SHIP:
			continue
		if int(node.get_meta("held")) != held and held != IN_SHIP:
			node.set_meta("held", held)
			_set_held(node.get_meta("hand"), held, int(node.get_meta("team")))
		var p := node.position.lerp(pos, k)
		var up := p.normalized()
		var f := (fwd - up * fwd.dot(up))
		if f.length() < 0.001:
			f = _up_basis(up).z
		f = f.normalized()
		var x := f.cross(up)   # вперёд = -Z, значит X = Y × Z = up × (-f) = f × up
		node.transform = Transform3D(Basis(x, up, -f), p)
		_apply_far(node, _cam_dist(p))
	for pid in others.keys():
		if not seen.has(pid):
			others[pid].queue_free()
			others.erase(pid)

	if player:
		var was_dead := player.dead
		player.dead = my_hp <= 0
		if player.dead and not was_dead:
			_on_death()
		elif was_dead and not player.dead:
			_on_revive()


## Башня поворачивается к цели (рысканье), ствол поднимается на угол выстрела (тангаж).
func _update_turrets(delta: float) -> void:
	var k := minf(1.0, delta * 6.0)
	for id in turret_nodes.keys():
		var n: Node3D = turret_nodes[id]
		if not is_instance_valid(n):
			turret_nodes.erase(id)
			continue
		if not turret_aim.has(id):
			continue
		var d: Vector3 = turret_aim[id]
		# переводим мировое направление в локальные оси декора (масштаб убираем)
		var local := n.global_transform.basis.orthonormalized().inverse() * d
		var yaw := atan2(-local.z, local.x)
		var pitch_ang := atan2(local.y, Vector2(local.x, local.z).length())
		var head: Node3D = n.get_meta("head")
		var pitch: Node3D = n.get_meta("pitch")
		head.rotation.y = lerp_angle(head.rotation.y, yaw, k)
		pitch.rotation.z = lerp_angle(pitch.rotation.z, pitch_ang, k)


## Сел в корабль: прячем персонажа, включаем камеру корабля.
func _start_piloting(id: int, pos: Vector3, quat: Quaternion, fuel: float, pn: int, kind := 0) -> void:
	if player == null or piloting != null:
		return
	var sh := Ship.new()
	add_child(sh)
	sh.global_transform = Transform3D(Basis(quat), pos)
	sh.setup(self, id, _make_ship(my_team, kind), fuel, pn, kind)
	piloting = sh
	piloting_id = id
	player.visible = false
	player.active = false
	player.set_physics_process(false)
	sh.cam.current = true
	crosshair.visible = false
	compass.visible = true
	navball.visible = true
	if ship_nodes.has(id):
		ship_nodes[id].queue_free()
		ship_nodes.erase(id)


func _stop_piloting(out_pos: Vector3) -> void:
	if piloting == null:
		return
	piloting.queue_free()
	piloting = null
	piloting_id = -1
	map_mode = 0
	compass.visible = false
	navball.visible = false
	for l in ap_labels:
		l.visible = false
	local_traj.visible = false
	map_ship_label.visible = false
	player.visible = true
	player.set_physics_process(true)
	player.teleport(out_pos)
	_set_fps(true)


## Выйти можно только после посадки. Выходим рядом с кораблём.
func _exit_ship() -> void:
	if piloting == null or not piloting.landed:
		return
	var pos := piloting.global_position
	var q := piloting.global_transform.basis.get_rotation_quaternion()
	var up := pos.normalized()
	var side := _up_basis(up).x
	if is_server:
		server_ship_exit(1, piloting_id, pos, q, piloting.pn)
	else:
		req_ship_exit.rpc_id(1, piloting_id, pos, q, piloting.pn)
	_stop_piloting(pos + side * 3.0 + up * 1.0)


# ---------------------------------------------------------------------
# Карта, прогноз траектории, компас
# ---------------------------------------------------------------------

## Прогноз полёта: внутри сферы планеты — притяжение планеты, снаружи — гиганта.
## local — точки в системе текущей планеты, inertial — в системе гиганта (для карты системы).
func _predict() -> Dictionary:
	var res := {"local": PackedVector3Array(), "inertial": PackedVector3Array(), "enc": -1,
		"enc_t": 0.0, "enc_idx": -1, "exit_t": -1.0, "impact": false}
	if piloting == null or piloting.landed:
		return res
	var loc := PackedVector3Array()
	var ine := PackedVector3Array()
	var start_pn: int = piloting.pn
	var cur := start_pn
	var r: Vector3 = piloting.global_position
	var v: Vector3 = piloting.vel
	var t := world_time
	var after_enc := 0
	# орбиту вокруг стартовой планеты рисуем относительно её положения СЕЙЧАС (как в KSP),
	# участок у планеты-цели — относительно её положения в момент встречи
	var p_now := SkyCalc.planet_pos(maxi(start_pn, 0), world_time)
	var ft_now := SkyCalc.frame(maxi(start_pn, 0), world_time).transposed()
	var p_enc := Vector3.ZERO
	var ft_enc := Basis.IDENTITY
	for step in 900:
		if cur >= 0:
			var rl := r.length()
			if rl < D.planet_r(cur):
				res.impact = true
				break
			if rl > SkyCalc.soi(cur):
				var ft := SkyCalc.frame(cur, t).transposed()
				r = SkyCalc.planet_pos(cur, t) + ft * r
				v = SkyCalc.planet_vel(cur, t) + ft * v
				if cur == start_pn and float(res.exit_t) < 0.0:
					res.exit_t = t - world_time
				cur = -1
				continue
			var dt := 0.25
			v -= r.normalized() * (D.planet_mu(cur) / (rl * rl)) * dt
			r += v * dt
			t += dt
			if cur == start_pn and int(res.enc) == -1:
				loc.append(r)
			if cur == start_pn and int(res.enc) == -1:
				ine.append(p_now + ft_now * r)
			else:
				ine.append(p_enc + ft_enc * r)
		else:
			var rl := r.length()
			if rl < D.GIANT_R:
				res.impact = true
				break
			var dt := 1.0
			v -= r.normalized() * (D.GIANT_MU / (rl * rl)) * dt
			r += v * dt
			t += dt
			ine.append(r)
			for j in D.PLANETS.size():
				var d := r - SkyCalc.planet_pos(j, t)
				if d.length() < SkyCalc.soi(j):
					if int(res.enc) == -1 and (j != start_pn or t - world_time > 30.0):
						res.enc = j
						res.enc_t = t - world_time
						res["enc_pos"] = SkyCalc.planet_pos(j, t)
						res.enc_idx = ine.size()
					p_enc = SkyCalc.planet_pos(j, t)
					ft_enc = SkyCalc.frame(j, t).transposed()
					var f := SkyCalc.frame(j, t)
					r = f * d
					v = f * (v - SkyCalc.planet_vel(j, t))
					cur = j
					break
		if int(res.enc) != -1:
			after_enc += 1
			if after_enc > 160:
				break
	res.local = loc
	res.inertial = ine
	return res


# ---------------------------------------------------------------------
# Помощник перелёта (T — выбрать планету-цель). Считает самый экономный перелёт по Гоману:
# когда стартовать (окно), сколько Δv, куда жечь. Управляет игрок сам.
# ---------------------------------------------------------------------

func _cycle_target() -> void:
	if piloting == null:
		return
	var n := D.PLANETS.size()
	var start := nav_target
	for i in n + 1:
		start += 1
		if start >= n:
			nav_target = -1
			break
		if start != piloting.pn:
			nav_target = start
			break
	plan = _plan()
	_draw_plan()


func _plan() -> Dictionary:
	var sh := piloting
	if sh == null or nav_target < 0 or nav_target == sh.pn:
		return {}
	var res := {"target": nav_target}
	if sh.pn < 0:
		res["space"] = true
		return res
	var mu: float = D.GIANT_MU
	var r1: float = D.PLANETS[sh.pn].a
	var r2: float = D.PLANETS[nav_target].a
	var at := (r1 + r2) * 0.5
	var tt := PI * sqrt(at * at * at / mu)
	var n1 := sqrt(mu / (r1 * r1 * r1))
	var n2 := sqrt(mu / (r2 * r2 * r2))
	var phi_req := wrapf(PI - n2 * tt, -PI, PI)   # на сколько цель должна опережать нас при старте
	var p1 := SkyCalc.planet_pos(sh.pn, world_time)
	var p2 := SkyCalc.planet_pos(nav_target, world_time)
	var phi_now := wrapf(atan2(p2.z, p2.x) - atan2(p1.z, p1.x), -PI, PI)
	var rel := n2 - n1
	var wait := fposmod(phi_req - phi_now, TAU) / rel if rel > 0.0 else fposmod(phi_now - phi_req, TAU) / -rel
	var syn := TAU / absf(rel)
	if wait > syn - 15.0:
		wait -= syn   # окно только что было — ещё можно успеть
	var vinf := sqrt(mu / r1) * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)   # > 0 — наружу, < 0 — внутрь
	var vinf2 := absf(sqrt(mu / r2) * (1.0 - sqrt(2.0 * r1 / (r1 + r2))))
	var mu1 := D.planet_mu(sh.pn)
	var rp := maxf(sh.global_position.length(), D.planet_r(sh.pn) + 5.0)
	var dv_ej := sqrt(vinf * vinf + 2.0 * mu1 / rp) - sqrt(mu1 / rp)
	var dv_land := sqrt(vinf2 * vinf2 + 2.0 * D.planet_mu(nav_target) / D.planet_r(nav_target))
	# куда жечь: по движению планеты вокруг гиганта (наружу) или против него (внутрь)
	var vm := (SkyCalc.frame(sh.pn, world_time) * SkyCalc.planet_vel(sh.pn, world_time)).normalized()
	var burn := vm if vinf > 0.0 else -vm
	res["wait"] = wait
	res["tt"] = tt
	res["dv_ej"] = dv_ej
	res["dv_land"] = dv_land
	res["burn_dir"] = burn
	res["outward"] = vinf > 0.0
	res["dep_ang"] = atan2(p1.z, p1.x) + n1 * wait
	res["r1"] = r1
	res["r2"] = r2
	res["arrive"] = SkyCalc.planet_pos(nav_target, world_time + maxf(wait, 0.0) + tt)
	# когда скорость корабля вокруг планеты совпадёт с направлением разгона
	var v := sh.vel
	var r := sh.global_position
	res["align_t"] = -1.0
	if not sh.landed and v.length() > 1.0:
		var ang := v.angle_to(burn)
		var omega := v.length() / r.length()
		var sgn := v.cross(burn).dot(r.cross(v))
		res["align_ang"] = rad_to_deg(ang)
		res["align_t"] = ang / omega if sgn >= 0.0 else (TAU - ang) / omega
	return res


## Эллипс перелёта на карте системы: от нашей планеты в момент окна до цели в момент прилёта.
func _draw_plan() -> void:
	if plan_traj == null:
		return
	if plan.is_empty() or not plan.has("r1"):
		plan_traj.mesh = null
		plan_label.visible = false
		return
	var r1: float = plan.r1
	var r2: float = plan.r2
	var at := (r1 + r2) * 0.5
	var e := absf(r2 - r1) / (r1 + r2)
	var pts := PackedVector3Array()
	var th0: float = plan.dep_ang
	for i in 97:
		var nu := PI * i / 96.0
		if r2 < r1:
			nu += PI   # внутрь: стартуем из апоцентра
		var rr := at * (1.0 - e * e) / (1.0 + e * cos(nu))
		var ang := th0 + (nu if r2 >= r1 else nu - PI)
		pts.append(Vector3(cos(ang), 0.0, sin(ang)) * rr)
	var w := maxf(orbit_width, 6.0) * 0.8
	_strip(plan_traj, pts, -1, Color(1.0, 0.75, 0.3), Color(1.0, 0.75, 0.3), Vector3.UP, w)
	plan_label.position = plan.arrive + Vector3.UP * D.planet_r(nav_target) * 1.6
	plan_label.text = "◎ " + String(D.PLANETS[nav_target].name) + " при прилёте"
	plan_label.visible = true


## Строки помощника перелёта в панели корабля.
func _plan_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if piloting == null:
		return out
	if nav_target < 0:
		out.append("T — выбрать планету для перелёта")
		return out
	out.append("ЦЕЛЬ: %s   (T — сменить)" % D.PLANETS[nav_target].name)
	var hit := int(pred.get("enc", -1)) == nav_target
	if plan.is_empty() or plan.has("space"):
		out.append("Перехват цели: ДА, через %d с" % int(pred.enc_t) if hit else "Перехвата нет — подправь скорость")
		return out
	var wait: float = plan.wait
	if piloting.landed:
		out.append("Сначала выйди на орбиту (~%d м/с)" % D.DV_LAUNCH)
	if hit:
		out.append("ПЕРЕХВАТ ЕСТЬ: у цели через %d с — гаси двигатель" % int(pred.enc_t))
	elif wait < -5.0:
		out.append("Окно только что прошло (%d с назад) — жги сейчас, чуть сильнее" % int(-wait))
	elif wait < 8.0:
		out.append("ОКНО СЕЙЧАС — разгон ~%d м/с %s" % [int(plan.dv_ej), "по движению планеты" if plan.outward else "против движения планеты"])
	else:
		out.append("Окно перелёта через %d с" % int(wait))
	if float(plan.align_t) >= 0.0 and not hit:
		out.append("Направление разгона (◆ на навболе): угол %d°, совпадёт через %d с" % [int(plan.get("align_ang", 0.0)), int(plan.align_t)])
	out.append("Разгон ~%d м/с, в пути ~%d с, посадка у цели ~%d м/с" % [int(plan.dv_ej), int(plan.tt), int(plan.dv_land)])
	var need: float = float(plan.dv_ej) + float(plan.dv_land) + (float(D.DV_LAUNCH) if piloting.landed else 0.0)
	out.append("Нужно ~%d м/с, есть %d м/с%s" % [int(need), int(piloting.dv()), "" if piloting.dv() >= need else "  — НЕ ХВАТИТ"])
	return out


func _draw_trajectories() -> void:
	var r := piloting.global_position
	var nrm := r.cross(piloting.vel)
	if nrm.length() < 0.01:
		nrm = _up_basis(r.normalized()).z
	var w_local := map_cam.size * 0.004 if map_mode == 1 else 0.6
	var w_sys := map_cam.size * 0.003 if map_mode == 2 else 3.0
	_strip(local_traj, pred.get("local", PackedVector3Array()), -1, Color(1.0, 0.85, 0.3), Color.WHITE,
		nrm.normalized(), w_local)
	_strip(sys_traj, pred.get("inertial", PackedVector3Array()), int(pred.get("enc_idx", -1)),
		Color(0.35, 0.8, 1.0), Color(0.35, 1.0, 0.45), Vector3.UP, w_sys)
	# «призрак» планеты-цели там, где она будет в момент встречи
	enc_label.visible = pred.has("enc_pos")
	if enc_label.visible:
		enc_label.position = pred.enc_pos
		enc_label.text = "◯ %s при встрече" % D.PLANETS[int(pred.enc)].name


## Линия по точкам; после split — другим цветом (участок у планеты, к которой летим).
## Траектория лентой шириной w в плоскости с нормалью nrm; после split — другим цветом.
func _strip(mi: MeshInstance3D, pts: PackedVector3Array, split: int, c1: Color, c2: Color,
		nrm: Vector3, w: float) -> void:
	var am := ArrayMesh.new()
	if pts.size() >= 2:
		var n1 := pts.size() if split <= 1 else mini(split, pts.size())
		_ribbon_surface(am, pts, 0, n1, nrm, w, c1)
		if split > 1 and split < pts.size() - 1:
			_ribbon_surface(am, pts, split - 1, pts.size(), nrm, w, c2)
	mi.mesh = am


func _ribbon_surface(am: ArrayMesh, pts: PackedVector3Array, from: int, to: int, nrm: Vector3,
		w: float, col: Color) -> void:
	if to - from < 2:
		return
	var verts := PackedVector3Array()
	for i in range(from, to):
		var a := pts[maxi(i - 1, from)]
		var b := pts[mini(i + 1, to - 1)]
		var side := (b - a).cross(nrm)
		side = side.normalized() * (w / 2.0) if side.length() > 0.000001 else Vector3.ZERO
		verts.append(pts[i] - side)
		verts.append(pts[i] + side)
	# вторая лента поперёк первой — траекторию видно с любого угла, а не только сверху
	var verts2 := PackedVector3Array()
	for i in range(from, to):
		var a := pts[maxi(i - 1, from)]
		var b := pts[mini(i + 1, to - 1)]
		var side := (b - a).cross(nrm)
		var up2 := side.cross(b - a)
		up2 = up2.normalized() * (w / 2.0) if up2.length() > 0.000001 else Vector3.ZERO
		verts2.append(pts[i] - up2)
		verts2.append(pts[i] + up2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col   # с проверкой глубины: за планетой и внутри неё не видно
	for vv in [verts, verts2]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vv
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arr)
		am.surface_set_material(am.get_surface_count() - 1, m)


## Камера карты: 1 — вид сверху на орбиту вокруг планеты, 2 — вся система сверху.
func _update_map_view() -> void:
	var sysv := _system_view()
	sys_traj.visible = sysv
	local_traj.visible = map_mode == 1
	var ship_i: Vector3 = piloting.global_position
	if piloting.pn >= 0:
		ship_i = SkyCalc.to_inertial(piloting.pn, world_time, piloting.global_position)
	sys_ship_label.visible = sysv
	sys_ship_label.position = ship_i
	map_ship_label.visible = map_mode == 1
	map_ship_label.position = piloting.global_position
	# на карте системы корабль внутри сферы планеты рисуем меткой (его модель в координатах планеты)
	piloting.visible = not (map_mode == 2 and piloting.pn >= 0)
	var oi := piloting.orbit_info()
	var show_local := map_mode == 1 and not oi.is_empty()
	var show_sys := sysv and piloting.pn < 0 and not oi.is_empty()
	ap_labels[0].visible = show_local
	ap_labels[1].visible = show_local
	ap_labels[2].visible = show_sys
	ap_labels[3].visible = show_sys
	if not oi.is_empty():
		for i in [0, 2]:
			ap_labels[i].position = oi.ap_pos
			ap_labels[i + 1].position = oi.pe_pos
	if map_mode == 0:
		_set_orbit_width(8.0)   # в полёте по космосу — ленты толщиной 8 м
		if not piloting.cam.current:
			piloting.cam.current = true
		return
	if not map_cam.current:
		map_cam.current = true
	# карта следит за ракетой: корабль всегда в центре
	if map_mode == 1:
		var r := piloting.global_position
		var nrm := r.cross(piloting.vel)
		if nrm.length() < 0.01:
			nrm = _up_basis(r.normalized()).z
		nrm = nrm.normalized()
		map_cam.size = map_zoom * maxf(r.length() * 4.0, 500.0)
		map_cam.global_position = r + nrm * 5000.0
		map_cam.look_at(r, _up_basis(nrm).z)
	else:
		map_cam.size = map_zoom * 3000.0
		map_cam.global_position = Vector3(ship_i.x, 12000, ship_i.z)
		map_cam.look_at(Vector3(ship_i.x, 0, ship_i.z), Vector3.FORWARD)
		_set_orbit_width(map_cam.size * 0.004)


## Компас: «север» — ось вращения планеты (в космосе — ось орбит), курс носа и направление полёта.
func _update_compass() -> void:
	var up := piloting.global_position.normalized()
	var north := Vector3.UP - up * up.y
	if north.length() < 0.05:
		north = Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
	north = north.normalized()
	var east := north.cross(up)
	var b := piloting.global_transform.basis
	var nose := b.y.normalized()
	var h := nose - up * nose.dot(up)
	if h.length() < 0.05:
		h = -b.z - up * (-b.z).dot(up)   # нос вертикально — курс по «спине» корабля
	var heading := rad_to_deg(atan2(h.dot(east), h.dot(north)))
	var pitch := rad_to_deg(asin(clampf(nose.dot(up), -1.0, 1.0)))
	var v := piloting.vel
	var show_pro := v.length() > 0.5
	var vh := v - up * v.dot(up)
	var pro_h := rad_to_deg(atan2(vh.dot(east), vh.dot(north)))
	var pro_p := rad_to_deg(asin(clampf(v.normalized().dot(up), -1.0, 1.0))) if show_pro else 0.0
	compass.set_data(heading, pitch, pro_h, pro_p, show_pro)
	# навбол: в центре нос, сверху на экране — «спина» корабля (сторона иллюминатора)
	var us := -b.z.normalized()
	var right := nose.cross(us)
	var hvec := piloting.global_position.cross(v)
	var marks: Array = []
	if show_pro:
		marks.append([v, "pro"])
		marks.append([-v, "retro"])
	if hvec.length() > 0.01:
		marks.append([hvec, "normal"])
		marks.append([-hvec, "anti"])
	marks.append([up, "out"])
	marks.append([-up, "in"])
	if not plan.is_empty() and plan.has("burn_dir") and float(plan.wait) < 40.0:
		marks.append([plan.burn_dir, "burn"])
	navball.set_data(nose, right, us, up, north, marks, piloting.sas_mode, piloting.power)


## Перешли на другую планету: перерисовываем постройки, сбрасываем то, что видели на старой.
func _switch_planet(pn: int) -> void:
	if pn == my_pn or pn < 0:
		return
	my_pn = pn
	planet = _pl(pn)
	_build_terrain()
	if player:
		player.gmul = float(D.PLANETS[pn].get("g", 1.0))
	for id in bnodes.keys():
		bnodes[id].queue_free()
	bnodes.clear()
	turret_nodes.clear()
	turret_aim.clear()
	asm_nodes.clear()
	for team in courier_nodes.keys():
		(courier_nodes[team][0] as Node).queue_free()
		(courier_nodes[team][1] as Node).queue_free()
	courier_nodes.clear()
	for dict in [others, rover_nodes, ship_nodes]:
		for id in dict.keys():
			dict[id].queue_free()
		dict.clear()
	cur_units = PackedFloat32Array()
	prev_units = PackedFloat32Array()
	cur_items = PackedVector3Array()
	cur_item_types = PackedByteArray()
	cur_players = []
	cur_rovers = []
	proj_pos = PackedVector3Array()
	ghost_key = ""
	lamp_acc = 1.0
	hover_seed = NO_CELL
	inspect_cell = NO_CELL
	inspect_info = []
	for b in buildings.values():
		if b.pn == pn:
			_vis_add(b)


## Корабль вошёл в сферу влияния планеты (или вылетел в открытый космос, pn = -1).
func on_ship_soi(pn: int) -> void:
	if pn >= 0:
		_switch_planet(pn)


## Корабль сам включил «против движения» перед посадкой.
func on_auto_retro() -> void:
	big_msg.text = "АВТОПИЛОТ: против движения (посадка)"
	get_tree().create_timer(2.0).timeout.connect(_clear_msg)


## Вызывает корабль при жёсткой посадке.
func on_ship_crash(_sh: Node3D, self_destruct := false, msg := "") -> void:
	var id := piloting_id
	if is_server:
		server_ship_crash(1, id)
	else:
		req_ship_crash.rpc_id(1, id)
	_switch_planet(_spawn_pn(my_team))
	_stop_piloting(_spawn_pos(my_team))
	if msg != "":
		big_msg.text = msg
	elif self_destruct:
		big_msg.text = "КОРАБЛЬ САМОУНИЧТОЖЕН"
	else:
		big_msg.text = "КОРАБЛЬ РАЗБИТ\nсадиться надо медленнее %d м/с" % int(D.SHIP_CRASH_SPEED)
	get_tree().create_timer(3.0).timeout.connect(_clear_msg)


func _clear_msg() -> void:
	if not finished:
		big_msg.text = ""


## Корабли из снапшота: стоящие и чужие летящие (свой летящий рисует контроллер).
func _update_ships(delta: float) -> void:
	var seen := {}
	var k := minf(1.0, delta * 12.0)
	for e in cur_ships:
		var id: int = e[0]
		if id == piloting_id or int(e[7]) != my_pn:
			continue
		seen[id] = true
		if not ship_nodes.has(id):
			var nn := _make_ship(int(e[1]), int(e[8]) if e.size() > 8 else 0)
			local_root.add_child(nn)
			nn.global_transform = Transform3D(Basis(Quaternion(e[3])), e[2])
			ship_nodes[id] = nn
		var node: Node3D = ship_nodes[id]
		var target := Transform3D(Basis(Quaternion(e[3])), e[2])
		node.global_transform = node.global_transform.interpolate_with(target, k)
		var flame: Node3D = node.get_meta("flame")
		flame.visible = bool(e[4])
	for id in ship_nodes.keys():
		if not seen.has(id):
			ship_nodes[id].queue_free()
			ship_nodes.erase(id)


## Ближайший свой стоящий корабль в пределах досягаемости. -1 — нет.
func _near_ship() -> int:
	if player == null:
		return -1
	var best := -1
	var bd := 6.0
	for e in cur_ships:
		if int(e[1]) != my_team or int(e[5]) != -1 or int(e[7]) != my_pn:
			continue
		var d := player.global_position.distance_to(Vector3(e[2]))
		if d < bd:
			bd = d
			best = e[0]
	return best


## Разведчик: корпус, обтекатель, иллюминатор, стабилизаторы, сопло, опоры, факел.
## Начало координат — низ опор, нос вдоль +Y.
func _make_ship(team: int, kind := 0) -> Node3D:
	if kind == 2:
		return _make_ufo(team)
	if kind == 3:
		return _make_missile(team)
	if kind == 4:
		return _make_jet(team)
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var hull := _pmat(Color(0.86, 0.86, 0.88), 1)
	var dark := _pmat(Color(0.25, 0.25, 0.28), 1)
	_part(n, "cyl", Vector3(0.7, 3.0, 0), Vector3(0, 2.1, 0), hull)
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.7
	nm.height = 1.3
	nm.radial_segments = 12
	nose.mesh = nm
	nose.position = Vector3(0, 4.25, 0)
	nose.material_override = _pmat(col, 0)
	n.add_child(nose)
	_box(n, Vector3(0.4, 0.4, 0.1), Vector3(0, 3.0, -0.68), Color(0.4, 0.85, 1.0), true)   # иллюминатор
	_part(n, "box", Vector3(1.45, 0.08, 1.45), Vector3(0, 2.4, 0), _pmat(col, 0))           # полоса команды
	for i in 3:
		var a := TAU * i / 3.0
		var fin := _part(n, "box", Vector3(0.08, 1.0, 0.6), Vector3(cos(a) * 0.85, 1.0, sin(a) * 0.85), dark)
		fin.rotation.y = -a
		var leg := _part(n, "box", Vector3(0.08, 0.7, 0.08), Vector3(cos(a + 0.5) * 0.75, 0.35, sin(a + 0.5) * 0.75), dark)
		leg.rotation = Vector3(sin(a + 0.5) * 0.3, 0, -cos(a + 0.5) * 0.3)
	var bell := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.3
	bm.bottom_radius = 0.5
	bm.height = 0.5
	bell.mesh = bm
	bell.position = Vector3(0, 0.45, 0)
	bell.material_override = dark
	n.add_child(bell)
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.45
	fm.bottom_radius = 0.0
	fm.height = 2.2
	flame.mesh = fm
	flame.position = Vector3(0, -0.9, 0)
	flame.material_override = _mat(Color(1.0, 0.6, 0.2), true)
	flame.visible = false
	n.add_child(flame)
	n.set_meta("flame", flame)
	# видимый луч посадочного фонаря (прозрачный конус вниз)
	var beam := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.35
	bcm.bottom_radius = 7.0
	bcm.height = 14.0
	bcm.radial_segments = 16
	beam.mesh = bcm
	beam.position = Vector3(0, -7.0, 0)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_color = Color(1.0, 0.95, 0.8, 0.08)
	beam.material_override = bmat
	beam.visible = false
	n.add_child(beam)
	n.set_meta("beam", beam)
	if kind == 1:
		# транспорт: шире и выше, по бокам — грузовые отсеки
		for sx in [-1.0, 1.0]:
			_part(n, "box", Vector3(0.7, 2.0, 1.2), Vector3(sx * 1.1, 1.6, 0), _pmat(Color(0.7, 0.68, 0.6), 1))
			_box(n, Vector3(0.05, 0.3, 0.8), Vector3(sx * 1.46, 1.6, 0), col, true)
		for c in n.get_children():
			if c != beam:
				c.scale *= Vector3(1.4, 1.2, 1.4)
				c.position *= Vector3(1.4, 1.2, 1.4)
	return n


## Истребитель-НЛО: тарелка из тёмного инопланетного металла с синими светящимися полосами,
## стеклянный купол, кольцо свечения снизу (оно же «пламя» двигателя).
func _make_ufo(team: int) -> Node3D:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var hull := _pmat(Color(0.24, 0.2, 0.34), 1)
	var blue := Color(0.35, 0.65, 1.0)
	var disc := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 2.6
	dm.height = 1.1
	dm.radial_segments = 32
	dm.rings = 10
	disc.mesh = dm
	disc.position = Vector3(0, 1.3, 0)
	disc.material_override = hull
	n.add_child(disc)
	for r in [2.55, 1.9, 1.2]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.05
		tm.outer_radius = r
		tm.rings = 48
		tm.ring_segments = 6
		ring.mesh = tm
		ring.position = Vector3(0, 1.3 + (0.0 if r > 2.5 else 0.33 * (2.55 - r) / 1.35 + 0.12), 0)
		ring.material_override = _mat(blue, true)
		n.add_child(ring)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.0
	dome.mesh = sm
	dome.position = Vector3(0, 1.85, 0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.45, 0.85, 1.0, 0.55)
	dome.material_override = gm
	n.add_child(dome)
	_box(n, Vector3(0.5, 0.1, 0.5), Vector3(0, 2.35, 0), col, true)   # метка команды на макушке
	for i in 3:
		var a := TAU * i / 3.0
		_part(n, "box", Vector3(0.1, 0.9, 0.1), Vector3(cos(a) * 1.4, 0.45, sin(a) * 1.4), hull)   # опоры
		_box(n, Vector3(0.35, 0.06, 0.35), Vector3(cos(a) * 1.4, 0.03, sin(a) * 1.4), Color(0.3, 0.3, 0.35))
	# кольцо свечения снизу — двигатель (в коде корабля это «пламя»)
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 1.3
	fm.bottom_radius = 0.2
	fm.height = 1.6
	flame.mesh = fm
	flame.position = Vector3(0, 0.1, 0)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(0.4, 0.7, 1.0, 0.6)
	flame.material_override = fmat
	flame.visible = false
	n.add_child(flame)
	n.set_meta("flame", flame)
	var beam := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.6
	bcm.bottom_radius = 6.0
	bcm.height = 12.0
	beam.mesh = bcm
	beam.position = Vector3(0, -6.0, 0)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_color = Color(0.5, 0.8, 1.0, 0.07)
	beam.material_override = bmat
	beam.visible = false
	n.add_child(beam)
	n.set_meta("beam", beam)
	return n


## Пламя двигателя и луч посадочного фонаря (их включает код корабля) — общие для моделей.
func _ship_fx(n: Node3D, flame_r: float, flame_y: float) -> void:
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = flame_r
	fm.bottom_radius = 0.0
	fm.height = flame_r * 5.0
	flame.mesh = fm
	flame.position = Vector3(0, flame_y - flame_r * 2.5, 0)
	flame.material_override = _mat(Color(1.0, 0.6, 0.2), true)
	flame.visible = false
	n.add_child(flame)
	n.set_meta("flame", flame)
	var beam := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.3
	bcm.bottom_radius = 5.0
	bcm.height = 10.0
	beam.mesh = bcm
	beam.position = Vector3(0, -5.0, 0)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_color = Color(1.0, 0.95, 0.8, 0.07)
	beam.material_override = bmat
	beam.visible = false
	n.add_child(beam)
	n.set_meta("beam", beam)


## Ракета-камикадзе: тонкий корпус, красная боеголовка, 4 стабилизатора, полоса команды.
func _make_missile(team: int) -> Node3D:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var body := _pmat(Color(0.82, 0.82, 0.8), 1)
	var dark := _pmat(Color(0.22, 0.22, 0.25), 1)
	_part(n, "cyl", Vector3(0.38, 4.2, 0), Vector3(0, 2.6, 0), body)
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.38
	nm.height = 1.2
	nm.radial_segments = 12
	nose.mesh = nm
	nose.position = Vector3(0, 5.3, 0)
	nose.material_override = _pmat(Color(0.85, 0.18, 0.12), 0)
	n.add_child(nose)
	_part(n, "cyl", Vector3(0.4, 0.25, 0), Vector3(0, 4.3, 0), _pmat(Color(0.95, 0.8, 0.1), 0))   # пояс «опасно»
	_part(n, "cyl", Vector3(0.39, 0.3, 0), Vector3(0, 2.0, 0), _pmat(col, 0))                       # полоса команды
	for i in 4:
		var a := TAU * i / 4.0
		var fin := _part(n, "box", Vector3(0.06, 0.9, 0.55), Vector3(cos(a) * 0.55, 0.85, sin(a) * 0.55), dark)
		fin.rotation.y = -a
	_part(n, "cyl", Vector3(0.28, 0.35, 0), Vector3(0, 0.35, 0), dark)   # сопло
	_ship_fx(n, 0.3, 0.2)
	return n


## Истребитель F: реактивный самолёт в духе американских истребителей — фюзеляж, треугольные крылья,
## два киля, фонарь кабины, сопло. Стоит на хвосте (нос — вверх), как и остальные корабли.
func _make_jet(team: int) -> Node3D:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var grey := _pmat(Color(0.55, 0.58, 0.62), 1)
	var dark := _pmat(Color(0.3, 0.32, 0.36), 1)
	_part(n, "box", Vector3(0.75, 4.6, 0.6), Vector3(0, 2.6, 0), grey)                # фюзеляж
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.38
	nm.height = 1.3
	nm.radial_segments = 8
	nose.mesh = nm
	nose.position = Vector3(0, 5.55, 0)
	nose.material_override = dark
	n.add_child(nose)
	var canopy := _part(n, "box", Vector3(0.4, 1.0, 0.3), Vector3(0, 4.3, -0.38), _pmat(Color(0.3, 0.6, 0.85), 0))
	canopy.rotation_degrees = Vector3(-6, 0, 0)
	for sx in [-1.0, 1.0]:
		# треугольное крыло: два бруса под углом (широко у хвоста, узко к носу)
		var w1 := _part(n, "box", Vector3(2.1, 1.5, 0.08), Vector3(sx * 1.25, 1.7, 0), grey)
		w1.rotation_degrees = Vector3(0, 0, sx * -18.0)
		_part(n, "box", Vector3(0.9, 0.5, 0.06), Vector3(sx * 0.75, 3.0, 0), grey)
		_box(n, Vector3(0.6, 0.12, 0.09), Vector3(sx * 2.0, 1.2, 0), col, true)        # огни на законцовках
		var tail := _part(n, "box", Vector3(0.06, 1.1, 0.9), Vector3(sx * 0.35, 0.8, 0.55), grey)   # кили
		tail.rotation_degrees = Vector3(0, 0, sx * 14.0)
		_part(n, "box", Vector3(1.0, 0.6, 0.06), Vector3(sx * 0.75, 0.55, 0), dark)     # стабилизаторы
	_part(n, "box", Vector3(0.77, 0.4, 0.62), Vector3(0, 3.6, 0), _pmat(col, 0))      # полоса команды
	_part(n, "cyl", Vector3(0.32, 0.5, 0), Vector3(0, 0.15, 0), dark)                  # сопло
	_ship_fx(n, 0.3, 0.0)
	return n


var fighter_cd := 0.0   # клиент: когда истребитель снова сможет выстрелить (время мира)


func _fighter_fire() -> void:
	if piloting == null or world_time < fighter_cd:
		return
	fighter_cd = world_time + D.FIGHTER_CD
	var from := piloting.global_position + piloting.global_transform.basis.y.normalized() * 1.5
	var dir := piloting.global_transform.basis.y.normalized()   # стреляет по носу (вверх по оси тарелки)
	if is_server:
		server_ship_fire(1, piloting_id, from, dir)
	else:
		req_ship_fire.rpc_id(1, piloting_id, from, dir)


@rpc("any_peer", "call_remote", "reliable")
func req_ship_fire(id: int, from: Vector3, dir: Vector3) -> void:
	if multiplayer.is_server():
		server_ship_fire(multiplayer.get_remote_sender_id(), id, from, dir)


## Бластер истребителя: луч на 300 м, 400 урона — по кораблям, юнитам, игрокам, курьерам, постройкам.
func server_ship_fire(peer: int, id: int, from: Vector3, dir: Vector3) -> void:
	if not ships.has(id):
		return
	var sh: Dictionary = ships[id]
	if int(sh.pilot) != peer or int(sh.kind) != 2:
		return
	if world_time < float(sh.get("fire_t", -100.0)):
		return
	sh["fire_t"] = world_time + D.FIGHTER_CD - 0.5
	dir = dir.normalized()
	var pn: int = int(sh.pn)
	var best_t: float = D.FIGHTER_RANGE
	var hit := {}
	var cands: Array = []
	for o in ships.values():
		if int(o.team) != int(sh.team) and int(o.pn) == pn:
			cands.append([{"k": "ship", "ref": int(o.id)}, 2.2])
	for u in units:
		if int(u.team) != int(sh.team) and int(u.pn) == pn and int(u.hp) > 0:
			cands.append([{"k": "unit", "ref": u}, 1.6 if int(u.kind) >= D.U_MECH else 0.8])
	for pid in players:
		var po: Dictionary = players[pid]
		if int(po.team) != int(sh.team) and int(po.get("pn", -9)) == pn and int(po.hp) > 0:
			cands.append([{"k": "pid", "ref": pid}, 0.8])
	for r in rovers:
		if int(r.team) != int(sh.team) and int(r.pn) == pn:
			cands.append([{"k": "rover", "ref": r}, 1.0])
	if pn >= 0:
		for b in buildings.values():
			if int(b.team) != int(sh.team) and int(b.pn) == pn and _bpos(b).distance_to(from) < D.FIGHTER_RANGE + 5.0:
				cands.append([{"k": "bld", "ref": int(b.id)}, 1.0 + 0.4 * float(b.cells.size())])
	for c in cands:
		var tp = _tpos(c[0])
		if tp == null:
			continue
		var t := _ray_sphere(from, dir, Vector3(tp), float(c[1]))
		if t > 0.0 and t < best_t:
			best_t = t
			hit = c[0]
	if not hit.is_empty():
		_damage_tgt(hit, D.FIGHTER_DMG)
	if pn >= 0:
		_fx_beam(from, from + dir * best_t, 3, pn)


## Мощный взрыв: юниты, игроки, корабли, курьеры, постройки в радиусе r (урон к краю — 30%).
func _blast(at: Vector3, team: int, pn: int, r: float, dmg: int) -> void:
	var k := func(d: float) -> int: return int(float(dmg) * lerpf(1.0, 0.3, clampf(d / r, 0.0, 1.0)))
	for u in units:
		if u.team == team or u.hp <= 0 or u.pn != pn:
			continue
		var d := at.distance_to(_tpos({"k": "unit", "ref": u}))
		if d < r:
			u.hp -= k.call(d)
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == team or o.hp <= 0 or int(o.get("pn", -9)) != pn:
			continue
		var d := at.distance_to(Vector3(o.pos))
		if d < r:
			_damage_player(pid, k.call(d))
	for sh in ships.values():
		if int(sh.team) == team or int(sh.pn) != pn:
			continue
		var d := at.distance_to(Vector3(sh.pos))
		if d < r:
			_damage_ship(sh, k.call(d))
	for rv in rovers.duplicate():
		if int(rv.team) == team or int(rv.pn) != pn:
			continue
		var d := at.distance_to(_rpos(rv))
		if d < r:
			_damage_rover(rv, k.call(d))
	if pn >= 0:
		for b in buildings.values():
			if b.team == team or b.pn != pn or not buildings.has(b.id):
				continue
			var d := at.distance_to(_bpos(b))
			if d < r + 1.0:
				_damage_building(b, k.call(d))
				if finished:
					break
	for p in Net.ready_peers:
		fx_boom.rpc_id(p, at, r, false, pn)
	if not headless and pn == my_pn:
		_boom(at, r, false)


var jet_cd := 0.0   # клиент: когда истребитель F снова сможет пустить ракету


func _jet_fire() -> void:
	if piloting == null or world_time < jet_cd or piloting.pn < 0:
		return
	jet_cd = world_time + D.JET_CD
	var nose := piloting.global_transform.basis.y.normalized()
	var from := piloting.global_position + nose * 3.5
	var vel := piloting.vel + nose * D.JET_MISSILE_SPEED
	if is_server:
		server_jet_fire(1, piloting_id, from, vel)
	else:
		req_jet_fire.rpc_id(1, piloting_id, from, vel)


@rpc("any_peer", "call_remote", "reliable")
func req_jet_fire(id: int, from: Vector3, vel: Vector3) -> void:
	if multiplayer.is_server():
		server_jet_fire(multiplayer.get_remote_sender_id(), id, from, vel)


func server_jet_fire(peer: int, id: int, from: Vector3, vel: Vector3) -> void:
	if not ships.has(id):
		return
	var sh: Dictionary = ships[id]
	if int(sh.pilot) != peer or int(sh.kind) != 4 or int(sh.pn) < 0:
		return
	if world_time < float(sh.get("fire_t", -100.0)):
		return
	sh["fire_t"] = world_time + D.JET_CD - 0.5
	if vel.length() > D.JET_MISSILE_SPEED * 3.0:
		vel = vel.normalized() * D.JET_MISSILE_SPEED * 3.0
	var c := _pl(int(sh.pn)).walk(-1, from.normalized())
	_spawn_proj(from, vel, int(sh.team), 6, D.JET_MISSILE_DMG, 8.0, c, int(sh.pn))


## Разрывная ракета истребителя F: летит прямо, рвётся у любой вражеской цели или о землю.
func _missile_near(pr: Dictionary, at: Vector3) -> bool:
	for u in units:
		if u.team != pr.team and u.hp > 0 and u.pn == pr.pn and at.distance_to(_tpos({"k": "unit", "ref": u})) < 3.0:
			return true
	for sh in ships.values():
		if int(sh.team) != int(pr.team) and int(sh.pn) == int(pr.pn) and at.distance_to(Vector3(sh.pos)) < 4.0:
			return true
	for pid in players:
		var o: Dictionary = players[pid]
		if int(o.team) != int(pr.team) and int(o.get("pn", -9)) == int(pr.pn) and o.hp > 0 and at.distance_to(Vector3(o.pos)) < 2.5:
			return true
	return false


func _update_proj(delta: float) -> void:
	proj_time += delta
	var t := proj_time
	var n := mini(proj_pos.size(), mm_proj.instance_count)
	for i in n:
		var p0 := proj_pos[i]
		var v0 := proj_vel[i] if i < proj_vel.size() else Vector3.ZERO
		var k := int(proj_kind[i]) if i < proj_kind.size() else 0
		var p := p0 + v0 * t - p0.normalized() * (0.0 if k >= 5 else 0.5 * D.PROJ_G * t * t)
		var sc := 1.0 if k == 0 else 2.0
		mm_proj.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), p))
		var col := Color(1.0, 0.9, 0.4)
		if k == 3:
			col = Color(0.85, 0.85, 0.9)
		elif k == 4:
			col = Color(0.5, 1.0, 0.35)
		elif k == 5:
			col = Color(0.4, 0.75, 1.0)
		elif k == 6:
			col = Color(1.0, 0.45, 0.15)
		if k == 1:
			col = Color(1.0, 0.55, 0.2)
		elif k == 2:
			col = Color(0.45, 1.0, 0.3)
		mm_proj.set_instance_color(i, col)
	mm_proj.visible_instance_count = n


func _update_rovers(delta: float) -> void:
	var seen := {}
	rover_lights.clear()
	var k := minf(1.0, delta * 12.0)
	for e in cur_rovers:
		var id: int = e[0]
		var pos: Vector3 = e[1]
		var fwd: Vector3 = e[2]
		seen[id] = true
		if not rover_nodes.has(id):
			var nn := _make_rover(int(e[3]), int(e[6]) if e.size() > 6 else 0)
			nn.position = pos
			rover_nodes[id] = nn
		var node: Node3D = rover_nodes[id]
		var p := node.position.lerp(pos, k)
		var up := p.normalized()
		var f := fwd - up * fwd.dot(up)
		if f.length() < 0.001:
			f = _up_basis(up).z
		f = f.normalized()
		node.transform = Transform3D(Basis(f.cross(up), up, -f), p)
		var crate: Node3D = node.get_meta("crate")
		crate.visible = int(e[4]) > 0
		if rover_lights.size() < 24:
			rover_lights.append([p + up * 0.6, f])
	for id in rover_nodes.keys():
		if not seen.has(id):
			rover_nodes[id].queue_free()
			rover_nodes.erase(id)


## Ровер-курьер: шасси на шести колёсах, кабина с фарами, ящик с грузом.
func _make_rover(team: int, kind := 0) -> Node3D:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var body := _pmat(Color(0.82, 0.8, 0.72), 1)
	var dark := _pmat(Color(0.2, 0.2, 0.22), 1)
	_part(n, "box", Vector3(1.1, 0.3, 1.7), Vector3(0, 0.5, 0), body)
	_part(n, "box", Vector3(0.9, 0.45, 0.55), Vector3(0, 0.85, -0.5), body)
	_box(n, Vector3(0.7, 0.18, 0.05), Vector3(0, 0.92, -0.78), col, true)          # стекло кабины
	for sx in [-0.42, 0.42]:
		_box(n, Vector3(0.12, 0.08, 0.04), Vector3(sx, 0.55, -0.86), Color(1, 1, 0.85), true)   # фары
	for sx in [-0.62, 0.62]:
		for sz in [-0.6, 0.0, 0.6]:
			var w := _part(n, "cyl", Vector3(0.24, 0.16, 0), Vector3(sx, 0.24, sz), dark)
			w.rotation_degrees = Vector3(0, 0, 90)
	_part(n, "cyl", Vector3(0.015, 0.5, 0), Vector3(0.35, 1.3, -0.45), dark)
	_box(n, Vector3(0.06, 0.06, 0.06), Vector3(0.35, 1.56, -0.45), col, true)
	var crate: MeshInstance3D
	if kind == 1:
		# заправщик: цистерна He-3 (полная — светится полоса)
		var tank := _part(n, "cyl", Vector3(0.38, 1.0, 0), Vector3(0, 0.95, 0.35), _pmat(Color(0.7, 0.7, 0.75), 1))
		tank.rotation_degrees = Vector3(90, 0, 0)
		crate = _box(n, Vector3(0.8, 0.08, 0.6), Vector3(0, 1.35, 0.35), Color(0.8, 0.4, 1.0), true)
	else:
		crate = _part(n, "box", Vector3(0.85, 0.45, 0.8), Vector3(0, 0.88, 0.35), _pmat(Color(0.6, 0.45, 0.25), 1))
	crate.visible = false
	n.set_meta("crate", crate)
	local_root.add_child(n)
	return n


## Космонавт: скафандр, шлем с визором, ранец с антенной цвета команды.
## Правая рука вытянута вперёд, в ней — предмет (метка "hand").
func _make_avatar(team: int) -> Node3D:
	var n := Node3D.new()
	var body := Node3D.new()   # сам космонавт; на дальнем зуме прячется, вместо него — стрелка
	n.add_child(body)
	var col: Color = D.TEAM_COLORS[team]
	var suit := _pmat(SUIT_COLOR, 1)
	var dark := _pmat(Color(0.35, 0.36, 0.4), 1)
	# ноги и ботинки
	for sx in [-0.12, 0.12]:
		_part(body, "box", Vector3(0.18, 0.75, 0.2), Vector3(sx, 0.45, 0), suit)
		_part(body, "box", Vector3(0.2, 0.12, 0.28), Vector3(sx, 0.06, -0.03), dark)
	# корпус + полоса цвета команды
	_part(body, "box", Vector3(0.5, 0.62, 0.3), Vector3(0, 1.12, 0), suit)
	_part(body, "box", Vector3(0.52, 0.08, 0.32), Vector3(0, 1.02, 0), _pmat(col, 0))
	# ранец и антенна
	_part(body, "box", Vector3(0.42, 0.5, 0.18), Vector3(0, 1.15, 0.24), dark)
	_part(body, "cyl", Vector3(0.015, 0.35, 0.015), Vector3(0.14, 1.55, 0.26), dark)
	_box(body, Vector3(0.06, 0.06, 0.06), Vector3(0.14, 1.74, 0.26), col, true)
	# шлем и визор
	_part(body, "sphere", Vector3(0.24, 0.48, 0), Vector3(0, 1.62, 0), suit)
	_box(body, Vector3(0.32, 0.17, 0.08), Vector3(0, 1.64, -0.2), Color(1.0, 0.75, 0.3), true)
	# левая рука опущена
	_part(body, "box", Vector3(0.13, 0.55, 0.14), Vector3(-0.33, 1.1, 0), suit)
	# правая рука вытянута вперёд, в кисти — предмет
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0.33, 1.35, 0)
	shoulder.rotation_degrees = Vector3(70, 0, 0)
	body.add_child(shoulder)
	_part(shoulder, "box", Vector3(0.13, 0.55, 0.14), Vector3(0, -0.27, 0), suit)
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.58, 0)
	hand.rotation_degrees = Vector3(-70, 0, 0)
	shoulder.add_child(hand)
	n.set_meta("hand", hand)
	n.set_meta("held", -999)
	n.set_meta("team", team)
	var arrow := _make_arrow(col)
	n.add_child(arrow)
	n.set_meta("body", body)
	n.set_meta("arrow", arrow)
	local_root.add_child(n)
	return n


## Стрелка на поверхности: остриё вперёд (-Z), видна сквозь рельеф.
func _make_arrow(col: Color) -> MeshInstance3D:
	var v := PackedVector3Array([
		Vector3(0, 0, -1.3), Vector3(0.8, 0, 0.7), Vector3(0, 0, 0.25),
		Vector3(0, 0, -1.3), Vector3(0, 0, 0.25), Vector3(-0.8, 0, 0.7),
	])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.albedo_color = col.lightened(0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = m
	mi.position = Vector3(0, 0.4, 0)
	mi.visible = false
	return mi


## Вблизи — космонавт, издалека — стрелка (растёт с расстоянием, чтобы не теряться).
func _apply_far(node: Node3D, cam_d: float) -> void:
	var far := cam_d > FAR_VIEW
	var body: Node3D = node.get_meta("body")
	var arrow: Node3D = node.get_meta("arrow")
	body.visible = not far
	arrow.visible = far
	if far:
		arrow.scale = Vector3.ONE * clampf(cam_d / 35.0, 1.0, 120.0)


func _cam_dist(p: Vector3) -> float:
	var c := get_viewport().get_camera_3d()
	return c.global_position.distance_to(p) if c else 0.0


## Источники света для шейдера: включённые лампы на моей планете и слабое свечение построек
## поближе к камере (всего не больше MAX_LIGHTS).
func _update_lights() -> void:
	if lamp_img == null:
		lamp_img = Image.create(D.MAX_LIGHTS, 1, false, Image.FORMAT_RGBAF)
		lamp_tex_res = ImageTexture.create_from_image(lamp_img)
		RenderingServer.global_shader_parameter_set("lamp_tex", lamp_tex_res)
	var lamps: Array = []
	var glows: Array = []
	var cam_p := Vector3.ZERO
	var cam_now := get_viewport().get_camera_3d()
	if cam_now:
		cam_p = cam_now.global_position
	for b in buildings.values():
		if b.pn != my_pn or _busy(b):
			continue
		var t: int = b.type
		if t == D.LAMP:
			if b.lit:
				var up: Vector3 = planet.dirs[b.cell]
				lamps.append(planet.top_pos(b.cell) + up * 2.2)
		elif not BELT_TYPES.has(t) and t != D.WALL and t != D.POWER_POLE:
			var c := _foot_center(b.cells, int(b.pn))
			glows.append([c.distance_squared_to(cam_p), c + c.normalized() * 1.0, b.cells.size()])
	glows.sort_custom(func(x, y): return x[0] < y[0])
	var n := 0
	for p in lamps:
		if n >= D.MAX_LIGHTS:
			break
		lamp_img.set_pixel(n, 0, Color(p.x, p.y, p.z, D.LAMP_RADIUS))
		n += 1
	# фары юнитов и курьеров: пятно света перед машиной
	for e in unit_lights + rover_lights:
		if n >= D.MAX_LIGHTS - 16:
			break
		var lp: Vector3 = Vector3(e[0]) + Vector3(e[1]) * 2.6
		if lp.distance_to(cam_p) > 120.0:
			continue
		lamp_img.set_pixel(n, 0, Color(lp.x, lp.y, lp.z, D.HEADLIGHT_RADIUS))
		n += 1
	for g in glows:
		if n >= D.MAX_LIGHTS:
			break
		var pp: Vector3 = g[1]
		var rad: float = D.GLOW_RADIUS * (1.0 if int(g[2]) == 1 else 1.6)
		lamp_img.set_pixel(n, 0, Color(pp.x, pp.y, pp.z, -rad))
		n += 1
	lamp_tex_res.update(lamp_img)
	RenderingServer.global_shader_parameter_set("lamp_count", n)


## Свой космонавт виден только со стороны (вид сверху), от первого лица — нет.
func _update_self_avatar() -> void:
	if self_avatar == null:
		return
	var vis := player != null and not fps_mode and piloting == null and not player.dead
	self_avatar.visible = vis
	if not vis:
		return
	self_avatar.global_transform = player.global_transform
	if int(self_avatar.get_meta("held")) != sel_type:
		self_avatar.set_meta("held", sel_type)
		_set_held(self_avatar.get_meta("hand"), sel_type, my_team)
	_apply_far(self_avatar, _cam_dist(player.global_position))


## Деталь из примитива: "box" — size; "cyl" и "sphere" — (радиус, высота, -).
func _part(parent: Node3D, kind: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	if kind == "box":
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	elif kind == "cyl":
		var cm := CylinderMesh.new()
		cm.top_radius = size.x
		cm.bottom_radius = size.x
		cm.height = size.y
		cm.radial_segments = 6
		mesh = cm
	else:
		var sm := SphereMesh.new()
		sm.radius = size.x
		sm.height = size.y
		sm.radial_segments = 12
		sm.rings = 6
		mesh = sm
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m


## Уменьшенная модель того, что держишь: постройка или бластер.
func _make_held(type: int, team: int) -> Node3D:
	var n := Node3D.new()
	if type == D.WEAPON:
		_part(n, "box", Vector3(0.1, 0.12, 0.42), Vector3(0, 0, -0.1), _pmat(Color(0.45, 0.46, 0.5), 1))
		_part(n, "box", Vector3(0.08, 0.16, 0.08), Vector3(0, -0.1, 0.03), _pmat(Color(0.3, 0.3, 0.33), 1))
		_box(n, Vector3(0.06, 0.06, 0.06), Vector3(0, 0, -0.33), Color(1.0, 0.85, 0.3), true)
	else:
		var model := Node3D.new()
		_vis_shape(model, type, D.TEAM_COLORS[maxi(team, 0)])
		model.scale = Vector3.ONE * 0.18
		model.position = Vector3(0, -0.05, -0.05)
		n.add_child(model)
	return n


func _set_held(holder: Node3D, type: int, team: int) -> void:
	for c in holder.get_children():
		c.queue_free()
	holder.add_child(_make_held(type, team))


## Рука в перчатке внизу справа, прикреплена к камере.
func _build_viewmodel() -> void:
	viewmodel = Node3D.new()
	player.cam.add_child(viewmodel)
	var arm := Node3D.new()
	arm.position = Vector3(0.32, -0.3, -0.45)
	arm.rotation_degrees = Vector3(-15, 10, 0)
	viewmodel.add_child(arm)
	_part(arm, "box", Vector3(0.11, 0.11, 0.42), Vector3(0, -0.02, 0.12), _pmat(SUIT_COLOR, 1))
	_part(arm, "box", Vector3(0.12, 0.1, 0.12), Vector3(0, -0.02, -0.12), _pmat(Color(0.35, 0.36, 0.4), 1))
	vm_hand = Node3D.new()
	vm_hand.position = Vector3(0, 0.06, -0.2)
	arm.add_child(vm_hand)


func _update_viewmodel(delta: float) -> void:
	if viewmodel == null:
		return
	viewmodel.visible = fps_mode and not player.dead and not radial.is_open and piloting == null
	if sel_type != held_type:
		held_type = sel_type
		_set_held(vm_hand, sel_type, my_team)
	# покачивание при ходьбе
	var moving := player.velocity.length() > 0.5 and player.is_on_floor()
	vm_time += delta * (9.0 if moving else 2.0)
	var amp := 0.012 if moving else 0.004
	viewmodel.position = Vector3(cos(vm_time * 0.5) * amp, sin(vm_time) * amp, 0)


func _fire() -> void:
	var from := player.cam.global_position
	var dir := player.look_dir()
	var b := player.cam.global_transform.basis
	var muzzle := from + b.x * 0.25 - b.y * 0.2 + dir * 0.5
	_tracer(muzzle, from + dir * D.GUN_RANGE)
	if is_server:
		server_shoot(1, from, dir)
	else:
		req_shoot.rpc_id(1, from, dir)


## Вспышка взрыва: светящийся шар быстро раздувается и гаснет.
func _boom(at: Vector3, r: float, uranium: bool) -> void:
	if headless:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := Color(0.5, 1.0, 0.3) if uranium else Color(1.0, 0.6, 0.2)
	m.albedo_color = Color(c.r, c.g, c.b, 0.8)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	mi.position = at
	mi.scale = Vector3.ONE * 0.5
	local_root.add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * r * 0.6, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(mi.queue_free)


func _tracer(a: Vector3, b: Vector3, col := Color(1.0, 0.85, 0.3)) -> void:
	if headless:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat(col, true))
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	local_root.add_child(mi)
	get_tree().create_timer(0.08).timeout.connect(mi.queue_free)


# ---------------------------------------------------------------------
# Интерфейс: панель справа — значки, полоски, цифры. Тревоги — сверху, подсказки — снизу.
# ---------------------------------------------------------------------

func _icon_rect(id: int, px := 22) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = icon_atlas
	var c := Icons.cell_of(id)
	at.region = Rect2(c.x * Icons.SIZE, c.y * Icons.SIZE, Icons.SIZE, Icons.SIZE)
	var tr := TextureRect.new()
	tr.texture = at
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(px, px)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _set_icon(tr: TextureRect, id: int) -> void:
	var c := Icons.cell_of(id)
	(tr.texture as AtlasTexture).region = Rect2(c.x * Icons.SIZE, c.y * Icons.SIZE, Icons.SIZE, Icons.SIZE)


func _ui_label(size := 13, col := Color(0.85, 0.87, 0.9)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(col: Color, h := 10) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.custom_minimum_size = Vector2(40, h)
	pb.add_theme_font_size_override("font_size", 1)   # высоту задаём сами, а не по шрифту
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	bg.border_color = Color(1, 1, 1, 0.18)
	bg.set_border_width_all(1)
	bg.set_content_margin_all(0)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.border_color = Color(0, 0, 0, 0.0)
	fg.set_border_width_all(1)   # заливка внутри рамки, а не поверх
	fg.set_content_margin_all(0)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


func _bar_color(pb: ProgressBar, col: Color) -> void:
	(pb.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = col


## Строка панели: [значок][полоска][число].
func _ui_row(parent: Control, icon_id: int, col: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon_rect(icon_id)
	row.add_child(ic)
	var bar := _bar(col)
	row.add_child(bar)
	var num := _ui_label(13)
	num.custom_minimum_size.x = 70
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(num)
	parent.add_child(row)
	return {"row": row, "bar": bar, "num": num, "icon": ic}


func _ui_section(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


func _ui_sep(parent: Control) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.12)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Строка без полоски — для величин без предела (высота, скорость): [значок][число].
func _ui_stat(parent: Control, icon_id: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon_rect(icon_id))
	var num := _ui_label(14, Color(1, 1, 1))
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(num)
	parent.add_child(row)
	return {"row": row, "num": num}


func _build_panel(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -290
	panel.offset_right = -12
	panel.offset_top = 12
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(root)
	ui.panel = panel

	# --- состояние: планета, здоровье, свет, энергия, базы
	var top := _ui_section(root)
	ui.top = top
	ui.planet = _ui_label(15, Color(1, 1, 1))
	top.add_child(ui.planet)
	ui.hp = _ui_row(top, Icons.UI_HEART, Color(0.9, 0.2, 0.25))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 6)
	lrow.add_child(_icon_rect(Icons.UI_SUN))
	var segs := HBoxContainer.new()
	segs.add_theme_constant_override("separation", 2)
	segs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var seg_list: Array = []
	for i in D.LIGHT_LEVELS:
		var sq := ColorRect.new()
		sq.custom_minimum_size = Vector2(9, 10)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segs.add_child(sq)
		seg_list.append(sq)
	lrow.add_child(segs)
	var ln := _ui_label(13)
	ln.custom_minimum_size = Vector2(40, 0)
	ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lrow.add_child(ln)
	ui.light_num = ln
	top.add_child(lrow)
	ui.light = seg_list
	ui.power = _ui_row(top, Icons.UI_BOLT, Color(1.0, 0.85, 0.2))
	ui.battery = _ui_row(top, Icons.UI_BATTERY, Color(0.3, 1.0, 0.5))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 3)
	brow.add_child(_icon_rect(Icons.UI_CORE))
	var bases := HBoxContainer.new()
	bases.add_theme_constant_override("separation", 3)
	bases.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(bases)
	top.add_child(brow)
	ui.bases = bases

	# --- склад
	ui.seps = [_ui_sep(root)]
	var store := GridContainer.new()
	store.columns = 3
	store.add_theme_constant_override("h_separation", 8)
	store.add_theme_constant_override("v_separation", 4)
	store.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(store)
	ui.store_box = store
	var cells := {}
	for it in D.CORE_ACCEPT:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.custom_minimum_size.x = 82
		cell.add_child(_icon_rect(it, 20))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var num := _ui_label(12)
		vb.add_child(num)
		var bar := _bar(Color(0.6, 0.75, 0.9), 4)
		vb.add_child(bar)
		cell.add_child(vb)
		store.add_child(cell)
		cells[it] = {"box": cell, "num": num, "bar": bar}
	ui.store = cells
	var cr := _ui_label(13, Color(1.0, 0.85, 0.3))
	cr.text = "КРЕАТИВ ∞"
	root.add_child(cr)
	ui.creative = cr

	# --- юниты: количество / лимит
	ui.seps.append(_ui_sep(root))
	var us := _ui_section(root)
	ui.units_box = us
	ui.units = [_ui_row(us, Icons.UI_TANK, Color(0.55, 0.8, 0.6)), _ui_row(us, Icons.UI_DRONE, Color(0.55, 0.8, 0.6)),
		_ui_row(us, Icons.UI_MECH, Color(0.55, 0.8, 0.6)), _ui_row(us, Icons.UI_MECH, Color(0.4, 0.65, 1.0))]

	# --- в руках: название и цена (значки ресурсов, красным — не хватает)
	ui.seps.append(_ui_sep(root))
	var held := _ui_section(root)
	ui.held_box = held
	ui.held_name = _ui_label(15, Color(1, 1, 1))
	held.add_child(ui.held_name)
	var cost := HBoxContainer.new()
	cost.add_theme_constant_override("separation", 8)
	held.add_child(cost)
	ui.held_cost = cost
	ui.held_key = -2

	# --- под прицелом: карточка слева от прицела
	var ipanel := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	isb.border_color = Color(1, 1, 1, 0.1)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(4)
	isb.set_content_margin_all(8)
	ipanel.add_theme_stylebox_override("panel", isb)
	ipanel.anchor_left = 0.5
	ipanel.anchor_right = 0.5
	ipanel.anchor_top = 0.5
	ipanel.anchor_bottom = 0.5
	ipanel.offset_left = -330
	ipanel.offset_right = -36
	ipanel.offset_top = -40
	ipanel.offset_bottom = -40
	ipanel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ipanel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ipanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ipanel)
	ui.ipanel = ipanel
	var iroot := VBoxContainer.new()
	iroot.add_theme_constant_override("separation", 4)
	iroot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ipanel.add_child(iroot)
	var insp := _ui_section(iroot)
	ui.insp = insp
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(dot)
	ui.insp_dot = dot
	ui.insp_name = _ui_label(15, Color(1, 1, 1))
	head.add_child(ui.insp_name)
	insp.add_child(head)
	ui.insp_hp = _ui_row(insp, Icons.UI_HEART, Color(0.9, 0.2, 0.25))
	ui.insp_prog = _ui_row(insp, Icons.UI_CLOCK, Color(0.3, 0.9, 0.4))
	var items := HFlowContainer.new()
	items.add_theme_constant_override("h_separation", 8)
	insp.add_child(items)
	ui.insp_items = items
	ui.insp_key = ""
	var itx := _ui_label(12, Color(0.7, 0.72, 0.76))
	itx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	itx.custom_minimum_size = Vector2(250, 0)
	insp.add_child(itx)
	ui.insp_text = itx
	var ore := HBoxContainer.new()
	ore.add_theme_constant_override("separation", 6)
	ui.ore_icon = _icon_rect(D.I_COAL_ORE)
	ore.add_child(ui.ore_icon)
	ui.ore_text = _ui_label(13)
	ore.add_child(ui.ore_text)
	iroot.add_child(ore)
	ui.ore = ore

	# --- корабль
	var ship := _ui_section(root)
	ui.ship = ship
	ui.ship_name = _ui_label(15, Color(1, 1, 1))
	ship.add_child(ui.ship_name)
	ui.s_fuel = _ui_row(ship, D.I_FUEL, Color(0.75, 0.4, 0.95))
	ui.s_dv = _ui_row(ship, Icons.UI_DV, Color(1.0, 0.6, 0.25))
	ui.s_hull = _ui_row(ship, Icons.UI_HULL, Color(0.6, 0.7, 0.85))
	ui.s_cargo = _ui_row(ship, Icons.UI_CARGO, Color(0.8, 0.65, 0.35))
	_ui_sep(ship)
	ui.s_alt = _ui_stat(ship, Icons.UI_ALT)
	ui.s_speed = _ui_stat(ship, Icons.UI_SPEED)
	ui.s_ap = _ui_stat(ship, Icons.UI_CLOCK)
	ui.s_pe = _ui_stat(ship, Icons.UI_CLOCK)
	var stx := _ui_label(12, Color(0.75, 0.78, 0.82))
	stx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stx.custom_minimum_size = Vector2(250, 0)
	ship.add_child(stx)
	ui.s_text = stx

	# --- сверху по центру: тревоги и захват
	var topc := VBoxContainer.new()
	topc.anchor_left = 0.5
	topc.anchor_right = 0.5
	topc.offset_left = -260
	topc.offset_right = 260
	topc.offset_top = 56
	topc.alignment = BoxContainer.ALIGNMENT_BEGIN
	topc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(topc)
	ui.alerts = _ui_label(16, Color(1.0, 0.35, 0.3))
	ui.alerts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topc.add_child(ui.alerts)
	var cap := VBoxContainer.new()
	ui.cap_text = _ui_label(14, Color(1, 1, 1))
	ui.cap_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(ui.cap_text)
	ui.cap_bar = _bar(Color(1.0, 0.85, 0.2), 12)
	cap.add_child(ui.cap_bar)
	topc.add_child(cap)
	ui.cap = cap

	# --- баннер тревоги: вражеский корабль в зоне притяжения нашей планеты
	var ban := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.55, 0.05, 0.03, 0.85)
	bsb.border_color = Color(1.0, 0.85, 0.2)
	bsb.set_border_width_all(3)
	bsb.set_corner_radius_all(4)
	bsb.set_content_margin_all(12)
	ban.add_theme_stylebox_override("panel", bsb)
	ban.anchor_left = 0.5
	ban.anchor_right = 0.5
	ban.offset_left = -330
	ban.offset_right = 330
	ban.offset_top = 120
	ban.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ban.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ban.visible = false
	layer.add_child(ban)
	var bl := _ui_label(24, Color(1.0, 0.95, 0.8))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ban.add_child(bl)
	ui.banner = ban
	ui.banner_text = bl
	ui.banner_until = 0.0
	ui.banner_msg = ""

	# --- гибель: выбор базы для возрождения
	var dp := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.08, 0.02, 0.02, 0.8)
	dsb.border_color = Color(1.0, 0.3, 0.25, 0.5)
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(6)
	dsb.set_content_margin_all(16)
	dp.add_theme_stylebox_override("panel", dsb)
	dp.anchor_left = 0.5
	dp.anchor_right = 0.5
	dp.anchor_top = 0.5
	dp.anchor_bottom = 0.5
	dp.offset_left = -200
	dp.offset_right = 200
	dp.offset_top = -150
	dp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dp.visible = false
	layer.add_child(dp)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dp.add_child(dv)
	var dt := _ui_label(34, Color(1.0, 0.35, 0.3))
	dt.text = "ТЫ ПОГИБ"
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(dt)
	ui.death_timer = _ui_label(16, Color(1, 1, 1))
	(ui.death_timer as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(ui.death_timer)
	ui.death_bar = _bar(Color(1.0, 0.35, 0.3), 8)
	dv.add_child(ui.death_bar)
	var dl := _ui_label(13, Color(0.8, 0.8, 0.85))
	dl.text = "Где возродиться (щелчок или цифра):"
	dv.add_child(dl)
	var dbases := VBoxContainer.new()
	dbases.add_theme_constant_override("separation", 4)
	dv.add_child(dbases)
	ui.death_bases = dbases
	ui.death = dp

	# --- снизу по центру: подсказка, что можно сделать сейчас
	var hint := _ui_label(15, Color(1, 1, 1))
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -64
	hint.offset_bottom = -36
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(hint)
	ui.hint = hint


## Мои базы для возрождения: главная первой, потом по планетам.
func _my_cores() -> Array:
	var out: Array = []
	for b in buildings.values():
		if b.type == D.CORE and int(b.team) == my_team:
			out.append(b)
	out.sort_custom(_core_order)
	return out


func _core_order(x: Dictionary, y: Dictionary) -> bool:
	if bool(x.main) != bool(y.main):
		return bool(x.main)
	return int(x.pn) < int(y.pn)


func _on_death() -> void:
	death_t = 0.0
	death_pick = -1
	death_pos = player.global_position
	death_pn = my_pn
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	big_msg.text = ""
	_fill_death_bases()


func _on_revive() -> void:
	death_t = -1.0
	ui.death.visible = false
	if fps_mode and piloting == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _fill_death_bases() -> void:
	var box: VBoxContainer = ui.death_bases
	for ch in box.get_children():
		ch.queue_free()
	var cores := _my_cores()
	for i in mini(cores.size(), 9):
		var c: Dictionary = cores[i]
		var btn := Button.new()
		btn.text = "%d   %s%s" % [i + 1, D.PLANETS[int(c.pn)].name, "  · главная" if c.main else ""]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 16)
		btn.set_meta("core", int(c.id))
		btn.pressed.connect(_choose_base.bind(int(c.id)))
		box.add_child(btn)


func _choose_base(core_id: int) -> void:
	if death_t < 0.0 or death_t > D.CHOOSE_TICKS * D.TICK:
		return
	death_pick = core_id
	if is_server:
		server_choose_base(1, core_id)
	else:
		req_choose_base.rpc_id(1, core_id)


## Пока мёртв: таймер, кнопки баз (5 с на выбор), какая база будет по умолчанию.
func _update_death(delta: float) -> void:
	if death_t < 0.0 or ui.is_empty():
		return
	death_t += delta
	ui.death.visible = not finished
	var total: float = D.RESPAWN_TICKS * D.TICK
	var window: float = D.CHOOSE_TICKS * D.TICK
	var left := maxf(total - death_t, 0.0)
	var ttxt := "Возрождение через %d с" % int(ceil(left))
	ui.death_bar.value = 1.0 - left / total
	var choosing := death_t < window
	# по умолчанию — ближайшая (то же правило, что на сервере)
	var auto = _respawn_core({"team": my_team, "pn": death_pn, "pos": death_pos, "spawn_core": death_pick})
	var auto_id: int = int(auto.id) if auto != null else -1
	for btn in (ui.death_bases as Control).get_children():
		var b := btn as Button
		var cid: int = b.get_meta("core")
		b.disabled = not choosing
		var mark := ""
		if cid == death_pick:
			mark = "   ◀ выбрано"
		elif death_pick == -1 and cid == auto_id:
			mark = "   ◀ ближайшая" if choosing else "   ◀ ближайшая (по умолчанию)"
		var base_txt: String = b.text.split("   ◀")[0]
		b.text = base_txt + mark
	if not choosing:
		ttxt += "   · выбор закрыт"
	ui.death_timer.text = ttxt


func _set_row(r: Dictionary, frac: float, txt: String) -> void:
	(r.bar as ProgressBar).value = clampf(frac, 0.0, 1.0)
	(r.num as Label).text = txt


func _update_hud() -> void:
	if my_team < 0 or ui.is_empty():
		return
	_update_banner()
	var alert_txt := "\n".join(_alert_lines())
	ui.alerts.text = alert_txt
	ui.alerts.visible = alert_txt != ""
	var flying := piloting != null
	for k in ["top", "store_box", "units_box", "held_box"]:
		(ui[k] as Control).visible = not flying
	for sp in ui.seps:
		(sp as Control).visible = not flying
	ui.ship.visible = flying
	ui.creative.visible = creative and not flying
	var hints := PackedStringArray()
	if flying:
		ui.insp.visible = false
		ui.ore.visible = false
		ui.ipanel.visible = false
		ui.cap.visible = false
		_update_ship_panel()
		if map_mode != 0:
			hints.append("КАРТА: %s   M — дальше, колесо — масштаб" % ["", "орбита вокруг планеты", "звёздная система"][map_mode])
		ui.hint.text = "\n".join(hints)
		return

	# состояние
	var lvl := light_level_at(player.global_position) if player else 0
	var eclipse := not sky_state.is_empty() and float(sky_state.sun_level) < 0.5
	ui.planet.text = String(D.PLANETS[my_pn].name) + ("   · затмение" if eclipse else "")
	_set_row(ui.hp, float(my_hp) / float(D.PLAYER_HP), str(my_hp))
	for i in D.LIGHT_LEVELS:
		var sq: ColorRect = ui.light[i]
		sq.color = Color(1.0, 0.85, 0.3).lerp(Color(1, 1, 0.9), float(i) / 16.0) if i < lvl else Color(1, 1, 1, 0.1)
	ui.light_num.text = "%d" % lvl
	var pw: Array = power_stats[my_team]
	var prod := float(pw[0])
	var dem := float(pw[1])
	_set_row(ui.power, 1.0 if dem <= 0.0 else prod / dem, "%d / %d" % [int(prod), int(dem)])
	_bar_color(ui.power.bar, Color(1.0, 0.85, 0.2) if prod >= dem else Color(1.0, 0.35, 0.2))
	var bcap: float = float(pw[3]) if pw.size() > 3 else 0.0
	(ui.battery.row as Control).visible = bcap > 0.0
	if bcap > 0.0:
		_set_row(ui.battery, float(pw[2]) / bcap, "%d / %d" % [int(pw[2]), int(bcap)])
	# базы: квадратики своего цвета, затем врага
	var want := int(base_count[my_team]) + int(base_count[1 - my_team])
	var box: HBoxContainer = ui.bases
	if box.get_child_count() != want or box.get_meta("mine", -1) != int(base_count[my_team]):
		for ch in box.get_children():
			ch.queue_free()
		for i in want:
			var sq := ColorRect.new()
			sq.custom_minimum_size = Vector2(14, 14)
			sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sq.color = D.TEAM_COLORS[my_team] if i < int(base_count[my_team]) else D.TEAM_COLORS[1 - my_team].darkened(0.2)
			box.add_child(sq)
		box.set_meta("mine", int(base_count[my_team]))

	# склад
	var st: Dictionary = storage[my_team]
	for it in ui.store:
		var c: Dictionary = ui.store[it]
		var n := int(st.get(it, 0))
		(c.box as Control).modulate = Color(1, 1, 1, 1.0 if n > 0 or creative else 0.35)
		(c.num as Label).text = "∞" if creative else str(n)
		(c.bar as ProgressBar).value = 1.0 if creative else float(n) / float(D.CORE_CAP)
		_bar_color(c.bar, Color(1.0, 0.45, 0.25) if n >= D.CORE_CAP else Color(0.6, 0.75, 0.9))

	# юниты
	if unit_stat.size() > my_team:
		var u: Array = unit_stat[my_team]
		var nk := D.UNIT_NAMES.size()
		for k in mini(nk, ui.units.size()):
			var lim := maxi(int(u[k + nk]), 1)
			_set_row(ui.units[k], float(u[k]) / float(lim), "%d / %d" % [int(u[k]), int(u[k + nk])])

	# в руках
	if ui.held_key != sel_type:
		ui.held_key = sel_type
		ui.held_name.text = "Бластер" if sel_type == D.WEAPON else String(D.NAMES[sel_type])
		for ch in (ui.held_cost as Control).get_children():
			ch.queue_free()
		if sel_type != D.WEAPON:
			var cost: Dictionary = D.COST[sel_type]
			for it in cost:
				var hb := HBoxContainer.new()
				hb.add_theme_constant_override("separation", 2)
				hb.add_child(_icon_rect(it, 18))
				var l := _ui_label(13)
				l.text = str(cost[it])
				l.set_meta("item", it)
				l.set_meta("need", int(cost[it]))
				hb.add_child(l)
				(ui.held_cost as Control).add_child(hb)
	for hb in (ui.held_cost as Control).get_children():
		if hb.get_child_count() < 2:
			continue
		var l: Label = hb.get_child(1)
		var ok := creative or int(st.get(int(l.get_meta("item")), 0)) >= int(l.get_meta("need"))
		l.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9) if ok else Color(1.0, 0.3, 0.25))

	# захват
	var cap_line := _capture_hint()
	ui.cap.visible = cap_line != ""
	ui.cap_text.text = cap_line
	ui.cap_bar.visible = cap_frac >= 0.0
	ui.cap_bar.value = maxf(cap_frac, 0.0)

	# под прицелом
	var show_insp := false
	ui.ore.visible = false
	if hover_cell != NO_CELL:
		if grid.has(_k(my_pn, hover_cell)):
			var b: Dictionary = buildings[grid[_k(my_pn, hover_cell)]]
			show_insp = true
			var info: Array = inspect_info if inspect_info.size() >= 7 \
					and int(grid.get(_k(my_pn, inspect_cell), -1)) == int(b.id) else []
			_fill_inspect(b, info)
			if _hover_own(D.UNLOADER) or _hover_own(D.SORTER):
				hints.append("E (держать) — выбрать груз")
			if _hover_own(D.SPACE_DOCK):
				hints.append("E (держать) — куда летит космический курьер")
			if _hover_own(D.LAUNCH_PAD):
				hints.append("E (держать) — собрать корабль")
			if _hover_own(D.ASSEMBLER):
				hints.append("E (держать) — выбрать юнита")
			if _hover_own(D.LAMP):
				hints.append("E — вкл/выкл лампу,  Shift+E — все свои лампы на планете")
			if _hover_upgradable():
				if int(b.lvl) >= D.UPG_MAX:
					hints.append("Максимальный уровень модернизации")
				else:
					hints.append("U — модернизировать до ур. %d (скорость ×%.1f): %s" % [int(b.lvl) + 1,
						float(D.UPG_SPEED[int(b.lvl)]), _cost_dict_text(_upgrade_cost(b))])
		else:
			var dep: int = planet.ore[hover_cell]
			if planet.level[hover_cell] >= D.MAX_LEVEL:
				ui.ore.visible = true
				ui.ore_icon.visible = false
				ui.ore_text.text = "Скалы — строить нельзя"
			elif _arc(hover_cell, planet.core_center[1 - my_team]) < D.ENEMY_ZONE:
				ui.ore.visible = true
				ui.ore_icon.visible = false
				ui.ore_text.text = "Зона вражеского ядра"
			elif dep != D.I_NONE:
				ui.ore.visible = true
				ui.ore_icon.visible = true
				_set_icon(ui.ore_icon, dep)
				ui.ore_text.text = String(D.ITEM_NAMES[dep]) + ("  · Бур II+" if D.RARE_ORES.has(dep) else "")
	ui.insp.visible = show_insp
	ui.ipanel.visible = show_insp or ui.ore.visible

	if not fps_mode:
		if selected.is_empty():
			hints.append("Ctrl + рамка — выделить юнитов   ·   строить с карты нельзя")
		else:
			hints.append("Выбрано %d:  1 агрессия · 2 охрана · 3 стоять · ПКМ — точка охраны" % selected.size())
	if _near_ship() != -1:
		hints.append("E — сесть в корабль")
	ui.hint.text = "\n".join(hints)


## Баннер «ВНИМАНИЕ»: пока вражеский корабль в сфере притяжения планеты, где наша база или мы сами,
## и ещё 8 с после тревоги о входе в атмосферу. Мигает.
func _update_banner() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var names := PackedStringArray()
	for pn in threat_pns:
		if pn >= 0 and pn < D.PLANETS.size():
			names.append(String(D.PLANETS[pn].name))
	var txt := ""
	if not names.is_empty():
		txt = "⚠ ВНИМАНИЕ! ПРОТИВНИК В ЗОНЕ ПРИТЯЖЕНИЯ: " + ", ".join(names)
	elif float(ui.banner_until) > now:
		txt = String(ui.banner_msg)
	var ban: Control = ui.banner
	ban.visible = txt != "" and not finished
	if ban.visible:
		ui.banner_text.text = txt
		ban.modulate.a = 0.65 + 0.35 * absf(sin(now * 4.0))


## Карточка постройки под прицелом. info от сервера может опаздывать — тогда только то, что знаем сами.
func _fill_inspect(b: Dictionary, info: Array) -> void:
	var t: int = b.type
	ui.insp_name.text = String(D.NAMES[t]) + (("  · ур. %d" % int(b.lvl)) if D.UPGRADABLE.has(t) else "")
	var state := ST_IDLE
	var txt := ""
	var hp := 1.0
	var prog := -1.0
	var items := PackedInt32Array()
	if not info.is_empty():
		state = int(info[1])
		txt = String(info[2])
		hp = float(info[3])
		prog = float(info[4])
		items = info[5]
	if _busy(b):
		prog = clampf(_shown_bt(b), 0.0, 1.0)
	(ui.insp_dot as ColorRect).color = STATE_COLORS[clampi(state, 0, 3)]
	ui.insp_name.add_theme_color_override("font_color", D.TEAM_COLORS[b.team].lightened(0.4))
	_set_row(ui.insp_hp, hp, "%d%%" % int(hp * 100.0))
	(ui.insp_hp.row as Control).visible = hp < 0.999 or _busy(b)
	(ui.insp_prog.row as Control).visible = prog >= 0.0
	if prog >= 0.0:
		_set_row(ui.insp_prog, prog, "%d%%" % int(prog * 100.0))
		var pc := Color(1.0, 0.55, 0.15) if b.decon else Color(0.3, 0.9, 0.4)
		_bar_color(ui.insp_prog.bar, pc)
	ui.insp_text.text = txt
	var key := str(items)
	if key != ui.insp_key:
		ui.insp_key = key
		for ch in (ui.insp_items as Control).get_children():
			ch.queue_free()
		for i in range(0, items.size() - 1, 2):
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 2)
			hb.add_child(_icon_rect(items[i], 18))
			var l := _ui_label(13)
			l.text = str(items[i + 1])
			hb.add_child(l)
			(ui.insp_items as Control).add_child(hb)


func _update_ship_panel() -> void:
	var sh := piloting
	var up := sh.global_position.normalized()
	var kind: int = sh.kind
	var tank: float = D.SHIP_KINDS[kind].tank
	ui.ship_name.text = String(D.SHIP_KINDS[kind].name)
	_set_row(ui.s_fuel, sh.fuel / tank, "%.1f / %d" % [sh.fuel, int(tank)])
	var dv_full := _ship_dv(tank, kind)
	_set_row(ui.s_dv, sh.dv() / maxf(dv_full, 1.0), "%d м/с" % int(sh.dv()))
	var hull := 1.0
	var used := 0
	for e in cur_ships:
		if int(e[0]) == piloting_id:
			if e.size() > 10:
				hull = float(e[10])
			if e.size() > 9:
				used = int(e[9])
	_set_row(ui.s_hull, hull, "%d%%" % int(hull * 100.0))
	_bar_color(ui.s_hull.bar, Color(0.6, 0.7, 0.85) if hull > 0.5 else Color(1.0, 0.3, 0.2))
	var cargo: int = D.SHIP_KINDS[kind].cargo
	(ui.s_cargo.row as Control).visible = cargo > 0
	_set_row(ui.s_cargo, float(used) / float(cargo), "%d / %d" % [used, cargo])
	var soi: float = SkyCalc.soi(sh.pn) if sh.pn >= 0 else 1.0
	ui.s_alt.num.text = "высота %d м" % int(sh.altitude())
	var vv := sh.vel.dot(up)
	ui.s_speed.num.text = "%d м/с   верт. %+d" % [int(sh.vel.length()), int(vv)]
	var orb := sh.orbit()
	var oi := sh.orbit_info()
	var has_orb: bool = not orb.is_empty() and not sh.landed
	(ui.s_ap.row as Control).visible = has_orb
	(ui.s_pe.row as Control).visible = has_orb
	if has_orb:
		var tap := ("   через %d с" % int(oi.t_ap)) if not oi.is_empty() else ""
		var tpe := ("   через %d с" % int(oi.t_pe)) if not oi.is_empty() else ""
		ui.s_ap.num.text = "Ап %d м%s" % [int(orb[0]), tap]
		ui.s_pe.num.text = "Пе %d м%s" % [int(orb[1]), tpe]
	var lines := PackedStringArray()
	if sh.landed:
		lines.append("На поверхности")
	elif orb.is_empty():
		lines.append("Уход от " + ("планеты" if sh.pn >= 0 else "гиганта"))
	elif float(orb[1]) > 5.0:
		lines.append("Орбита")
	else:
		lines.append("Суборбита — подними перицентр выше 5 м")
	if sh.pn >= 0:
		var soi_txt := "%s, граница %d м" % [D.PLANETS[sh.pn].name, int(soi)]
		if float(pred.get("exit_t", -1.0)) >= 0.0:
			soi_txt += ", выход через %d с" % int(pred.exit_t)
		lines.append(soi_txt)
	else:
		lines.append("Открытый космос")
	if int(pred.get("enc", -1)) != -1:
		lines.append("Сближение: %s через %d с" % [D.PLANETS[int(pred.enc)].name, int(pred.enc_t)])
	elif bool(pred.get("impact", false)):
		lines.append("Траектория пересекает поверхность")
	if kind == 2:
		var cdl := fighter_cd - world_time
		lines.append("Бластер (F): " + ("ГОТОВ" if cdl <= 0.0 else "перезарядка %d с" % int(ceil(cdl))))
	elif kind == 3:
		lines.append("F — подрыв (взрыв %d м). Врезался — тоже взрыв" % int(D.KAMIKAZE_R))
	elif kind == 4:
		var jcd := jet_cd - world_time
		lines.append("Ракета (F): " + ("ГОТОВА" if jcd <= 0.0 else "перезарядка %d с" % int(ceil(jcd))) + ("" if sh.pn >= 0 else " (только у планеты)"))
	lines.append("")
	lines.append_array(_plan_lines())
	ui.s_text.text = "\n".join(lines)


## Строки активных тревог (упакованные массивы в GDScript передаются по значению — поэтому возвращаем).
func _alert_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var now := Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	for a in alerts:
		if float(a[1]) > now:
			keep.append(a)
			out.append("!!! " + String(a[0]))
	alerts = keep
	return out


## Подсказка про захват, если стоишь рядом с чужим ядром.
var cap_frac := -1.0   # прогресс захвата для полоски (-1 — полоски нет)


func _capture_hint() -> String:
	cap_frac = -1.0
	if player == null:
		return ""
	for e in cur_caps:
		var id: int = e[0]
		if not buildings.has(id):
			continue
		var team: int = e[1]
		if team == my_team:
			continue
		var d := player.global_position.distance_to(_bpos(buildings[id]))
		if d > D.CAPTURE_RADIUS * 2.0:
			continue
		if team == D.T_NEUTRAL:
			if int(e[2]) >= 0:
				cap_frac = float(e[3])
				return "ЗАХВАТ БАЗЫ: %s %d%%%s" % [D.TEAM_NAMES[int(e[2])], int(float(e[3]) * 100.0),
					"" if d < D.CAPTURE_RADIUS else "  (подойди ближе к ядру)"]
			return "Нейтральная база: встань у ядра (ближе %d м), чтобы захватить" % int(D.CAPTURE_RADIUS)
		cap_frac = float(e[4])
		return "Вражеская база: разрушь ядро — оно станет нейтральным"
	return ""


func _build_help() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible = false
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.text = """УПРАВЛЕНИЕ

Ходьба                      WASD
Прыжок / бег                Space / Shift
Фонарик                     F
Меню построек               держать Z: мышь — группа, колесо — подтип
Быстрый выбор группы        1–7,  бластер — 8
Корабль                     E на площадке — собрать, E рядом — сесть, G — выйти
Перелёт к другой планете         в корабле T — выбрать цель: окно, Δv, ◆ на навболе — куда жечь
Модернизация завода         U на своём заводе (до ур. 3)
В полёте                    Shift/Ctrl — дроссель, Z — полный, X — ноль, Space — полная тяга пока держишь
                            W/S A/D Q/E — повороты, мышь — камера
Автопилот ориентации        1 выкл, 2 по движению, 3 против, 4 нормаль, 5 антинормаль, 6/7 радиально
Самоуничтожение             Backspace дважды
Карта в корабле             M (орбита -> система), колесо — масштаб
Груз точки выгрузки         навестись и держать E
Повернуть постройку         R
Строить / снести            ЛКМ (можно тянуть) / ПКМ
Вид сверху                  Tab  (WASD — крутить планету, колесо — зум; строить с карты нельзя)
Отпустить курсор            Esc

ЮНИТЫ (вид сверху — Tab)
Ctrl + рамка или щелчок — выделить, 1 агрессия, 2 охрана, 3 стоять, ПКМ — точка охраны
сборщик: держать E — выбрать юнита; транспорт: L — забрать, U — выгрузить

ЗАХВАТ БАЗ
нейтральную — стоять у ядра 15 с, пока рядом нет врагов
вражескую — разрушить ядро, оно станет нейтральным, потом захватить
проигрывает команда, у которой не осталось ни одного ядра

ОГОНЁК НА ПОСТРОЙКЕ
зелёный — работает     жёлтый — мало энергии
красный — стоит        серый — ждёт сырьё / темно

H — закрыть"""
	bg.add_child(lbl)
	return bg


func _unhandled_input(event: InputEvent) -> void:
	if headless:
		return
	# --- мёртв: только выбор базы цифрами (мышь свободна для кнопок) ---
	if player != null and player.dead and death_t >= 0.0:
		var kd := event as InputEventKey
		if kd and kd.pressed and not kd.echo and kd.keycode >= KEY_1 and kd.keycode <= KEY_9:
			var idx: int = kd.keycode - KEY_1
			var cores := _my_cores()
			if idx < cores.size():
				_choose_base(int(cores[idx].id))
		if kd == null or kd.keycode != KEY_H:
			return
	# --- в корабле: управление у самого корабля, тут только выход ---
	if piloting:
		var kp := event as InputEventKey
		if kp and kp.pressed and not kp.echo:
			if kp.keycode == KEY_G:
				_exit_ship()
			elif kp.keycode == KEY_F and piloting.kind == 2:
				_fighter_fire()
			elif kp.keycode == KEY_F and piloting.kind == 3:
				on_ship_crash(piloting, false, "РАКЕТА ПОДОРВАНА")
			elif kp.keycode == KEY_F and piloting.kind == 4:
				_jet_fire()
			elif (kp.keycode == KEY_L or kp.keycode == KEY_U) and int(D.SHIP_KINDS[piloting.kind].cargo) > 0 and piloting.landed:
				var do_load := kp.keycode == KEY_L
				if is_server:
					if do_load:
						server_ship_load(1, piloting_id)
					else:
						server_ship_unload(1, piloting_id)
				elif do_load:
					req_ship_load.rpc_id(1, piloting_id)
				else:
					req_ship_unload.rpc_id(1, piloting_id)
			elif kp.keycode >= KEY_1 and kp.keycode <= KEY_7:
				piloting.sas_mode = kp.keycode - KEY_1   # 1 — выкл, 2..7 — режимы автопилота
			elif kp.keycode == KEY_BACKSPACE:
				var now := Time.get_ticks_msec() / 1000.0
				if now < destruct_armed:
					on_ship_crash(piloting, true)
				else:
					destruct_armed = now + 2.0
					big_msg.text = "САМОУНИЧТОЖЕНИЕ?\nнажми Backspace ещё раз"
					get_tree().create_timer(2.0).timeout.connect(_clear_msg)
			elif kp.keycode == KEY_T:
				_cycle_target()
			elif kp.keycode == KEY_M:
				# в сфере планеты: нет -> орбита -> система; в космосе: нет -> система
				if piloting.pn >= 0:
					map_mode = (map_mode + 1) % 3
				else:
					map_mode = 2 if map_mode == 0 else 0
				map_zoom = 1.0
			elif kp.keycode == KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif kp.keycode == KEY_H:
				help_panel.visible = not help_panel.visible
		var mbp := event as InputEventMouseButton
		if mbp and mbp.pressed and map_mode != 0:
			if mbp.button_index == MOUSE_BUTTON_WHEEL_UP:
				map_zoom = maxf(0.02, map_zoom / 1.2)
			elif mbp.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				map_zoom = minf(5.0, map_zoom * 1.2)
		if mbp and mbp.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	# --- круговое меню: держишь Z ---
	var kz := event as InputEventKey
	if kz and kz.keycode == KEY_Z and not kz.echo:
		if kz.pressed and not radial.is_open:
			radial.open(sel_type)
			drag_mode = 0
			if player:
				player.look_locked = true
		elif not kz.pressed and radial.is_open:
			var res = radial.close()
			if res != null:
				sel_type = res
			if player:
				player.look_locked = false
		return
	# --- E рядом с кораблём — сесть; на площадке — собрать корабль ---
	if kz and kz.keycode == KEY_E and kz.pressed and not kz.echo and not radial.is_open \
			and not item_radial.is_open:
		var sid := _near_ship()
		if sid != -1:
			if is_server:
				server_board(1, sid)
			else:
				req_board.rpc_id(1, sid)
			return
	# --- U на своём заводе: модернизация ---
	if kz and kz.keycode == KEY_U and kz.pressed and not kz.echo and _hover_upgradable():
		if is_server:
			if _in_reach(1, hover_cell, my_pn):
				server_upgrade(my_team, hover_cell, my_pn)
		else:
			req_upgrade.rpc_id(1, hover_cell)
		return
	# --- E на своей лампе: вкл/выкл; Shift+E — все свои лампы на планете (маскировка) ---
	if kz and kz.keycode == KEY_E and kz.pressed and not kz.echo and e_menu == null and _hover_own(D.LAMP):
		var all_l := Input.is_key_pressed(KEY_SHIFT)
		if is_server:
			server_lamp(my_team, hover_cell, my_pn, all_l)
		else:
			req_lamp.rpc_id(1, hover_cell, all_l)
		return
	# --- держать E на своей постройке: точка выгрузки — груз, сборщик — юнит, площадка — корабль ---
	if kz and kz.keycode == KEY_E and not kz.echo:
		if kz.pressed and e_menu == null and not radial.is_open:
			var menu: RadialMenu = null
			var cur := 0
			if _hover_own(D.UNLOADER) or _hover_own(D.SORTER):
				menu = item_radial
				cur = buildings[grid[_k(my_pn, hover_cell)]].filter
			elif _hover_own(D.SPACE_DOCK):
				menu = dock_radial
				cur = maxi(int(buildings[grid[_k(my_pn, hover_cell)]].get("dest_pn", -1)), 0)
			elif _hover_own(D.ASSEMBLER):
				menu = unit_radial
				cur = maxi(int(buildings[grid[_k(my_pn, hover_cell)]].ukind), 0)
			elif _hover_own(D.LAUNCH_PAD):
				menu = ship_radial
			if menu:
				e_menu = menu
				filter_cell = hover_cell
				menu.open(cur)
				drag_mode = 0
				if player:
					player.look_locked = true
		elif not kz.pressed and e_menu != null:
			var res = e_menu.close()
			if res != null and filter_cell != NO_CELL:
				if e_menu == item_radial:
					if is_server:
						server_set_filter(my_team, filter_cell, res, my_pn)
					else:
						req_set_filter.rpc_id(1, filter_cell, res)
				elif e_menu == unit_radial:
					if is_server:
						server_set_unit(my_team, filter_cell, res, my_pn)
					else:
						req_set_unit.rpc_id(1, filter_cell, res)
				elif e_menu == ship_radial:
					if is_server:
						server_pad_action(my_team, filter_cell, my_pn, res)
					else:
						req_pad_action.rpc_id(1, filter_cell, res)
				elif e_menu == dock_radial:
					if is_server:
						server_set_dest(my_team, filter_cell, res, my_pn)
					else:
						req_set_dest.rpc_id(1, filter_cell, res)
			e_menu = null
			filter_cell = NO_CELL
			if player:
				player.look_locked = false
		return
	var open_menu: RadialMenu = null
	if radial.is_open:
		open_menu = radial
	elif e_menu != null:
		open_menu = e_menu
	if open_menu:
		var mmo := event as InputEventMouseMotion
		if mmo:
			open_menu.on_mouse_motion(mmo.relative)
		var mbo := event as InputEventMouseButton
		if mbo and mbo.pressed:
			if mbo.button_index == MOUSE_BUTTON_WHEEL_UP:
				open_menu.on_scroll(-1)
			elif mbo.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				open_menu.on_scroll(1)
		return
	var mb := event as InputEventMouseButton
	if mb:
		# в режиме от первого лица первый клик только захватывает курсор
		if fps_mode and mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if fps_mode:
				_cycle_slot(-1)
			else:
				orbit_dist = maxf(planet.radius + 10.0, orbit_dist - (orbit_dist - planet.radius) * 0.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if fps_mode:
				_cycle_slot(1)
			else:
				orbit_dist = minf(800.0 * planet.radius / D.PLANET_R, orbit_dist + (orbit_dist - planet.radius) * 0.12 + 1.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# вид сверху: Ctrl + рамка — выделить юнитов
			if not fps_mode and mb.pressed and Input.is_key_pressed(KEY_CTRL):
				selecting = true
				sel_start = mb.position
				return
			if selecting and not mb.pressed:
				_finish_selection(mb.position)
				return
			drag_mode = 1 if mb.pressed and fps_mode else 0   # строить — только руками, не с карты
			drag_last = NO_CELL
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# вид сверху с выделением: ПКМ — точка охраны
			if not fps_mode and not selected.is_empty():
				if mb.pressed:
					var gp = _mouse_ground()
					if gp != null:
						_command(-1, gp, true)
				return
			drag_mode = 2 if mb.pressed and fps_mode else 0
			drag_last = NO_CELL
		return
	if selecting and event is InputEventMouseMotion:
		sel_box.queue_redraw()
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		match k.keycode:
			KEY_1:
				if not fps_mode and not selected.is_empty():
					_command(D.MODE_AGGRO)
				else:
					_select_category(0)
			KEY_2:
				if not fps_mode and not selected.is_empty():
					_command(D.MODE_GUARD)
				else:
					_select_category(1)
			KEY_3:
				if not fps_mode and not selected.is_empty():
					_command(D.MODE_HOLD)
				else:
					_select_category(2)
			KEY_4:
				_select_category(3)
			KEY_5:
				_select_category(4)
			KEY_6:
				_select_category(5)
			KEY_7:
				_select_category(6)
			KEY_8:
				sel_type = D.WEAPON
			KEY_R:
				sel_rot += 1
			KEY_F:
				flash_on = not flash_on
			KEY_TAB:
				_set_fps(not fps_mode)
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_H:
				help_panel.visible = not help_panel.visible


func _unit_info(k: int) -> Array:
	var st: Dictionary = D.UNIT_STATS[k]
	var lim := ""
	if unit_stat.size() > my_team and my_team >= 0:
		var nk := D.UNIT_NAMES.size()
		lim = "   |   Сейчас: %d / %d" % [int(unit_stat[my_team][k]), int(unit_stat[my_team][k + nk])]
	var desc := ""
	if k == D.U_DRONE:
		desc = "очень быстрый, таранит цель: −25% её прочности, сам погибает"
	else:
		var dps := int(float(st.dmg) * 10.0 / maxf(float(st.cd), 1.0))
		desc = "%d прочности, бьёт на %d клеток, %d урона/с" % [int(st.hp), int(float(st.range) / D.CELL_M), dps]
	return [D.UNIT_NAMES[k], desc, "Цена: " + _cost_dict_text(D.UNIT_RECIPES[k]),
		"Лимит: %d на каждое ядро%s" % [int(D.UNIT_LIMIT[k]), lim]]


func _ship_info(k: int) -> Array:
	var sk: Dictionary = D.SHIP_KINDS[k]
	var dv := _ship_dv(float(sk.tank), k)
	var extra := "мест для юнитов: %d (танк и дрон — 1, мех — 4)" % int(sk.cargo) if int(sk.cargo) > 0 else "1 игрок"
	if k == 2:
		extra = "уникальное топливо, бластер (F) на %d м раз в %d с, берёт 2 уникальных меха" % [int(D.FIGHTER_RANGE), int(D.FIGHTER_CD)]
	elif k == 3:
		extra = "пилотируемая ракета: врезалась или F — взрыв радиусом %d м, %d урона" % [int(D.KAMIKAZE_R), D.KAMIKAZE_DMG]
	elif k == 4:
		extra = "разрывная ракета (F) раз в минуту: взрыв %d м, %d урона" % [int(D.JET_MISSILE_R), D.JET_MISSILE_DMG]
	return [sk.name, "Δv полного бака %d м/с, %s" % [int(dv), extra], "Цена: " + _cost_dict_text(D.SHIP_COSTS[k])]


func _draw_sel_box() -> void:
	if selecting:
		var r := Rect2(sel_start, sel_box.get_local_mouse_position() - sel_start).abs()
		sel_box.draw_rect(r, Color(0.4, 1.0, 0.5, 0.15), true)
		sel_box.draw_rect(r, Color(0.4, 1.0, 0.5, 0.9), false, 2.0)


## Строки для кругового меню: название, описание, цена, размер, энергия.
func _type_info(t: int) -> Array:
	if t == D.WEAPON:
		return ["Бластер", "ЛКМ — огонь. Бьёт вражеских юнитов и игроков"]
	var lines: Array = [D.NAMES[t], D.DESC[t], "Цена: " + _cost_text(t)]
	var extra := "Размер: %d %s" % [_size_of(t), "клетка" if _size_of(t) == 1 else "клетки" if _size_of(t) < 5 else "клеток"]
	if D.POWER_USE.has(t):
		extra += "   |   Потребляет энергии: %d" % int(D.POWER_USE[t])
	elif t == D.SOLAR:
		extra += "   |   Выработка: до %d (зависит от света)   |   Зона: %d колец" % [int(D.SOLAR_POWER), D.POWER_RING]
	elif t == D.COAL_PLANT:
		extra += "   |   Выработка: %d   |   Зона: %d колец" % [int(D.COAL_POWER), D.POWER_RING]
	elif t == D.NUCLEAR:
		extra += "   |   Выработка: %d   |   Зона: %d колец" % [int(D.NUCLEAR_POWER), D.POWER_RING]
	lines.append(extra)
	return lines


func _hover_upgradable() -> bool:
	if hover_cell == NO_CELL or not grid.has(_k(my_pn, hover_cell)):
		return false
	var b: Dictionary = buildings[grid[_k(my_pn, hover_cell)]]
	return int(b.team) == my_team and D.UPGRADABLE.has(int(b.type))


func _hover_own(type: int) -> bool:
	if hover_cell == NO_CELL or not grid.has(_k(my_pn, hover_cell)):
		return false
	var b: Dictionary = buildings[grid[_k(my_pn, hover_cell)]]
	return b.type == type and b.team == my_team


func _cycle_slot(step: int) -> void:
	var i := all_slots.find(sel_type)
	sel_type = all_slots[posmod(i + step, all_slots.size())]


func _select_category(ci: int) -> void:
	var group: Array = D.CATEGORIES[ci][1]
	var i := group.find(sel_type)
	sel_type = group[(i + 1) % group.size()] if i >= 0 else group[0]


func _request_place(cell: int, dir: int) -> void:
	if not _can_place(my_team, sel_type, cell, dir, my_pn):
		return
	if is_server:
		if _in_reach(1, cell, my_pn):
			server_place(my_team, sel_type, cell, dir, my_pn, 1)
	else:
		req_place.rpc_id(1, sel_type, cell, dir)


func _request_remove(cell: int) -> void:
	if my_team < 0 or not grid.has(_k(my_pn, cell)):
		return
	if is_server:
		if _in_reach(1, cell, my_pn):
			server_remove(my_team, cell, my_pn, 1)
	else:
		req_remove.rpc_id(1, cell)


func _show_over(winner: int) -> void:
	finished = true
	if big_msg == null:
		return
	if winner == my_team:
		big_msg.text = "ПОБЕДА\nядро противника уничтожено"
	else:
		big_msg.text = "ПОРАЖЕНИЕ\nтвоё ядро уничтожено"
