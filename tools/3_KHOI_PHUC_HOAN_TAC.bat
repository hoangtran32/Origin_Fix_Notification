@echo off
setlocal
title 3_KHOI_PHUC_HOAN_TAC
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -Restore %*
set "toolExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %toolExitCode%
