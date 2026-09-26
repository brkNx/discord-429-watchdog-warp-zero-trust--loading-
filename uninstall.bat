@echo off
title Discord 429 Watchdog - Uninstall
echo ============================================
echo   Discord 429 Watchdog - Uninstall
echo ============================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator rights required, prompting UAC...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Stop-ScheduledTask -TaskName 'Discord429Watchdog' -ErrorAction SilentlyContinue;" ^
  "Unregister-ScheduledTask -TaskName 'Discord429Watchdog' -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "Stop-ScheduledTask -TaskName 'DiscordWarpRoutes' -ErrorAction SilentlyContinue;" ^
  "Unregister-ScheduledTask -TaskName 'DiscordWarpRoutes' -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "$desktop = [Environment]::GetFolderPath('Desktop');" ^
  "$sc = Join-Path $desktop 'Discord 429 Watchdog.lnk';" ^
  "if (Test-Path $sc) { Remove-Item $sc -Force -ErrorAction SilentlyContinue };" ^
  "if (Test-Path 'C:\ProgramData\Discord429Watchdog') { Remove-Item 'C:\ProgramData\Discord429Watchdog' -Recurse -Force -ErrorAction SilentlyContinue };" ^
  "Write-Host 'Tasks and installed files removed successfully.'"

echo.
echo ============================================
echo   Uninstallation completed!
echo ============================================
pause
