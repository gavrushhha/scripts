@echo off
setlocal EnableDelayedExpansion
set "SOURCE="
set "DEST="
set "LOG=%~dp0Robocopy.log"
for %%I in ("%LOG%") do set "LOG=%%~fI"

if "%~1"=="" goto usage
if /i "%~1"=="Config.ini" goto useconfig
if "%~2"=="" goto usage
set "SOURCE=%~1"
set "DEST=%~2"
goto run

:useconfig
set "CFG=%~dp0..\config\Config.ini"
if not exist "%CFG%" (
    echo [ERROR] Config not found: %CFG%
    exit /b 1
)
for /f "tokens=2 delims==" %%a in ('findstr /B "SourceFolder=" "%CFG%"') do set "SOURCE=%%a"
for /f "tokens=2 delims==" %%a in ('findstr /B "DestinationFolder=" "%CFG%"') do set "DEST=%%a"
if not defined SOURCE (
    echo [ERROR] SourceFolder not found in config
    exit /b 1
)
if not defined DEST (
    echo [ERROR] DestinationFolder not found in config
    exit /b 1
)
goto run

:run
if "%SOURCE:~-1%"=="\" set "SOURCE=%SOURCE:~0,-1%"
if "%DEST:~-1%"=="\" set "DEST=%DEST:~0,-1%"
if not exist "%SOURCE%" (
    echo [ERROR] Source folder not found: %SOURCE%
    exit /b 1
)

echo Source: %SOURCE%
echo Dest:   %DEST%
echo Log:    %LOG%
echo Stop: Ctrl+C
echo.

if not exist "%LOG%" type nul > "%LOG%"
echo [%date% %time%] Robocopy started: "%SOURCE%" -^> "%DEST%" >> "%LOG%"

robocopy "%SOURCE%" "%DEST%" /E /MON:1 /MOT:1 /R:3 /W:5 /LOG+:"%LOG%" /TEE
if errorlevel 8 echo [%date% %time%] Robocopy had errors. >> "%LOG%"
echo Done.
exit /b 0

:usage
echo Usage: %~nx0 Config.ini
echo    or: %~nx0 "C:\Source" "D:\Dest"
exit /b 1
