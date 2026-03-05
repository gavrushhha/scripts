@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ============================================================================
:: RobocopyMonitor.bat (папка robocopy)
:: Мониторинг папки через Robocopy /MON и /MOT с копированием с той же структурой
:: Конфиг по умолчанию: ..\config\Config.ini
:: ============================================================================

set "SOURCE="
set "DEST="
set "LOG_FILE="
set "MON_CHANGES=1"
set "MOT_MINUTES=1"
set "RETRIES=3"
set "WAIT_SEC=5"

:: Флаг версионного копирования (имя_файла_дата_время.расширение)
set "VERSIONED=0"
if /i "%~1"=="/VERSIONED" set "VERSIONED=1" & shift
if /i "%~1"=="/V" set "VERSIONED=1" & shift

:: Разбор аргументов: (Config.ini) ИЛИ (источник, назначение, [лог])
if "%~1"=="" goto :usage

:: Если первый аргумент — путь к INI, читаем SourceFolder и DestinationFolder
set "ARG1=%~1"
if /i "%ARG1:~-4%"==".ini" (
    if /i "%ARG1%"=="Config.ini" set "ARG1=%~dp0..\config\Config.ini"
    if not exist "%ARG1%" (
        echo [ERROR] Config file not found: %ARG1%
        exit /b 1
    )
    for /f "usebackq eol=;# tokens=1,2 delims==" %%a in ("%ARG1%") do (
        set "line=%%a"
        set "line=!line: =!"
        if "!line!"=="SourceFolder" set "SOURCE=%%b"
        if "!line!"=="DestinationFolder" set "DEST=%%b"
        if "!line!"=="LogFile" set "LOG_FILE=%%b"
    )
    set "SOURCE=!SOURCE: =!"
    set "DEST=!DEST: =!"
    if defined LOG_FILE set "LOG_FILE=!LOG_FILE: =!"
    if not defined SOURCE (
        echo [ERROR] SourceFolder not found in config: %ARG1%
        exit /b 1
    )
    if not defined DEST (
        echo [ERROR] DestinationFolder not found in config: %ARG1%
        exit /b 1
    )
    if /i "%~2"=="/VERSIONED" set "VERSIONED=1"
    if /i "%~2"=="/V" set "VERSIONED=1"
    goto :paths_ready
)

if "%~2"=="" goto :usage
set "SOURCE=%~1"
set "DEST=%~2"
set "ARG3=%~3"
if defined ARG3 if /i not "!ARG3!"=="/VERSIONED" if /i not "!ARG3!"=="/V" set "LOG_FILE=!ARG3!"
if /i "!ARG3!"=="/VERSIONED" set "VERSIONED=1"
if /i "!ARG3!"=="/V" set "VERSIONED=1"
if /i "%~4"=="/VERSIONED" set "VERSIONED=1"
if /i "%~4"=="/V" set "VERSIONED=1"

:paths_ready

:: Убираем завершающий \ для единообразия (robocopy сам нормализует)
if "%SOURCE:~-1%"=="\" set "SOURCE=%SOURCE:~0,-1%"
if "%DEST:~-1%"=="\" set "DEST=%DEST:~0,-1%"

:: Проверка существования исходной папки
if not exist "%SOURCE%" (
    echo [ERROR] Source folder does not exist: %SOURCE%
    exit /b 1
)

:: Режим версионного копирования: имя_файла_дата_время.расширение (PowerShell)
if "%VERSIONED%"=="1" (
    echo [INFO] Versioned copy mode: files saved as name_yyyy-MM-dd_HHmmss.ext
    if not defined LOG_FILE set "LOG_FILE=%~dp0RobocopyMonitor.log"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VersionedCopyWatcher.ps1" -Source "%SOURCE%" -Dest "%DEST%" -LogFile "%LOG_FILE%"
    echo [INFO] Watcher stopped.
    exit /b 0
)

:: Папка назначения будет создана robocopy при необходимости
echo [INFO] Monitoring started.
echo [INFO] Source:      %SOURCE%
echo [INFO] Destination: %DEST%
echo [INFO] Robocopy will run on change (/MON:%MON_CHANGES%) or every %MOT_MINUTES% min (/MOT:%MOT_MINUTES%). Press Ctrl+C to stop.
echo.

:: Собираем команду robocopy
set "ROBO_CMD=robocopy "%SOURCE%" "%DEST%" /E /MON:%MON_CHANGES% /MOT:%MOT_MINUTES% /R:%RETRIES% /W:%WAIT_SEC% /DCOPY:DAT /MT:8 /V /FP /TS"

if not defined LOG_FILE set "LOG_FILE=%~dp0RobocopyMonitor.log"
set "ROBO_CMD=!ROBO_CMD! /LOG+:"!LOG_FILE!" /TEE"
echo [INFO] Log file: %LOG_FILE%
echo.

%ROBO_CMD%
echo.
echo [INFO] Monitoring stopped.
exit /b 0

:usage
echo Usage:
echo   %~nx0 [/VERSIONED] ^<SourceFolder^> ^<DestinationFolder^> [LogFile]
echo   %~nx0 Config.ini [/VERSIONED]   ... config from ..\config\Config.ini
echo.
echo Examples:
echo   %~nx0 "C:\MonitorFolder" "D:\Backup"
echo   %~nx0 Config.ini /VERSIONED
exit /b 1
