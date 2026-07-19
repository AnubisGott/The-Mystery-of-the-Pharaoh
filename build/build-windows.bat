@echo off
rem Baut den Windows-Desktop-Build nach build\windows\.
rem Diese Datei liegt in build\ ; das Projekt ist eine Ebene hoeher (%~dp0..).
rem Bei anderem Godot-Pfad: Zeile unten anpassen.
set "GODOT=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Godot nicht gefunden: %GODOT%
    echo Bitte den Pfad in build-windows.bat anpassen.
    if not "%1"=="nopause" pause
    exit /b 1
)
if not exist "%~dp0windows" mkdir "%~dp0windows"
echo Exportiere Windows-Build nach build\windows\ ...
"%GODOT%" --headless --path "%~dp0.." --export-release "Windows Desktop"
if errorlevel 1 (
    echo Erster Versuch fehlgeschlagen, wiederhole...
    "%GODOT%" --headless --path "%~dp0.." --export-release "Windows Desktop"
)
if errorlevel 1 (
    echo.
    echo Export fehlgeschlagen. Sind die Godot 4.7 Windows-Export-Templates installiert?
    if not "%1"=="nopause" pause
    exit /b 1
)
echo.
echo Fertig: %~dp0windows\
if not "%1"=="nopause" pause
