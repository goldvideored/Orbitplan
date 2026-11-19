extends RefCounted
## Пиксельные значки предметов 8×8, рисуются кодом в один атлас-текстуру.
## Шаблон формы + палитра предмета. Обозначения в шаблонах:
##   . прозрачно   o контур   b основной   l светлый   d тёмный   s акцент (вкрапления)

const D = preload("res://scripts/defs.gd")

const COLS := 8   # значков в строке атласа
const ROWS := 4
const SIZE := 8

# значки интерфейса (не предметы) — номера от 100, чтобы не пересекаться с предметами
const UI_HEART := 100
const UI_SUN := 101
const UI_BOLT := 102
const UI_CORE := 103
const UI_TANK := 104
const UI_DRONE := 105
const UI_MECH := 106
const UI_HULL := 107
const UI_DV := 108
const UI_ALT := 109
const UI_SPEED := 110
const UI_CLOCK := 111
const UI_CARGO := 112
const UI_BATTERY := 113

const SHAPES := {
	"ore": [
		"..oooo..",
		".obbsbo.",
		"obsbbbbo",
		"obbbbsdo",
		"osbbbbdo",
		"obbsbddo",
		".oddddo.",
		"..oooo..",
	],
	"lump": [
		"..oooo..",
		".olbbbo.",
		"olbbsbbo",
		"obbbbbdo",
		"obsbbbdo",
		"obbbbddo",
		".oddddo.",
		"..oooo..",
	],
	"ingot": [
		"........",
		"........",
		"..oooooo",
		".ollllbo",
		"ollllbdo",
		"obbbbddo",
		"oooooooo",
		"........",
	],
	"wafer": [
		"oooooooo",
		"olllllbo",
		"olbsbsbo",
		"olsbsbbo",
		"olbsbsbo",
		"olsbsbbo",
		"obbbbbdo",
		"oooooooo",
	],
	"rod": [
		"...oo...",
		"..olbo..",
		"..olbo..",
		"..olso..",
		"..olbo..",
		"..olso..",
		"..olbo..",
		"...oo...",
	],
	"canister": [
		"..oooo..",
		"..olbo..",
		".oooooo.",
		".olbbbo.",
		".olsbbo.",
		".olbbbo.",
		".olbbdo.",
		".oooooo.",
	],
	"drop": [
		"...o....",
		"..olo...",
		"..olbo..",
		".olbbbo.",
		".olbbbo.",
		".obbbdo.",
		"..oddo..",
		"...oo...",
	],
	"cube": [
		".oooooo.",
		"olllllbo",
		"ollllbbo",
		"olllbbbo",
		"ollbbbdo",
		"olbbbddo",
		"obbbdddo",
		".oooooo.",
	],
	"chip": [
		".s.s.s..",
		"oooooooo",
		"olllllbo",
		"olbbbbbo",
		"olbssbbo",
		"olbbbbdo",
		"oooooooo",
		".s.s.s..",
	],
	"crystal": [
		"...oo...",
		"..olbo..",
		"..olbo..",
		".ollbbo.",
		".olbbbo.",
		"olllbbdo",
		"olbbbbdo",
		".oooooo.",
	],
	"heart": [
		"........",
		".oo..oo.",
		"olloobbo",
		"olbbbbbo",
		"obbbbbdo",
		".obbbdo.",
		"..obdo..",
		"...oo...",
	],
	"sun": [
		"s..s..s.",
		".s.oo.s.",
		"..olbo..",
		"sollbbos",
		"sobbbdos",
		"..obdo..",
		".s.oo.s.",
		"s..s..s.",
	],
	"bolt": [
		"....ooo.",
		"...olo..",
		"..olo...",
		".ollooo.",
		".oooblo.",
		"...obo..",
		"..obo...",
		".ooo....",
	],
	"core": [
		"..oooo..",
		".olllbo.",
		"olsllbdo",
		"olllbbdo",
		"obbbbbdo",
		"obbbsddo",
		".oddddo.",
		"oooooooo",
	],
	"tank": [
		"........",
		"..ooo...",
		".olbbooo",
		"..obbo..",
		"oooooooo",
		"olllbbdo",
		"osdsdsdo",
		".oooooo.",
	],
	"drone": [
		"oo....oo",
		"ol.oo.lo",
		".oolboo.",
		"..obbo..",
		"..osbo..",
		".oobdoo.",
		"ol....do",
		"oo....oo",
	],
	"mech": [
		"..oooo..",
		"..olso..",
		"oooooooo",
		"olobbodo",
		"o.obbo.o",
		"..o..o..",
		"..o..o..",
		".oo..oo.",
	],
	"shield": [
		"oooooooo",
		"ollllbbo",
		"olllbbbo",
		"ollbbbdo",
		".olbbdo.",
		".obbbdo.",
		"..obdo..",
		"...oo...",
	],
	"rocket": [
		"...oo...",
		"..olbo..",
		"..olbo..",
		"..osbo..",
		".ollbdo.",
		"oolbbdoo",
		"o.oooo.o",
		"..s..s..",
	],
	"up": [
		"...oo...",
		"..olbo..",
		".olbbdo.",
		"oolbbdoo",
		"..olbo..",
		"..olbo..",
		"..olbo..",
		"..oooo..",
	],
	"speed": [
		"o...o...",
		"oo..oo..",
		".lo..lo.",
		"..lo..lo",
		"..lo..lo",
		".lo..lo.",
		"oo..oo..",
		"o...o...",
	],
	"battery": [
		"..oooo..",
		".oolloo.",
		".olllbo.",
		".obbbbo.",
		".osssso.",
		".osssso.",
		".osssso.",
		".oooooo.",
	],
	"clock": [
		"..oooo..",
		".olllbo.",
		"olllsbbo",
		"ollsbbbo",
		"olllbbdo",
		"olbbbbdo",
		".obbddo.",
		"..oooo..",
	],
}

# предмет -> [шаблон, основной цвет, цвет вкраплений]
const ICONS := {
	D.I_COAL_ORE: ["ore", Color(0.42, 0.4, 0.4), Color(0.08, 0.08, 0.09)],
	D.I_COPPER_ORE: ["ore", Color(0.45, 0.4, 0.38), Color(0.95, 0.55, 0.25)],
	D.I_IRON_ORE: ["ore", Color(0.5, 0.48, 0.47), Color(0.65, 0.3, 0.18)],
	D.I_ICE: ["cube", Color(0.6, 0.8, 0.95), Color(1, 1, 1)],
	D.I_QUARTZ: ["crystal", Color(0.88, 0.85, 0.72), Color(1, 1, 1)],
	D.I_LEAD_ORE: ["ore", Color(0.45, 0.45, 0.5), Color(0.55, 0.6, 0.85)],
	D.I_URANIUM_ORE: ["ore", Color(0.4, 0.42, 0.38), Color(0.4, 1.0, 0.25)],
	D.I_HELIUM_ORE: ["ore", Color(0.42, 0.38, 0.45), Color(0.85, 0.5, 1.0)],
	D.I_COAL: ["lump", Color(0.13, 0.13, 0.15), Color(0.55, 0.55, 0.6)],
	D.I_COPPER: ["ingot", Color(0.9, 0.5, 0.22), Color(1, 0.8, 0.5)],
	D.I_IRON: ["ingot", Color(0.72, 0.73, 0.78), Color(1, 1, 1)],
	D.I_SILICON: ["wafer", Color(0.25, 0.3, 0.5), Color(0.55, 0.75, 1.0)],
	D.I_LEAD: ["ingot", Color(0.45, 0.47, 0.62), Color(0.8, 0.82, 0.95)],
	D.I_URANIUM: ["rod", Color(0.3, 0.85, 0.25), Color(0.75, 1.0, 0.5)],
	D.I_FUEL: ["canister", Color(0.6, 0.3, 0.8), Color(1.0, 0.7, 1.0)],
	D.I_WATER: ["drop", Color(0.2, 0.5, 1.0), Color(0.7, 0.9, 1.0)],
	D.I_CHIP: ["chip", Color(0.15, 0.5, 0.25), Color(0.95, 0.8, 0.3)],
	D.I_ALLOY: ["ingot", Color(0.32, 0.4, 0.35), Color(0.5, 1.0, 0.35)],
	UI_HEART: ["heart", Color(0.9, 0.2, 0.25), Color(1, 1, 1)],
	UI_SUN: ["sun", Color(1.0, 0.85, 0.3), Color(1.0, 0.75, 0.2)],
	UI_BOLT: ["bolt", Color(1.0, 0.85, 0.2), Color(1, 1, 1)],
	UI_CORE: ["core", Color(0.55, 0.6, 0.7), Color(0.4, 0.9, 1.0)],
	UI_TANK: ["tank", Color(0.7, 0.72, 0.75), Color(0.25, 0.25, 0.28)],
	UI_DRONE: ["drone", Color(0.7, 0.72, 0.75), Color(1.0, 0.3, 0.2)],
	UI_MECH: ["mech", Color(0.7, 0.72, 0.75), Color(1.0, 0.6, 0.2)],
	UI_HULL: ["shield", Color(0.6, 0.65, 0.75), Color(1, 1, 1)],
	UI_DV: ["rocket", Color(0.85, 0.85, 0.9), Color(1.0, 0.55, 0.2)],
	UI_ALT: ["up", Color(0.4, 0.85, 0.45), Color(1, 1, 1)],
	UI_SPEED: ["speed", Color(0.35, 0.8, 1.0), Color(1, 1, 1)],
	UI_CLOCK: ["clock", Color(0.75, 0.75, 0.8), Color(0.2, 0.2, 0.25)],
	UI_CARGO: ["cube", Color(0.75, 0.6, 0.35), Color(1, 1, 1)],
	UI_BATTERY: ["battery", Color(0.45, 0.47, 0.52), Color(0.3, 1.0, 0.5)],
}


## Ячейка атласа для предмета: Vector2(столбец, строка).
static func cell_of(item: int) -> Vector2:
	var keys := ICONS.keys()
	var i := keys.find(item)
	if i < 0:
		i = 0
	return Vector2(i % COLS, i / COLS)


static func build_atlas() -> ImageTexture:
	var img := Image.create(COLS * SIZE, ROWS * SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var keys := ICONS.keys()
	for i in keys.size():
		var spec: Array = ICONS[keys[i]]
		var shape: Array = SHAPES[spec[0]]
		var base: Color = spec[1]
		var acc: Color = spec[2]
		var pal := {
			"o": base.darkened(0.65), "b": base, "l": base.lightened(0.35),
			"d": base.darkened(0.3), "s": acc,
		}
		var ox := (i % COLS) * SIZE
		var oy := (i / COLS) * SIZE
		for y in SIZE:
			var row: String = shape[y]
			for x in SIZE:
				var ch := row[x]
				if pal.has(ch):
					img.set_pixel(ox + x, oy + y, pal[ch])
	return ImageTexture.create_from_image(img)
