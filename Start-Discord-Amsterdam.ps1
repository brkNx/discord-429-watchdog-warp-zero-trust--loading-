# Discord Amsterdam Proxy Launcher (Oracle Cloud 141.148.242.87)
# Connects Discord directly through personal dedicated IP in Netherlands.
$ErrorActionPreference = 'SilentlyContinue'

$key = Join-Path $env:USERPROFILE ".ssh\oracle-amsterdam.key"
if (-not (Test-Path $key)) {
    $key = Join-Path $env:USERPROFILE "Downloads\ssh-key-2026-08-28.key"
}

# Function to check if port 1080 is listening
function Test-PortListening([int]$Port = 1080) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect('127.0.0.1', $Port, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(400, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            $tcp.Close()
            return $true
        }
        $tcp.Close()
    } catch { }
    return $false
}

# 1. Start SSH tunnel if not running
if (-not (Test-PortListening 1080)) {
    Write-Host "[1/2] Amsterdam SOCKS5 proxy tüneli başlatılıyor..." -ForegroundColor Cyan
    $sshArgs = "-i `"$key`" -D 1080 -N -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o ExitOnForwardFailure=yes ubuntu@141.148.242.87"
    
    $proc = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
    
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-PortListening 1080) { break }
    }
}

$isReady = Test-PortListening 1080

if ($isReady) {
    Write-Host "[2/2] Amsterdam tüneli aktif (141.148.242.87). Discord başlatılıyor..." -ForegroundColor Green
} else {
    Write-Host "[!] Tünel başlatılamadı, Discord doğrudan açılıyor..." -ForegroundColor Yellow
}

# 2. Launch Discord with Proxy
$discordDir = Join-Path $env:LOCALAPPDATA "Discord"
$upd = Join-Path $discordDir "Update.exe"

$latestApp = Get-ChildItem -Directory $discordDir -Filter "app-*" | Sort-Object Name -Descending | Select-Object -First 1
$discordExe = if ($latestApp) { Join-Path $latestApp.FullName "Discord.exe" } else { "" }

if ($isReady) {
    if (Test-Path $discordExe) {
        Start-Process -FilePath $discordExe -ArgumentList '--proxy-server="socks5://127.0.0.1:1080"' -WorkingDirectory (Split-Path $discordExe)
    } elseif (Test-Path $upd) {
        Start-Process -FilePath $upd -ArgumentList '--processStart Discord.exe --process-start-args="--proxy-server=socks5://127.0.0.1:1080"'
    } else {
        Start-Process "discord://"
    }
} else {
    if (Test-Path $upd) {
        Start-Process -FilePath $upd -ArgumentList "--processStart Discord.exe"
    } else {
        Start-Process "discord://"
    }
}
