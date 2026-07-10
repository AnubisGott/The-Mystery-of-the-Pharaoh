@echo off
set "GODOT_EXE=C:\dev\godot\Godot_v4.7-stable_win64.exe"
set "PROJECT_DIR=%~dp0."

if not exist "%GODOT_EXE%" (
    echo Godot was not found at "%GODOT_EXE%".
    echo Install Godot there or update GODOT_EXE in this file.
    pause
    exit /b 1
)

start "" "%GODOT_EXE%" --path "%PROJECT_DIR%"
