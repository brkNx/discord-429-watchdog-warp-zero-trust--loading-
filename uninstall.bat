@echo off
title Discord 429 Watchdog - Uninstall
echo ============================================
echo   Discord 429 Watchdog - Uninstall
echo ============================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator rights required, please approve UAC...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Stop-ScheduledTask -TaskName 'Discord429Watchdog' -ErrorAction SilentlyContinue;" ^
  "Unregister-ScheduledTask -TaskName 'Discord429Watchdog' -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "Write-Host 'Task removed.'"

echo.
echo Uninstalled. You can delete this folder if you no longer need the scripts.
pause
