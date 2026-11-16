extends Node
## Сеть. Автозагрузка "Net".
## Три режима: хост (сервер + игрок), клиент, выделенный сервер без графики.
## Сервер — единственный, кто считает игру. Клиенты шлют команды и рисуют снапшоты.

const World = preload("res://scripts/world.gd")
const DEFAULT_PORT := 7777
const MAX_CLIENTS := 10

signal status(text: String)
signal game_started

var peer_team := {}          # peer_id -> команда (0/1)
var ready_peers: Array = []  # удалённые пиры, у которых World уже создан
var world: Node = null
var seed_val := 0
var dedicated := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

	var args := OS.get_cmdline_user_args()
	if "--server" in args or DisplayServer.get_name() == "headless":
		dedicated = true
		Engine.max_fps = 30
		var port := DEFAULT_PORT
		for a in args:
			if a.begins_with("--port="):
				port = int(a.substr(7))
		start_dedicated.call_deferred(port)


func host(port: int) -> void:
	var p := ENetMultiplayerPeer.new()
	if p.create_server(port, MAX_CLIENTS) != OK:
		status.emit("Не удалось открыть порт %d" % port)
		return
	multiplayer.multiplayer_peer = p
	seed_val = randi()
	peer_team[1] = 0
	_create_world(seed_val, 0)


func start_dedicated(port: int) -> void:
	var p := ENetMultiplayerPeer.new()
	if p.create_server(port, MAX_CLIENTS) != OK:
		print("[server] Не удалось открыть порт %d" % port)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = p
	seed_val = randi()
	_create_world(seed_val, -1)
	print("[server] Выделенный сервер запущен на порту %d" % port)


func join(ip: String, port: int) -> void:
	if ip.is_empty():
		ip = "127.0.0.1"
	var p := ENetMultiplayerPeer.new()
	if p.create_client(ip, port) != OK:
		status.emit("Не удалось создать подключение")
		return
	multiplayer.multiplayer_peer = p
	status.emit("Подключение к %s:%d..." % [ip, port])


func team_of(peer_id: int) -> int:
	if peer_id == 0:
		peer_id = 1
	return peer_team.get(peer_id, -1)


func team_has_players(team: int) -> bool:
	for t in peer_team.values():
		if t == team:
			return true
	return false


func _pick_team() -> int:
	var count := [0, 0]
	for t in peer_team.values():
		count[t] += 1
	return 0 if count[0] <= count[1] else 1


func _create_world(s: int, team: int) -> void:
	var w := World.new()
	w.name = "World"
	get_tree().root.add_child(w)
	w.setup(s, team, multiplayer.is_server(), dedicated)
	world = w
	game_started.emit()


# ---------- события сети ----------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var team := _pick_team()
	peer_team[id] = team
	if dedicated:
		print("[server] Игрок %d подключился, команда %d" % [id, team])
	start_game.rpc_id(id, seed_val, team)


func _on_peer_disconnected(id: int) -> void:
	peer_team.erase(id)
	ready_peers.erase(id)
	if dedicated:
		print("[server] Игрок %d отключился" % id)


func _on_connected() -> void:
	status.emit("Подключено, ждём данные...")


func _on_failed() -> void:
	multiplayer.multiplayer_peer = null
	status.emit("Не удалось подключиться")


func _on_server_gone() -> void:
	print("Сервер отключился")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if world:
		world.queue_free()
		world = null
	multiplayer.multiplayer_peer = null
	peer_team.clear()
	ready_peers.clear()
	get_tree().reload_current_scene()


# ---------- RPC ----------

@rpc("authority", "call_remote", "reliable")
func start_game(s: int, team: int) -> void:
	seed_val = s
	_create_world(s, team)
	client_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if world:
		world.send_full_sync(id)
	if not ready_peers.has(id):
		ready_peers.append(id)
