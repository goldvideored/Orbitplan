extends RefCounted
## Все игровые константы в одном месте. Баланс крутить здесь.

const MAP := 64            # размер карты в клетках
const TICK := 0.1          # шаг симуляции сервера, сек (10 тиков/с)

# Типы построек
const CORE := 0
const CONVEYOR := 1
const DRILL := 2
const ASSEMBLER := 3
const TURRET := 4

const NAMES := {CORE: "Ядро", CONVEYOR: "Конвейер", DRILL: "Бур", ASSEMBLER: "Сборщик", TURRET: "Турель"}
const COST := {CORE: 0, CONVEYOR: 1, DRILL: 10, ASSEMBLER: 30, TURRET: 25}
const HP := {CORE: 3000, CONVEYOR: 40, DRILL: 150, ASSEMBLER: 300, TURRET: 350}

# Направления: 0 = +X (вправо), 1 = +Z (вниз на экране), 2 = -X, 3 = -Z
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const DIR_ARROWS := ["→", "↓", "←", "↑"]

const TEAM_NAMES := ["Синие", "Красные"]
const TEAM_COLORS := [Color(0.25, 0.6, 1.0), Color(1.0, 0.35, 0.25)]
const CORE_POS := [Vector2i(8, 32), Vector2i(55, 32)]

const START_ORE := 60
const BUILD_RADIUS := 20.0     # строить можно только в этом радиусе от своего ядра

const DRILL_TICKS := 8         # бур выдаёт 1 руду раз в 8 тиков
const CONVEYOR_SPEED := 0.25   # доля клетки за тик

const UNIT_COST := 8           # руды на одного юнита
const UNIT_BUILD_TICKS := 25
const UNIT_HP := 60
const UNIT_SPEED := 0.22
const UNIT_RANGE := 2.0
const UNIT_AGGRO := 6.0
const UNIT_DMG := 6
const UNIT_CD := 6

const TURRET_RANGE := 8.0
const TURRET_DMG := 8
const TURRET_CD := 4

const WAVE_TICKS := 300        # волна от пустой (без игроков) команды раз в 30 с

# Персонаж
const WEAPON := -1             # "постройка" в слоте 5 = бластер
const PLAYER_HP := 100
const RESPAWN_TICKS := 50      # 5 с до респауна
const GUN_DMG := 15
const GUN_RANGE := 40.0
const GUN_CD_MS := 200
const BUILD_REACH := 12.0      # дальность стройки от первого лица
