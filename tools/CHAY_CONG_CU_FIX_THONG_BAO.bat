@echo off
setlocal
title CHAY_CONG_CU_FIX_THONG_BAO
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1"  %*
set "toolExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %toolExitCode%
