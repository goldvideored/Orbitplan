#!/usr/bin/env bash
# Выделенный сервер без графики (Linux VPS). GODOT — путь к бинарнику Godot 4.3+.
GODOT="${GODOT:-godot}"
PORT="${PORT:-7777}"
cd "$(dirname "$0")"
exec "$GODOT" --headless --path . -- --server --port="$PORT"
