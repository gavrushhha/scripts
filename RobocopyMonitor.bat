@echo off
setlocal EnableDelayedExpansion
set "SOURCE="
set "DEST="
set "LOG=%~dp0Robocopy.log"
for %%I in ("%LOG%") do set "LOG=%%~fI"

set "VERSIONED=0"
if /i "%~1"=="/V" set "VERSIONED=1" & shift
if /i "%~1"=="/VERSIONED" set "VERSIONED=1" & shift

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
if /i "%~2"=="/V" set "VERSIONED=1"
if /i "%~2"=="/VERSIONED" set "VERSIONED=1"
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
if "%VERSIONED%"=="1" (
    echo Mode: VERSIONED - each change saved as new file in folder
    echo.
)
echo Log:    %LOG%
echo Stop: Ctrl+C
echo.

if not exist "%LOG%" type nul > "%LOG%"
echo [%date% %time%] Started: "%SOURCE%" -^> "%DEST%" >> "%LOG%"

if "%VERSIONED%"=="1" goto versioned_loop

robocopy "%SOURCE%" "%DEST%" /E /MON:1 /MOT:1 /R:3 /W:5 /LOG+:"%LOG%" /TEE
if errorlevel 8 echo [%date% %time%] Robocopy had errors. >> "%LOG%"
echo Done.
exit /b 0

:versioned_loop
set "SRC_BASE=%SOURCE%\"
:ver_cycle
for /f "skip=1" %%T in ('wmic os get localdatetime 2^>nul') do set "DT=%%T" & goto :ver_dt_done
:ver_dt_done
set "DT=!DT: =!"
set "DT=!DT:~0,8!_!DT:~8,6!"
for /f "delims=" %%F in ('dir /s /b /a-d "%SOURCE%\*" 2^>nul') do (
    set "SRCF=%%F"
    set "REL=!SRCF:%SRC_BASE%=!"
    set "BASE=%%~nF"
    set "EXT=%%~xF"
    set "DIRP=%%~dpF"
    set "DIRP=!DIRP:%SRC_BASE%=!"
    if "!DIRP!"=="" (set "DESTDIR=%DEST%\!BASE!\") else (set "DESTDIR=%DEST%\!DIRP!!BASE!\")
    if not exist "!DESTDIR!" mkdir "!DESTDIR!" 2>nul
    call :ver_copy_one
)
timeout /t 60 /nobreak >nul
goto ver_cycle

:ver_copy_one
set "WMICPATH=!SRCF:\=\\!"
set "SRCMOD=00000000000000"
for /f "skip=1" %%M in ('wmic datafile where "name='!WMICPATH!'" get lastmodified 2^>nul') do set "SRCMOD=%%M" & goto :ver_got_src
:ver_got_src
set "SRCMOD=!SRCMOD: =!"
set "SRCMOD=!SRCMOD:~0,14!"
set "LATEST=00000000000000"
for /f "delims=" %%V in ('dir /b /o-n "!DESTDIR!!BASE!_*!EXT!" 2^>nul') do (
    set "VF=%%V"
    set "VF=!VF:%BASE%=!"
    set "VF=!VF:_=!"
    set "VF=!VF:!EXT!=!"
    set "VF=!VF: =!"
    if "!VF!" gtr "00000000000000" if "!VF!" lss "99999999999999" set "LATEST=!VF!"
    if "!LATEST!" gtr "00000000000000" goto :ver_do_copy_check
)
:ver_do_copy_check
if "!SRCMOD!" gtr "!LATEST!" goto :ver_do_copy
goto :eof
:ver_do_copy
set "DESTF=!DESTDIR!!BASE!_!DT!!EXT!"
if exist "!DESTF!" set "DESTF=!DESTDIR!!BASE!_!DT!_!RANDOM!!EXT!"
copy /Y "!SRCF!" "!DESTF!" >nul 2>&1
if exist "!DESTF!" (
    echo [%time%] !REL! -^> !BASE!_... >> "%LOG%"
    echo Copied: !REL!
)
goto :eof

:usage
echo Usage: %~nx0 [Config.ini] ["C:\Source" "D:\Dest"]
echo        Add /V or /VERSIONED for versioned copy
exit /b 1
