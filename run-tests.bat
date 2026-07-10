@echo off
setlocal

set "GODOT_EXE=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
set "PROJECT_DIR=%~dp0."

if not exist "%GODOT_EXE%" (
    echo Godot console executable was not found at "%GODOT_EXE%".
    echo Install Godot there or update GODOT_EXE in this file.
    exit /b 1
)

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" res://tests/run_tests.tscn
exit /b %errorlevel%
