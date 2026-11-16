extends Node3D
## Игровой мир: одна круглая планета.
## На сервере: симуляция (буры, конвейеры, сборщики, турели, юниты, персонажи).
## На клиенте: отрисовка, камера, ввод. Хост делает и то и другое.

const D = preload("res://scripts/defs.gd")
const Planet = preload("res://scripts/planet.gd")
const Player = preload("res://scripts/player.gd")
const NO_CELL := -1
const SLOTS := [D.CONVEYOR, D.DRILL, D.ASSEMBLER, D.TURRET, D.WEAPON]

var my_team := 0
var is_server := false
var headless := false
var planet: Planet

# --- общее состояние (есть у всех) ---
var grid := {}       # клетка -> id постройки
var buildings := {}  # id -> Dictionary
var storage := [D.START_ORE, D.START_ORE]
var core_hp := [D.HP[D.CORE], D.HP[D.CORE]]
var finished := false

# --- только сервер ---
var units: Array = []   # {id, team, dir: Vector3, cell, hp, cd}
var next_id := 1
var next_unit_id := 1
var tick_acc := 0.0
var wave_timer := [0, 0]
var wave_count := [0, 0]
var players := {}       # peer_id -> {team, pos, fwd, hp, dead_t, last_shot}

# --- только клиент ---
var bnodes := {}
var mats := {}
var orbit_cam: Camera3D
var orbit_yaw := 0.0
var orbit_pitch := 0.0
var orbit_dist := 75.0
var ghost: Node3D
var ghost_mat: StandardMaterial3D
var sel_type := D.CONVEYOR
var sel_rot := 0
var mm_items: MultiMesh
var mm_units: MultiMesh
var hud: Label
var big_msg: Label
var crosshair: Label
var prev_units := PackedFloat32Array()
var cur_units := PackedFloat32Array()
var cur_items := PackedVector3Array()
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
var terrain_body: StaticBody3D


func setup(seed_val: int, team: int, server: bool, dedicated: bool) -> void:
	my_team = team
	is_server = server
	headless = dedicated
	planet = Planet.new()
	planet.generate(seed_val)
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


func _cells_of(type: int, cell: int) -> Array:
	if type == D.CORE:
		var arr: Array = [cell]
		arr.append_array(Array(planet.nbrs[cell]))
		return arr
	return [cell]


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


func _can_place(team: int, type: int, cell: int) -> bool:
	if team < 0 or finished or cell < 0 or cell >= planet.count():
		return false
	if grid.has(cell):
		return false
	if planet.level[cell] >= D.MAX_LEVEL:
		return false
	if type == D.DRILL and planet.ore[cell] == 0:
		return false
	if _arc(cell, planet.core_center[team]) > D.BUILD_ARC:
		return false
	if storage[team] < D.COST[type]:
		return false
	return true


# =====================================================================
# Постройки (общая часть)
# =====================================================================

func _add_building(d: Dictionary) -> void:
	var b := {
		"id": int(d.id), "type": int(d.type), "team": int(d.team),
		"cell": int(d.cell), "dir": int(d.dir),
		"hp": D.HP[int(d.type)], "item": false, "prog": 0.0,
		"store": 0, "timer": 0, "rr": 0,
	}
	buildings[b.id] = b
	for c in _cells_of(b.type, b.cell):
		grid[c] = b.id
	next_id = maxi(next_id, b.id + 1)
	if not headless:
		_vis_add(b)


func _remove_building(id: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	for c in _cells_of(b.type, b.cell):
		grid.erase(c)
	buildings.erase(id)
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
	if not _can_place(team, type, cell):
		return
	storage[team] -= D.COST[type]
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
	storage[team] += D.COST[b.type] / 2
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


func server_player_state(peer: int, pos: Vector3, fwd: Vector3) -> void:
	var team: int = Net.team_of(peer)
	if team < 0:
		return
	if not players.has(peer):
		players[peer] = {"team": team, "pos": pos, "fwd": fwd, "hp": D.PLAYER_HP, "dead_t": 0, "last_shot": 0}
	var pl: Dictionary = players[peer]
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
func req_player_state(pos: Vector3, fwd: Vector3) -> void:
	if multiplayer.is_server():
		server_player_state(multiplayer.get_remote_sender_id(), pos, fwd)


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
func snapshot(u: PackedFloat32Array, it: PackedVector3Array, pl: Array, st: Array, hp: Array) -> void:
	_apply_snapshot(u, it, pl, st, hp)


@rpc("authority", "call_remote", "unreliable")
func fx_shot(from: Vector3, to: Vector3) -> void:
	_tracer(from, to)


# =====================================================================
# Сервер: симуляция
# =====================================================================

func _process(delta: float) -> void:
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


func _sim_tick() -> void:
	for b in buildings.values():
		if not buildings.has(b.id):
			continue
		var t: int = b.type
		if t == D.DRILL:
			b.timer += 1
			if b.timer >= D.DRILL_TICKS:
				b.timer = 0 if _drill_output(b) else D.DRILL_TICKS
		elif t == D.CONVEYOR:
			if b.item:
				b.prog = minf(b.prog + D.CONVEYOR_SPEED, 1.0)
				if b.prog >= 1.0 and _push(_out_cell(b), b.cell, b.team):
					b.item = false
					b.prog = 0.0
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
	_waves()
	_units_tick()


## Положить 1 руду в клетку cell, пришедшую из клетки from. true — если взяли.
func _push(cell: int, from: int, team: int) -> bool:
	if not grid.has(cell):
		return false
	var o: Dictionary = buildings[grid[cell]]
	if o.team != team:
		return false
	if o.type == D.CONVEYOR:
		if o.item or _out_cell(o) == from:
			return false
		o.item = true
		o.prog = 0.0
		return true
	if o.type == D.CORE:
		storage[team] += 1
		return true
	if o.type == D.ASSEMBLER:
		if o.store < D.UNIT_COST * 3:
			o.store += 1
			return true
	return false


func _drill_output(b: Dictionary) -> bool:
	var nb: PackedInt32Array = planet.nbrs[b.cell]
	var k := nb.size()
	for i in k:
		var idx: int = (b.rr + i) % k
		if _push(nb[idx], b.cell, b.team):
			b.rr = (idx + 1) % k
			return true
	return false


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


## Пока ботов нет: команда без игроков шлёт волны юнитов из ядра (временный PvE).
func _waves() -> void:
	if Net.peer_team.is_empty():
		return
	for t in 2:
		if Net.team_has_players(t):
			continue
		wave_timer[t] += 1
		if wave_timer[t] >= D.WAVE_TICKS:
			wave_timer[t] = 0
			wave_count[t] += 1
			var nb: PackedInt32Array = planet.nbrs[planet.core_center[t]]
			var n: int = 1 + wave_count[t] / 2
			for i in n:
				_spawn_unit(t, nb[i % nb.size()])


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
	for b in buildings.values():
		if b.type == D.CONVEYOR and b.item:
			var a := _bpos(b)
			var nxt := planet.top_pos(_out_cell(b))
			var up: Vector3 = planet.dirs[b.cell]
			it.append(a + (nxt - a) * (float(b.prog) - 0.5) + up * 0.3)
	var pl: Array = []
	for pid in players:
		var o: Dictionary = players[pid]
		pl.append([pid, o.pos, o.fwd, o.team, o.hp])
	for p in Net.ready_peers:
		snapshot.rpc_id(p, u, it, pl, storage, core_hp)
	if not headless:
		_apply_snapshot(u, it, pl, storage, core_hp)


# =====================================================================
# Клиент: сцена
# =====================================================================

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.6)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_color = Color(1.0, 0.92, 0.85)
	sun.shadow_enabled = true
	add_child(sun)

	# поверхность планеты: меш + коллизия
	var built: Array = planet.build_mesh()
	var terrain := MeshInstance3D.new()
	terrain.mesh = built[0]
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.roughness = 0.95
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
	var giant := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 700
	sm.height = 1400
	sm.radial_segments = 96
	sm.rings = 48
	giant.mesh = sm
	giant.position = Vector3(-600, 500, -2400)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.85, 0.55, 0.3)
	gmat.emission_enabled = true
	gmat.emission = Color(0.45, 0.22, 0.08)
	giant.material_override = gmat
	add_child(giant)

	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.instance_count = 600
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 3.0
	star_mesh.height = 6.0
	star_mesh.radial_segments = 4
	star_mesh.rings = 2
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(1, 1, 1)
	star_mesh.material = star_mat
	stars.mesh = star_mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in stars.instance_count:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		stars.set_instance_transform(i, Transform3D(Basis(), v * 3500.0))
	var stars_mmi := MultiMeshInstance3D.new()
	stars_mmi.multimesh = stars
	add_child(stars_mmi)

	# руда на лентах
	mm_items = MultiMesh.new()
	mm_items.transform_format = MultiMesh.TRANSFORM_3D
	mm_items.instance_count = 8192
	mm_items.visible_instance_count = 0
	var isph := SphereMesh.new()
	isph.radius = 0.18
	isph.height = 0.36
	isph.material = _mat(Color(1.0, 0.6, 0.25), true)
	mm_items.mesh = isph
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
	var umat := StandardMaterial3D.new()
	umat.vertex_color_use_as_albedo = true
	ubox.material = umat
	mm_units.mesh = ubox
	var units_mmi := MultiMeshInstance3D.new()
	units_mmi.multimesh = mm_units
	add_child(units_mmi)

	# орбитальная камера
	orbit_cam = Camera3D.new()
	orbit_cam.far = 6000
	add_child(orbit_cam)
	var cd: Vector3 = planet.dirs[planet.core_center[maxi(my_team, 0)]]
	_orbit_look_at(cd)

	# призрак постройки: шестигранник + стрелка направления
	ghost = Node3D.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var gh := MeshInstance3D.new()
	var ghm := CylinderMesh.new()
	ghm.top_radius = 0.95
	ghm.bottom_radius = 0.95
	ghm.height = 0.3
	ghm.radial_segments = 6
	gh.mesh = ghm
	gh.position.y = 0.15
	gh.material_override = ghost_mat
	ghost.add_child(gh)
	var ga := MeshInstance3D.new()
	var gam := BoxMesh.new()
	gam.size = Vector3(0.8, 0.35, 0.2)
	ga.mesh = gam
	ga.position = Vector3(0.45, 0.3, 0)
	ga.material_override = ghost_mat
	ghost.add_child(ga)
	add_child(ghost)

	# интерфейс
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_size_override("font_size", 17)
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
		_set_fps(true)
	else:
		_set_fps(false)


func _mat(color: Color, glow := false) -> StandardMaterial3D:
	var key := "%s|%s" % [color, glow]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.5
	mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := false) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = _mat(color, glow)
	parent.add_child(m)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, color: Color, segs := 16) -> void:
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


## Ставит узел на верх клетки: локальная Y — нормаль, локальная X — в сторону соседа.
func _orient(n: Node3D, cell: int, toward: int) -> void:
	var o := planet.top_pos(cell)
	var up: Vector3 = planet.dirs[cell]
	var f := planet.top_pos(toward) - o
	f = (f - up * f.dot(up)).normalized()
	n.transform = Transform3D(Basis(f, up, f.cross(up)), o)


func _vis_add(b: Dictionary) -> void:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[b.team]
	var t: int = b.type
	if t == D.CORE:
		_cyl(n, 2.6, 1.4, Vector3(0, 0.7, 0), col.darkened(0.4), 6)
		_box(n, Vector3(1.6, 1.4, 1.6), Vector3(0, 2.1, 0), col, true)
	elif t == D.CONVEYOR:
		_cyl(n, 0.85, 0.1, Vector3(0, 0.05, 0), Color(0.27, 0.27, 0.3), 6)
		_box(n, Vector3(0.8, 0.12, 0.22), Vector3(0.2, 0.12, 0), col, true)
	elif t == D.DRILL:
		_box(n, Vector3(1.1, 0.7, 1.1), Vector3(0, 0.35, 0), col.darkened(0.45))
		_cyl(n, 0.28, 0.8, Vector3(0, 1.1, 0), Color(0.85, 0.6, 0.3))
	elif t == D.ASSEMBLER:
		_box(n, Vector3(1.3, 1.2, 1.3), Vector3(0, 0.6, 0), col.darkened(0.25))
		_box(n, Vector3(0.7, 0.25, 0.7), Vector3(0, 1.32, 0), col, true)
	elif t == D.TURRET:
		_cyl(n, 0.55, 0.6, Vector3(0, 0.3, 0), col.darkened(0.35))
		_box(n, Vector3(1.0, 0.2, 0.2), Vector3(0.4, 0.75, 0), Color(0.75, 0.75, 0.8))
	# твёрдое тело, чтобы персонаж не проходил сквозь постройки (по конвейерам ходим)
	if t != D.CONVEYOR:
		var size := Vector3(4.4, 2.8, 4.4) if t == D.CORE else Vector3(1.2, 1.3, 1.2)
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		shape_node.position.y = size.y / 2.0
		body.add_child(shape_node)
		n.add_child(body)
	add_child(n)
	var nb: PackedInt32Array = planet.nbrs[b.cell]
	_orient(n, b.cell, nb[int(b.dir) % nb.size()])
	bnodes[b.id] = n


# =====================================================================
# Клиент: снапшоты, камера, ввод
# =====================================================================

func _apply_snapshot(u: PackedFloat32Array, it: PackedVector3Array, pl: Array, st: Array, hp: Array) -> void:
	prev_units = cur_units
	cur_units = u
	cur_items = it
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
		var sp := delta * 1.2 * (orbit_dist / 75.0)
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
				server_player_state(1, player.global_position, fwd)
			else:
				req_player_state.rpc_id(1, player.global_position, fwd)

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
			and sel_type != D.WEAPON and alive
	if ghost.visible:
		var nb: PackedInt32Array = planet.nbrs[hover_cell]
		_orient(ghost, hover_cell, nb[hover_dir])
		var ok := _can_place(my_team, sel_type, hover_cell)
		ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)
	if drag_mode != 0 and hover_cell != NO_CELL and hover_cell != drag_last and alive:
		drag_last = hover_cell
		if drag_mode == 1 and sel_type != D.WEAPON:
			_request_place(hover_cell, hover_dir)
		elif drag_mode == 2:
			_request_remove(hover_cell)

	_update_hud()


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
		mm_items.set_instance_transform(i, Transform3D(Basis(), cur_items[i]))
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
	hover_cell = planet.nearest_cell(hp.normalized())

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


func _make_avatar(team: int) -> Node3D:
	var n := Node3D.new()
	var col: Color = D.TEAM_COLORS[team]
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.8
	body.mesh = cm
	body.position.y = 0.9
	body.material_override = _mat(col.darkened(0.2))
	n.add_child(body)
	_box(n, Vector3(0.5, 0.2, 0.2), Vector3(0, 1.55, -0.28), Color(0.4, 0.9, 1.0), true)  # визор
	add_child(n)
	return n


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
	var enemy := 1 - my_team
	var lines := PackedStringArray()
	lines.append("Команда: %s     Здоровье: %d" % [D.TEAM_NAMES[my_team], my_hp])
	lines.append("Руда в ядре: %d" % storage[my_team])
	lines.append("Ядро: %d   |   Ядро врага: %d (на другой стороне планеты)" % [core_hp[my_team], core_hp[enemy]])
	lines.append("")
	lines.append("[1] Конвейер (%d)   [2] Бур (%d)   [3] Сборщик (%d)   [4] Турель (%d)   [5] Бластер" % [
		D.COST[D.CONVEYOR], D.COST[D.DRILL], D.COST[D.ASSEMBLER], D.COST[D.TURRET]])
	if sel_type == D.WEAPON:
		lines.append("В руках: Бластер  (ЛКМ — огонь)")
	else:
		var info := ""
		if hover_cell != NO_CELL:
			var lv: int = planet.level[hover_cell]
			info = "   | клетка: высота %d%s%s" % [lv, ", руда" if planet.ore[hover_cell] == 1 else "",
				", скалы — нельзя" if lv >= D.MAX_LEVEL else ""]
		lines.append("В руках: %s   (направление — куда смотришь, R — повернуть)%s" % [D.NAMES[sel_type], info])
	if fps_mode:
		lines.append("WASD — ходить   Space — прыжок   Shift — бег   ЛКМ/ПКМ — строить/снести")
		lines.append("Tab — орбитальная камера   Esc — отпустить курсор")
	else:
		lines.append("ЛКМ — строить (можно тянуть)   ПКМ — снести   WASD — крутить планету   колесо — зум")
		lines.append("Tab — от первого лица")
	hud.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if headless:
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
				orbit_dist = maxf(D.PLANET_R + 8.0, orbit_dist - 4.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if fps_mode:
				_cycle_slot(1)
			else:
				orbit_dist = minf(250.0, orbit_dist + 4.0)
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
				sel_type = D.CONVEYOR
			KEY_2:
				sel_type = D.DRILL
			KEY_3:
				sel_type = D.ASSEMBLER
			KEY_4:
				sel_type = D.TURRET
			KEY_5:
				sel_type = D.WEAPON
			KEY_R:
				sel_rot += 1
			KEY_TAB:
				_set_fps(not fps_mode)
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cycle_slot(step: int) -> void:
	var i := SLOTS.find(sel_type)
	sel_type = SLOTS[posmod(i + step, SLOTS.size())]


func _request_place(cell: int, dir: int) -> void:
	if not _can_place(my_team, sel_type, cell):
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
