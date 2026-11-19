extends RefCounted
## Сферическая планета из многоугольников (многогранник Голдберга):
## шестиугольники + 12 пятиугольников. Каждая клетка — зона постройки.
## Генерация детерминирована по seed — у сервера и всех клиентов одинаковая.

const D = preload("res://scripts/defs.gd")

var dirs := PackedVector3Array()   # центр клетки, единичный вектор
var nbrs: Array = []               # [PackedInt32Array] соседи, по кругу
var corners: Array = []            # [PackedVector3Array] углы (единичные), по кругу
var level := PackedInt32Array()    # высота террасы
var ore := PackedInt32Array()      # тип залежи (D.I_*) или D.I_NONE
var radius: float = D.PLANET_R
var subdiv: int = D.SUBDIV
var kind := 0                       # 0 обычная, 1 малая токсичная, 2 большая с атмосферой
var hazard := PackedByteArray()     # жгучие клетки (светятся красным, жгут игрока)
var deco := PackedByteArray()       # окружение: 0 нет, 1 валун, 2 кристаллический шпиль, 3 растение (строить нельзя)
var extra_sites: Array = []         # дополнительные нейтральные базы (на большой планете)
var core_center := [0, 0, 0]   # центр площадки под базу (по D.CORE_DIRS)
var spawn_cell := [0, 0, 0]

# временные буферы для сборки меша
var _mv := PackedVector3Array()
var _mn := PackedVector3Array()
var _mc := PackedColorArray()
var _mu := PackedVector2Array()    # UV: пиксельные координаты в плоскости клетки (м)
var _mu2 := PackedVector2Array()   # UV2: (уровень, вид грани * 16 + руда + 1) — для шейдера


func generate(seed_val: int, pn: int = D.HOME_PLANET) -> void:
	var spec: Dictionary = D.PLANETS[pn]
	radius = float(spec.get("r", D.PLANET_R))
	subdiv = int(spec.get("subdiv", D.SUBDIV))
	kind = int(spec.get("kind", 0))
	_build_geometry()
	_build_relief(seed_val)


func count() -> int:
	return dirs.size()


func top_r(c: int) -> float:
	return radius + level[c] * D.LEVEL_STEP


func top_pos(c: int) -> Vector3:
	return dirs[c] * top_r(c)


## Ближайшая клетка к направлению (перебором).
func nearest_cell(dir: Vector3) -> int:
	var best := 0
	var bd := -2.0
	for i in dirs.size():
		var d := dirs[i].dot(dir)
		if d > bd:
			bd = d
			best = i
	return best


## Ближайшая клетка, начиная поиск с клетки c (быстро, если двигаемся понемногу).
func walk(c: int, dir: Vector3) -> int:
	if c < 0:
		return nearest_cell(dir)
	for _guard in 64:
		var best := c
		var bd := dirs[c].dot(dir)
		var nb: PackedInt32Array = nbrs[c]
		for x in nb:
			var d := dirs[x].dot(dir)
			if d > bd:
				bd = d
				best = x
		if best == c:
			return c
		c = best
	return c


## Обход в ширину: клетка -> расстояние в шагах.
func rings(start: int, max_d: int) -> Dictionary:
	var dist := {start: 0}
	var queue: Array = [start]
	var qi := 0
	while qi < queue.size():
		var c: int = queue[qi]
		qi += 1
		var dc: int = dist[c]
		if dc >= max_d:
			continue
		var nb: PackedInt32Array = nbrs[c]
		for x in nb:
			if not dist.has(x):
				dist[x] = dc + 1
				queue.append(x)
	return dist


# ---------------------------------------------------------------------
# Геометрия
# ---------------------------------------------------------------------

func _build_geometry() -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var iv := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var n: int = subdiv
	var index := {}
	var tri := PackedInt32Array()
	for f in faces:
		var a: Vector3 = iv[f[0]]
		var b: Vector3 = iv[f[1]]
		var c: Vector3 = iv[f[2]]
		var ids := {}
		for i in range(n + 1):
			for j in range(n + 1 - i):
				var p: Vector3 = (a * float(n - i - j) + b * float(i) + c * float(j)) / float(n)
				p = p.normalized()
				var key := Vector3i(roundi(p.x * 100000.0), roundi(p.y * 100000.0), roundi(p.z * 100000.0))
				var id: int
				if index.has(key):
					id = index[key]
				else:
					id = dirs.size()
					index[key] = id
					dirs.append(p)
				ids[Vector2i(i, j)] = id
		for i in range(n):
			for j in range(n - i):
				tri.append(ids[Vector2i(i, j)])
				tri.append(ids[Vector2i(i + 1, j)])
				tri.append(ids[Vector2i(i, j + 1)])
				if j < n - 1 - i:
					tri.append(ids[Vector2i(i + 1, j)])
					tri.append(ids[Vector2i(i + 1, j + 1)])
					tri.append(ids[Vector2i(i, j + 1)])

	var cnt := dirs.size()
	var nb_sets: Array = []
	var corner_raw: Array = []
	for i in cnt:
		nb_sets.append({})
		corner_raw.append([])
	for k in range(0, tri.size(), 3):
		var v := [tri[k], tri[k + 1], tri[k + 2]]
		var cen: Vector3 = (dirs[v[0]] + dirs[v[1]] + dirs[v[2]]).normalized()
		for m in 3:
			corner_raw[v[m]].append(cen)
			nb_sets[v[m]][v[(m + 1) % 3]] = true
			nb_sets[v[m]][v[(m + 2) % 3]] = true

	for i in cnt:
		var nrm := dirs[i]
		var helper := Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT
		var t1 := nrm.cross(helper).normalized()
		var t2 := nrm.cross(t1)
		var nl: Array = nb_sets[i].keys()
		nl.sort_custom(func(x, y): return _ang(dirs[x], nrm, t1, t2) < _ang(dirs[y], nrm, t1, t2))
		nbrs.append(PackedInt32Array(nl))
		var cl: Array = corner_raw[i]
		cl.sort_custom(func(x, y): return _ang(x, nrm, t1, t2) < _ang(y, nrm, t1, t2))
		corners.append(PackedVector3Array(cl))


func _ang(v: Vector3, nrm: Vector3, t1: Vector3, t2: Vector3) -> float:
	var d := v - nrm * v.dot(nrm)
	return atan2(d.dot(t2), d.dot(t1))


# ---------------------------------------------------------------------
# Рельеф и руда
# ---------------------------------------------------------------------

func _build_relief(seed_val: int) -> void:
	var cnt := count()
	level.resize(cnt)
	ore.resize(cnt)
	ore.fill(D.I_NONE)
	var hn := FastNoiseLite.new()
	hn.seed = seed_val
	hn.frequency = 0.03
	hn.fractal_octaves = 3
	for i in cnt:
		var h := hn.get_noise_3dv(dirs[i] * radius)
		# пороги разнесены широко: больше ровных участков, скалы — редкость
		var lv := 1
		if h > 0.45:
			lv = 4
		elif h > 0.3:
			lv = 3
		elif h > 0.12:
			lv = 2
		elif h < -0.2:
			lv = 0
		level[i] = lv

	# большая планета: кратеры (низина с валом) и плато
	var frng := RandomNumberGenerator.new()
	frng.seed = seed_val + 4242
	if kind == 2:
		for k in 26:
			var c0 := frng.randi_range(0, cnt - 1)
			var rad := frng.randi_range(3, 8)
			var rr := rings(c0, rad + 1)
			for x in rr:
				var dd: int = rr[x]
				if dd <= rad - 1:
					level[x] = 0
				elif dd <= rad + 1:
					level[x] = maxi(level[x], 3 if frng.randf() < 0.75 else 2)
		for k in 14:
			var c1 := frng.randi_range(0, cnt - 1)
			var rp := rings(c1, frng.randi_range(3, 6))
			for x in rp:
				level[x] = 3 if int(rp[x]) < 5 else maxi(level[x], 2)

	# площадки под ядра: ровные, без руды
	for team in D.CORE_DIRS.size():
		var cc := nearest_cell(D.CORE_DIRS[team])
		core_center[team] = cc
		var r := rings(cc, 4)
		var spawn_set := false
		for c in r:
			var dist: int = r[c]
			if dist <= 2:
				level[c] = 1
				if dist == 2 and not spawn_set:
					spawn_cell[team] = c
					spawn_set = true
			else:
				level[c] = mini(level[c], 2)
	# большая планета: вторая нейтральная база — на другой стороне, тоже на ровной площадке
	if kind == 2:
		var xs := nearest_cell(Vector3(0.0, 0.55, -1.0).normalized())
		extra_sites.append(xs)
		var rx := rings(xs, 11)
		for c in rx:
			level[c] = 1 if int(rx[c]) <= 10 else mini(level[c], 2)
		var rn := rings(core_center[2], 11)   # и первую — пошире, под стены
		for c in rn:
			level[c] = 1 if int(rn[c]) <= 10 else mini(level[c], 2)

	# руды — жилами: каждая жила одного типа, извилистая полоса 1–2 клетки шириной
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 999

	# стартовые жилы у каждой базы: медь, железо, уголь, кварц уходят от ядра наружу
	var starter := [D.I_COPPER_ORE, D.I_IRON_ORE, D.I_COAL_ORE, D.I_QUARTZ]
	for team in D.CORE_DIRS.size():
		var cc: int = core_center[team]
		var nb: PackedInt32Array = nbrs[cc]
		for i in starter.size():
			# старт на 3-м кольце, по разные стороны от ядра
			var c := cc
			var heading := dirs[nb[int(round(i * nb.size() / 4.0)) % nb.size()]] - dirs[cc]
			for _s in 3:
				c = _step(c, heading)
			_vein(c, heading, starter[i], 6, 0.3, rng)

	# жилы по всей планете: [тип, сколько жил, длина от, длина до, толщина, далеко от баз?]
	var area := float(cnt) / 17642.0   # число жил — по площади планеты
	var plan := [
		[D.I_COPPER_ORE, 26, 8, 18, 0.35, false],
		[D.I_IRON_ORE, 26, 8, 18, 0.35, false],
		[D.I_COAL_ORE, 22, 8, 16, 0.35, false],
		[D.I_QUARTZ, 18, 6, 14, 0.3, false],
		[D.I_ICE, 14, 6, 14, 0.4, false],
		[D.I_LEAD_ORE, 9, 4, 8, 0.15, true],      # редкие — короткие и тонкие
		[D.I_URANIUM_ORE, 6, 3, 6, 0.1, true],
		[D.I_HELIUM_ORE, 6, 3, 6, 0.1, true],
	]
	if kind == 1:
		plan.append([D.I_UNIQUE_ORE, 7, 3, 5, 0.25, true])   # малые: уникальная материя
	elif kind == 2:
		# большая: есть все типы, но встречаются редко
		plan = [
			[D.I_COPPER_ORE, 18, 5, 10, 0.3, false], [D.I_IRON_ORE, 18, 5, 10, 0.3, false],
			[D.I_COAL_ORE, 15, 5, 9, 0.3, false], [D.I_QUARTZ, 13, 4, 8, 0.25, false],
			[D.I_ICE, 10, 4, 8, 0.3, false], [D.I_LEAD_ORE, 8, 3, 6, 0.15, true],
			[D.I_URANIUM_ORE, 6, 3, 5, 0.12, true], [D.I_HELIUM_ORE, 6, 3, 5, 0.12, true],
			[D.I_UNIQUE_ORE, 3, 2, 4, 0.1, true],
		]
		area = 1.0
	for row in plan:
		var placed := 0
		var tries := 0
		var want := maxi(1, int(round(float(row[1]) * area)))
		while placed < want and tries < 600:
			tries += 1
			var c := rng.randi_range(0, cnt - 1)
			if ore[c] != D.I_NONE or level[c] >= D.MAX_LEVEL:
				continue
			# у баз чисто; редкие — ещё дальше
			var min_d := (70.0 if row[5] else 22.0) * radius / D.PLANET_R
			var ok := true
			for d in D.CORE_DIRS:
				if dirs[c].angle_to(d) * radius < min_d:
					ok = false
			# лёд чаще ближе к полюсам
			if row[0] == D.I_ICE and absf(dirs[c].y) < 0.5 and rng.randf() < 0.7:
				ok = false
			if not ok:
				continue
			var nb: PackedInt32Array = nbrs[c]
			var heading := dirs[nb[rng.randi_range(0, nb.size() - 1)]] - dirs[c]
			_vein(c, heading, row[0], rng.randi_range(row[2], row[3]), row[4], rng)
			placed += 1

	# окружение большой планеты: валуны, кристаллические шпили, инопланетные растения
	deco.resize(cnt)
	deco.fill(0)
	if kind == 2:
		var placed := 0
		var guard := 0
		while placed < cnt / 28 and guard < cnt:
			guard += 1
			var c := rng.randi_range(0, cnt - 1)
			if ore[c] != D.I_NONE or deco[c] != 0:
				continue
			var near_base := false
			for d in D.CORE_DIRS:
				if dirs[c].angle_to(d) * radius < 26.0:
					near_base = true
			for xs in extra_sites:
				if dirs[c].angle_to(dirs[int(xs)]) * radius < 26.0:
					near_base = true
			if near_base:
				continue
			var kd := 1
			var roll := rng.randf()
			if level[c] >= D.MAX_LEVEL or roll < 0.45:
				kd = 1
			elif roll < 0.7:
				kd = 2
			else:
				kd = 3
			deco[c] = kd
			placed += 1
			# растения и валуны — группками
			if kd != 2 and rng.randf() < 0.6:
				var nb: PackedInt32Array = nbrs[c]
				var x: int = nb[rng.randi_range(0, nb.size() - 1)]
				if ore[x] == D.I_NONE and deco[x] == 0:
					deco[x] = kd
					placed += 1

	# малые планеты: жгучие пятна (не у баз)
	hazard.resize(cnt)
	hazard.fill(0)
	if kind == 1:
		var spots := 0
		var tries := 0
		while spots < 18 and tries < 500:
			tries += 1
			var c := rng.randi_range(0, cnt - 1)
			if ore[c] != D.I_NONE or level[c] >= D.MAX_LEVEL:
				continue
			var near_base := false
			for d in D.CORE_DIRS:
				if dirs[c].angle_to(d) * radius < 18.0:
					near_base = true
			if near_base:
				continue
			var r := rings(c, rng.randi_range(0, 2))
			for x in r:
				if ore[x] == D.I_NONE and level[x] < D.MAX_LEVEL and rng.randf() < 0.8:
					hazard[x] = 1
			spots += 1


## Шаг на соседнюю клетку, которая ближе всего к направлению heading.
func _step(c: int, heading: Vector3) -> int:
	var nb: PackedInt32Array = nbrs[c]
	var best := nb[0]
	var bd := -INF
	for x in nb:
		var v := (dirs[x] - dirs[c]).normalized()
		var d := v.dot(heading.normalized())
		if d > bd:
			bd = d
			best = x
	return best


## Прокладывает жилу: идём от клетки c, слегка виляя, и помечаем руду.
## thick — шанс прихватить соседнюю клетку (толщина жилы).
func _vein(c: int, heading: Vector3, type: int, length: int, thick: float, rng: RandomNumberGenerator) -> void:
	for i in length:
		if level[c] < D.MAX_LEVEL and ore[c] == D.I_NONE:
			ore[c] = type
		if rng.randf() < thick:
			var nb: PackedInt32Array = nbrs[c]
			var side := nb[rng.randi_range(0, nb.size() - 1)]
			if level[side] < D.MAX_LEVEL and ore[side] == D.I_NONE:
				ore[side] = type
		# поворачиваем направление чуть-чуть и переносим его в касательную плоскость
		var up := dirs[c]
		var wiggle := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		heading = heading.normalized() + (wiggle - up * wiggle.dot(up)) * 0.45
		c = _step(c, heading)
		heading = heading - dirs[c] * heading.dot(dirs[c])


# ---------------------------------------------------------------------
# Меш поверхности
# ---------------------------------------------------------------------

const LEVEL_COLORS := [
	Color(0.20, 0.21, 0.28), Color(0.30, 0.29, 0.34), Color(0.40, 0.37, 0.38),
	Color(0.50, 0.45, 0.40), Color(0.72, 0.70, 0.68),
]


## Возвращает [ArrayMesh, PackedVector3Array треугольников для коллизии].
func build_mesh() -> Array:
	_reset_buffers()
	for c in count():
		var r := top_r(c)
		var n := dirs[c]
		var ctr := n * r
		var cs: PackedVector3Array = corners[c]
		var nb: PackedInt32Array = nbrs[c]
		var k := cs.size()
		var fill: Color = LEVEL_COLORS[level[c]]
		if ore[c] != D.I_NONE:
			fill = D.ITEM_COLORS[ore[c]]
		# касательная плоскость клетки — в ней квадратные пиксели
		var helper := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
		var t1 := n.cross(helper).normalized()
		var t2 := n.cross(t1)
		var off := Vector2(float(c % 97), float(c % 89)) * 3.7   # чтобы соседние клетки не повторялись
		var ore_code: int = ore[c] + 1
		if hazard.size() > c and hazard[c] == 1:
			ore_code = 15   # жгучая клетка
		var top2 := Vector2(level[c], 0 * 16 + ore_code)
		var rim2 := Vector2(level[c], 1 * 16 + ore_code)
		var wall2 := Vector2(level[c], 2 * 16)
		var uc := off
		for i in k:
			var a := cs[i] * r
			var b := cs[(i + 1) % k] * r
			var ia := ctr + (a - ctr) * 0.86
			var ib := ctr + (b - ctr) * 0.86
			var ua := Vector2((a - ctr).dot(t1), (a - ctr).dot(t2)) + off
			var ub := Vector2((b - ctr).dot(t1), (b - ctr).dot(t2)) + off
			var uia := Vector2((ia - ctr).dot(t1), (ia - ctr).dot(t2)) + off
			var uib := Vector2((ib - ctr).dot(t1), (ib - ctr).dot(t2)) + off
			_tri(ctr, ia, ib, n, fill, uc, uia, uib, top2)
			_tri(ia, a, b, n, fill, uia, ua, ub, rim2)
			_tri(ia, b, ib, n, fill, uia, ub, uib, rim2)
			# стенка вниз — только если сосед за этой гранью ниже
			var mid := (cs[i] + cs[(i + 1) % k]).normalized()
			var other := nb[0]
			for x in nb:
				if dirs[x].dot(mid) > dirs[other].dot(mid):
					other = x
			if level[other] < level[c]:
				var r2 := top_r(other)
				var a2 := cs[i] * r2
				var b2 := cs[(i + 1) % k] * r2
				var wn := ((a + b) * 0.5 - ctr)
				wn = (wn - n * wn.dot(n)).normalized()
				# у стенки UV.y — радиус: слои породы идут вокруг всей планеты
				var edge_len := a.distance_to(b)
				var wa := Vector2(off.x, r)
				var wb := Vector2(off.x + edge_len, r)
				var wa2 := Vector2(off.x, r2)
				var wb2 := Vector2(off.x + edge_len, r2)
				_tri(a, b, b2, wn, fill, wa, wb, wb2, wall2)
				_tri(a, b2, a2, wn, fill, wa, wb2, wa2, wall2)
	var am := _commit_mesh()
	var faces := _mv
	_reset_buffers()
	return [am, faces]


func _reset_buffers() -> void:
	_mv = PackedVector3Array()
	_mn = PackedVector3Array()
	_mc = PackedColorArray()
	_mu = PackedVector2Array()
	_mu2 = PackedVector2Array()


func _commit_mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _mv
	arr[Mesh.ARRAY_NORMAL] = _mn
	arr[Mesh.ARRAY_COLOR] = _mc
	arr[Mesh.ARRAY_TEX_UV] = _mu
	arr[Mesh.ARRAY_TEX_UV2] = _mu2
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## Призмы точно по контуру клеток (для построек «по форме клеток»).
## Координаты мировые. Возвращает [ArrayMesh, PackedVector3Array для коллизии].
func prism(cells: Array, height: float, inset: float, side_col: Color, top_col: Color) -> Array:
	_reset_buffers()
	for c in cells:
		var r := top_r(c)
		var n := dirs[c]
		var ctr := n * r
		var top := ctr + n * height
		var cs: PackedVector3Array = corners[c]
		var k := cs.size()
		for i in k:
			var a := ctr + (cs[i] * r - ctr) * inset
			var b := ctr + (cs[(i + 1) % k] * r - ctr) * inset
			var a2 := a + n * height
			var b2 := b + n * height
			_tri(top, a2, b2, n, top_col)
			var sn := ((a + b) * 0.5 - ctr)
			sn = (sn - n * sn.dot(n)).normalized()
			_tri(a, b, b2, sn, side_col)
			_tri(a, b2, a2, sn, side_col)
	var am := _commit_mesh()
	var faces := _mv
	_reset_buffers()
	return [am, faces]


func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
	_mv.append(a)
	_mv.append(b)
	_mv.append(c)
	_mu.append(ua)
	_mu.append(ub)
	_mu.append(uc)
	for i in 3:
		_mn.append(n)
		_mc.append(col)
		_mu2.append(u2)
