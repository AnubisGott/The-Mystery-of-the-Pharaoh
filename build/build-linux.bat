@echo off
rem Baut den Linux-Build (x86_64) nach build\linux\.
rem Diese Datei liegt in build\ ; das Projekt ist eine Ebene hoeher (%~dp0..).
rem Bei anderem Godot-Pfad: Zeile unten anpassen.
set "GODOT=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Godot nicht gefunden: %GODOT%
    echo Bitte den Pfad in build-linux.bat anpassen.
    if not "%1"=="nopause" pause
    exit /b 1
)
if not exist "%~dp0linux" mkdir "%~dp0linux"
echo Exportiere Linux-Build nach build\linux\ ...
"%GODOT%" --headless --path "%~dp0.." --export-release "Linux"
if errorlevel 1 (
    echo Erster Versuch fehlgeschlagen, wiederhole...
    "%GODOT%" --headless --path "%~dp0.." --export-release "Linux"
)
if errorlevel 1 (
    echo.
    echo Export fehlgeschlagen. Sind die Godot 4.7 Linux-Export-Templates installiert?
    if not "%1"=="nopause" pause
    exit /b 1
)
echo.
echo Fertig: %~dp0linux\
if not "%1"=="nopause" pause
