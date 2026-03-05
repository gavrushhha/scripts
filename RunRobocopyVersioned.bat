@echo off
REM Запуск Robocopy в режиме версий (имя_файла_дата_время.ext) с config\Config.ini
cd /d "%~dp0robocopy"
call RobocopyMonitor.bat "%~dp0config\Config.ini" /VERSIONED
pause
