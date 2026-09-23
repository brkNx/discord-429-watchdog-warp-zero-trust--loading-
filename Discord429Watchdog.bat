@echo off
title Discord 429 Watchdog
echo ============================================
echo   Discord 429 Watchdog - Manual Run
echo ============================================
echo.
echo Log: %LOCALAPPDATA%\discord-429-watchdog.log
echo Close this window or press Ctrl+C to stop
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Discord429Watchdog.ps1" -CheckIntervalSeconds 30
pause
