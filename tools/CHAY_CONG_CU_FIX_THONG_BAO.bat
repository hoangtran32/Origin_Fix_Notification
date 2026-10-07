@echo off
title CONG CU TOI UU THONG BAO VIVO ORIGINOS (ADB CHUYEN NGHIEP)
chcp 65001 >nul
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1"

pause
