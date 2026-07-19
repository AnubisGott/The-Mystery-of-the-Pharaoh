@echo off
rem Baut den Web-Build (nothreads, kein SharedArrayBuffer noetig) nach build\web\.
rem index.html liegt danach im Wurzel von build\web\ - bereit fuer itch.io
rem (Ordner per butler pushen, oder build\web\ zippen und hochladen).
rem Lokal testen:  python -m http.server 8100 --directory build\web
rem Diese Datei liegt in build\ ; das Projekt ist eine Ebene hoeher (%~dp0..).
rem Bei anderem Godot-Pfad: Zeile unten anpassen.
set "GODOT=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Godot nicht gefunden: %GODOT%
    echo Bitte den Pfad in build-web.bat anpassen.
    if not "%1"=="nopause" pause
    exit /b 1
)
if not exist "%~dp0web" mkdir "%~dp0web"
echo Exportiere Web-Build nach build\web\ ...
"%GODOT%" --headless --path "%~dp0.." --export-release "Web"
if errorlevel 1 (
    echo Erster Versuch fehlgeschlagen, wiederhole...
    "%GODOT%" --headless --path "%~dp0.." --export-release "Web"
)
if errorlevel 1 (
    echo.
    echo Export fehlgeschlagen. Sind die Godot 4.7 Web-Export-Templates installiert?
    if not "%1"=="nopause" pause
    exit /b 1
)
echo.
echo Fertig: %~dp0web\
if not "%1"=="nopause" pause
