@echo off
rem Baut alle Deploy-Targets: Windows, Linux, Android und Web (build\<ziel>\).
rem Einzeln: build-windows.bat / build-linux.bat / build-android.bat /
rem build-web.bat (liegen daneben in build\).
call "%~dp0build-windows.bat" nopause
if errorlevel 1 (
    echo Windows-Build fehlgeschlagen.
    pause
    exit /b 1
)
call "%~dp0build-linux.bat" nopause
if errorlevel 1 (
    echo Linux-Build fehlgeschlagen.
    pause
    exit /b 1
)
call "%~dp0build-android.bat" nopause
if errorlevel 1 (
    echo Android-Build fehlgeschlagen.
    pause
    exit /b 1
)
call "%~dp0build-web.bat" nopause
if errorlevel 1 (
    echo Web-Build fehlgeschlagen.
    pause
    exit /b 1
)
echo.
echo Alle Builds fertig:
echo   build\windows\
echo   build\linux\
echo   build\android\
echo   build\web\
pause
