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
const ICON_SHADER = preload("res://shaders/icon.gdshader")
const SUIT_COLOR := Color(0.88, 0.88, 0.9)
const LIT_SHADER = preload("res://shaders/lit16.gdshader")
const GIANT_SHADER = preload("res://shaders/giant.gdshader")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const RINGS_SHADER = preload("res://shaders/rings.gdshader")
const SKY_SHADER = preload("res://shaders/sky.gdshader")
const NO_CELL := -1
const CORE_H := 1.1   # высота основания ядра

# состояние постройки -> цвет огонька-индикатора
const ST_IDLE := 0    # ждёт (нет сырья, темно)
const ST_OK := 1      # работает
const ST_SLOW := 2    # работает медленно (мало энергии)
const ST_STOP := 3    # стоит (некуда отдавать, нет энергии, нет воды)
const STATE_COLORS := [Color(0.55, 0.55, 0.6), Color(0.2, 1.0, 0.3), Color(1.0, 0.8, 0.15), Color(1.0, 0.15, 0.1)]
# высота огонька над постройкой (в локальных координатах декора)
const IND_H := {
	D.CORE: 2.4, D.DRILL: 1.75, D.DRILL2: 2.3, D.DRILL3: 2.6, D.SOLAR: 0.95,
	D.COAL_PLANT: 1.4, D.NUCLEAR: 2.4, D.SMELTER: 1.45, D.CRUSHER: 1.5, D.MELTER: 1.55,
	D.CENTRIFUGE: 2.1, D.FUEL_SYNTH: 1.7, D.TURRET: 1.1, D.ASSEMBLER: 1.7,
}

var my_team := 0
var is_server := false
var headless := false
var planet: Planet

# --- общее состояние (есть у всех) ---
var grid := {}       # клетка -> id постройки
var buildings := {}  # id -> Dictionary
var storage := [D.START_STORAGE.duplicate(), D.START_STORAGE.duplicate()]   # предмет -> количество
var power_stats := [[0.0, 0.0], [0.0, 0.0]]   # [выработка, спрос] по командам
var core_hp := [D.HP[D.CORE], D.HP[D.CORE]]
var finished := false

# --- только сервер ---
var units: Array = []   # {id, team, dir: Vector3, cell, hp, cd}
var next_id := 1
var next_unit_id := 1
var tick_acc := 0.0
var players := {}       # peer_id -> {team, pos, fwd, hp, dead_t, last_shot}
var power_dirty := true # пересобрать энергосети (после стройки/сноса)
var power_root := {}    # id постройки -> id корня её энергосети
var power_has_gen := {} # корень -> есть ли в сети генератор

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
var inspect_text := ""
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
var mm_units: MultiMesh
var hud: Label
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


func setup(seed_val: int, team: int, server: bool, dedicated: bool) -> void:
	my_team = team
	is_server = server
	headless = dedicated
	planet = Planet.new()
	planet.generate(seed_val)
	for cat in D.CATEGORIES:
		all_slots.append_array(cat[1])
	all_slots.append(D.WEAPON)
	if not headless:
		_build_scene()
	if is_server:
		for t in 2:
			_add_building({"id": _new_id(), "type": D.CORE, "team": t, "cell": planet.core_center[t], "dir": 0})


# =====================================================================
# Помощники
# =====================================================================

func _new_id() -> int:
	var i := next_id
	next_id += 1
	return i


func _size_of(type: int) -> int:
	return 7 if type == D.CORE else int(D.SIZE.get(type, 1))


## Клетки, которые займёт постройка: 1 клетка, 3 (треугольник), 9 (ромб 3×3), ядро — 7.
func _footprint(type: int, cell: int, dir: int) -> Array:
	var nb: PackedInt32Array = planet.nbrs[cell]
	var k := nb.size()
	if type == D.CORE:
		var core_cells: Array = [cell]
		core_cells.append_array(Array(nb))
		return core_cells
	var size := _size_of(type)
	if size == 3:
		return [cell, nb[posmod(dir, k)], nb[posmod(dir + 1, k)]]
	if size == 9:
		var o: Vector3 = planet.dirs[cell]
		var v1: Vector3 = planet.dirs[nb[posmod(dir, k)]] - o
		var v2: Vector3 = planet.dirs[nb[posmod(dir + 1, k)]] - o
		var rhombus: Array = []
		for a in [-1.0, 0.0, 1.0]:
			for bb in [-1.0, 0.0, 1.0]:
				var p: Vector3 = (o + v1 * float(a) + v2 * float(bb)).normalized()
				var c := planet.walk(cell, p)
				if not rhombus.has(c):
					rhombus.append(c)
		return rhombus   # у пятиугольника может выйти меньше 9 — тогда ставить нельзя
	return [cell]


## Какую руду добывает бур на этих клетках: [тип, сколько клеток с ней].
func _drill_ore(cells: Array) -> Array:
	var cnt := {}
	for c in cells:
		var o: int = planet.ore[c]
		if o != D.I_NONE:
			cnt[o] = int(cnt.get(o, 0)) + 1
	var best := D.I_NONE
	var bn := 0
	for o in cnt:
		if int(cnt[o]) > bn:
			bn = cnt[o]
			best = o
	return [best, bn]


func _foot_center(cells: Array) -> Vector3:
	var d := Vector3.ZERO
	var r := 0.0
	for c in cells:
		d += planet.dirs[c]
		r = maxf(r, planet.top_r(c))
	return d.normalized() * r


func _arc(a: int, b: int) -> float:
	return planet.dirs[a].angle_to(planet.dirs[b]) * D.PLANET_R


func _bpos(b: Dictionary) -> Vector3:
	return planet.top_pos(b.cell)


func _out_cell(b: Dictionary) -> int:
	var nb: PackedInt32Array = planet.nbrs[b.cell]
	return nb[int(b.dir) % nb.size()]


func _upos(u: Dictionary) -> Vector3:
	var d: Vector3 = u.dir
	return d * (planet.top_r(u.cell) + 0.3)


func _spawn_pos(team: int) -> Vector3:
	var c: int = planet.spawn_cell[team]
	return planet.dirs[c] * (planet.top_r(c) + 1.0)


func _is_drill(t: int) -> bool:
	return t == D.DRILL or t == D.DRILL2 or t == D.DRILL3


func _can_afford(team: int, type: int) -> bool:
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


func _can_place(team: int, type: int, cell: int, dir: int) -> bool:
	if team < 0 or finished or cell < 0 or cell >= planet.count():
		return false
	if not D.COST.has(type):
		return false
	var foot := _footprint(type, cell, dir)
	if foot.size() != _size_of(type):
		return false
	for c in foot:
		if grid.has(c) or planet.level[c] >= D.MAX_LEVEL:
			return false
		if _arc(c, planet.core_center[1 - team]) < D.ENEMY_ZONE:
			return false
	if _is_drill(type):
		var dep: int = _drill_ore(foot)[0]
		if dep == D.I_NONE:
			return false
		if type == D.DRILL and D.RARE_ORES.has(dep):
			return false
	return _can_afford(team, type)


# =====================================================================
# Постройки (общая часть)
# =====================================================================

func _add_building(d: Dictionary) -> void:
	var b := {
		"id": int(d.id), "type": int(d.type), "team": int(d.team),
		"cell": int(d.cell), "dir": int(d.dir),
		"hp": D.HP[int(d.type)], "item": D.I_NONE, "prog": 0.0,
		"store": 0, "timer": 0, "rr": 0,
		"buf": {}, "cur": -1, "out_item": D.I_NONE, "out_n": 0,
		"blocked": false, "water": 0, "wuse": 0, "burn": 0, "wt": 0, "cool": false,
		"pr": 0.0, "pout": 0.0, "out_blocked": false,
	}
	var cells := _footprint(b.type, b.cell, b.dir)
	b["cells"] = cells
	# соседние клетки снаружи контура — сюда машина отдаёт продукт
	var outs: Array = []
	for c in cells:
		var nb: PackedInt32Array = planet.nbrs[c]
		for x in nb:
			if not cells.has(x) and not outs.has(x):
				outs.append(x)
	b["outs"] = outs
	if _is_drill(b.type):
		var info := _drill_ore(cells)
		b["ore"] = info[0]
		b["ore_n"] = info[1]
	buildings[b.id] = b
	for c in cells:
		grid[c] = b.id
	power_dirty = true
	next_id = maxi(next_id, b.id + 1)
	if not headless:
		_vis_add(b)


func _remove_building(id: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	for c in b.cells:
		grid.erase(c)
	buildings.erase(id)
	power_dirty = true
	if bnodes.has(id):
		bnodes[id].queue_free()
		bnodes.erase(id)


func _bdata(b: Dictionary) -> Dictionary:
	return {"id": b.id, "type": b.type, "team": b.team, "cell": b.cell, "dir": b.dir}


# =====================================================================
# Сервер: команды игроков
# =====================================================================

func server_place(team: int, type: int, cell: int, dir: int) -> void:
	if not D.COST.has(type) or type == D.CORE:
		return
	var nb0: PackedInt32Array = planet.nbrs[cell]
	dir = posmod(dir, nb0.size())
	if not _can_place(team, type, cell, dir):
		return
	var st: Dictionary = storage[team]
	var cost: Dictionary = D.COST[type]
	for it in cost:
		st[it] = int(st.get(it, 0)) - int(cost[it])
	var nb: PackedInt32Array = planet.nbrs[cell]
	var d := {"id": _new_id(), "type": type, "team": team, "cell": cell, "dir": posmod(dir, nb.size())}
	_add_building(d)
	for peer in Net.ready_peers:
		ev_add.rpc_id(peer, d)


func server_remove(team: int, cell: int) -> void:
	if finished or not grid.has(cell):
		return
	var b: Dictionary = buildings[grid[cell]]
	if b.team != team or b.type == D.CORE:
		return
	var st: Dictionary = storage[team]
	var cost: Dictionary = D.COST[b.type]
	for it in cost:
		st[it] = mini(int(st.get(it, 0)) + int(cost[it]) / 2, D.CORE_CAP)   # возврат половины, не выше лимита
	_destroy(b.id)


func _destroy(id: int) -> void:
	_remove_building(id)
	for peer in Net.ready_peers:
		ev_remove.rpc_id(peer, id)


func send_full_sync(peer: int) -> void:
	var list: Array = []
	for b in buildings.values():
		list.append(_bdata(b))
	full_sync.rpc_id(peer, list)
	if finished:
		ev_over.rpc_id(peer, 0 if core_hp[0] > 0 else 1)


func server_player_state(peer: int, pos: Vector3, fwd: Vector3, held: int) -> void:
	var team: int = Net.team_of(peer)
	if team < 0:
		return
	if not players.has(peer):
		players[peer] = {"team": team, "pos": pos, "fwd": fwd, "hp": D.PLAYER_HP, "dead_t": 0,
			"last_shot": 0, "held": held}
	var pl: Dictionary = players[peer]
	pl.held = held
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

	var best_t: float = D.GUN_RANGE
	var hit_unit = null
	var hit_peer := -1
	for u in units:
		if u.team == pl.team or u.hp <= 0:
			continue
		var t := _ray_sphere(from, dir, _upos(u), 0.5)
		if t > 0.0 and t < best_t:
			best_t = t
			hit_unit = u
			hit_peer = -1
	for pid in players:
		var o: Dictionary = players[pid]
		if o.team == pl.team or o.hp <= 0:
			continue
		var p: Vector3 = o.pos
		var up := p.normalized()
		for h in [0.5, 1.3]:
			var t := _ray_sphere(from, dir, p + up * h, 0.5)
			if t > 0.0 and t < best_t:
				best_t = t
				hit_unit = null
				hit_peer = pid

	if hit_unit != null:
		hit_unit.hp -= D.GUN_DMG
	elif hit_peer != -1:
		_damage_player(hit_peer, D.GUN_DMG)

	var end := from + dir * best_t
	for p in Net.ready_peers:
		if p != peer:
			fx_shot.rpc_id(p, from, end)
	if not headless and peer != 1:
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


# =====================================================================
# RPC
# =====================================================================

@rpc("any_peer", "call_remote", "reliable")
func req_place(type: int, cell: int, dir: int) -> void:
	if multiplayer.is_server():
		var team: int = Net.team_of(multiplayer.get_remote_sender_id())
		server_place(team, type, cell, dir)


@rpc("any_peer", "call_remote", "reliable")
func req_remove(cell: int) -> void:
	if multiplayer.is_server():
		var team: int = Net.team_of(multiplayer.get_remote_sender_id())
		server_remove(team, cell)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func req_player_state(pos: Vector3, fwd: Vector3, held: int) -> void:
	if multiplayer.is_server():
		server_player_state(multiplayer.get_remote_sender_id(), pos, fwd, held)


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


@rpc("authority", "call_remote", "reliable")
func ev_over(winner: int) -> void:
	_show_over(winner)


@rpc("authority", "call_remote", "reliable")
func ev_respawn(pos: Vector3) -> void:
	if player:
		player.teleport(pos)


@rpc("authority", "call_remote", "reliable")
func full_sync(list: Array) -> void:
	for d in list:
		if not buildings.has(int(d.id)):
			_add_building(d)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(u: PackedFloat32Array, it: PackedVector3Array, itt: PackedByteArray, pl: Array,
		st: Array, hp: Array, pw: Array, t: float) -> void:
	_apply_snapshot(u, it, itt, pl, st, hp, pw)
	# часы клиента подтягиваем к серверным
	if absf(world_time - t) > 1.0:
		world_time = t
	else:
		world_time = lerpf(world_time, t, 0.1)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func req_inspect(cell: int) -> void:
	if multiplayer.is_server():
		inspect_reply.rpc_id(multiplayer.get_remote_sender_id(), cell, _inspect_text(cell))


@rpc("authority", "call_remote", "unreliable_ordered")
func inspect_reply(cell: int, text: String) -> void:
	inspect_cell = cell
	inspect_text = text


## Одна строка о постройке под прицелом (считает сервер — у него внутренности машин).
func _inspect_text(cell: int) -> String:
	if not grid.has(cell):
		return ""
	var b: Dictionary = buildings[grid[cell]]
	var st: Array = _status(b)
	var txt := "%s — %s" % [D.NAMES[b.type], st[1]]
	if b.hp < D.HP[b.type]:
		txt += "   (прочность %d%%)" % int(100.0 * b.hp / D.HP[b.type])
	return txt


## [состояние ST_*, короткий текст]
func _status(b: Dictionary) -> Array:
	var t: int = b.type
	if D.POWER_USE.has(t) and not power_has_gen.has(power_root.get(b.id, b.id)):
		return [ST_STOP, "нет энергии: рядом нет генератора"]
	if t == D.CORE:
		var full := PackedStringArray()
		var st: Dictionary = storage[b.team]
		for it in D.CORE_ACCEPT:
			if int(st.get(it, 0)) >= D.CORE_CAP:
				full.append(D.ITEM_NAMES[it])
		if full.is_empty():
			return [ST_OK, "склад принимает всё переработанное"]
		return [ST_SLOW, "склад полон: " + ", ".join(full)]
	if t == D.TURRET:
		return [ST_OK, "в строю"]
	if t == D.CONVEYOR or t == D.PIPE:
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
	if t == D.ASSEMBLER:
		return [ST_OK, "собирает юнита"] if b.timer > 0 else [ST_IDLE, "ждёт железо"]
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
		if b.type == D.CONVEYOR or b.type == D.PIPE:
			continue
		ids.append(b.id)
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
func fx_shot(from: Vector3, to: Vector3) -> void:
	_tracer(from, to)


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
		if D.GENERATORS.has(b.type) or D.POWER_USE.has(b.type):
			parent[b.id] = b.id
	for b in buildings.values():
		if not D.GENERATORS.has(b.type):
			continue
		var covered := {}
		for c in b.cells:
			var r := planet.rings(c, D.POWER_RING)
			for x in r:
				covered[x] = true
		for x in covered:
			if grid.has(x):
				var oid: int = grid[x]
				if parent.has(oid) and buildings[oid].team == b.team:
					_uf_union(parent, b.id, oid)
	power_root.clear()
	power_has_gen.clear()
	for id in parent:
		var root := _uf_find(parent, id)
		power_root[id] = root
		if D.GENERATORS.has(buildings[id].type):
			power_has_gen[root] = true


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
	if power_dirty:
		_rebuild_power()
	var sky := SkyCalc.state(world_time)
	var prod := [0.0, 0.0]
	var demand := [0.0, 0.0]
	var gprod := {}   # корень сети -> выработка
	var gdem := {}    # корень сети -> спрос
	var list: Array = buildings.values()

	# проход 1: генераторы и спрос на энергию
	for b in list:
		var t: int = b.type
		var team: int = b.team
		var out := 0.0
		if t == D.SOLAR:
			var lvl := SkyCalc.level_at(planet.dirs[b.cell], sky)
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
			demand[team] += D.POWER_USE[t]
			gdem[root] = float(gdem.get(root, 0.0)) + float(D.POWER_USE[t])

	# в каждой сети: не хватает энергии — все её машины работают медленнее
	var gratio := {}
	for root in gdem:
		gratio[root] = minf(1.0, float(gprod.get(root, 0.0)) / float(gdem[root]))
	for team in 2:
		power_stats[team] = [prod[team], demand[team]]

	# проход 2: работа
	for b in list:
		if not buildings.has(b.id):
			continue
		var t: int = b.type
		var r := 1.0
		if D.POWER_USE.has(t):
			var root: int = power_root.get(b.id, b.id)
			r = float(gratio.get(root, 1.0 if power_has_gen.has(root) else 0.0))
			b.pr = r
		if _is_drill(t):
			_drill_tick(b, r)
		elif t == D.CONVEYOR or t == D.PIPE:
			_belt_tick(b)
		elif D.RECIPES.has(t):
			_factory_tick(b, r)
		elif t == D.ASSEMBLER:
			if b.timer > 0:
				b.timer -= 1
				if b.timer == 0:
					_spawn_unit(b.team, b.cell)
			elif b.store >= D.UNIT_COST:
				b.store -= D.UNIT_COST
				b.timer = D.UNIT_BUILD_TICKS
		elif t == D.TURRET:
			_turret_tick(b)
	_players_tick()
	_units_tick()
	state_acc += 1
	if state_acc >= 5:
		state_acc = 0
		_send_states()


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
	return false


func _drill_tick(b: Dictionary, r: float) -> void:
	var t: int = b.type
	var ore: int = b.ore
	if b.blocked:
		# выход забит — пробуем выгрузить готовую руду
		if _output(b, ore):
			b.blocked = false
			b.prog = 0.0
		return
	if t == D.DRILL3 and b.water <= 0:
		return
	b.prog += r
	# скорость пропорциональна доле рудных клеток под буром
	var need: float = float(D.DRILL_TICKS[t]) * float(b.cells.size()) / float(maxi(int(b.ore_n), 1))
	if b.prog >= need:
		if t == D.DRILL3:
			b.wuse += 1
			if b.wuse >= D.DRILL3_WATER_PER:
				b.wuse = 0
				b.water -= 1
		if _output(b, ore):
			b.prog = 0.0
		else:
			b.blocked = true


func _belt_tick(b: Dictionary) -> void:
	if b.item == D.I_NONE:
		return
	var speed: float = D.PIPE_SPEED if b.type == D.PIPE else D.CONVEYOR_SPEED
	b.prog = minf(b.prog + speed, 1.0)
	if b.prog >= 1.0 and _push(_out_cell(b), b.id, b.team, b.item):
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
	var outs: Array = b.outs
	var k := outs.size()
	for i in k:
		var idx: int = (b.rr + i) % k
		if _push(outs[idx], b.id, b.team, item):
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
		return item == D.I_IRON and o.store < D.UNIT_COST * 3
	return false


## Положить предмет в клетку cell от постройки src_id. true — если взяли.
func _push(cell: int, src_id: int, team: int, item: int) -> bool:
	if not grid.has(cell):
		return false
	var o: Dictionary = buildings[grid[cell]]
	if o.team != team:
		return false
	var t: int = o.type
	if t == D.CONVEYOR or t == D.PIPE:
		# вода — только в трубы, всё твёрдое — только на конвейеры
		if (item == D.I_WATER) != (t == D.PIPE):
			return false
		# лента, которая смотрит в источник, у него ничего не берёт
		if o.item != D.I_NONE or int(grid.get(_out_cell(o), -1)) == src_id:
			return false
		o.item = item
		o.prog = 0.0
		return true
	if t == D.CORE:
		# сырую руду ядро не принимает — только переработанное
		if not D.CORE_ACCEPT.has(item):
			return false
		var st: Dictionary = storage[team]
		if int(st.get(item, 0)) >= D.CORE_CAP:
			return false   # склад полон — лента встаёт
		st[item] = int(st.get(item, 0)) + 1
		return true
	if not _accepts(o, item):
		return false
	if t == D.DRILL3:
		o.water += 1
	elif t == D.ASSEMBLER:
		o.store += 1
	else:
		var buf: Dictionary = o.buf
		buf[item] = int(buf.get(item, 0)) + 1
	return true


func _turret_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	var c := _bpos(b) + planet.dirs[b.cell] * 0.5
	var best = null
	var bd: float = D.TURRET_RANGE
	for u in units:
		if u.team != b.team and u.hp > 0:
			var d: float = c.distance_to(_upos(u))
			if d < bd:
				bd = d
				best = u
	if best != null:
		best.hp -= D.TURRET_DMG
		b.timer = D.TURRET_CD
		if not headless:
			_tracer(c, _upos(best))


func _spawn_unit(team: int, cell: int) -> void:
	var d: Vector3 = planet.dirs[cell]
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.01
	d = (d + jitter).normalized()
	units.append({"id": next_unit_id, "team": team, "dir": d, "cell": cell, "hp": D.UNIT_HP, "cd": 0})
	next_unit_id += 1


func _players_tick() -> void:
	for pid in players.keys():
		if Net.team_of(pid) < 0:
			players.erase(pid)   # игрок вышел
			continue
		var o: Dictionary = players[pid]
		if o.hp > 0:
			continue
		o.dead_t -= 1
		if o.dead_t <= 0:
			o.hp = D.PLAYER_HP
			o.pos = _spawn_pos(o.team)
			if pid == 1 and not headless:
				if player:
					player.teleport(o.pos)
			elif Net.ready_peers.has(pid):
				ev_respawn.rpc_id(pid, o.pos)


func _units_tick() -> void:
	for u in units:
		if u.hp <= 0:
			continue
		if u.cd > 0:
			u.cd -= 1
		var upos := _upos(u)
		var target_unit = null
		var target_player := -1
		var best: float = D.UNIT_AGGRO
		var tpos := Vector3.ZERO
		for o in units:
			if o.hp <= 0 or o.id == u.id:
				continue
			var op := _upos(o)
			var d: float = upos.distance_to(op)
			if o.team != u.team:
				if d < best:
					best = d
					target_unit = o
					tpos = op
			elif d < 0.6 and d > 0.001:
				# чтобы свои не слипались в одну точку
				var away: Vector3 = (u.dir - o.dir)
				u.dir = (u.dir + away.normalized() * 0.002).normalized()
		for pid in players:
			var pl: Dictionary = players[pid]
			if pl.team == u.team or pl.hp <= 0:
				continue
			var pp: Vector3 = pl.pos
			var d: float = upos.distance_to(pp)
			if d < best:
				best = d
				target_unit = null
				target_player = pid
				tpos = pp

		var reach: float = D.UNIT_RANGE
		var target_b = null
		if target_player == -1 and target_unit == null:
			target_b = _nearest_enemy_building(upos, u.team)
			if target_b == null:
				continue
			tpos = _bpos(target_b)
			reach = D.UNIT_RANGE + (2.2 if target_b.type == D.CORE else 0.6)

		var dist: float = upos.distance_to(tpos)
		if dist > reach:
			var ud: Vector3 = u.dir
			var tdir := tpos.normalized()
			var tangent := tdir - ud * ud.dot(tdir)
			if tangent.length() > 0.00001:
				var step: float = minf(D.UNIT_SPEED, dist - reach + 0.01)
				u.dir = (ud + tangent.normalized() * (step / D.PLANET_R)).normalized()
				u.cell = planet.walk(u.cell, u.dir)
		elif u.cd == 0:
			u.cd = D.UNIT_CD
			if target_player != -1:
				_damage_player(target_player, D.UNIT_DMG)
			elif target_unit != null:
				target_unit.hp -= D.UNIT_DMG
			else:
				_damage_building(target_b, D.UNIT_DMG)
				if finished:
					return
	units = units.filter(func(x): return x.hp > 0)


func _nearest_enemy_building(from: Vector3, team: int):
	var best = null
	var bd := INF
	for b in buildings.values():
		if b.team == team:
			continue
		var d: float = from.distance_squared_to(_bpos(b))
		if d < bd:
			bd = d
			best = b
	return best


func _damage_building(b: Dictionary, dmg: int) -> void:
	b.hp -= dmg
	if b.type == D.CORE:
		core_hp[b.team] = maxi(b.hp, 0)
	if b.hp > 0:
		return
	if b.type == D.CORE:
		finished = true
		var winner: int = 1 - b.team
		_destroy(b.id)
		for p in Net.ready_peers:
			ev_over.rpc_id(p, winner)
		if headless:
			print("[server] Игра окончена, победили: %s" % D.TEAM_NAMES[winner])
		else:
			_show_over(winner)
	else:
		_destroy(b.id)


func _send_snapshot() -> void:
	var u := PackedFloat32Array()
	for x in units:
		var p := _upos(x)
		u.append(p.x)
		u.append(p.y)
		u.append(p.z)
		u.append(float(x.team))
		u.append(float(x.hp) / D.UNIT_HP)
	var it := PackedVector3Array()
	var itt := PackedByteArray()
	for b in buildings.values():
		if (b.type == D.CONVEYOR or b.type == D.PIPE) and b.item != D.I_NONE:
			var a := _bpos(b)
			var nxt := planet.top_pos(_out_cell(b))
			var up: Vector3 = planet.dirs[b.cell]
			it.append(a + (nxt - a) * (float(b.prog) - 0.5) + up * 0.3)
			itt.append(b.item)
	var pl: Array = []
	for pid in players:
		var o: Dictionary = players[pid]
		pl.append([pid, o.pos, o.fwd, o.team, o.hp, o.held])
	for p in Net.ready_peers:
		snapshot.rpc_id(p, u, it, itt, pl, storage, core_hp, power_stats, world_time)
	if not headless:
		_apply_snapshot(u, it, itt, pl, storage, core_hp, power_stats)


# =====================================================================
# Клиент: сцена
# =====================================================================

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# ламп нет: весь свет считает шейдер lit16 по положению солнца и гиганта

	# поверхность планеты: меш + коллизия
	var built: Array = planet.build_mesh()
	var terrain := MeshInstance3D.new()
	terrain.mesh = built[0]
	var tmat := ShaderMaterial.new()
	tmat.shader = TERRAIN_SHADER
	terrain.material_override = tmat
	add_child(terrain)
	terrain_body = StaticBody3D.new()
	var tcol := CollisionShape3D.new()
	var tshape := ConcavePolygonShape3D.new()
	tshape.backface_collision = true
	tshape.set_faces(built[1])
	tcol.shape = tshape
	terrain_body.add_child(tcol)
	add_child(terrain_body)

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
	add_child(giant_node)
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
	imat.set_shader_parameter("atlas", Icons.build_atlas())
	imat.set_shader_parameter("grid", Vector2(Icons.COLS, Icons.ROWS))
	iq.material = imat
	mm_items.mesh = iq
	var items_mmi := MultiMeshInstance3D.new()
	items_mmi.multimesh = mm_items
	add_child(items_mmi)

	# юниты
	mm_units = MultiMesh.new()
	mm_units.transform_format = MultiMesh.TRANSFORM_3D
	mm_units.use_colors = true
	mm_units.instance_count = 4096
	mm_units.visible_instance_count = 0
	var ubox := BoxMesh.new()
	ubox.size = Vector3(0.6, 0.45, 0.6)
	ubox.material = _vc_mat()
	mm_units.mesh = ubox
	var units_mmi := MultiMeshInstance3D.new()
	units_mmi.multimesh = mm_units
	add_child(units_mmi)

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
	add_child(ghost)

	# интерфейс
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_constant_override("outline_size", 5)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(hud)

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

	# персонаж
	if my_team >= 0:
		player = Player.new()
		add_child(player)
		player.teleport(_spawn_pos(my_team))
		_build_viewmodel()
		_set_fps(true)
	else:
		_set_fps(false)


## Обычные поверхности — шейдер с 16 уровнями света. Светящиеся (glow) — сами светятся в темноте.
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
	if multi:
		# основание — призмы точно по контуру клеток
		var pr: Array = planet.prism(cells, base_h, 0.94, col.darkened(0.55), col.darkened(0.3))
		var mi := MeshInstance3D.new()
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
		_box(n, Vector3(1.1, 1.6, 1.1), Vector3(0, 1.3, 0), col, true)
	else:
		_vis_shape(n, t, col)
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
	# твёрдое тело для одноклеточных (по конвейерам и трубам ходим)
	if not multi and t != D.CONVEYOR and t != D.PIPE:
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 1.3, 1.2)
		shape_node.shape = shape
		shape_node.position.y = 0.65
		body.add_child(shape_node)
		n.add_child(body)
	add_child(root)

	var nb: PackedInt32Array = planet.nbrs[b.cell]
	var toward: int = nb[int(b.dir) % nb.size()]
	if multi:
		# декор — в центре контура, поверх основания, крупнее
		var center := _foot_center(cells)
		var up := center.normalized()
		var f := planet.top_pos(toward) - planet.top_pos(b.cell)
		f = (f - up * f.dot(up)).normalized()
		n.transform = Transform3D(Basis(f, up, f.cross(up)), center + up * base_h)
		if t != D.CORE:
			n.scale = Vector3.ONE * (1.6 if cells.size() == 3 else 2.4)
	else:
		_orient(n, b.cell, toward)
	bnodes[b.id] = root


## Простые формы построек. Светящиеся детали видны и в полной темноте.
func _vis_shape(n: Node3D, t: int, col: Color) -> void:
	var dark := col.darkened(0.45)
	var metal := Color(0.6, 0.6, 0.65)
	if t == D.CONVEYOR:
		_cyl(n, 0.85, 0.1, Vector3(0, 0.05, 0), Color(0.27, 0.27, 0.3), 6).material_override = \
				_pmat(Color(0.3, 0.3, 0.33), 2)
		_box(n, Vector3(0.8, 0.12, 0.22), Vector3(0.2, 0.12, 0), col, true)
	elif t == D.PIPE:
		_cyl(n, 0.6, 0.12, Vector3(0, 0.06, 0), Color(0.3, 0.35, 0.45), 6).material_override = \
				_pmat(Color(0.25, 0.4, 0.6), 3)
		_box(n, Vector3(0.8, 0.14, 0.2), Vector3(0.2, 0.14, 0), Color(0.25, 0.55, 1.0), true)
	elif t == D.DRILL:
		_box(n, Vector3(1.1, 0.7, 1.1), Vector3(0, 0.35, 0), dark)
		_cyl(n, 0.28, 0.8, Vector3(0, 1.1, 0), Color(0.85, 0.6, 0.3))
	elif t == D.DRILL2:
		_box(n, Vector3(1.2, 0.8, 1.2), Vector3(0, 0.4, 0), dark)
		_cyl(n, 0.32, 1.1, Vector3(0, 1.35, 0), metal)
		_box(n, Vector3(0.3, 0.15, 0.3), Vector3(0, 2.0, 0), Color(1.0, 0.9, 0.3), true)
	elif t == D.DRILL3:
		_box(n, Vector3(1.3, 0.9, 1.3), Vector3(0, 0.45, 0), dark)
		_cyl(n, 0.38, 1.3, Vector3(0, 1.55, 0), metal)
		_cyl(n, 0.2, 0.9, Vector3(0.45, 1.3, 0.0), Color(0.25, 0.55, 1.0))
		_box(n, Vector3(0.35, 0.15, 0.35), Vector3(0, 2.3, 0), Color(0.4, 0.8, 1.0), true)
	elif t == D.SOLAR:
		_cyl(n, 0.08, 0.6, Vector3(0, 0.3, 0), metal)
		_box(n, Vector3(1.5, 0.06, 1.5), Vector3(0, 0.65, 0), Color(0.12, 0.18, 0.4))
	elif t == D.COAL_PLANT:
		_box(n, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.5, 0), Color(0.3, 0.28, 0.27))
		_cyl(n, 0.22, 1.4, Vector3(0.35, 1.7, 0.35), Color(0.4, 0.38, 0.36))
		_box(n, Vector3(0.5, 0.2, 0.1), Vector3(0, 0.5, 0.71), Color(1.0, 0.45, 0.15), true)
	elif t == D.NUCLEAR:
		_cyl(n, 0.85, 1.8, Vector3(0, 0.9, 0), Color(0.75, 0.75, 0.72), 6)
		_cyl(n, 0.4, 0.15, Vector3(0, 1.85, 0), Color(0.4, 1.0, 0.3))
		_box(n, Vector3(0.3, 0.3, 0.3), Vector3(0, 2.0, 0), Color(0.4, 1.0, 0.3), true)
	elif t == D.SMELTER:
		_box(n, Vector3(1.3, 1.0, 1.3), Vector3(0, 0.5, 0), Color(0.35, 0.3, 0.28))
		_box(n, Vector3(0.7, 0.2, 0.7), Vector3(0, 1.1, 0), Color(1.0, 0.5, 0.15), true)
	elif t == D.CRUSHER:
		_box(n, Vector3(1.3, 0.8, 1.3), Vector3(0, 0.4, 0), Color(0.4, 0.4, 0.42))
		_cyl(n, 0.3, 0.5, Vector3(0.3, 1.0, 0), metal)
		_cyl(n, 0.3, 0.5, Vector3(-0.3, 1.0, 0), metal)
	elif t == D.MELTER:
		_cyl(n, 0.6, 1.0, Vector3(0, 0.5, 0), Color(0.45, 0.5, 0.55))
		_cyl(n, 0.4, 0.15, Vector3(0, 1.05, 0), Color(0.5, 0.8, 1.0))
		_box(n, Vector3(0.25, 0.25, 0.25), Vector3(0, 1.2, 0), Color(0.4, 0.75, 1.0), true)
	elif t == D.CENTRIFUGE:
		_cyl(n, 0.55, 1.6, Vector3(0, 0.8, 0), Color(0.5, 0.55, 0.5))
		_box(n, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.75, 0), Color(0.45, 1.0, 0.3), true)
	elif t == D.FUEL_SYNTH:
		_box(n, Vector3(1.3, 1.2, 1.3), Vector3(0, 0.6, 0), Color(0.3, 0.25, 0.4))
		_box(n, Vector3(0.6, 0.25, 0.6), Vector3(0, 1.32, 0), Color(0.85, 0.45, 1.0), true)
	elif t == D.ASSEMBLER:
		_box(n, Vector3(1.3, 1.2, 1.3), Vector3(0, 0.6, 0), col.darkened(0.25))
		_box(n, Vector3(0.7, 0.25, 0.7), Vector3(0, 1.32, 0), col, true)
	elif t == D.TURRET:
		_cyl(n, 0.55, 0.6, Vector3(0, 0.3, 0), col.darkened(0.35))
		_box(n, Vector3(1.0, 0.2, 0.2), Vector3(0.4, 0.75, 0), Color(0.75, 0.75, 0.8))
	# метка команды — маленький огонёк, чтобы своё было видно ночью
	if t != D.CONVEYOR and t != D.PIPE:
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
		st: Array, hp: Array, pw: Array) -> void:
	prev_units = cur_units
	cur_units = u
	cur_items = it
	cur_item_types = itt
	power_stats = pw
	cur_players = pl
	snap_time = 0.0
	if not is_server:
		storage = st
		core_hp = hp


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
		var sp := delta * 0.6 * ((orbit_dist - D.PLANET_R) / 150.0)
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
		if player.global_position.length() < D.PLANET_R - 2.0:
			player.teleport(_spawn_pos(my_team))
		send_acc += delta
		if send_acc >= 0.05:
			send_acc = 0.0
			var fwd := -player.global_transform.basis.z
			if is_server:
				server_player_state(1, player.global_position, fwd, sel_type)
			else:
				req_player_state.rpc_id(1, player.global_position, fwd, sel_type)

	_update_sky()
	_update_flashlight()
	_update_viewmodel(delta)
	_update_units()
	_update_items()
	_update_players(delta)

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
			and sel_type != D.WEAPON and alive and not radial.is_open
	if ghost.visible:
		_update_ghost()
		var ok := _can_place(my_team, sel_type, hover_cell, hover_dir)
		ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)

	# осмотр постройки под прицелом (данные присылает сервер)
	inspect_acc += delta
	if hover_cell != NO_CELL and grid.has(hover_cell) and inspect_acc >= 0.25:
		inspect_acc = 0.0
		if is_server:
			inspect_cell = hover_cell
			inspect_text = _inspect_text(hover_cell)
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
func _update_sky() -> void:
	var st := SkyCalc.state(world_time)
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
	sun_node.position = sun * D.SUN_VIS_DIST
	sun_node.visible = float(st.sun_level) > 0.02
	stars_node.transform = Transform3D(frame, Vector3.ZERO)


func _update_flashlight() -> void:
	var on := flash_on and player != null and not player.dead
	RenderingServer.global_shader_parameter_set("flash_on", 1.0 if on else 0.0)
	if player:
		RenderingServer.global_shader_parameter_set("flash_pos", player.cam.global_position)
		RenderingServer.global_shader_parameter_set("flash_dir", player.look_dir())


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
	ghost_cover.visible = D.GENERATORS.has(sel_type)
	if ghost_cover.visible:
		var zone := {}
		for c in foot:
			var r := planet.rings(c, D.POWER_RING)
			for x in r:
				zone[x] = true
		var cp: Array = planet.prism(zone.keys(), 0.08, 0.9, Color.WHITE, Color.WHITE)
		ghost_cover.mesh = cp[0]


func _update_units() -> void:
	var a := clampf(snap_time / D.TICK, 0.0, 1.0)
	snap_time += get_process_delta_time()
	var n := mini(cur_units.size() / 5, mm_units.instance_count)
	var can_lerp := prev_units.size() == cur_units.size()
	for i in n:
		var j := i * 5
		var p := Vector3(cur_units[j], cur_units[j + 1], cur_units[j + 2])
		if can_lerp:
			p = Vector3(prev_units[j], prev_units[j + 1], prev_units[j + 2]).lerp(p, a)
		var team := int(cur_units[j + 3])
		var hpf := cur_units[j + 4]
		var col: Color = D.TEAM_COLORS[team]
		mm_units.set_instance_transform(i, Transform3D(_up_basis(p.normalized()), p))
		mm_units.set_instance_color(i, col.darkened(0.6 * (1.0 - hpf)))
	mm_units.visible_instance_count = n


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
		if int(node.get_meta("held")) != held:
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
	for pid in others.keys():
		if not seen.has(pid):
			others[pid].queue_free()
			others.erase(pid)

	if player:
		player.dead = my_hp <= 0
		if not finished:
			big_msg.text = "ТЫ ПОГИБ\nреспаун через пару секунд..." if player.dead else ""


## Космонавт: скафандр, шлем с визором, ранец с антенной цвета команды.
## Правая рука вытянута вперёд, в ней — предмет (метка "hand").
func _make_avatar(team: int) -> Node3D:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var suit := _pmat(SUIT_COLOR, 1)
	var dark := _pmat(Color(0.35, 0.36, 0.4), 1)
	# ноги и ботинки
	for sx in [-0.12, 0.12]:
		_part(n, "box", Vector3(0.18, 0.75, 0.2), Vector3(sx, 0.45, 0), suit)
		_part(n, "box", Vector3(0.2, 0.12, 0.28), Vector3(sx, 0.06, -0.03), dark)
	# корпус + полоса цвета команды
	_part(n, "box", Vector3(0.5, 0.62, 0.3), Vector3(0, 1.12, 0), suit)
	_part(n, "box", Vector3(0.52, 0.08, 0.32), Vector3(0, 1.02, 0), _pmat(col, 0))
	# ранец и антенна
	_part(n, "box", Vector3(0.42, 0.5, 0.18), Vector3(0, 1.15, 0.24), dark)
	_part(n, "cyl", Vector3(0.015, 0.35, 0.015), Vector3(0.14, 1.55, 0.26), dark)
	_box(n, Vector3(0.06, 0.06, 0.06), Vector3(0.14, 1.74, 0.26), col, true)
	# шлем и визор
	_part(n, "sphere", Vector3(0.24, 0.48, 0), Vector3(0, 1.62, 0), suit)
	_box(n, Vector3(0.32, 0.17, 0.08), Vector3(0, 1.64, -0.2), Color(1.0, 0.75, 0.3), true)
	# левая рука опущена
	_part(n, "box", Vector3(0.13, 0.55, 0.14), Vector3(-0.33, 1.1, 0), suit)
	# правая рука вытянута вперёд, в кисти — предмет
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0.33, 1.35, 0)
	shoulder.rotation_degrees = Vector3(70, 0, 0)
	n.add_child(shoulder)
	_part(shoulder, "box", Vector3(0.13, 0.55, 0.14), Vector3(0, -0.27, 0), suit)
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.58, 0)
	hand.rotation_degrees = Vector3(-70, 0, 0)
	shoulder.add_child(hand)
	n.set_meta("hand", hand)
	n.set_meta("held", -999)
	n.set_meta("team", team)
	add_child(n)
	return n


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
	viewmodel.visible = fps_mode and not player.dead and not radial.is_open
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


func _tracer(a: Vector3, b: Vector3) -> void:
	if headless:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat(Color(1.0, 0.85, 0.3), true))
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	get_tree().create_timer(0.08).timeout.connect(mi.queue_free)


func _update_hud() -> void:
	if my_team < 0:
		return
	var lines := PackedStringArray()
	var lvl := light_level_at(player.global_position) if player else 0
	var pw: Array = power_stats[my_team]
	var eclipse := not sky_state.is_empty() and float(sky_state.sun_level) < 0.5
	var top := "Здоровье %d    Свет %d/16    Энергия %d / %d" % [my_hp, lvl, int(pw[0]), int(pw[1])]
	if core_hp[my_team] < D.HP[D.CORE]:
		top += "    Ядро %d%%" % int(100.0 * core_hp[my_team] / D.HP[D.CORE])
	if eclipse:
		top += "    ЗАТМЕНИЕ"
	lines.append(top)

	# склад: только то, что есть
	var st: Dictionary = storage[my_team]
	var parts := PackedStringArray()
	for it in D.CORE_ACCEPT:
		var n := int(st.get(it, 0))
		if n > 0:
			parts.append("%s %d/%d" % [D.ITEM_NAMES[it], n, D.CORE_CAP])
	lines.append("   ".join(parts) if not parts.is_empty() else "Склад пуст")

	lines.append("В руках: " + ("Бластер" if sel_type == D.WEAPON else String(D.NAMES[sel_type])))

	# под прицелом — одна строка
	if hover_cell != NO_CELL:
		if grid.has(hover_cell):
			if inspect_text != "" and int(grid.get(inspect_cell, -1)) == int(grid[hover_cell]):
				lines.append(inspect_text)
		else:
			var dep: int = planet.ore[hover_cell]
			if planet.level[hover_cell] >= D.MAX_LEVEL:
				lines.append("Скалы — строить нельзя")
			elif _arc(hover_cell, planet.core_center[1 - my_team]) < D.ENEMY_ZONE:
				lines.append("Зона вражеского ядра — строить нельзя")
			elif dep != D.I_NONE:
				lines.append("Залежь: " + D.ITEM_NAMES[dep] + ("  (нужен Бур II+)" if D.RARE_ORES.has(dep) else ""))
	hud.text = "\n".join(lines)


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
Быстрый выбор группы        1–5,  бластер — 6
Повернуть постройку         R
Строить / снести            ЛКМ (можно тянуть) / ПКМ
Орбитальная камера          Tab  (WASD — крутить планету, колесо — зум)
Отпустить курсор            Esc

ОГОНЁК НА ПОСТРОЙКЕ
зелёный — работает     жёлтый — мало энергии
красный — стоит        серый — ждёт сырьё / темно

H — закрыть"""
	bg.add_child(lbl)
	return bg


func _unhandled_input(event: InputEvent) -> void:
	if headless:
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
	if radial.is_open:
		var mmo := event as InputEventMouseMotion
		if mmo:
			radial.on_mouse_motion(mmo.relative)
		var mbo := event as InputEventMouseButton
		if mbo and mbo.pressed:
			if mbo.button_index == MOUSE_BUTTON_WHEEL_UP:
				radial.on_scroll(-1)
			elif mbo.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				radial.on_scroll(1)
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
				orbit_dist = maxf(D.PLANET_R + 10.0, orbit_dist - (orbit_dist - D.PLANET_R) * 0.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if fps_mode:
				_cycle_slot(1)
			else:
				orbit_dist = minf(800.0, orbit_dist + (orbit_dist - D.PLANET_R) * 0.12 + 1.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			drag_mode = 1 if mb.pressed else 0
			drag_last = NO_CELL
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			drag_mode = 2 if mb.pressed else 0
			drag_last = NO_CELL
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		match k.keycode:
			KEY_1:
				_select_category(0)
			KEY_2:
				_select_category(1)
			KEY_3:
				_select_category(2)
			KEY_4:
				_select_category(3)
			KEY_5:
				_select_category(4)
			KEY_6:
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


func _cycle_slot(step: int) -> void:
	var i := all_slots.find(sel_type)
	sel_type = all_slots[posmod(i + step, all_slots.size())]


func _select_category(ci: int) -> void:
	var group: Array = D.CATEGORIES[ci][1]
	var i := group.find(sel_type)
	sel_type = group[(i + 1) % group.size()] if i >= 0 else group[0]


func _request_place(cell: int, dir: int) -> void:
	if not _can_place(my_team, sel_type, cell, dir):
		return
	if is_server:
		server_place(my_team, sel_type, cell, dir)
	else:
		req_place.rpc_id(1, sel_type, cell, dir)


func _request_remove(cell: int) -> void:
	if my_team < 0 or not grid.has(cell):
		return
	if is_server:
		server_remove(my_team, cell)
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
