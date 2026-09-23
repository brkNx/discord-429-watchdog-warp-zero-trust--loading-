# Discord 429 Watchdog - WARP IP rotasyonu + kontrollu kurtarma
# Cok kullanici destekler: log/state kullaniciya ozel, script ortak
param(
    [int]$CooldownMinutes = 12,
    [int]$CheckIntervalSeconds = 30,
    [switch]$Once,
    [switch]$Force
)

$LogFile = Join-Path $env:APPDATA "discord\logs\renderer_js.log"
$StateFile = Join-Path $env:LOCALAPPDATA "discord-429-watchdog.state"
$LogPath = Join-Path $env:LOCALAPPDATA "discord-429-watchdog.log"
$MaxRotationsPerHour = 3

$mutexName = "Local\$($env:USERNAME)_Discord429Watchdog"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    Write-Host "Zaten calisiyor, cikis."
    exit 0
}

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

function Get-RecentState {
    if (Test-Path $StateFile) {
        try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ LastAction = [datetime]::MinValue.ToString("o"); Rotations = @() }
}

function Save-State($state) {
    $state | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8
}

function Test-Recent429 {
    if (-not (Test-Path $LogFile)) { return $false }
    $cutoff = (Get-Date).AddMinutes(-3)
    $lines = Get-Content $LogFile -Tail 300 -ErrorAction SilentlyContinue
    foreach ($l in $lines) {
        if ($l -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\].*(\[429\]|Failed to fetch messages)') {
            $ts = $null
            try { $ts = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd HH:mm:ss", $null) } catch { continue }
            if ($ts -ge $cutoff) { return $true }
        }
    }
    return $false
}

function Rotate-WarpIp {
    Write-Log "WARP IP rotasyonu baslatiliyor..."
    warp-cli disconnect 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    warp-cli connect 2>&1 | Out-Null
    Start-Sleep -Seconds 6
    $status = (warp-cli status 2>&1 | Out-String).Trim().Replace("`r`n", " ")
    $trace = curl.exe -s --max-time 8 "https://www.cloudflare.com/cdn-cgi/trace"
    $ip = ($trace | Select-String "^ip=").ToString().Split("=")[1]
    Write-Log "WARP: $status | Yeni IP: $ip"
}

function Restart-DiscordOnce {
    Write-Log "Discord tek seferlik kontrollu restart..."
    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 4
    $upd = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
    if (Test-Path $upd) {
        Start-Process $upd -ArgumentList "--processStart Discord.exe"
    } else {
        Start-Process "discord://"
    }
}

Write-Log "=== Watchdog basladi (cooldown=${CooldownMinutes}m, interval=${CheckIntervalSeconds}s, user=$($env:USERNAME)) ==="

try {
    while ($true) {
        $state = Get-RecentState
        $now = Get-Date
        $lastAction = [datetime]::Parse($state.LastAction)

        $rotationsLastHour = @($state.Rotations | Where-Object { [datetime]$_ -gt $now.AddHours(-1) }).Count
        $sinceLastAction = if ($lastAction -eq [datetime]::MinValue) { [TimeSpan]::MaxValue } else { $now - $lastAction }
        $inCooldown = $sinceLastAction.TotalMinutes -lt $CooldownMinutes

        if ($Force -or ((Test-Recent429) -and -not $inCooldown)) {
            if ($rotationsLastHour -ge $MaxRotationsPerHour) {
                Write-Log "Saatlik rotasyon limiti doldu ($rotationsLastHour), beklemede..."
            } else {
                Write-Log "429/hata algilandi! Kurtarma basliyor..."
                Rotate-WarpIp

                Start-Sleep -Seconds 90
                if (Test-Recent429) {
                    Write-Log "Hala hata var, Discord restart yapiliyor..."
                    Restart-DiscordOnce
                    Start-Sleep -Seconds 45
                } else {
                    Write-Log "Hata gecti, Discord'a dokunulmadi."
                }

                $state.LastAction = $now.ToString("o")
                $state.Rotations = @($state.Rotations | Where-Object { [datetime]$_ -gt $now.AddHours(-1) }) + @($now.ToString("o"))
                Save-State $state
                Write-Log "Kurtarma tamamlandi. Cooldown ${CooldownMinutes} dk."
            }
        }

        if ($Once -or $Force) { break }
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
