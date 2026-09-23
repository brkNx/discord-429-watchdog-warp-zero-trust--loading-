@echo off
title Discord 429 Watchdog
echo ============================================
echo   Discord 429 Watchdog - Manuel Calistir
echo ============================================
echo.
echo Log: %LOCALAPPDATA%\discord-429-watchdog.log
echo Kapatmak icin pencereyi kapatin veya Ctrl+C
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Discord429Watchdog.ps1" -CheckIntervalSeconds 30
pause
