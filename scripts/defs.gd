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
const I_CHIP := 17         # микросхема: кремний + медь на заводе микросхем
# жидкость — только по трубам
const I_WATER := 20

const ITEM_NAMES := {
	I_COAL_ORE: "Угольная руда", I_COPPER_ORE: "Медная руда", I_IRON_ORE: "Железная руда",
	I_ICE: "Лёд", I_QUARTZ: "Кварцевый песок", I_LEAD_ORE: "Свинцовая руда",
	I_URANIUM_ORE: "Урановая руда", I_HELIUM_ORE: "Гелиевый реголит",
	I_COAL: "Уголь", I_COPPER: "Медь", I_IRON: "Железо", I_SILICON: "Кремний",
	I_LEAD: "Свинец", I_URANIUM: "Уран", I_FUEL: "Топливо He-3", I_WATER: "Вода",
	I_CHIP: "Микросхема",
}
const ITEM_COLORS := {
	I_COAL_ORE: Color(0.12, 0.12, 0.13), I_COPPER_ORE: Color(0.78, 0.45, 0.25),
	I_IRON_ORE: Color(0.55, 0.38, 0.33), I_ICE: Color(0.75, 0.9, 1.0),
	I_QUARTZ: Color(0.92, 0.88, 0.72), I_LEAD_ORE: Color(0.42, 0.45, 0.6),
	I_URANIUM_ORE: Color(0.35, 0.8, 0.25), I_HELIUM_ORE: Color(0.75, 0.45, 0.95),
	I_COAL: Color(0.2, 0.2, 0.22), I_COPPER: Color(1.0, 0.55, 0.25), I_IRON: Color(0.8, 0.8, 0.85),
	I_SILICON: Color(0.35, 0.4, 0.55), I_LEAD: Color(0.55, 0.55, 0.75), I_URANIUM: Color(0.45, 1.0, 0.3),
	I_FUEL: Color(0.9, 0.5, 1.0), I_WATER: Color(0.25, 0.55, 1.0), I_CHIP: Color(0.2, 0.6, 0.3),
}
const CORE_ACCEPT := [I_COAL, I_COPPER, I_IRON, I_SILICON, I_LEAD, I_URANIUM, I_FUEL, I_CHIP]
const RARE_ORES := [I_LEAD_ORE, I_URANIUM_ORE, I_HELIUM_ORE]   # базовый бур не берёт
const CORE_CAP := 500          # ядро (база) хранит не больше 500 каждого ресурса
const START_STORAGE := {I_COPPER: 150, I_IRON: 80, I_SILICON: 30}

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
const LOADER := 16        # точка погрузки: принимает с конвейеров, тут живёт ровер
const UNLOADER := 17      # точка выгрузки: ровер привозит выбранный груз
const CHIP_FACTORY := 18  # завод микросхем
const TURRET2 := 19       # пулемётная турель (медь)
const TURRET3 := 20       # артиллерия (свинец или уран, взрыв)
const LAUNCH_PAD := 21    # стартовая площадка: собирает корабли и заправляет их
const WEAPON := -1        # не постройка: бластер в руках

const NAMES := {
	CORE: "Ядро", CONVEYOR: "Конвейер", PIPE: "Труба",
	DRILL: "Бур I", DRILL2: "Бур II", DRILL3: "Бур III",
	SOLAR: "Солнечная панель", COAL_PLANT: "Угольная ТЭС", NUCLEAR: "АЭС",
	SMELTER: "Плавильня", CRUSHER: "Дробилка", MELTER: "Растопитель",
	CENTRIFUGE: "Центрифуга", FUEL_SYNTH: "Синтезатор топлива",
	TURRET: "Лазерная турель", TURRET2: "Пулемётная турель", TURRET3: "Артиллерия",
	ASSEMBLER: "Сборщик юнитов", LAUNCH_PAD: "Стартовая площадка",
	LOADER: "Точка погрузки", UNLOADER: "Точка выгрузки", CHIP_FACTORY: "Завод микросхем",
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
	TURRET: "лазер на 6 клеток, без энергии и боеприпасов",
	LAUNCH_PAD: "собирает корабли (E) и заправляет их топливом He-3 с конвейера",
	TURRET2: "пули на 10 клеток, медь с конвейера (1 медь = 4 пули)",
	TURRET3: "навесные снаряды на 50 клеток, взрыв 10 клеток. Свинец или уран (облучение 2 с)",
	ASSEMBLER: "железо -> боевой юнит",
	LOADER: "принимает грузы с конвейеров, ровер развозит их по точкам выгрузки",
	UNLOADER: "ровер привозит сюда выбранный груз (E — выбрать), выдаёт на конвейеры",
	CHIP_FACTORY: "1 кремний + 1 медь -> микросхема. 80 энергии",
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
	TURRET2: {I_IRON: 40, I_COPPER: 20, I_CHIP: 5},
	LAUNCH_PAD: {I_IRON: 150, I_SILICON: 40, I_CHIP: 30, I_LEAD: 20},
	TURRET3: {I_IRON: 120, I_LEAD: 40, I_SILICON: 20, I_CHIP: 20},
	ASSEMBLER: {I_COPPER: 30, I_IRON: 20},
	LOADER: {I_IRON: 20, I_CHIP: 10},
	UNLOADER: {I_IRON: 15, I_CHIP: 5},
	CHIP_FACTORY: {I_COPPER: 40, I_IRON: 30, I_SILICON: 10},
}
const HP := {
	CORE: 3000, CONVEYOR: 40, PIPE: 40, DRILL: 150, DRILL2: 200, DRILL3: 250,
	SOLAR: 80, COAL_PLANT: 300, NUCLEAR: 600, SMELTER: 250, CRUSHER: 200, MELTER: 200,
	CENTRIFUGE: 300, FUEL_SYNTH: 300, TURRET: 350, ASSEMBLER: 300,
	LOADER: 250, UNLOADER: 250, CHIP_FACTORY: 300, TURRET2: 600, TURRET3: 1200, LAUNCH_PAD: 1500,
}
# размер в клетках: базовые — 1, второй уровень — 3 (треугольник), третий — 9 (ромб 3×3)
const SIZE := {
	DRILL2: 3, DRILL3: 9, COAL_PLANT: 3, NUCLEAR: 9,
	CENTRIFUGE: 3, FUEL_SYNTH: 9, ASSEMBLER: 3, CHIP_FACTORY: 3, TURRET2: 3, TURRET3: 9, LAUNCH_PAD: 9,
}
const GENERATORS := [SOLAR, COAL_PLANT, NUCLEAR]
const POWER_RING := 4          # генератор питает клетки в 4 кольцах вокруг себя (~61 клетка)

# группы для клавиш 1–5 (повторное нажатие листает внутри группы), 6 — бластер
const CATEGORIES := [
	["Транспорт", [CONVEYOR, PIPE]],
	["Добыча", [DRILL, DRILL2, DRILL3]],
	["Энергия", [SOLAR, COAL_PLANT, NUCLEAR]],
	["Переработка", [SMELTER, CRUSHER, MELTER, CENTRIFUGE, FUEL_SYNTH, CHIP_FACTORY]],
	["Логистика", [LOADER, UNLOADER]],
	["Оборона", [TURRET, TURRET2, TURRET3, ASSEMBLER]],
	["Космос", [LAUNCH_PAD]],
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
	MELTER: 30.0, CENTRIFUGE: 200.0, FUEL_SYNTH: 150.0, CHIP_FACTORY: 80.0}
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
	CHIP_FACTORY: [{"in": {I_SILICON: 1, I_COPPER: 1}, "out": I_CHIP, "n": 1, "t": 12.0}],
}

# ---------------------------------------------------------------------
# Логистика: точки погрузки/выгрузки и роверы-курьеры
# ---------------------------------------------------------------------
const ROVER_CAP := 25          # единиц груза за рейс
const ROVER_SPEED := 0.5       # м за тик (5 м/с)
const ROVER_REACH := 2.5       # с какого расстояния ровер грузится/выгружается
const LOADER_CAP := 100        # сколько всего держит точка погрузки
const UNLOADER_CAP := 50       # сколько держит точка выгрузки
# группы для меню выбора груза точки выгрузки (колесо — сырьё/продукт)
const FILTER_GROUPS := [
	["Уголь", [I_COAL_ORE, I_COAL]],
	["Медь", [I_COPPER_ORE, I_COPPER]],
	["Железо", [I_IRON_ORE, I_IRON]],
	["Кремний", [I_QUARTZ, I_SILICON]],
	["Свинец", [I_LEAD_ORE, I_LEAD]],
	["Уран", [I_URANIUM_ORE, I_URANIUM]],
	["Топливо", [I_HELIUM_ORE, I_FUEL]],
	["Лёд", [I_ICE]],
	["Микросхемы", [I_CHIP]],
]

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

const CELL_M := 1.9            # примерная ширина клетки, м (для дальностей «в клетках»)

# I — лазер: мгновенный луч
const TURRET_RANGE := 6 * CELL_M
const TURRET_DMG := 7
const TURRET_CD := 5           # тиков между выстрелами

# II — пулемёт: пули с баллистикой
const T2_RANGE := 10 * CELL_M
const T2_DMG := 9
const T2_CD := 2
const T2_SPEED := 45.0         # м/с
const T2_SHOTS_PER_COPPER := 4
const T2_AMMO_CAP := 20

# III — артиллерия: навесной снаряд со взрывом
const T3_RANGE := 50 * CELL_M
const T3_SPLASH := 10 * CELL_M
const T3_DMG := 60             # в центре взрыва, к краю — 20%
const T3_CD := 40
const T3_SPEED := 33.5         # м/с: на этой планете даёт ~104 м — с запасом на 50 клеток
const T3_AMMO_CAP := 10

const POISON_TICKS := 20       # облучение ураном: 2 с
const POISON_DMG := 1          # урона за тик
const PROJ_G := 15.0           # гравитация для снарядов, м/с² (с 6 м/с² снаряд ушёл бы на орбиту)
const PROJ_DT := 0.025         # шаг физики снаряда, с

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
const AXIS_TILT := 15.0        # наклон оси, градусы
const GIANT_R := 500.0         # радиус газового гиганта, м
const SUN_DIR := Vector3(1, 0, 0)   # направление на солнце в «неподвижной» системе
const SUN_VIS_DIST := 12000.0  # где рисовать солнце
const SUN_VIS_R := 70.0        # маленькая яркая точка
const LIGHT_LEVELS := 16
const GIANT_MAX_LEVEL := 4     # гигант даёт максимум 4 уровня из 16

# ---------------------------------------------------------------------
# Корабли. Разведчик: 1 игрок, топливо He-3, Δv по формуле Циолковского
#   Δv = VE * ln((сухая масса + топливо) / сухая масса)
# Бюджет для этой системы (считал по орбитам и симуляцией): взлёт на орбиту ~35 м/с,
# перелёт к соседней луне ~17 м/с (уход с орбиты + Гоман + захват), посадка ~30 м/с.
# Полный бак разведчика даёт ~116 м/с — с запасом на ошибки пилота.
# ---------------------------------------------------------------------
const SCOUT_COST := {I_IRON: 60, I_COPPER: 30, I_SILICON: 20, I_CHIP: 20}
const SCOUT_BUILD_TICKS := 150     # сборка 15 с
const SCOUT_DRY := 2.0             # сухая масса, т
const FUEL_UNIT_MASS := 0.15       # т на 1 единицу топлива
const SCOUT_TANK := 12             # единиц топлива в баке
const SCOUT_VE := 180.0            # скорость истечения, м/с
const SCOUT_THRUST := 35.0         # тяга (т·м/с²): на полном баке ускорение ~9 м/с² при g=6
const SHIP_MU := 6.0 * 84.0 * 84.0 # гравитационный параметр луны: g * R²
const SHIP_TURN := 1.3             # рад/с — скорость поворота
const SHIP_CRASH_SPEED := 6.0      # посадка быстрее — корабль разбит
const PAD_FUEL_CAP := 24           # сколько топлива держит площадка
const DV_LAUNCH := 35              # справочные цифры для интерфейса (проверено симуляцией взлёта)
const DV_TRANSFER := 17
const DV_LAND := 30

# ---------------------------------------------------------------------
# Звёздная система: 5 лун-клонов (одинаковый рельеф) на орбитах вокруг гиганта.
# Подобрано так, чтобы перелёт к соседу занимал 1.5–2.5 мин, а сферы влияния не перекрывались.
# ---------------------------------------------------------------------
const GIANT_MU := 6.0e6            # гравитационный параметр гиганта
const HOME_PLANET := 1             # на какой луне ядра и старт
const PLANETS := [
	{"name": "Луна I", "a": 1400.0, "phase": 0.6},
	{"name": "Луна II (дом)", "a": 2000.0, "phase": 0.0},
	{"name": "Луна III", "a": 2800.0, "phase": 2.6},
	{"name": "Луна IV", "a": 3900.0, "phase": 4.4},
	{"name": "Луна V", "a": 5400.0, "phase": 1.9},
]
const SOI_FRAC := 0.138            # сфера влияния = орбита * (μ луны / μ гиганта)^0.4
