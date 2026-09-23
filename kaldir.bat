@echo off
title Discord 429 Watchdog - Kaldirma
echo ============================================
echo   Discord 429 Watchdog - Kaldirma
echo ============================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Yonetici yetkisi gerekli, UAC onaylayın...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Stop-ScheduledTask -TaskName 'Discord429Watchdog' -ErrorAction SilentlyContinue;" ^
  "Unregister-ScheduledTask -TaskName 'Discord429Watchdog' -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "Write-Host 'Gorev silindi.'"

echo.
echo Kaldirildi. Script dosyalarini silmek isterseniz bu klasoru silebilirsiniz.
pause
