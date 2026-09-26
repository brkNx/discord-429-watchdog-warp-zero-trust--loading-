# Discord 429 Watchdog - WARP IP rotation + route healing + controlled recovery
# Multi-user safe: log/state are per-user, script can be shared
param(
    [int]$CooldownMinutes = 3,
    [int]$CheckIntervalSeconds = 20,
    [int]$PostRotationWaitSeconds = 15,
    [switch]$Once,
    [switch]$Force
)

$LogFile = Join-Path $env:APPDATA "discord\logs\renderer_js.log"
$StateFile = Join-Path $env:LOCALAPPDATA "discord-429-watchdog.state"
$LogPath = Join-Path $env:LOCALAPPDATA "discord-429-watchdog.log"
$MaxRotationsPerHour = 15

$mutexName = "Local\$($env:USERNAME)_Discord429Watchdog"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$hasMutex = $false
try {
    $hasMutex = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    # Mutex was abandoned by a terminated process; this instance now owns it.
    $hasMutex = $true
}

if (-not $hasMutex) {
    Write-Host "Already running, exiting."
    exit 0
}

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    try {
        Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    } catch { }
}

function Get-RecentState {
    if (Test-Path $StateFile) {
        try {
            $parsed = Get-Content $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($parsed -and $parsed.LastAction) {
                if ($null -eq $parsed.Rotations) {
                    $parsed.Rotations = @()
                }
                return $parsed
            }
        } catch { }
    }
    return [pscustomobject]@{ LastAction = [datetime]::MinValue.ToString("o"); Rotations = @() }
}

function Save-State($state) {
    try {
        $state | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8 -Force
    } catch {
        Write-Log "Warning: Could not save state: $_"
    }
}

function Restore-WarpRoutes {
    try {
        # Check if the Discord prefix exists on CloudflareWARP interface
        $route = Get-NetRoute -DestinationPrefix '162.159.0.0/16' -InterfaceAlias 'CloudflareWARP' -ErrorAction SilentlyContinue
        if (-not $route) {
            Write-Log "Discord WARP routes missing. Triggering DiscordWarpRoutes task..."
            Start-ScheduledTask -TaskName "DiscordWarpRoutes" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Log "Route check warning: $_"
    }
}

function Test-Recent429 {
    param(
        [double]$Minutes = 2,
        [datetime]$Since = [datetime]::MinValue
    )
    if (-not (Test-Path $LogFile)) { return $false }
    $cutoff = if ($Since -gt [datetime]::MinValue) { $Since } else { (Get-Date).AddMinutes(-$Minutes) }
    $lines = Get-Content $LogFile -Tail 250 -ErrorAction SilentlyContinue
    if (-not $lines) { return $false }
    foreach ($l in $lines) {
        if ($l -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\.\d+)?\].*?(\[429\]|Failed to fetch messages|rate limited)') {
            $ts = $null
            try {
                $ts = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            } catch { continue }
            if ($ts -ge $cutoff) { return $true }
        }
    }
    return $false
}

function Rotate-WarpIp {
    Write-Log "Starting WARP recovery & IP rotation..."
    warp-cli disconnect 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    warp-cli connect 2>&1 | Out-Null
    Start-Sleep -Seconds 4

    # Ensure routes are restored immediately after connect
    Start-ScheduledTask -TaskName "DiscordWarpRoutes" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $status = (warp-cli status 2>&1 | Out-String).Trim() -replace "[\r\n]+", " "
    $trace = curl.exe -s --max-time 6 "https://www.cloudflare.com/cdn-cgi/trace" 2>$null
    $ipMatch = $trace | Select-String "(?m)^ip=(.+)$"
    $ip = if ($ipMatch) { $ipMatch.Matches[0].Groups[1].Value.Trim() } else { "Unknown" }
    Write-Log "WARP: $status | IP: $ip"
}

function Restart-DiscordOnce {
    Write-Log "Performing controlled Discord restart..."
    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3

    # Restore routes just before launching Discord
    Start-ScheduledTask -TaskName "DiscordWarpRoutes" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    $discordDir = Join-Path $env:LOCALAPPDATA "Discord"
    $upd = Join-Path $discordDir "Update.exe"
    if (Test-Path $upd) {
        Start-Process -FilePath $upd -ArgumentList "--processStart Discord.exe" -WorkingDirectory $discordDir
    } else {
        Start-Process "discord://"
    }

    # Verify launch
    Start-Sleep -Seconds 3
    $running = Get-Process Discord -ErrorAction SilentlyContinue
    if (-not $running) {
        Write-Log "Retrying Discord launch directly..."
        $latestApp = Get-ChildItem -Directory $discordDir -Filter "app-*" | Sort-Object Name -Descending | Select-Object -First 1
        if ($latestApp) {
            $exe = Join-Path $latestApp.FullName "Discord.exe"
            if (Test-Path $exe) {
                Start-Process -FilePath $exe -WorkingDirectory $latestApp.FullName
            }
        }
    }
}

Write-Log "=== Watchdog started (cooldown=${CooldownMinutes}m, interval=${CheckIntervalSeconds}s, user=$($env:USERNAME)) ==="

try {
    while ($true) {
        # Periodic route check to heal missing routes silently
        Restore-WarpRoutes

        $state = Get-RecentState
        $now = Get-Date
        $lastAction = try { [datetime]::Parse($state.LastAction) } catch { [datetime]::MinValue }

        $rotationsLastHour = @($state.Rotations | Where-Object {
            try { [datetime]$_ -gt $now.AddHours(-1) } catch { $false }
        }).Count
        $sinceLastAction = if ($lastAction -eq [datetime]::MinValue) { [TimeSpan]::MaxValue } else { $now - $lastAction }
        $inCooldown = $sinceLastAction.TotalMinutes -lt $CooldownMinutes

        if ($Force -or ((Test-Recent429) -and -not $inCooldown)) {
            if ($rotationsLastHour -ge $MaxRotationsPerHour) {
                Write-Log "Hourly rotation limit reached ($rotationsLastHour), waiting..."
            } else {
                Write-Log "429/error detected! Starting recovery..."
                $rotationStartTime = Get-Date
                Rotate-WarpIp

                if ($PostRotationWaitSeconds -gt 0) {
                    Start-Sleep -Seconds $PostRotationWaitSeconds
                }

                # Only check for new errors that occurred AFTER the rotation started
                if (Test-Recent429 -Since $rotationStartTime) {
                    Write-Log "Errors persist after rotation, restarting Discord..."
                    Restart-DiscordOnce
                    Start-Sleep -Seconds 15
                } else {
                    Write-Log "Errors cleared, Discord left running."
                }

                $state.LastAction = (Get-Date).ToString("o")
                $state.Rotations = @($state.Rotations | Where-Object {
                    try { [datetime]$_ -gt (Get-Date).AddHours(-1) } catch { $false }
                }) + @((Get-Date).ToString("o"))
                Save-State $state
                Write-Log "Recovery complete. Cooldown ${CooldownMinutes}m."
            }
        }

        if ($Once -or $Force) { break }
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
} finally {
    if ($hasMutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    $mutex.Dispose()
}
