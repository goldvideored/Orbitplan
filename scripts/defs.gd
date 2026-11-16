extends RefCounted
## Все игровые константы в одном месте. Баланс крутить здесь.

const TICK := 0.1          # шаг симуляции сервера, сек (10 тиков/с)

# ---------------------------------------------------------------------
# Планета
# ---------------------------------------------------------------------
const SUBDIV := 42         # детализация сферы: клеток = 10*SUBDIV^2 + 2 (42 -> 17642, клетка ~2 м)
const PLANET_R := 84.0     # радиус планеты, м
const LEVEL_STEP := 0.4    # высота одной террасы рельефа, м
const MAX_LEVEL := 4       # уровень 4 — скалы, строить нельзя
const CORE_DIRS := [Vector3(1, 0, 0), Vector3(-1, 0, 0)]   # ядра на противоположных сторонах

# ---------------------------------------------------------------------
# Предметы
# ---------------------------------------------------------------------
const I_NONE := -1
# сырьё (залежи на планете) — в ядро не принимается
const I_COAL_ORE := 0
const I_COPPER_ORE := 1
const I_IRON_ORE := 2
const I_ICE := 3
const I_QUARTZ := 4
const I_LEAD_ORE := 5      # редкое
const I_URANIUM_ORE := 6   # редкое
const I_HELIUM_ORE := 7    # редкое: реголит с гелием-3, из него делают топливо
# переработанное — идёт в ядро
const I_COAL := 10
const I_COPPER := 11
const I_IRON := 12
const I_SILICON := 13
const I_LEAD := 14
const I_URANIUM := 15
const I_FUEL := 16
# жидкость — только по трубам
const I_WATER := 20

const ITEM_NAMES := {
	I_COAL_ORE: "Угольная руда", I_COPPER_ORE: "Медная руда", I_IRON_ORE: "Железная руда",
	I_ICE: "Лёд", I_QUARTZ: "Кварцевый песок", I_LEAD_ORE: "Свинцовая руда",
	I_URANIUM_ORE: "Урановая руда", I_HELIUM_ORE: "Гелиевый реголит",
	I_COAL: "Уголь", I_COPPER: "Медь", I_IRON: "Железо", I_SILICON: "Кремний",
	I_LEAD: "Свинец", I_URANIUM: "Уран", I_FUEL: "Топливо He-3", I_WATER: "Вода",
}
const ITEM_COLORS := {
	I_COAL_ORE: Color(0.12, 0.12, 0.13), I_COPPER_ORE: Color(0.78, 0.45, 0.25),
	I_IRON_ORE: Color(0.55, 0.38, 0.33), I_ICE: Color(0.75, 0.9, 1.0),
	I_QUARTZ: Color(0.92, 0.88, 0.72), I_LEAD_ORE: Color(0.42, 0.45, 0.6),
	I_URANIUM_ORE: Color(0.35, 0.8, 0.25), I_HELIUM_ORE: Color(0.75, 0.45, 0.95),
	I_COAL: Color(0.2, 0.2, 0.22), I_COPPER: Color(1.0, 0.55, 0.25), I_IRON: Color(0.8, 0.8, 0.85),
	I_SILICON: Color(0.35, 0.4, 0.55), I_LEAD: Color(0.55, 0.55, 0.75), I_URANIUM: Color(0.45, 1.0, 0.3),
	I_FUEL: Color(0.9, 0.5, 1.0), I_WATER: Color(0.25, 0.55, 1.0),
}
const CORE_ACCEPT := [I_COAL, I_COPPER, I_IRON, I_SILICON, I_LEAD, I_URANIUM, I_FUEL]
const RARE_ORES := [I_LEAD_ORE, I_URANIUM_ORE, I_HELIUM_ORE]   # базовый бур не берёт
const CORE_CAP := 100          # ядро (база) хранит не больше 100 каждого ресурса
const START_STORAGE := {I_COPPER: 100, I_IRON: 80, I_SILICON: 30}

# ---------------------------------------------------------------------
# Постройки
# ---------------------------------------------------------------------
const CORE := 0
const CONVEYOR := 1
const DRILL := 2          # бур 1: базовый, без энергии
const ASSEMBLER := 3
const TURRET := 4
const DRILL2 := 5         # бур 2: продвинутый, нужно электричество
const DRILL3 := 6         # бур 3: ультрабыстрый, нужны электричество и вода
const PIPE := 7
const SOLAR := 8
const COAL_PLANT := 9
const NUCLEAR := 10
const SMELTER := 11
const CRUSHER := 12
const MELTER := 13
const CENTRIFUGE := 14
const FUEL_SYNTH := 15
const WEAPON := -1        # не постройка: бластер в руках

const NAMES := {
	CORE: "Ядро", CONVEYOR: "Конвейер", PIPE: "Труба",
	DRILL: "Бур I", DRILL2: "Бур II", DRILL3: "Бур III",
	SOLAR: "Солнечная панель", COAL_PLANT: "Угольная ТЭС", NUCLEAR: "АЭС",
	SMELTER: "Плавильня", CRUSHER: "Дробилка", MELTER: "Растопитель",
	CENTRIFUGE: "Центрифуга", FUEL_SYNTH: "Синтезатор топлива",
	TURRET: "Турель", ASSEMBLER: "Сборщик юнитов",
}
const DESC := {
	CONVEYOR: "везёт твёрдые предметы, воду не берёт",
	PIPE: "только для воды",
	DRILL: "медленно, без энергии, редкие руды не берёт",
	DRILL2: "быстро, 50 энергии, берёт любые руды",
	DRILL3: "очень быстро, 150 энергии + вода по трубе",
	SOLAR: "до 100 энергии, зависит от света (ночью 0)",
	COAL_PLANT: "500 энергии, жжёт уголь",
	NUCLEAR: "1000 энергии, нужны уран и вода",
	SMELTER: "руда меди/железа/свинца -> металл, кварц -> кремний. 60 энергии",
	CRUSHER: "угольная руда -> уголь. 40 энергии",
	MELTER: "лёд -> вода (выход в трубы). 30 энергии",
	CENTRIFUGE: "4 урановой руды -> уран. 200 энергии",
	FUEL_SYNTH: "2 гелиевого реголита + 2 воды -> топливо. 150 энергии",
	TURRET: "стреляет по вражеским юнитам",
	ASSEMBLER: "железо -> боевой юнит",
}
const COST := {
	CORE: {},
	CONVEYOR: {I_COPPER: 1},
	PIPE: {I_IRON: 1},
	DRILL: {I_COPPER: 12},
	DRILL2: {I_COPPER: 25, I_IRON: 15},
	DRILL3: {I_IRON: 40, I_SILICON: 20, I_LEAD: 10},
	SOLAR: {I_COPPER: 10, I_SILICON: 10},
	COAL_PLANT: {I_COPPER: 30, I_IRON: 30},
	NUCLEAR: {I_IRON: 120, I_LEAD: 60, I_SILICON: 40},
	SMELTER: {I_COPPER: 20, I_IRON: 10},
	CRUSHER: {I_COPPER: 15, I_IRON: 5},
	MELTER: {I_COPPER: 15, I_IRON: 10},
	CENTRIFUGE: {I_IRON: 60, I_SILICON: 30, I_LEAD: 20},
	FUEL_SYNTH: {I_IRON: 50, I_SILICON: 40, I_LEAD: 20},
	TURRET: {I_COPPER: 25, I_IRON: 15},
	ASSEMBLER: {I_COPPER: 30, I_IRON: 20},
}
const HP := {
	CORE: 3000, CONVEYOR: 40, PIPE: 40, DRILL: 150, DRILL2: 200, DRILL3: 250,
	SOLAR: 80, COAL_PLANT: 300, NUCLEAR: 600, SMELTER: 250, CRUSHER: 200, MELTER: 200,
	CENTRIFUGE: 300, FUEL_SYNTH: 300, TURRET: 350, ASSEMBLER: 300,
}
# размер в клетках: базовые — 1, второй уровень — 3 (треугольник), третий — 9 (ромб 3×3)
const SIZE := {
	DRILL2: 3, DRILL3: 9, COAL_PLANT: 3, NUCLEAR: 9,
	CENTRIFUGE: 3, FUEL_SYNTH: 9, ASSEMBLER: 3,
}
const GENERATORS := [SOLAR, COAL_PLANT, NUCLEAR]
const POWER_RING := 4          # генератор питает клетки в 4 кольцах вокруг себя (~61 клетка)

# группы для клавиш 1–5 (повторное нажатие листает внутри группы), 6 — бластер
const CATEGORIES := [
	["Транспорт", [CONVEYOR, PIPE]],
	["Добыча", [DRILL, DRILL2, DRILL3]],
	["Энергия", [SOLAR, COAL_PLANT, NUCLEAR]],
	["Переработка", [SMELTER, CRUSHER, MELTER, CENTRIFUGE, FUEL_SYNTH]],
	["Оборона", [TURRET, ASSEMBLER]],
]

# ---------------------------------------------------------------------
# Производство и энергия
# ---------------------------------------------------------------------
const BUFFER_CAP := 10                 # сколько каждого входа держит машина
const CONVEYOR_SPEED := 0.25           # доля клетки за тик
const PIPE_SPEED := 0.5
const DRILL_TICKS := {DRILL: 16.0, DRILL2: 6.0, DRILL3: 2.5}   # тиков на 1 руду
const DRILL3_WATER_PER := 4            # бур III тратит 1 воду на 4 руды

const POWER_USE := {DRILL2: 50.0, DRILL3: 150.0, SMELTER: 60.0, CRUSHER: 40.0,
	MELTER: 30.0, CENTRIFUGE: 200.0, FUEL_SYNTH: 150.0}
const SOLAR_POWER := 100.0             # при свете 16/16
const COAL_POWER := 500.0
const COAL_BURN_TICKS := 20            # 1 уголь = 2 с работы
const NUCLEAR_POWER := 1000.0
const NUCLEAR_URANIUM_TICKS := 300     # 1 уран = 30 с работы
const NUCLEAR_WATER_TICKS := 5         # и 1 воду каждые 0.5 с на охлаждение
const NUCLEAR_URANIUM_CAP := 5
const NUCLEAR_WATER_CAP := 20

# рецепты: in — что съесть, out — что выдать, n — сколько, t — тиков работы
const RECIPES := {
	SMELTER: [
		{"in": {I_COPPER_ORE: 1}, "out": I_COPPER, "n": 1, "t": 10.0},
		{"in": {I_IRON_ORE: 1}, "out": I_IRON, "n": 1, "t": 12.0},
		{"in": {I_LEAD_ORE: 1}, "out": I_LEAD, "n": 1, "t": 15.0},
		{"in": {I_QUARTZ: 1}, "out": I_SILICON, "n": 1, "t": 14.0},
	],
	CRUSHER: [{"in": {I_COAL_ORE: 1}, "out": I_COAL, "n": 1, "t": 8.0}],
	MELTER: [{"in": {I_ICE: 1}, "out": I_WATER, "n": 2, "t": 6.0}],
	CENTRIFUGE: [{"in": {I_URANIUM_ORE: 4}, "out": I_URANIUM, "n": 1, "t": 40.0}],
	FUEL_SYNTH: [{"in": {I_HELIUM_ORE: 2, I_WATER: 2}, "out": I_FUEL, "n": 1, "t": 30.0}],
}

const TEAM_NAMES := ["Синие", "Красные"]
const TEAM_COLORS := [Color(0.25, 0.6, 1.0), Color(1.0, 0.35, 0.25)]
const ENEMY_ZONE := 40.0       # нельзя строить ближе этого (по поверхности, м) к вражескому ядру

# ---------------------------------------------------------------------
# Юниты и оборона (вражеские волны пока выключены)
# ---------------------------------------------------------------------
const UNIT_COST := 8           # железа на одного юнита
const UNIT_BUILD_TICKS := 25
const UNIT_HP := 60
const UNIT_SPEED := 0.4        # м за тик
const UNIT_RANGE := 2.2
const UNIT_AGGRO := 7.0
const UNIT_DMG := 6
const UNIT_CD := 6

const TURRET_RANGE := 9.0
const TURRET_DMG := 8
const TURRET_CD := 4

# ---------------------------------------------------------------------
# Персонаж
# ---------------------------------------------------------------------
const PLAYER_HP := 100
const RESPAWN_TICKS := 50      # 5 с до респауна
const GUN_DMG := 15
const GUN_RANGE := 40.0
const GUN_CD_MS := 200
const BUILD_REACH := 12.0      # дальность стройки от первого лица

# ---------------------------------------------------------------------
# Небесная механика и свет
# ---------------------------------------------------------------------
const DAY_LENGTH := 240.0      # сутки (оборот вокруг оси), с
const ORBIT_PERIOD := 960.0    # оборот вокруг газового гиганта, с
const AXIS_TILT := 15.0        # наклон оси, градусы
const GIANT_DIST := 6000.0     # расстояние до гиганта, м (масштаб условный)
const GIANT_R := 1800.0
const SUN_DIR := Vector3(1, 0, 0)   # направление на солнце в «неподвижной» системе
const SUN_VIS_DIST := 12000.0  # где рисовать солнце
const SUN_VIS_R := 70.0        # маленькая яркая точка
const LIGHT_LEVELS := 16
const GIANT_MAX_LEVEL := 4     # гигант даёт максимум 4 уровня из 16
