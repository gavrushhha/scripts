@echo off
REM Запуск Robocopy-мониторинга с общим конфигом config\Config.ini
cd /d "%~dp0robocopy"
call RobocopyMonitor.bat "%~dp0config\Config.ini" %*
