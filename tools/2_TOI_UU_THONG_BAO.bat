@echo off
setlocal
title CHON APP VA USER DE TOI UU THONG BAO
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -Fix %*
set "toolExitCode=%ERRORLEVEL%"
echo.
pause
exit /b %toolExitCode%
