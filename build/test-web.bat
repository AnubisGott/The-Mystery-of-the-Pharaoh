@echo off
setlocal
rem Testet den Web-Build lokal: entpackt das neueste
rem build\web\TheMysteryOfThePharaoh-web-*.zip in einen Temp-Ordner und
rem startet dort einen Webserver. build\web\ bleibt sauber (nur das Zip).
rem Aufruf:  test-web.bat  [port]     (Standardport 8100)
rem Danach im Browser oeffnen und mit Strg+F5 hart neu laden.
rem Beenden: Strg+C in diesem Fenster.
set "PORT=8100"
if not "%1"=="" set "PORT=%1"
set "TESTDIR=%TEMP%\pharaoh-web-test"
set "ZIP="
for /f "delims=" %%F in ('dir /b /o-d "%~dp0web\TheMysteryOfThePharaoh-web-*.zip" 2^>nul') do (
    if not defined ZIP set "ZIP=%~dp0web\%%F"
)
if not defined ZIP (
    echo Kein Web-Zip in build\web\ gefunden - erst build-web.bat ausfuehren.
    pause
    exit /b 1
)
echo Entpacke: %ZIP%
if exist "%TESTDIR%" rmdir /s /q "%TESTDIR%"
mkdir "%TESTDIR%"
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP%' -DestinationPath '%TESTDIR%' -Force"
if errorlevel 1 (
    echo Entpacken fehlgeschlagen.
    pause
    exit /b 1
)
echo.
echo   http://127.0.0.1:%PORT%/index.html
echo.
echo Server laeuft - beenden mit Strg+C.
pushd "%TESTDIR%"
python -m http.server %PORT% --bind 127.0.0.1
popd
endlocal
