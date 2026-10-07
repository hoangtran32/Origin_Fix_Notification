@echo off
title KIEM TRA TRANG THAI THONG BAO (AUDIT ONLY)
chcp 65001 >nul
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -Audit

echo.
pause
