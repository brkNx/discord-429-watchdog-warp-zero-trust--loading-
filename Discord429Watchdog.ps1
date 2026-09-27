# Discord 429 Watchdog - WARP IP rotation + route healing + controlled recovery
# Multi-user safe: log/state are per-user, script can be shared
param(
    [switch]$Manual,
    [int]$CooldownMinutes = 3,
    [int]$CheckIntervalSeconds = 20,
    [int]$PostRotationWaitSeconds = 15,
    [switch]$Once,
    [switch]$Force
)

# Auto-start prevention: Do not run automatically on boot/logon unless explicitly triggered with -Manual
if (-not $Manual -and -not $Force) {
    exit 0
}

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
        $warpIf = Get-NetIPInterface -InterfaceAlias 'CloudflareWARP' -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $warpIf -or $warpIf.ConnectionState -ne 'Connected') { return }

        # Check if traffic to Discord is actively routed through CloudflareWARP
        $route = Find-NetRoute -RemoteIPAddress '162.159.137.232' -ErrorAction SilentlyContinue
        if ($route -and ($route.InterfaceAlias -contains 'CloudflareWARP')) {
            return
        }

        # Fallback check: check for any Discord routes on the interface
        $anyRoute = Get-NetRoute -InterfaceAlias 'CloudflareWARP' -ErrorAction SilentlyContinue | Where-Object {
            $_.DestinationPrefix -like '162.159.*' -or $_.DestinationPrefix -eq '104.16.0.0/12'
        }
        if ($anyRoute) {
            return
        }

        # If routes are truly missing, attempt restoration
        Write-Log "Discord WARP routes missing. Restoring routes..."
        $task = Get-ScheduledTask -TaskName "DiscordWarpRoutes" -ErrorAction SilentlyContinue
        if ($task) {
            try {
                Start-ScheduledTask -TaskName "DiscordWarpRoutes" -ErrorAction Stop
                Start-Sleep -Seconds 2
            } catch {
                warp-cli connect 2>&1 | Out-Null
            }
        } else {
            warp-cli connect 2>&1 | Out-Null
        }
    } catch { }
}

function Test-DiscordInCall {
    if (-not (Test-Path $LogFile)) { return $false }
    $recent = Get-Content $LogFile -Tail 100 -ErrorAction SilentlyContinue
    if (-not $recent) { return $false }
    $inCall = $false
    foreach ($line in $recent) {
        if ($line -match 'RTC connection state:.*RTC_CONNECTED') { $inCall = $true }
        if ($line -match 'RTC connection state:.*(?:DISCONNECTED|RTC_DISCONNECTED)') { $inCall = $false }
    }
    return $inCall
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
        # Skip all non-chat / background telemetry calls:
        # webauthn, read receipts (/ack), public apps, analytics
        if ($l -match 'webauthn|\/ack\b|applications\/public|science|experiments|tracking') { continue }

        # ONLY match actual channel message loading failures that break user UI
        if ($l -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\.\d+)?\].*?(Failed to fetch messages|GET \/channels\/\d+\/messages.*?\[429\]|rate limited)') {
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
    try { warp-cli tunnel rotate-keys 2>&1 | Out-Null } catch { }
    warp-cli disconnect 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    warp-cli connect 2>&1 | Out-Null
    Start-Sleep -Seconds 4

    # Ensure routes are restored immediately after connect
    Restore-WarpRoutes

    $status = (warp-cli status 2>&1 | Out-String).Trim() -replace "[\r\n]+", " "
    $trace = curl.exe -s --max-time 6 "https://www.cloudflare.com/cdn-cgi/trace" 2>$null
    $ipMatch = $trace | Select-String "(?m)^ip=(.+)$"
    $ip = if ($ipMatch) { $ipMatch.Matches[0].Groups[1].Value.Trim() } else { "Unknown" }
    Write-Log "WARP: $status | IP: $ip"
}

function Start-DiscordClean {
    Write-Log "Launching Discord GUI cleanly..."
    $discordDir = Join-Path $env:LOCALAPPDATA "Discord"
    $upd = Join-Path $discordDir "Update.exe"
    $desktopLnk = Join-Path $env:USERPROFILE "Desktop\Discord.lnk"

    if (Test-Path $desktopLnk) {
        Start-Process -FilePath "explorer.exe" -ArgumentList "`"$desktopLnk`""
    } elseif (Test-Path $upd) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c start `"`" `"$upd`" --processStart Discord.exe"
    } else {
        Start-Process "discord://"
    }
    Start-Sleep -Seconds 5
}

function Restart-DiscordOnce {
    param([int]$CoolOffSeconds = 35)
    Write-Log "Performing controlled Discord restart..."
    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 3

    # Restore routes just before launching Discord
    Restore-WarpRoutes

    if ($CoolOffSeconds -gt 0) {
        Write-Log "Waiting ${CoolOffSeconds}s for Discord server rate-limit to cool down..."
        Start-Sleep -Seconds $CoolOffSeconds
    }

    Start-DiscordClean
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
            if (Test-DiscordInCall) {
                Write-Log "Discord is in an active voice call. Skipping restart to protect user conversation."
            } elseif ($rotationsLastHour -ge $MaxRotationsPerHour) {
                Write-Log "Hourly rotation limit reached ($rotationsLastHour), waiting..."
            } else {
                Write-Log "Actual message fetch failure detected! Starting recovery..."
                # 1. Stop Discord immediately to avoid resetting server rate-limit bucket
                Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 2

                # 2. Rotate WARP keys and reconnect
                Rotate-WarpIp

                # 3. Wait for Discord server rate-limit to clear
                Write-Log "Waiting 35s for Discord server-side rate-limit to clear..."
                Start-Sleep -Seconds 35

                # 4. Start Discord cleanly
                $launchTime = Get-Date
                Start-DiscordClean
                Start-Sleep -Seconds 15

                # 5. Verify if message errors recur
                if (Test-Recent429 -Since $launchTime) {
                    Write-Log "Errors persisted on restart, performing second cool-off cycle..."
                    Restart-DiscordOnce -CoolOffSeconds 30
                    Start-Sleep -Seconds 15
                } else {
                    Write-Log "Discord started cleanly, messages loading normally."
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
