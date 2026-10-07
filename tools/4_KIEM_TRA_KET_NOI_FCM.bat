@echo off
title CHAN DOAN KET NOI GOOGLE FCM THOI GIAN THUC
chcp 65001 >nul
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VivoNotificationFixer.ps1" -FCMTest

echo.
pause
