# Stop Amsterdam SSH Tunnel
$ErrorActionPreference = 'SilentlyContinue'
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*141.148.242.87*" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force
    Write-Host "Amsterdam proxy tüneli sonlandırıldı (PID: $($_.ProcessId))." -ForegroundColor Yellow
}
