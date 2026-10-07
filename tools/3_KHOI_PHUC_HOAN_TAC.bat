@echo off
title HOAN TAC VE BAN SAO LUU GOC (GRANULAR RESTORE)
chcp 65001 >nul
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -Restore

echo.
pause
