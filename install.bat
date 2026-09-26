@echo off
title Discord 429 Watchdog - Install
echo ============================================
echo   Discord 429 Watchdog - Install
echo ============================================
echo.
echo A Scheduled Task will be registered for ALL users on this PC.
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator rights required, prompting UAC...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "TARGET_DIR=C:\ProgramData\Discord429Watchdog"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo Installing files to %TARGET_DIR%...
copy /y "%~dp0Discord429Watchdog.ps1" "%TARGET_DIR%\" >nul
copy /y "%~dp0route-fix.ps1" "%TARGET_DIR%\" >nul
copy /y "%~dp0Discord429Watchdog.bat" "%TARGET_DIR%\" >nul

echo.
echo Registering Scheduled Tasks...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$targetDir = 'C:\ProgramData\Discord429Watchdog';" ^
  "$watchdogScript = Join-Path $targetDir 'Discord429Watchdog.ps1';" ^
  "$routeScript = Join-Path $targetDir 'route-fix.ps1';" ^
  "$action1 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + $watchdogScript + '\"');" ^
  "$trigger1 = New-ScheduledTaskTrigger -AtLogOn;" ^
  "$settings1 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero);" ^
  "Register-ScheduledTask -TaskName 'Discord429Watchdog' -Action $action1 -Trigger $trigger1 -Settings $settings1 -Force -Description 'Discord 429 automatic recovery' | Out-Null;" ^
  "$action2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + $routeScript + '\"');" ^
  "$trigger2 = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn));" ^
  "$principal2 = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Administrators' -RunLevel Highest;" ^
  "$settings2 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::FromMinutes(2));" ^
  "Register-ScheduledTask -TaskName 'DiscordWarpRoutes' -Action $action2 -Trigger $trigger2 -Principal $principal2 -Settings $settings2 -Force -Description 'Discord WARP route helper' | Out-Null;" ^
  "Start-ScheduledTask -TaskName 'DiscordWarpRoutes' -ErrorAction SilentlyContinue;" ^
  "Start-ScheduledTask -TaskName 'Discord429Watchdog' -ErrorAction SilentlyContinue;" ^
  "Write-Host ('Watchdog Task: ' + (Get-ScheduledTask -TaskName 'Discord429Watchdog').State);" ^
  "Write-Host ('Routes Task:   ' + (Get-ScheduledTask -TaskName 'DiscordWarpRoutes').State);" ^
  "$sh = New-Object -ComObject WScript.Shell;" ^
  "$desktop = [Environment]::GetFolderPath('Desktop');" ^
  "$sc = $sh.CreateShortcut((Join-Path $desktop 'Discord 429 Watchdog.lnk'));" ^
  "$sc.TargetPath = 'powershell.exe';" ^
  "$sc.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File \"' + $watchdogScript + '\" -CheckIntervalSeconds 20');" ^
  "$sc.WorkingDirectory = $targetDir;" ^
  "$sc.Description = 'Discord 429 Watchdog';" ^
  "$sc.Save();"

echo.
echo ============================================
echo   Installation completed successfully!
echo   Active for all users on this computer.
echo ============================================
pause
