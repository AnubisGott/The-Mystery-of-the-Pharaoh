@echo off
setlocal
rem Baut das signierte Release-APK nach build\android\.
rem Keystore: %USERPROFILE%\.android\pharaoh-release.keystore (Fallback:
rem Android\pharaoh-release.keystore im Projekt). Alias und Passwort werden
rem zur Laufzeit aus Android\android.txt gelesen und nie ausgegeben.
rem Diese Datei liegt in build\ ; das Projekt ist eine Ebene hoeher (%~dp0..).
rem Bei anderem Godot-Pfad: Zeile unten anpassen.
set "GODOT=C:\dev\godot\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
    echo Godot nicht gefunden: %GODOT%
    echo Bitte den Pfad in build-android.bat anpassen.
    if not "%1"=="nopause" pause
    exit /b 1
)
set "KEYSTORE=%USERPROFILE%\.android\pharaoh-release.keystore"
if not exist "%KEYSTORE%" set "KEYSTORE=%~dp0..\Android\pharaoh-release.keystore"
if not exist "%KEYSTORE%" (
    echo Release-Keystore nicht gefunden.
    echo Erwartet: %%USERPROFILE%%\.android\pharaoh-release.keystore
    if not "%1"=="nopause" pause
    exit /b 1
)
if not exist "%~dp0..\Android\android.txt" (
    echo Android\android.txt nicht gefunden - dort stehen Alias und Passwort.
    if not "%1"=="nopause" pause
    exit /b 1
)
rem Alias/Passwort aus der Beschreibungszeile "(alias X, password Y)" ziehen.
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$t=Get-Content -Raw '%~dp0..\Android\android.txt'; if($t -match 'alias ([\w.\-]+)'){$Matches[1]}"`) do set "KS_USER=%%A"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$t=Get-Content -Raw '%~dp0..\Android\android.txt'; if($t -match 'password ([\w.\-]+)'){$Matches[1]}"`) do set "KS_PASS=%%A"
if "%KS_USER%"=="" (
    echo Konnte den Keystore-Alias nicht aus Android\android.txt lesen.
    if not "%1"=="nopause" pause
    exit /b 1
)
if "%KS_PASS%"=="" (
    echo Konnte das Keystore-Passwort nicht aus Android\android.txt lesen.
    if not "%1"=="nopause" pause
    exit /b 1
)
set "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%KEYSTORE%"
set "GODOT_ANDROID_KEYSTORE_RELEASE_USER=%KS_USER%"
set "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=%KS_PASS%"
if not exist "%~dp0android" mkdir "%~dp0android"
echo Exportiere signiertes Android-Release-APK nach build\android\ ...
"%GODOT%" --headless --path "%~dp0.." --export-release "Android"
if errorlevel 1 (
    echo Erster Versuch fehlgeschlagen, wiederhole...
    "%GODOT%" --headless --path "%~dp0.." --export-release "Android"
)
if errorlevel 1 (
    echo.
    echo Export fehlgeschlagen. Sind die Godot 4.7 Android-Export-Templates
    echo installiert und ist das Android-SDK konfiguriert?
    if not "%1"=="nopause" pause
    exit /b 1
)
echo.
echo Fertig: %~dp0android\
if not "%1"=="nopause" pause
endlocal
