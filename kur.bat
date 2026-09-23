@echo off
title Discord 429 Watchdog - Kurulum
echo ============================================
echo   Discord 429 Watchdog - Kurulum
echo ============================================
echo.
echo Bu bilgisayardaki TUM kullan icin gorev kaydedilecek.
echo Yoneticici olarak calistirmaniz onerilir.
echo.

:: Kendini yonetici yap
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Yonetici yetkisi gerekli, UAC onaylayın...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT=%~dp0Discord429Watchdog.ps1"
if not exist "%SCRIPT%" (
    echo HATA: Discord429Watchdog.ps1 bulunamadi!
    pause
    exit /b 1
)

echo Script: %SCRIPT%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%SCRIPT%\"';" ^
  "$trigger = New-ScheduledTaskTrigger -AtLogOn;" ^
  "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero);" ^
  "Register-ScheduledTask -TaskName 'Discord429Watchdog' -Action $action -Trigger $trigger -Settings $settings -Force -Description 'Discord 429 otomatik kurtarma' | Out-Null;" ^
  "Start-ScheduledTask -TaskName 'Discord429Watchdog';" ^
  "Write-Host ('Durum: ' + (Get-ScheduledTask -TaskName 'Discord429Watchdog').State)"

echo.
echo Kurulum tamamlandi! Artik her kullanici girisinde otomatik baslar.
pause
