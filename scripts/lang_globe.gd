extends SubViewportContainer
## Выбор языка: шестиугольная планета-Земля. Страны (по языкам) — группы ячеек, границы идут по краям ячеек.
## Тянуть мышью — крутить, щелчок по стране — выбрать её язык.

signal picked(code: String)

const Planet = preload("res://scripts/planet.gd")
const I18n = preload("res://scripts/i18n.gd")
const R := 10.0

# Области по языкам: [код, [lon, lat], ...] — грубые контуры стран и регионов. Порядок важен (первая подходящая).
const REGIONS := [
	["uk", [[22, 45], [40, 46], [40, 52], [32, 52.5], [24, 52], [22, 48]]],
	["pl", [[14, 49], [24, 49], [24, 54.5], [14, 54.5]]],
	["de", [[6, 47.5], [15, 47.5], [15, 54.8], [8, 55], [6, 51]]],
	["fr", [[-4.5, 43], [7.5, 43.5], [8, 49], [2.5, 51], [-4.5, 48.5]]],
	["it", [[7, 44], [13.5, 46.5], [18.5, 40], [16, 38], [12, 41.5], [7, 44]]],
	["es", [[-9.5, 36], [3.3, 36.5], [3.3, 43], [-9.5, 43.7]]],
	["en", [[-8, 50], [1.8, 51], [0, 55], [-3, 58.6], [-6.5, 58], [-8, 54]]],
	["tr", [[26, 36], [44.8, 36.5], [44.8, 41.5], [26, 42]]],
	["ru", [[28, 44], [38, 44], [48, 41], [55, 41], [68, 40], [80, 42], [87, 49], [97, 50], [120, 50], [127, 50], [135, 43],
		[140, 52], [156, 51], [163, 60], [180, 65], [180, 71], [140, 74], [105, 78], [70, 73], [50, 69], [32, 70], [28, 60]]],
	["ar", [[-17, 15], [-17, 28], [-6, 36], [10, 37.5], [32, 31.5], [36, 37], [42, 37], [48, 30], [56, 26], [60, 22], [52, 16],
		[43, 12], [37, 18], [33, 14], [24, 13], [15, 15]]],
	["hi", [[68, 23], [72, 34], [79, 35], [88, 28], [97, 28], [92, 21], [80, 8], [73, 16]]],
	["zh", [[73, 39], [80, 45], [87, 49], [97, 50], [120, 50], [127, 50], [134, 48], [123, 40], [122, 30], [121, 24], [110, 20],
		[100, 21], [97, 28], [88, 28], [79, 35]]],
	["ko", [[125, 34.5], [129.5, 35], [129.5, 42.5], [124.5, 40]]],
	["ja", [[130, 31], [140, 35], [142, 41], [145.5, 44], [141, 45.5], [139.5, 40], [131, 34]]],
	["pt", [[-74, -8], [-70, -10], [-62, -14], [-57, -22], [-54, -27], [-53, -33.5], [-41, -22], [-35, -6], [-50, 0], [-60, 5],
		[-70, 2]]],
	["es", [[-117, 32.5], [-97, 26], [-90, 21], [-87, 16], [-83, 9], [-77, 8], [-72, 12], [-60, 10], [-60, 5], [-70, 2], [-74, -8],
		[-70, -10], [-62, -14], [-57, -22], [-54, -27], [-53, -33.5], [-58, -38], [-65, -55], [-74, -52], [-71, -18], [-81, -5],
		[-80, 1], [-92, 15], [-105, 20], [-110, 23]]],
	["en", [[-168, 66], [-141, 70], [-95, 72], [-62, 66], [-55, 52], [-66, 44], [-76, 35], [-81, 25], [-97, 26], [-117, 32.5],
		[-124, 40], [-125, 49], [-135, 58], [-150, 60]]],
	["en", [[113, -22], [122, -17], [131, -12], [142, -11], [146, -19], [153, -26], [151, -34], [146, -39], [138, -35],
		[130, -32], [115, -34]]],
	["fr", [[-17, 15], [15, 15], [24, 13], [30, 10], [30, -5], [18, -6], [12, -5], [9, 4], [-8, 4.5], [-13, 8]]],
	["en", [[30, 10], [33, 14], [37, 18], [43, 12], [51, 11.5], [41, -2], [40, -16], [33, -26], [28, -33], [18, -35], [12, -17],
		[12, -5], [18, -6], [30, -5]]],
	["en", [[5, 58], [11, 59], [18, 56], [24, 60], [30, 61], [30, 70], [20, 70], [12, 66], [5, 61]]],
	["en", [[44, 37], [62, 37], [62, 25], [56, 26], [48, 30]]],
	["en", [[61, 25], [68, 23], [72, 34], [62, 37]]],
	["en", [[97, 28], [100, 21], [110, 20], [108, 11], [104, 9], [103, 1], [98, 8]]],
	["en", [[95, 5], [106, -6], [115, -8], [125, -9], [141, -9], [141, -3], [130, -1], [119, 6], [109, 2], [103, 2]]],
	["en", [[-50, 60], [-20, 70], [-20, 82], [-60, 82], [-72, 77]]],
]
const COLORS := {
	"ru": Color(0.85, 0.35, 0.3), "en": Color(0.35, 0.55, 0.85), "es": Color(0.95, 0.75, 0.25), "pt": Color(0.35, 0.75, 0.4),
	"fr": Color(0.55, 0.45, 0.85), "de": Color(0.85, 0.6, 0.3), "it": Color(0.45, 0.8, 0.6), "pl": Color(0.9, 0.5, 0.6),
	"uk": Color(0.95, 0.85, 0.35), "tr": Color(0.8, 0.3, 0.45), "ar": Color(0.4, 0.7, 0.45), "hi": Color(0.95, 0.6, 0.35),
	"zh": Color(0.9, 0.3, 0.25), "ja": Color(0.95, 0.95, 0.95), "ko": Color(0.45, 0.6, 0.95),
}
const OCEAN := Color(0.08, 0.2, 0.4)

var planet: Planet
var region := PackedStringArray()   # язык ячейки ("" — океан)
var globe: Node3D
var cam: Camera3D
var overlay: MeshInstance3D
var hover_code := ""
var drag := false
var moved := 0.0
var label: Label


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(420, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	add_child(vp)
	cam = Camera3D.new()
	cam.position = Vector3(0, 0, 30)
	cam.fov = 45
	vp.add_child(cam)
	var tilt := Node3D.new()   # постоянный наклон оси; сам глобус только крутится вокруг своей оси
	tilt.rotation.x = 0.3
	vp.add_child(tilt)
	globe = Node3D.new()
	tilt.add_child(globe)
	planet = Planet.new()
	planet.subdiv = 24
	planet._build_geometry()
	_assign_regions()
	var mi := MeshInstance3D.new()
	mi.mesh = _build_mesh()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	globe.add_child(mi)
	overlay = MeshInstance3D.new()
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.albedo_color = Color(1, 1, 1, 0.4)
	overlay.material_override = om
	globe.add_child(overlay)
	# повернуть к текущему языку
	globe.rotation.y = -0.3
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -30
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)
	_set_hover(I18n.lang)


func _lonlat(d: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(-d.z, d.x)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))


func _inside(p: Vector2, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := Vector2(poly[i][0], poly[i][1])
		var b := Vector2(poly[j][0], poly[j][1])
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


func _assign_regions() -> void:
	region.resize(planet.count())
	for c in planet.count():
		var ll := _lonlat(planet.dirs[c])
		var code := ""
		for rg in REGIONS:
			if _inside(ll, rg[1]):
				code = rg[0]
				break
		region[c] = code


func _cell_color(c: int) -> Color:
	var code := region[c]
	var col: Color = OCEAN if code == "" else COLORS.get(code, Color(0.6, 0.6, 0.6))
	if code != "":
		# граница страны — по краям ячеек: ячейки у соседей с другим языком темнее
		var nb: PackedInt32Array = planet.nbrs[c]
		for x in nb:
			if region[x] != code:
				return col.darkened(0.35)
	return col


func _build_mesh(only := "") -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var rr := R * (1.004 if only != "" else 1.0)
	for c in planet.count():
		if only != "" and region[c] != only:
			continue
		var ctr: Vector3 = planet.dirs[c] * rr
		var cs: PackedVector3Array = planet.corners[c]
		var col := Color(1, 1, 1) if only != "" else _cell_color(c)
		for i in cs.size():
			var a: Vector3 = (cs[i] * rr).lerp(ctr, 0.08)
			var b: Vector3 = (cs[(i + 1) % cs.size()] * rr).lerp(ctr, 0.08)
			verts.append(ctr)
			verts.append(b)
			verts.append(a)
			for k in 3:
				cols.append(col)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	if not verts.is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _set_hover(code: String) -> void:
	if code == hover_code:
		return
	hover_code = code
	overlay.mesh = _build_mesh(code) if code != "" else null
	label.text = I18n.lang_name(code) if code != "" else ""


func _pick(pos: Vector2) -> String:
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	var b := o.dot(d)
	var cc := o.dot(o) - R * R
	var disc := b * b - cc
	if disc < 0.0:
		return ""
	var t := -b - sqrt(disc)
	var p := o + d * t
	var lp := globe.global_transform.affine_inverse() * p
	return region[planet.nearest_cell(lp.normalized())]


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			drag = true
			moved = 0.0
		else:
			drag = false
			if moved < 6.0:
				var code := _pick(mb.position)
				if code != "":
					picked.emit(code)
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm:
		if drag:
			moved += mm.relative.length()
			globe.rotation.y += mm.relative.x * 0.01   # только вращение вокруг оси, наклон постоянный
		_set_hover(_pick(mm.position))


func _process(delta: float) -> void:
	if not drag:
		globe.rotation.y += delta * 0.08
