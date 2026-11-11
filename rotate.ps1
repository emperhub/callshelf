# rotate.ps1 - change the public IP address of this machine's WARP tunnel.
#
#   .\rotate.ps1                 show current IP and WARP mode
#   .\rotate.ps1 -Rotate         reconnect once, wait for a new address
#   .\rotate.ps1 -Rotate -Deep   reconnect, then re-register if the IP sticks
#   .\rotate.ps1 -Rotate -Json   machine-readable result
#
# Works with WARP in WarpProxy mode (default here): the tunnel is used only by
# clients that dial the SOCKS port, so the rest of the machine keeps its normal
# route. In full-tunnel mode it reads the address directly.
#
# Exit 0 = address changed, 1 = no change or WARP problem.

[CmdletBinding()]
param(
  [switch]$Rotate,
  [switch]$Deep,
  [switch]$Json,
  [int]$TimeoutSec = 20,
  [int]$Retries = 2
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Find-WarpCli {
  $cmd = Get-Command warp-cli.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($path in @(
      (Join-Path $env:ProgramFiles 'Cloudflare\Cloudflare WARP\warp-cli.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Cloudflare\Cloudflare WARP\warp-cli.exe'),
      (Join-Path $env:LOCALAPPDATA 'Cloudflare\Cloudflare WARP\warp-cli.exe'))) {
    if ($path -and (Test-Path -LiteralPath $path)) { return $path }
  }
  return $null
}

function Invoke-Warp {
  param([string]$Cli, [string[]]$Arguments)
  $out = & $Cli --accept-tos --no-ansi @Arguments 2>&1
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out | Out-String).Trim() }
}

function Get-ProxyPort {
  param([string]$Cli)
  $s = (Invoke-Warp $Cli @('settings')).Text
  if ($s -match 'Mode:\s*WarpProxy on port (\d+)') { return [int]$Matches[1] }
  return 0
}

function Get-EgressIp {
  param([string]$Cli, [int]$Port)

  if ($Port -gt 0) {
    $out = curl.exe -s -m 8 --socks5-hostname "127.0.0.1:$Port" https://www.cloudflare.com/cdn-cgi/trace 2>$null
  } else {
    $out = curl.exe -s -m 8 --noproxy '*' https://www.cloudflare.com/cdn-cgi/trace 2>$null
  }
  $m = [regex]::Match(($out | Out-String), '(?m)^ip=(.+)$')
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return $null
}

function Wait-NewIp {
  param([string]$Cli, [int]$Port, [string]$Before, [int]$Seconds)
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $ip = Get-EgressIp -Cli $Cli -Port $Port
    if ($ip -and $ip -ne $Before) { return $ip }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Connect-Warp {
  param([string]$Cli)
  Invoke-Warp $Cli @('connect') | Out-Null
  Start-Sleep -Milliseconds 800
}

function Invoke-FastRotate {
  param([string]$Cli, [int]$Port, [string]$Before)

  for ($try = 1; $try -le $Retries; $try++) {
    if (-not $Json) { Write-Host "  reconnect $try/$Retries" -ForegroundColor DarkGray }
    Invoke-Warp $Cli @('disconnect') | Out-Null
    Start-Sleep -Milliseconds 700
    Invoke-Warp $Cli @('connect') | Out-Null
    $ip = Wait-NewIp -Cli $Cli -Port $Port -Before $Before -Seconds $TimeoutSec
    if ($ip) { return [pscustomobject]@{ Ok = $true; Ip = $ip; Method = 'reconnect' } }
  }
  return [pscustomobject]@{ Ok = $false; Ip = (Get-EgressIp -Cli $Cli -Port $Port); Method = 'reconnect' }
}

function Invoke-DeepRotate {
  param([string]$Cli, [int]$Port, [string]$Before)

  if (-not $Json) { Write-Host '  re-registering the tunnel' -ForegroundColor DarkGray }
  Invoke-Warp $Cli @('disconnect') | Out-Null
  Start-Sleep -Seconds 2

  $cleared = $false
  for ($try = 1; $try -le 3; $try++) {
    Invoke-Warp $Cli @('registration', 'delete') | Out-Null
    Start-Sleep -Seconds 2
    $show = (Invoke-Warp $Cli @('registration', 'show')).Text
    if ($show -match 'Missing registration') { $cleared = $true; break }
  }
  if (-not $cleared) {
    Connect-Warp $Cli
    return [pscustomobject]@{ Ok = $false; Ip = (Get-EgressIp -Cli $Cli -Port $Port); Method = 'register' }
  }

  $registered = $false
  for ($try = 1; $try -le 2; $try++) {
    $r = Invoke-Warp $Cli @('registration', 'new')
    if ($r.Code -eq 0) { $registered = $true; break }
    Start-Sleep -Seconds (8 + (Get-Random -Minimum 0 -Maximum 5))
  }
  if (-not $registered) {
    Connect-Warp $Cli
    return [pscustomobject]@{ Ok = $false; Ip = (Get-EgressIp -Cli $Cli -Port $Port); Method = 'register' }
  }

  Connect-Warp $Cli
  $ip = Wait-NewIp -Cli $Cli -Port $Port -Before $Before -Seconds ([math]::Max($TimeoutSec, 15))
  return [pscustomobject]@{ Ok = [bool]$ip; Ip = $(if ($ip) { $ip } else { Get-EgressIp -Cli $Cli -Port $Port }); Method = 'register' }
}

# --------------------------------------------------------------------- main
$cli = Find-WarpCli
if (-not $cli) {
  if ($Json) {
    '{"ok":false,"error":"warp-cli not found"}'
  } else {
    Write-Host 'warp-cli not found. Install Cloudflare WARP first: winget install Cloudflare.Warp' -ForegroundColor Red
  }
  exit 1
}

$port = Get-ProxyPort $cli
$before = Get-EgressIp -Cli $cli -Port $port
if (-not $before) {
  if ($Json) {
    '{"ok":false,"error":"tunnel is not answering"}'
  } else {
    Write-Host 'The tunnel is not answering. Connect WARP and try again.' -ForegroundColor Red
  }
  exit 1
}

$account = (Invoke-Warp $cli @('registration', 'show')).Text
$managed = $account -match 'Account type:\s*(Team|Enterprise|Managed)'

if (-not $Rotate) {
  if ($Json) {
    [pscustomobject]@{
      ok = $true
      ip = $before
      proxyPort = $port
      mode = $(if ($port) { 'warp-proxy' } else { 'full-tunnel' })
      managed = [bool]$managed
    } | ConvertTo-Json -Compress
  } else {
    Write-Host ''
    Write-Host "  warp-cli  : $cli"
    Write-Host "  mode      : $(if ($port) { "WarpProxy on 127.0.0.1:$port" } else { 'full tunnel' })"
    Write-Host "  egress ip : $before"
    Write-Host "  account   : $(if ($managed) { 'managed - rotation blocked' } else { 'personal' })"
    Write-Host ''
    Write-Host '  -Rotate        get a new IP' -ForegroundColor DarkGray
    Write-Host '  -Rotate -Deep  re-register if reconnect keeps the same IP' -ForegroundColor DarkGray
  }
  exit 0
}

if ($managed) {
  if ($Json) {
    '{"ok":false,"error":"managed registration; refusing to rotate"}'
  } else {
    Write-Host 'This tunnel belongs to an organisation. Refusing to delete its registration.' -ForegroundColor Red
  }
  exit 1
}

$started = Get-Date
$result = $null

if ($Deep) {
  $result = Invoke-DeepRotate -Cli $cli -Port $port -Before $before
} else {
  $result = Invoke-FastRotate -Cli $cli -Port $port -Before $before
  if (-not $result.Ok) {
    if (-not $Json) { Write-Host '  no change; falling back to re-registration' -ForegroundColor DarkGray }
    $result = Invoke-DeepRotate -Cli $cli -Port $port -Before $before
  }
}

# Never leave the tunnel down because a probe failed.
if (-not (Get-EgressIp -Cli $cli -Port $port)) { Connect-Warp $cli }

$elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)

if ($Json) {
  [pscustomobject]@{
    ok = [bool]$result.Ok
    before = $before
    after = $result.Ip
    method = $result.Method
    elapsedSec = $elapsed
  } | ConvertTo-Json -Compress
} elseif ($result.Ok) {
  Write-Host "  $before -> $($result.Ip)  ($($result.Method), ${elapsed}s)" -ForegroundColor Green
} else {
  Write-Host "  still on $($result.Ip)  ($($result.Method), ${elapsed}s)" -ForegroundColor Red
}

if ($result.Ok) { exit 0 } else { exit 1 }
