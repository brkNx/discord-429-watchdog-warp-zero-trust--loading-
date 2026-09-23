@echo off
title Discord 429 Watchdog - Install
echo ============================================
echo   Discord 429 Watchdog - Install
echo ============================================
echo.
echo A Scheduled Task will be registered for this PC.
echo Running as administrator is recommended.
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator rights required, please approve UAC...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT=%~dp0Discord429Watchdog.ps1"
if not exist "%SCRIPT%" (
    echo ERROR: Discord429Watchdog.ps1 not found!
    pause
    exit /b 1
)

echo Script: %SCRIPT%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%SCRIPT%\"';" ^
  "$trigger = New-ScheduledTaskTrigger -AtLogOn;" ^
  "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero);" ^
  "Register-ScheduledTask -TaskName 'Discord429Watchdog' -Action $action -Trigger $trigger -Settings $settings -Force -Description 'Discord 429 automatic recovery' | Out-Null;" ^
  "Start-ScheduledTask -TaskName 'Discord429Watchdog';" ^
  "Write-Host ('Status: ' + (Get-ScheduledTask -TaskName 'Discord429Watchdog').State)"

echo.
echo Installation complete! It now starts automatically on user logon.
pause
