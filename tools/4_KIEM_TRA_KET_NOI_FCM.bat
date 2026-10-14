@echo off
setlocal
title 4_KIEM_TRA_KET_NOI_FCM
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -FCMTest %*
set "toolExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %toolExitCode%
