@echo off
setlocal
rem Testet den Web-Build lokal: entpackt das neueste
rem build\web\TheMysteryOfThePharaoh-web-*.zip in einen Temp-Ordner und
rem startet dort einen Webserver. build\web\ bleibt sauber (nur das Zip).
rem
rem Aufruf:  test-web.bat [port] [usb oder lan]     (Standardport 8100)
rem
rem   (ohne Modus)  nur dieser PC   -> http://127.0.0.1:PORT/index.html
rem   usb           Android per USB -> Tunnel via "adb reverse", auf dem Handy
rem                 ebenfalls http://127.0.0.1:PORT/index.html oeffnen.
rem                 Braucht USB-Debugging auf dem Handy.
rem   lan           Android per WLAN -> HTTPS auf allen Adressen, auf dem Handy
rem                 die unten angezeigte https://192.168.x.y aufrufen und die
rem                 Zertifikatswarnung einmal bestaetigen.
rem
rem Warum lan zwingend HTTPS spricht: Godot verlangt im Browser einen Secure
rem Context. Vertrauenswuerdig sind nur https:// sowie localhost/127.0.0.1 -
rem deshalb kommen die Modi "usb" und "ohne" mit einfachem HTTP aus, waehrend
rem eine LAN-IP ueber HTTP mit "Secure Context - Check web server
rem configuration (use HTTPS)" abbricht. Das Zertifikat wird beim ersten
rem lan-Lauf selbst erzeugt und in build\.webtestcert\ abgelegt (nicht im
rem Git); pro IP eines, damit ein Adresswechsel automatisch ein neues bekommt.
rem
rem Im Browser mit Strg+F5 hart neu laden (Handy: Inkognito-Tab).
rem Beenden: Strg+C in diesem Fenster.
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "PORT=8100"
if not "%1"=="" set "PORT=%1"
set "MODE=%2"
set "SECURE="
set "TESTDIR=%TEMP%\pharaoh-web-test"
set "CERTDIR=%~dp0.webtestcert"
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
if /i "%MODE%"=="usb" goto :usb
if /i "%MODE%"=="lan" goto :lan
echo   http://127.0.0.1:%PORT%/index.html
goto :serve

:usb
if not exist "%ADB%" (
    echo adb nicht gefunden: %ADB%
    echo Pfad oben in test-web.bat anpassen oder Modus "lan" verwenden.
    pause
    exit /b 1
)
"%ADB%" reverse tcp:%PORT% tcp:%PORT%
if errorlevel 1 (
    echo.
    echo adb reverse fehlgeschlagen. Haengt das Handy per USB dran, ist
    echo USB-Debugging aktiv und die Verbindung auf dem Handy bestaetigt?
    echo Pruefen mit:  "%ADB%" devices
    pause
    exit /b 1
)
echo   Auf dem HANDY (Chrome) oeffnen:  http://127.0.0.1:%PORT%/index.html
echo   Auf diesem PC ebenfalls:         http://127.0.0.1:%PORT%/index.html
goto :serve

:lan
rem Die Pipes stehen innerhalb der Anfuehrungszeichen und duerfen deshalb
rem NICHT mit ^ escaped werden - sonst landet das ^ in PowerShell.
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notmatch 'Loopback' | Where-Object InterfaceAlias -notmatch 'vEthernet' | Where-Object InterfaceAlias -notmatch 'WSL' | Where-Object IPAddress -notlike '169.254.*' | Select-Object -First 1 -ExpandProperty IPAddress"`) do set "LANIP=%%A"
if "%LANIP%"=="" (
    echo Konnte die LAN-IP dieses PCs nicht ermitteln.
    pause
    exit /b 1
)
set "PEM=%CERTDIR%\server-%LANIP%.pem"
if not exist "%PEM%" call :makecert || exit /b 1
set "SECURE=1"
echo   Auf dem HANDY (gleiches WLAN) oeffnen:  https://%LANIP%:%PORT%/index.html
echo.
echo   Chrome warnt vor dem selbstsignierten Zertifikat - das ist erwartet:
echo   "Erweitert" antippen, dann "Weiter zu %LANIP% (unsicher)".
echo.
echo   Kommt gar nichts an, blockt die Windows-Firewall den Port. Einmalig in
echo   einer Administrator-PowerShell freigeben:
echo     New-NetFirewallRule -DisplayName "Pharaoh Web-Test %PORT%" -Direction Inbound -Action Allow -Protocol TCP -LocalPort %PORT% -Profile Any
goto :serve

:makecert
rem openssl liegt bei Git fuer Windows, steht dort aber nicht im PATH.
set "OPENSSL="
for %%P in (
    "C:\Program Files\Git\mingw64\bin\openssl.exe"
    "C:\Program Files\Git\usr\bin\openssl.exe"
    "C:\Program Files (x86)\Git\mingw64\bin\openssl.exe"
) do if not defined OPENSSL if exist %%P set "OPENSSL=%%~P"
if not defined OPENSSL for %%P in (openssl.exe) do if not defined OPENSSL if not "%%~$PATH:P"=="" set "OPENSSL=%%~$PATH:P"
if not defined OPENSSL (
    echo openssl nicht gefunden - wird fuer das Testzertifikat gebraucht.
    echo Git fuer Windows installieren oder openssl in den PATH legen.
    pause
    exit /b 1
)
if not exist "%CERTDIR%" mkdir "%CERTDIR%"
echo Erzeuge Testzertifikat fuer %LANIP% ...
"%OPENSSL%" req -x509 -newkey rsa:2048 -keyout "%CERTDIR%\key.pem" -out "%CERTDIR%\cert.pem" -days 365 -nodes -subj "/CN=%LANIP%" -addext "subjectAltName=IP:%LANIP%" 2>nul
if errorlevel 1 (
    echo Zertifikat konnte nicht erzeugt werden.
    pause
    exit /b 1
)
copy /b "%CERTDIR%\cert.pem"+"%CERTDIR%\key.pem" "%PEM%" >nul
del /q "%CERTDIR%\cert.pem" "%CERTDIR%\key.pem"
goto :eof

:serve
echo.
echo Server laeuft - beenden mit Strg+C.
if defined SECURE (
    python "%~dp0web-https-server.py" %PORT% "%TESTDIR%" "%PEM%"
) else (
    pushd "%TESTDIR%"
    python -m http.server %PORT% --bind 127.0.0.1
    popd
)
if /i "%MODE%"=="usb" "%ADB%" reverse --remove tcp:%PORT%
endlocal
