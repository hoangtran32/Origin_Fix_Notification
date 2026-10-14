@echo off
setlocal
title 1_KIEM_TRA_TRANG_THAI
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -Audit %*
set "toolExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %toolExitCode%
