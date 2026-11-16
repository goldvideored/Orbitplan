extends Node3D
## Игровой мир одного спутника.
## На сервере: симуляция (буры, конвейеры, сборщики, турели, юниты).
## На клиенте: отрисовка, камера, ввод. Хост делает и то и другое.

const D = preload("res://scripts/defs.gd")
const NO_TILE := Vector2i(-9999, -9999)

var my_team := 0
var is_server := false
var headless := false

# --- общее состояние (есть у всех) ---
var ore := {}        # Vector2i -> true
var grid := {}       # Vector2i -> id постройки
var buildings := {}  # id -> Dictionary
var storage := [D.START_ORE, D.START_ORE]
var core_hp := [D.HP[D.CORE], D.HP[D.CORE]]
var finished := false

# --- только сервер ---
var units: Array = []
var next_id := 1
var next_unit_id := 1
var tick_acc := 0.0
var wave_timer := [0, 0]
var wave_count := [0, 0]

# --- только клиент ---
var bnodes := {}
var mats := {}
var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_dist := 28.0
var ghost: Node3D
var ghost_mat: StandardMaterial3D
var sel_type := D.CONVEYOR
var sel_dir := 0
var mm_items: MultiMesh
var mm_units: MultiMesh
var hud: Label
var big_msg: Label
var prev_units := PackedFloat32Array()
var cur_units := PackedFloat32Array()
var cur_items := PackedVector2Array()
var snap_time := 0.0
var drag_mode := 0   # 0 нет, 1 строим, 2 сносим
var drag_last := NO_TILE


func setup(seed_val: int, team: int, server: bool, dedicated: bool) -> void:
	my_team = team
	is_server = server
	headless = dedicated
	_gen_ore(seed_val)
	if not headless:
		_build_scene()
	if is_server:
		for t in 2:
			var c: Vector2i = D.CORE_POS[t]
			_add_building({"id": _new_id(), "type": D.CORE, "team": t, "x": c.x, "y": c.y, "dir": 0})


# =====================================================================
# Карта
# =====================================================================

func _gen_ore(seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var centers: Array = []
	for t in 2:
		var c: Vector2i = D.CORE_POS[t]
		var side := 1 if t == 0 else -1
		centers.append(c + Vector2i(5 * side, -5))
		centers.append(c + Vector2i(5 * side, 5))
	for i in 3:
		var p := Vector2i(rng.randi_range(18, 29), rng.randi_range(6, 57))
		centers.append(p)
		centers.append(Vector2i(D.MAP - 1 - p.x, p.y))  # зеркально для честности
	for c in centers:
		var r := rng.randf_range(1.8, 3.2)
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				if Vector2(dx, dy).length() <= r:
					var p: Vector2i = c + Vector2i(dx, dy)
					if _in_map(p):
						ore[p] = true


func _in_map(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < D.MAP and p.y < D.MAP


func _tiles_of(type: int, pos: Vector2i) -> Array:
	if type == D.CORE:
		var arr: Array = []
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				arr.append(pos + Vector2i(dx, dy))
		return arr
	return [pos]


func _bcenter(b: Dictionary) -> Vector2:
	var p: Vector2i = b.pos
	return Vector2(p) + Vector2(0.5, 0.5)


func _new_id() -> int:
	var i := next_id
	next_id += 1
	return i


func _can_place(team: int, type: int, p: Vector2i) -> bool:
	if team < 0 or finished:
		return false
	if not _in_map(p) or grid.has(p):
		return false
	if type == D.DRILL and not ore.has(p):
		return false
	var c: Vector2i = D.CORE_POS[team]
	if Vector2(p - c).length() > D.BUILD_RADIUS:
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
		"pos": Vector2i(int(d.x), int(d.y)), "dir": int(d.dir),
		"hp": D.HP[int(d.type)], "item": false, "prog": 0.0,
		"store": 0, "timer": 0, "rr": 0,
	}
	buildings[b.id] = b
	for t in _tiles_of(b.type, b.pos):
		grid[t] = b.id
	next_id = maxi(next_id, b.id + 1)
	if not headless:
		_vis_add(b)


func _remove_building(id: int) -> void:
	if not buildings.has(id):
		return
	var b: Dictionary = buildings[id]
	for t in _tiles_of(b.type, b.pos):
		grid.erase(t)
	buildings.erase(id)
	if bnodes.has(id):
		bnodes[id].queue_free()
		bnodes.erase(id)


func _bdata(b: Dictionary) -> Dictionary:
	var p: Vector2i = b.pos
	return {"id": b.id, "type": b.type, "team": b.team, "x": p.x, "y": p.y, "dir": b.dir}


# =====================================================================
# Сервер: команды игроков
# =====================================================================

func server_place(team: int, type: int, x: int, y: int, dir: int) -> void:
	if not D.COST.has(type) or type == D.CORE:
		return
	var p := Vector2i(x, y)
	if not _can_place(team, type, p):
		return
	storage[team] -= D.COST[type]
	var d := {"id": _new_id(), "type": type, "team": team, "x": x, "y": y, "dir": posmod(dir, 4)}
	_add_building(d)
	for peer in Net.ready_peers:
		ev_add.rpc_id(peer, d)


func server_remove(team: int, x: int, y: int) -> void:
	var p := Vector2i(x, y)
	if finished or not grid.has(p):
		return
	var b: Dictionary = buildings[grid[p]]
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


# =====================================================================
# RPC
# =====================================================================

@rpc("any_peer", "call_remote", "reliable")
func req_place(type: int, x: int, y: int, dir: int) -> void:
	if not multiplayer.is_server():
		return
	var team := Net.team_of(multiplayer.get_remote_sender_id())
	server_place(team, type, x, y, dir)


@rpc("any_peer", "call_remote", "reliable")
func req_remove(x: int, y: int) -> void:
	if not multiplayer.is_server():
		return
	var team := Net.team_of(multiplayer.get_remote_sender_id())
	server_remove(team, x, y)


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
func full_sync(list: Array) -> void:
	for d in list:
		if not buildings.has(int(d.id)):
			_add_building(d)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(u: PackedFloat32Array, it: PackedVector2Array, st: Array, hp: Array) -> void:
	_apply_snapshot(u, it, st, hp)


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
				var next: Vector2i = b.pos + D.DIRS[b.dir]
				if b.prog >= 1.0 and _push(next, b.pos, b.team):
					b.item = false
					b.prog = 0.0
		elif t == D.ASSEMBLER:
			if b.timer > 0:
				b.timer -= 1
				if b.timer == 0:
					_spawn_unit(b.team, _bcenter(b))
			elif b.store >= D.UNIT_COST:
				b.store -= D.UNIT_COST
				b.timer = D.UNIT_BUILD_TICKS
		elif t == D.TURRET:
			_turret_tick(b)
	_waves()
	_units_tick()


## Положить 1 руду в клетку tile, пришедшую из клетки from. true — если взяли.
func _push(tile: Vector2i, from: Vector2i, team: int) -> bool:
	if not grid.has(tile):
		return false
	var o: Dictionary = buildings[grid[tile]]
	if o.team != team:
		return false
	if o.type == D.CONVEYOR:
		var out: Vector2i = tile + D.DIRS[o.dir]
		if o.item or out == from:
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
	for i in 4:
		var k: int = (b.rr + i) % 4
		var tile: Vector2i = b.pos + D.DIRS[k]
		if _push(tile, b.pos, b.team):
			b.rr = (k + 1) % 4
			return true
	return false


func _turret_tick(b: Dictionary) -> void:
	if b.timer > 0:
		b.timer -= 1
		return
	var c := _bcenter(b)
	var best = null
	var bd: float = D.TURRET_RANGE
	for u in units:
		if u.team != b.team and u.hp > 0:
			var d: float = c.distance_to(u.pos)
			if d < bd:
				bd = d
				best = u
	if best != null:
		best.hp -= D.TURRET_DMG
		b.timer = D.TURRET_CD


func _spawn_unit(team: int, at: Vector2) -> void:
	var jitter := Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
	units.append({"id": next_unit_id, "team": team, "pos": at + jitter, "hp": D.UNIT_HP, "cd": 0})
	next_unit_id += 1


## Пока ботов нет: команда без игроков шлёт волны юнитов из ядра (это и есть PvE).
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
			var c: Vector2i = D.CORE_POS[t]
			var side := 2.5 if t == 0 else -1.5
			var n: int = 1 + wave_count[t] / 2
			for i in n:
				_spawn_unit(t, Vector2(c) + Vector2(0.5 + side, 0.5))


func _units_tick() -> void:
	for u in units:
		if u.hp <= 0:
			continue
		if u.cd > 0:
			u.cd -= 1
		var target_unit = null
		var best: float = D.UNIT_AGGRO
		for o in units:
			if o.hp <= 0 or o.id == u.id:
				continue
			var d: float = u.pos.distance_to(o.pos)
			if o.team != u.team:
				if d < best:
					best = d
					target_unit = o
			elif d < 0.5 and d > 0.001:
				# чтобы свои не слипались в одну точку
				u.pos += (u.pos - o.pos).normalized() * 0.05

		var tpos: Vector2
		var reach: float
		var target_b = null
		if target_unit != null:
			tpos = target_unit.pos
			reach = D.UNIT_RANGE
		else:
			target_b = _nearest_enemy_building(u)
			if target_b == null:
				continue
			tpos = _bcenter(target_b)
			reach = D.UNIT_RANGE + (1.5 if target_b.type == D.CORE else 0.5)

		var dist: float = u.pos.distance_to(tpos)
		if dist > reach:
			var step: float = minf(D.UNIT_SPEED, dist - reach + 0.01)
			u.pos += (tpos - u.pos).normalized() * step
		elif u.cd == 0:
			u.cd = D.UNIT_CD
			if target_unit != null:
				target_unit.hp -= D.UNIT_DMG
			else:
				_damage_building(target_b, D.UNIT_DMG)
				if finished:
					return
	units = units.filter(func(x): return x.hp > 0)


func _nearest_enemy_building(u: Dictionary):
	var best = null
	var bd := INF
	for b in buildings.values():
		if b.team == u.team:
			continue
		var d: float = u.pos.distance_squared_to(_bcenter(b))
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
		u.append(x.pos.x)
		u.append(x.pos.y)
		u.append(float(x.team))
		u.append(float(x.hp) / D.UNIT_HP)
	var it := PackedVector2Array()
	for b in buildings.values():
		if b.type == D.CONVEYOR and b.item:
			var dv: Vector2 = Vector2(D.DIRS[b.dir])
			it.append(_bcenter(b) + dv * (float(b.prog) - 0.5))
	for p in Net.ready_peers:
		snapshot.rpc_id(p, u, it, storage, core_hp)
	if not headless:
		_apply_snapshot(u, it, storage, core_hp)


# =====================================================================
# Клиент: сцена
# =====================================================================

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.6)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color(1.0, 0.92, 0.85)
	sun.shadow_enabled = true
	add_child(sun)

	# поверхность спутника
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(D.MAP, D.MAP)
	ground.mesh = pm
	ground.position = Vector3(D.MAP / 2.0, 0, D.MAP / 2.0)
	ground.material_override = _mat(Color(0.16, 0.15, 0.19))
	add_child(ground)

	# газовый гигант на фоне
	var giant := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 250
	sm.height = 500
	giant.mesh = sm
	giant.position = Vector3(D.MAP / 2.0, -300, -400)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.85, 0.55, 0.3)
	gmat.emission_enabled = true
	gmat.emission = Color(0.5, 0.25, 0.1)
	giant.material_override = gmat
	add_child(giant)

	# руда
	var ore_mm := MultiMesh.new()
	ore_mm.transform_format = MultiMesh.TRANSFORM_3D
	ore_mm.instance_count = ore.size()
	var ob := BoxMesh.new()
	ob.size = Vector3(0.96, 0.04, 0.96)
	ob.material = _mat(Color(0.75, 0.45, 0.2))
	ore_mm.mesh = ob
	var i := 0
	for p in ore.keys():
		ore_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x + 0.5, 0.02, p.y + 0.5)))
		i += 1
	var ore_mmi := MultiMeshInstance3D.new()
	ore_mmi.multimesh = ore_mm
	add_child(ore_mmi)

	# предметы на конвейерах
	mm_items = MultiMesh.new()
	mm_items.transform_format = MultiMesh.TRANSFORM_3D
	mm_items.instance_count = 8192
	mm_items.visible_instance_count = 0
	var isph := SphereMesh.new()
	isph.radius = 0.14
	isph.height = 0.28
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
	ubox.size = Vector3(0.5, 0.35, 0.5)
	var umat := StandardMaterial3D.new()
	umat.vertex_color_use_as_albedo = true
	ubox.material = umat
	mm_units.mesh = ubox
	var units_mmi := MultiMeshInstance3D.new()
	units_mmi.multimesh = mm_units
	add_child(units_mmi)

	# камера
	cam = Camera3D.new()
	cam.far = 2000
	add_child(cam)
	cam.current = true
	var start_team := maxi(my_team, 0)
	var cp: Vector2i = D.CORE_POS[start_team]
	cam_target = Vector3(cp.x + 0.5, 0, cp.y + 0.5)

	# призрак постройки
	ghost = Node3D.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var gb := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(0.95, 0.3, 0.95)
	gb.mesh = gbm
	gb.material_override = ghost_mat
	ghost.add_child(gb)
	var ga := MeshInstance3D.new()
	var gam := BoxMesh.new()
	gam.size = Vector3(0.5, 0.35, 0.15)
	ga.mesh = gam
	ga.position = Vector3(0.2, 0, 0)
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


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	m.mesh = cm
	m.position = pos
	m.material_override = _mat(color)
	parent.add_child(m)


func _vis_add(b: Dictionary) -> void:
	var n := Node3D.new()
	var p: Vector2i = b.pos
	n.position = Vector3(p.x + 0.5, 0, p.y + 0.5)
	var col: Color = D.TEAM_COLORS[b.team]
	var t: int = b.type
	if t == D.CORE:
		_box(n, Vector3(2.8, 1.2, 2.8), Vector3(0, 0.6, 0), col.darkened(0.4))
		_box(n, Vector3(1.4, 1.0, 1.4), Vector3(0, 1.7, 0), col, true)
	elif t == D.CONVEYOR:
		_box(n, Vector3(0.94, 0.08, 0.94), Vector3(0, 0.04, 0), Color(0.27, 0.27, 0.3))
		_box(n, Vector3(0.45, 0.1, 0.14), Vector3(0.12, 0.09, 0), col, true)
		n.rotation.y = -float(b.dir) * PI / 2.0
	elif t == D.DRILL:
		_box(n, Vector3(0.8, 0.5, 0.8), Vector3(0, 0.25, 0), col.darkened(0.45))
		_cyl(n, 0.2, 0.6, Vector3(0, 0.8, 0), Color(0.85, 0.6, 0.3))
	elif t == D.ASSEMBLER:
		_box(n, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), col.darkened(0.25))
		_box(n, Vector3(0.5, 0.2, 0.5), Vector3(0, 1.0, 0), col, true)
	elif t == D.TURRET:
		_cyl(n, 0.4, 0.4, Vector3(0, 0.2, 0), col.darkened(0.35))
		_box(n, Vector3(0.7, 0.15, 0.15), Vector3(0.3, 0.5, 0), Color(0.75, 0.75, 0.8))
	add_child(n)
	bnodes[b.id] = n


# =====================================================================
# Клиент: снапшоты, камера, ввод
# =====================================================================

func _apply_snapshot(u: PackedFloat32Array, it: PackedVector2Array, st: Array, hp: Array) -> void:
	prev_units = cur_units
	cur_units = u
	cur_items = it
	snap_time = 0.0
	if not is_server:
		storage = st
		core_hp = hp


func _update_client(delta: float) -> void:
	# камера
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1
	if mv != Vector3.ZERO:
		cam_target += mv.normalized() * delta * cam_dist * 1.2
	cam_target.x = clampf(cam_target.x, 0, D.MAP)
	cam_target.z = clampf(cam_target.z, 0, D.MAP)
	cam.position = cam_target + Vector3(0, cam_dist * 0.85, cam_dist * 0.55)
	cam.look_at(cam_target, Vector3.UP)

	# юниты (плавно между снапшотами)
	snap_time += delta
	var a := clampf(snap_time / D.TICK, 0.0, 1.0)
	var n := mini(cur_units.size() / 4, mm_units.instance_count)
	var can_lerp := prev_units.size() == cur_units.size()
	for i in n:
		var x := cur_units[i * 4]
		var z := cur_units[i * 4 + 1]
		if can_lerp:
			x = lerpf(prev_units[i * 4], x, a)
			z = lerpf(prev_units[i * 4 + 1], z, a)
		var team := int(cur_units[i * 4 + 2])
		var hpf := cur_units[i * 4 + 3]
		var col: Color = D.TEAM_COLORS[team]
		mm_units.set_instance_transform(i, Transform3D(Basis(), Vector3(x, 0.25, z)))
		mm_units.set_instance_color(i, col.darkened(0.6 * (1.0 - hpf)))
	mm_units.visible_instance_count = n

	# руда на лентах
	var m := mini(cur_items.size(), mm_items.instance_count)
	for i in m:
		var p := cur_items[i]
		mm_items.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.22, p.y)))
	mm_items.visible_instance_count = m

	# призрак и строительство протяжкой
	var tile := _mouse_tile()
	ghost.visible = tile != NO_TILE and not finished and my_team >= 0
	if ghost.visible:
		ghost.position = Vector3(tile.x + 0.5, 0.15, tile.y + 0.5)
		ghost.rotation.y = -float(sel_dir) * PI / 2.0
		var ok := _can_place(my_team, sel_type, tile)
		ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)
		if drag_mode != 0 and tile != drag_last:
			drag_last = tile
			if drag_mode == 1:
				_request_place(tile)
			else:
				_request_remove(tile)

	_update_hud()


func _update_hud() -> void:
	if my_team < 0:
		return
	var enemy := 1 - my_team
	var lines := PackedStringArray()
	lines.append("Команда: %s" % D.TEAM_NAMES[my_team])
	lines.append("Руда в ядре: %d" % storage[my_team])
	lines.append("Ядро: %d   |   Ядро врага: %d" % [core_hp[my_team], core_hp[enemy]])
	lines.append("")
	lines.append("[1] Конвейер (%d)   [2] Бур (%d)   [3] Сборщик (%d)   [4] Турель (%d)" % [
		D.COST[D.CONVEYOR], D.COST[D.DRILL], D.COST[D.ASSEMBLER], D.COST[D.TURRET]])
	lines.append("Выбрано: %s   направление %s  (R — повернуть)" % [D.NAMES[sel_type], D.DIR_ARROWS[sel_dir]])
	lines.append("ЛКМ — строить (можно тянуть)   ПКМ — снести   WASD — камера   колесо — зум")
	hud.text = "\n".join(lines)


func _mouse_tile() -> Vector2i:
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if dir.y > -0.001:
		return NO_TILE
	var hit := from + dir * (-from.y / dir.y)
	var t := Vector2i(floori(hit.x), floori(hit.z))
	return t if _in_map(t) else NO_TILE


func _unhandled_input(event: InputEvent) -> void:
	if headless:
		return
	var mb := event as InputEventMouseButton
	if mb:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = maxf(8.0, cam_dist - 2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = minf(70.0, cam_dist + 2.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			drag_mode = 1 if mb.pressed else 0
			drag_last = NO_TILE
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			drag_mode = 2 if mb.pressed else 0
			drag_last = NO_TILE
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
			KEY_R:
				sel_dir = (sel_dir + 1) % 4


func _request_place(tile: Vector2i) -> void:
	if not _can_place(my_team, sel_type, tile):
		return
	if is_server:
		server_place(my_team, sel_type, tile.x, tile.y, sel_dir)
	else:
		req_place.rpc_id(1, sel_type, tile.x, tile.y, sel_dir)


func _request_remove(tile: Vector2i) -> void:
	if my_team < 0 or not grid.has(tile):
		return
	if is_server:
		server_remove(my_team, tile.x, tile.y)
	else:
		req_remove.rpc_id(1, tile.x, tile.y)


func _show_over(winner: int) -> void:
	finished = true
	if big_msg == null:
		return
	if winner == my_team:
		big_msg.text = "ПОБЕДА\nядро противника уничтожено"
	else:
		big_msg.text = "ПОРАЖЕНИЕ\nтвоё ядро уничтожено"
