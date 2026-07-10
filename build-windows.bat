@echo off
setlocal

set "GODOT_EXE=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
set "PROJECT_DIR=%~dp0."
set "BUILD_DIR=%~dp0builds\windows"
set "OUTPUT_EXE=%BUILD_DIR%\TheMysteryOfThePharaoh.exe"

if not exist "%GODOT_EXE%" (
    echo Godot console executable was not found at "%GODOT_EXE%".
    echo Install Godot there or update GODOT_EXE in this file.
    exit /b 1
)

if not exist "%PROJECT_DIR%\export_presets.cfg" (
    echo Missing export_presets.cfg.
    exit /b 1
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --export-release "Windows Desktop" "%OUTPUT_EXE%"
if errorlevel 1 (
    echo Windows export failed.
    exit /b 1
)

echo Built "%OUTPUT_EXE%".
