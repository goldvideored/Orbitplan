@echo off
rem Выделенный сервер без графики. Укажи путь к Godot, если он не в PATH.
set GODOT=godot
%GODOT% --headless --path "%~dp0" -- --server --port=7777
pause
