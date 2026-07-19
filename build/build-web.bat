@echo off
setlocal
rem Baut den Web-Build (nothreads, kein SharedArrayBuffer noetig) und packt
rem ihn als build\web\TheMysteryOfThePharaoh-web-<version>.zip - die Datei,
rem die bei itch.io hochgeladen wird ("This file will be played in the
rem browser"). Die losen Export-Dateien werden nach dem Packen geloescht;
rem zum lokalen Testen das Zip entpacken und im entpackten Ordner z. B.
rem   python -m http.server 8100
rem starten. Die Version kommt aus project.godot (config/version).
rem Diese Datei liegt in build\ ; das Projekt ist eine Ebene hoeher (%~dp0..).
rem Bei anderem Godot-Pfad: Zeile unten anpassen.
set "GODOT=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Godot nicht gefunden: %GODOT%
    echo Bitte den Pfad in build-web.bat anpassen.
    if not "%1"=="nopause" pause
    exit /b 1
)
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$t=Get-Content -Raw '%~dp0..\project.godot'; if($t -match 'config/version=.([0-9.]+)'){$Matches[1]}"`) do set "VERSION=%%A"
if "%VERSION%"=="" (
    echo Konnte config/version nicht aus project.godot lesen.
    if not "%1"=="nopause" pause
    exit /b 1
)
if not exist "%~dp0web" mkdir "%~dp0web"
echo Exportiere Web-Build %VERSION% nach build\web\ ...
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
echo Packe build\web\TheMysteryOfThePharaoh-web-%VERSION%.zip ...
powershell -NoProfile -Command "Compress-Archive -Path '%~dp0web\index*' -DestinationPath '%~dp0web\TheMysteryOfThePharaoh-web-%VERSION%.zip' -Force"
if errorlevel 1 (
    echo Packen fehlgeschlagen - die Export-Dateien bleiben liegen.
    if not "%1"=="nopause" pause
    exit /b 1
)
del /q "%~dp0web\index*"
echo.
echo Fertig: %~dp0web\TheMysteryOfThePharaoh-web-%VERSION%.zip
if not "%1"=="nopause" pause
endlocal
