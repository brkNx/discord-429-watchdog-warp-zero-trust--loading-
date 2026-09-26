# Cloudflare WARP Discord Route Fixer (Elevated Helper)
# Ensures Discord CIDR prefixes route through CloudflareWARP interface
$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $env:TEMP "discord-warp-routes.log"
function L($m){ "$(Get-Date -Format 'HH:mm:ss') $m" | Add-Content -Path $log -Encoding UTF8 -ErrorAction SilentlyContinue }
$if = "CloudflareWARP"

$up = Get-NetIPInterface -InterfaceAlias $if -AddressFamily IPv4 -ErrorAction SilentlyContinue
if (-not $up) { exit 0 }
if ($up.ConnectionState -ne 'Connected') { exit 0 }

$nh = "192.0.2.1"
$ranges = @('172.64.0.0/13', '104.16.0.0/12', '104.24.0.0/14', '162.159.0.0/16')
foreach ($r in $ranges) {
    $ex = Get-NetRoute -DestinationPrefix $r -InterfaceAlias $if -ErrorAction SilentlyContinue
    if (-not $ex) {
        New-NetRoute -DestinationPrefix $r -InterfaceAlias $if -NextHop $nh -ErrorAction SilentlyContinue | Out-Null
        L "Added route: $r"
    }
}
exit 0
