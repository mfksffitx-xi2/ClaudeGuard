# Claude bodyguard v3 (2026-10-26) - force-closes Claude + interactive browsers when the proxy path is unsafe.
# Setup: Clash Verge Rev must be mode=global + target-country node; system proxy on (TUN info only). Non-global => kill Claude. Read-only: never changes Clash/adapters/firewall/proxy.
# Every 2s : core running | system proxy on 127.0.0.1:<mixed-port> | port listening | live node (via controller pipe) is in the target country
# Every 15s: exit country THROUGH local proxy (cloudflare, then ip-api, ipinfo fallback) in background
# Debounce (2026-10-27 flaky fix): nothing is killed on a single bad probe. Measured-bad must persist >=3 checks AND >=20s
#   (exit wrong country: 2 measurements in a row); 'could not measure' (controller/exit APIs unreachable) needs >=30s of repeats.
#   Claude/claude.ai reachability is NOT checked here and never kills anything (display-only in the UI).
# Test: powershell -File claude-bodyguard.ps1 -TestOnce   (prints checks + timings + browser dry-run, never kills)
param([switch]$TestOnce, [int]$ParentPid = 0)   # ParentPid = SwitcherUI powershell; bodyguard lives only while it lives
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$BASE = Join-Path $env:USERPROFILE '.claude-switcher'

# 可打包配置: %USERPROFILE%\.claude-switcher\guard-settings.json
# 自动识别: { "auto": true }  — 首次检查时按当前出口写入 country/city，然后 auto 变 false
# 手写示例: { "auto": false, "country":"US", "city":"Los Angeles", "timezone":"Pacific Standard Time", "node_match":"美国|USA|US", "ip_mode":"dynamic" }
function Get-GuardSettings {
    $f = Join-Path $BASE 'guard-settings.json'
    $d = @{
        auto       = $true
        country    = ''
        city       = ''
        timezone   = ''
        node_match = ''
        ip_mode    = 'dynamic'
        browsers   = $null
    }
    if (-not (Test-Path $f)) { return $d }
    try {
        $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $j.auto) { $d.auto = [bool]$j.auto }
        if ($j.country) { $d.country = [string]$j.country }
        if ($j.city) { $d.city = [string]$j.city }
        if ($j.timezone) { $d.timezone = [string]$j.timezone }
        if ($null -ne $j.node_match) { $d.node_match = [string]$j.node_match }
        if ($j.ip_mode) { $d.ip_mode = ([string]$j.ip_mode).ToLower() }
        if ($j.PSObject.Properties.Name -contains 'browsers') { $d.browsers = @(@($j.browsers) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() }) }
    } catch {}
    return $d
}

function Save-GuardSettings($s) {
    $f = Join-Path $BASE 'guard-settings.json'
    $obj = [ordered]@{
        auto       = [bool]$s.auto
        country    = [string]$s.country
        city       = [string]$s.city
        timezone   = [string]$s.timezone
        node_match = [string]$s.node_match
        ip_mode    = [string]$s.ip_mode
    }
    if ($null -ne $s.browsers) { $obj.browsers = [object[]]@($s.browsers) }
    ($obj | ConvertTo-Json) | Out-File -Encoding utf8 $f
}

# 用当前出口自动填 country/city；时区保留本机或已有配置
function Update-GuardSettingsFromEgress($ip, $loc) {
    $s = Get-GuardSettings
    if (-not $s.auto) { return $s }
    if (-not $loc -and -not $ip) { return $s }
    $city = ''
    try {
        if ($ip) {
            $j = (& curl.exe -s --max-time 3 "https://ipinfo.io/$ip/json" 2>$null) | ConvertFrom-Json
            if ($j.city) { $city = [string]$j.city }
            if (-not $loc -and $j.country) { $loc = [string]$j.country }
        }
    } catch {}
    if ($loc) { $s.country = $loc.ToUpper() }
    if ($city) { $s.city = $city }
    if (-not $s.timezone) { $s.timezone = (Get-TimeZone).Id }
    if (-not $s.ip_mode) { $s.ip_mode = 'dynamic' }
    $s.auto = $false
    Save-GuardSettings $s
    return $s
}

function Resolve-GuardTargets {
    $s = Get-GuardSettings
    $country = if ($s.country) { $s.country } else { 'US' }
    $tz = if ($s.timezone) { $s.timezone } else { (Get-TimeZone).Id }
    $ipMode = if ($s.ip_mode) { $s.ip_mode } else { 'dynamic' }
    return @{ settings = $s; country = $country; timezone = $tz; ip_mode = $ipMode; city = $s.city }
}





$LOG  = Join-Path $BASE 'bodyguard.log'
$COUNTRY_TARGET = 'US'
$__rt = Resolve-GuardTargets
$COUNTRY_TARGET = $__rt.country
# Node name match for target country (override via guard-settings.json node_match). Escapes keep this file encoding-proof.
$NODE_RX = '\u7f8e\u56fd|\uD83C\uDDFA\uD83C\uDDF8|United States|USA|(^|[^A-Za-z])US([^A-Za-z]|$)'
if ($__rt.settings.node_match) { $NODE_RX = $__rt.settings.node_match }
$LOOP_SEC = 2
$EXIT_EVERY_SEC = 15
$EXIT_RETRY_SEC = 5
# Debounce thresholds: measured-bad needs N consecutive checks AND T seconds; unknown (couldn't measure) needs N repeats AND T seconds
$DEBOUNCE = @{
    local = @{ badN = 3; badSec = 20; unkN = 0; unkSec = 0 }
    node  = @{ badN = 3; badSec = 20; unkN = 5; unkSec = 30 }
    exit  = @{ badN = 2; badSec = 0;  unkN = 3; unkSec = 30 }
    loc   = @{ badN = 3; badSec = 20; unkN = 0; unkSec = 0 }
}
$HTTP_TIMEOUT_SEC = 5
$PAUSE_FLAG = Join-Path $BASE 'bodyguard-off.flag'   # exists -> paused (no kills)
$CLASH_YAML = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml'

function Write-Log([string]$m) {
    if ($TestOnce) { Write-Output "[log] $m"; return }
    try {
        if ((Test-Path $LOG) -and ((Get-Item $LOG).Length -gt 1MB)) { Move-Item $LOG "$LOG.old" -Force }
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File -Append -Encoding utf8 $LOG
    } catch {}
}

function Get-ProxyMode {
    $f = Join-Path $BASE 'proxy-mode.txt'; $m = ''
    if (Test-Path $f) { $m = (Get-Content $f -Raw).Trim() }
    if (-not $m) { $m = 'clash-verge' }
    return $m
}
function Get-CoreName([string]$mode) { switch ($mode) { 'sing-box' { 'sing-box' } 'clashx' { 'ClashX' } default { 'verge-mihomo' } } }

function Get-YamlValue([string]$key) {
    if (-not (Test-Path $CLASH_YAML)) { return '' }
    $l = Select-String -Path $CLASH_YAML -Pattern "^$([regex]::Escape($key)):\s*(.*)$" | Select-Object -First 1
    if ($l) { return $l.Matches[0].Groups[1].Value.Trim().Trim("'").Trim('"') }
    return ''
}
function Get-ClashPort {
    $p = 0
    $v = Get-YamlValue 'mixed-port'; if (-not $v) { $v = Get-YamlValue 'port' }
    if ($v -match '^\d+$') { $p = [int]$v }
    if ($p -le 0) { $p = 7897 }
    return $p
}
function Test-PortListening([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $ar = $c.BeginConnect('127.0.0.1', $port, $null, $null); return ($ar.AsyncWaitHandle.WaitOne(1000) -and $c.Connected) }
    catch { return $false } finally { $c.Close() }
}
function Test-SystemProxy([int]$port) {
    $k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $srv = [string]$k.ProxyServer
    $ok = ($k.ProxyEnable -eq 1) -and ($srv -match "(^|[=;])\s*(127\.0\.0\.1|localhost)\s*:\s*$port(\s*;|\s*$)")
    return @{ ok = $ok; detail = "ProxyEnable=$($k.ProxyEnable) ProxyServer=$srv" }
}
$script:tunInfo = 'tun=?'; $script:tunAt = [datetime]::MinValue
function Get-TunInfo {
    if (((Get-Date) - $script:tunAt).TotalSeconds -ge 30) {
        $script:tunInfo = if (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '198.18.*' }) { 'tun=on' } else { 'tun=off' }
        $script:tunAt = Get-Date
    }
    return $script:tunInfo
}

function Get-LocalState {
    $mode = Get-ProxyMode; $core = Get-CoreName $mode; $port = Get-ClashPort
    $reasons = @()
    if (-not (Get-Process -Name $core)) { $reasons += "core $core not running" }
    $sp = Test-SystemProxy $port
    if (-not $sp.ok) { $reasons += "system proxy not on 127.0.0.1:$port ($($sp.detail))" }
    if (-not (Test-PortListening $port)) { $reasons += "port $port not listening" }
    return @{ ok = ($reasons.Count -eq 0); port = $port; reason = ($reasons -join '; '); info = "core=$core port=$port $(Get-TunInfo)" }
}

# ---- Clash controller over named pipe (external-controller is '' on this box) ----
$script:pipeName = ''
function Find-ControllerPipe {
    $cands = @()
    $y = Get-YamlValue 'external-controller-pipe'
    if ($y) { $cands += ($y -replace '^\\\\\.\\pipe\\', '') }
    try { $cands += [IO.Directory]::GetFiles('\\.\pipe\') | ForEach-Object { $_ -replace '^\\\\\.\\pipe\\', '' } | Where-Object { $_ -like 'verge-mihomo*' } } catch {}
    foreach ($c in ($cands | Select-Object -Unique)) { if ([IO.File]::Exists("\\.\pipe\$c")) { return $c } }
    return ''
}
function Invoke-PipeGet([string]$path) {
    if (-not $script:pipeName) { $script:pipeName = Find-ControllerPipe }
    if (-not $script:pipeName) { throw 'controller pipe not found' }
    $sec = Get-YamlValue 'secret'
    $c = New-Object System.IO.Pipes.NamedPipeClientStream('.', $script:pipeName, [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
    try {
        try { $c.Connect(1000) } catch { $script:pipeName = ''; throw 'controller pipe connect failed' }
        $req = "GET $path HTTP/1.0`r`nHost: localhost`r`n" + $(if ($sec) { "Authorization: Bearer $sec`r`n" } else { '' }) + "`r`n"
        $b = [Text.Encoding]::ASCII.GetBytes($req); $c.Write($b, 0, $b.Length); $c.Flush()
        $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 65536; $deadline = (Get-Date).AddMilliseconds(1500)
        while ($true) {
            $t = $c.ReadAsync($buf, 0, $buf.Length)
            $left = [int][Math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds)
            if (-not $t.Wait($left)) { throw 'controller read timeout' }
            if ($t.Result -le 0) { break }
            $ms.Write($buf, 0, $t.Result)
        }
        $s = [Text.Encoding]::UTF8.GetString($ms.ToArray())
        $i = $s.IndexOf("`r`n`r`n")
        if ($i -lt 0 -or $s -notmatch '^HTTP/1\.\d 200') { throw "controller bad response: $($s.Split("`n")[0])" }
        return ($s.Substring($i + 4) | ConvertFrom-Json)
    } finally { $c.Dispose() }
}
# Live mode + leaf node. mode=global -> GLOBAL chain; rule -> Proxy chain; direct -> unsafe.
function Get-NodeState {
    try {
        $mode = [string](Invoke-PipeGet '/configs').mode
        $px = (Invoke-PipeGet '/proxies').proxies
    } catch { return @{ ok = $false; unknown = $true; node = ''; reason = "controller unreachable: $_" } }
    if ($mode.ToLower() -ne 'global') {
        return @{ ok = $false; node = ''; reason = "clash mode=$mode (need global)"; mode = $mode }
    }
    $start = 'GLOBAL'
    if (-not $start) { return @{ ok = $false; node = ''; reason = "clash mode=$mode"; mode = $mode } }
    $name = $start; $path = @($start)
    for ($i = 0; $i -lt 10; $i++) {
        $n = $px.$name
        if ($n -and $n.now) { $name = [string]$n.now; $path += $name } else { break }
    }
    $leaf = $px.$name
    if (-not $leaf) { return @{ ok = $false; node = $name; reason = "leaf not found mode=$mode" } }
    if ($name -in @('DIRECT', 'REJECT')) { return @{ ok = $false; node = $name; reason = "leaf=$name mode=$mode" } }
    $inTarget = $name -match $NODE_RX
    return @{ ok = $inTarget; node = $name; reason = $(if ($inTarget) { '' } else { "node not target country (mode=$mode, $($path -join ' > '))" }); mode = $mode }
}

# ---- Exit check (runs in a background runspace so the 2s loop never blocks) ----
$EXIT_SCRIPT = {
    param([int]$port, [int]$timeout, [datetime]$ipapiUntil, [datetime]$ipinfoUntil)
    $ProgressPreference = 'SilentlyContinue'
    $px = "http://127.0.0.1:$port"; $now = Get-Date; $res = @{ country = ''; ip = ''; src = ''; unreachable = $false; skipped = $false; ipapiUntil = $ipapiUntil; ipinfoUntil = $ipinfoUntil }
    $tried = $false
    # Cloudflare trace first (no rate limit on shared exit IP)
    $tried = $true
    try {
        $c = (Invoke-WebRequest -UseBasicParsing -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -Proxy $px -TimeoutSec $timeout).Content
        $loc = ([regex]::Match($c, '(?m)^loc=(\w+)')).Groups[1].Value; $cip = ([regex]::Match($c, '(?m)^ip=(\S+)')).Groups[1].Value
        if ($loc) { $res.country = $loc; $res.ip = $cip; $res.src = 'cloudflare'; return $res }
    } catch { }
    if ($now -ge $ipapiUntil) {
        $tried = $true
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://ip-api.com/json/?fields=status,countryCode,query' -Proxy $px -TimeoutSec $timeout
            $rl = $r.Headers['X-Rl']; $ttl = $r.Headers['X-Ttl']
            if ($rl -ne $null -and [int]$rl -le 2 -and $ttl) { $res.ipapiUntil = $now.AddSeconds([int]$ttl + 1) }
            $j = $r.Content | ConvertFrom-Json
            if ($j.status -eq 'success' -and $j.countryCode) { $res.country = $j.countryCode; $res.ip = $j.query; $res.src = 'ip-api'; return $res }
        } catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 429) { $res.ipapiUntil = $now.AddSeconds(60) } }
    }
    if ($now -ge $ipinfoUntil) {
        $tried = $true
        try {
            $j = Invoke-RestMethod -UseBasicParsing -Uri 'https://ipinfo.io/json' -Proxy $px -TimeoutSec $timeout
            if ($j.country) { $res.country = $j.country; $res.ip = $j.ip; $res.src = 'ipinfo'; return $res }
        } catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 429) { $res.ipinfoUntil = $now.AddMinutes(10) } }
    }
    if (-not $tried) { $res.skipped = $true } else { $res.unreachable = $true }
    return $res
}

# ---- Location sharing (system ConsentStore + selected browser geo policy) ----
function Test-LocationSharingUnsafe {
    $reasons = @()
    $hkcu = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    $sysVal = ''
    try {
        if (Test-Path $hkcu) {
            $sysVal = [string](Get-ItemProperty -Path $hkcu -Name 'Value' -ErrorAction SilentlyContinue).Value
        }
    } catch {}
    if ($sysVal -eq 'Allow' -or $sysVal -eq 'Prompt') {
        $reasons += "system location=$sysVal"
    } else {
        try {
            $svc = Get-Service -Name 'lfsvc' -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running' -and $sysVal -ne 'Deny') {
                $reasons += 'system location service running'
            }
        } catch {}
    }
    $s = Get-GuardSettings
    $sel = if ($null -ne $s.browsers -and @($s.browsers).Count -gt 0) {
        @($s.browsers | ForEach-Object { ([string]$_).ToLower() } | Where-Object { $_ -in @('edge','chrome') })
    } else {
        $cands = @()
        if (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')) { $cands += 'edge' }
        if (Test-Path (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')) { $cands += 'chrome' }
        $cands
    }
    $policyMap = @{
        edge   = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'
        chrome = 'HKCU:\SOFTWARE\Policies\Google\Chrome'
    }
    foreach ($k in $sel) {
        $pol = $policyMap[$k]
        $geo = $null
        try {
            # machine policy (HKLM) wins over user policy (HKCU); UI check reads them in the same order
            foreach ($pp in @(($pol -replace '^HKCU:', 'HKLM:'), $pol)) {
                if ($null -eq $geo -and $pp -and (Test-Path $pp)) {
                    $geo = (Get-ItemProperty -Path $pp -Name 'DefaultGeolocationSetting' -ErrorAction SilentlyContinue).DefaultGeolocationSetting
                }
            }
        } catch {}
        if ($null -eq $geo -or [int]$geo -ne 2) {
            $reasons += "$k location not blocked"
        }
    }
    if ($reasons.Count -gt 0) {
        return @{ ok = $false; reason = ($reasons -join '; ') }
    }
    return @{ ok = $true; reason = '' }
}

# ---- Browser kill (interactive default profiles only) ----
$BROWSER_EXES = @('chrome.exe','msedge.exe','firefox.exe','brave.exe','opera.exe','360ChromeX.exe','360chrome.exe')
$DEFAULT_UDD = @(
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
    (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'),
    (Join-Path $env:LOCALAPPDATA '360ChromeX\Chrome\User Data')
) | ForEach-Object { $_.TrimEnd('\').ToLower() }

function Get-UserDataDir([string]$cmd) {
    if ($cmd -match '--user-data-dir="([^"]+)"') { return $Matches[1] }
    if ($cmd -match '--user-data-dir=(\S+)') { return $Matches[1] }
    return ''
}

# Returns root browser processes with decision: kill=$true/$false + why
function Get-BrowserTargets {
    $all = @(Get-CimInstance Win32_Process)
    $byId = @{}; foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
    $out = @()
    foreach ($p in $all) {
        $name = [string]$p.Name
        $cmd  = [string]$p.CommandLine
        if ($BROWSER_EXES -notcontains $name.ToLower()) { continue }
        if ($cmd -match '--type=|-contentproc') { continue }          # child process; dies with its root
        $par = $byId[[int]$p.ParentProcessId]
        if ($par -and $par.Name -eq $name -and ([string]$par.CommandLine -notmatch '--type=')) { continue }  # not the root
        $udd = Get-UserDataDir $cmd
        $kill = $false; $why = ''
        if ($cmd -match '(^|\s)--?headless') { $why = 'skip: headless' }
        elseif ($cmd -match '--remote-debugging-(port|pipe)|--enable-automation|(^|\s)-marionette|--embedded-browser-webview') { $why = 'skip: automation/debug' }
        elseif ($udd -and ($DEFAULT_UDD -notcontains $udd.TrimEnd('\').ToLower())) { $why = "skip: non-default profile $udd" }
        elseif ($name -eq 'firefox.exe' -and $cmd -match '(^|\s)-(profile|no-remote)\b') { $why = 'skip: firefox custom profile' }
        else { $kill = $true; $why = if ($udd) { "default profile $udd" } else { 'default profile' } }
        $out += [pscustomobject]@{ Name = $name; Pid = [int]$p.ProcessId; Kill = $kill; Why = $why }
    }
    return $out
}

function Stop-Browsers([string]$why) {
    $t = @(Get-BrowserTargets | Where-Object Kill)
    if ($t.Count -eq 0) { return }
    $list = ($t | ForEach-Object { "$($_.Name):$($_.Pid)" }) -join ','
    foreach ($x in $t) { & taskkill.exe /PID $x.Pid /T /F 2>&1 | Out-Null }
    Write-Log "KILL browsers [$list]: $why"
}
function Stop-Claude([string]$why) {
    $p = Get-Process -Name 'Claude'   # case-insensitive: Claude / claude
    if ($p) {
        $ids = ($p | ForEach-Object { $_.Id }) -join ','
        $p | Stop-Process -Force
        Write-Log "KILL Claude (pid $ids): $why"
    }
    Stop-Browsers $why
}

# ---- Debounced decision (pure functions; no side effects, testable with fake inputs) ----
# obs: 'ok' = measured fine; 'bad' = measured and unsafe; 'unknown' = couldn't measure; 'skip' = not measured this round
function New-SignalState { return @{ badN = 0; badSince = $null; unkN = 0; unkSince = $null; reason = '' } }
function New-GuardDecisionState { return @{ local = (New-SignalState); node = (New-SignalState); exit = (New-SignalState); loc = (New-SignalState) } }
function Update-SignalState($sig, [string]$obs, [datetime]$now, [string]$reason = '') {
    switch ($obs) {
        'ok'      { $sig.badN = 0; $sig.badSince = $null; $sig.unkN = 0; $sig.unkSince = $null; $sig.reason = '' }
        'bad'     { $sig.badN++; if ($null -eq $sig.badSince) { $sig.badSince = $now }; $sig.unkN = 0; $sig.unkSince = $null; $sig.reason = $reason }
        'unknown' { $sig.unkN++; if ($null -eq $sig.unkSince) { $sig.unkSince = $now }; if ($sig.badN -eq 0) { $sig.reason = $reason } }
        default   { }
    }
}
function Test-SignalTripped($sig, $cfg, [datetime]$now) {
    if ($sig.badN -gt 0 -and $sig.badN -ge $cfg.badN -and ($now - $sig.badSince).TotalSeconds -ge $cfg.badSec) { return $true }
    if ($cfg.unkN -gt 0 -and $sig.unkN -ge $cfg.unkN -and ($now - $sig.unkSince).TotalSeconds -ge $cfg.unkSec) { return $true }
    return $false
}
# Returns @{ kill = bool; reason = string; pending = string }  (order: local, node, exit, loc)
function Get-GuardDecision($state, $cfgAll, [datetime]$now) {
    $pending = @()
    foreach ($k in @('local', 'node', 'exit', 'loc')) {
        $sig = $state[$k]
        if (Test-SignalTripped $sig $cfgAll[$k] $now) {
            $kind = if ($sig.badN -gt 0) { "x$($sig.badN)" } else { "unmeasurable x$($sig.unkN)" }
            return @{ kill = $true; reason = "$k unsafe ($kind): $($sig.reason)"; pending = '' }
        }
        if ($sig.badN -gt 0) { $pending += "$k bad x$($sig.badN)" } elseif ($sig.unkN -gt 0) { $pending += "$k unknown x$($sig.unkN)" }
    }
    return @{ kill = $false; reason = ''; pending = ($pending -join ', ') }
}

# ---- Lifetime: follow the switcher window (SwitcherUI.ps1) ----
function Find-SwitcherPid {
    $p = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'SwitcherUI\.ps1' } | Select-Object -First 1
    if ($p) { return [int]$p.ProcessId } else { return 0 }
}
function Test-SwitcherAlive {
    if ($script:ParentPid -gt 0 -and (Get-Process -Id $script:ParentPid)) { return $true }
    $script:ParentPid = Find-SwitcherPid          # parent gone: adopt another open switcher window if any
    return ($script:ParentPid -gt 0)
}
if ($TestOnce) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $ls = Get-LocalState; $t1 = $sw.ElapsedMilliseconds
    Write-Output ("LOCAL ok={0} {1} {2}  [{3} ms]" -f $ls.ok, $ls.info, $ls.reason, $t1)
    $sw.Restart(); $ns = Get-NodeState; $t2 = $sw.ElapsedMilliseconds
    Write-Output ("NODE  ok={0} mode={1} leaf={2} {3}  [{4} ms] pipe={5}" -f $ns.ok, $ns.mode, $ns.node, $ns.reason, $t2, $script:pipeName)
    $sw.Restart(); $ex = & $EXIT_SCRIPT $ls.port $HTTP_TIMEOUT_SEC ([datetime]::MinValue) ([datetime]::MinValue); $t3 = $sw.ElapsedMilliseconds
    Write-Output ("EXIT  ok={0} country={1} ip={2} src={3} unreachable={4}  [{5} ms]" -f ($ex.country -eq $COUNTRY_TARGET), $ex.country, $ex.ip, $ex.src, $ex.unreachable, $t3)
    $loc = Test-LocationSharingUnsafe
    Write-Output ("LOC   ok={0} {1}" -f $loc.ok, $loc.reason)
    Write-Output 'BROWSER DRY-RUN (nothing killed):'
    Get-BrowserTargets | Sort-Object Kill -Descending | ForEach-Object { Write-Output ("  {0} {1} pid={2} :: {3}" -f $(if ($_.Kill) { 'WOULD-KILL' } else { 'keep      ' }), $_.Name, $_.Pid, $_.Why) }
    exit 0
}

# Single instance
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeBodyguardV2', [ref]$created)
if (-not $created) { exit 0 }

Write-Log "START bodyguard v3 pid=$PID target=$COUNTRY_TARGET loop=${LOOP_SEC}s node-check=${LOOP_SEC}s exit-check=${EXIT_EVERY_SEC}s"
$lastLocal = ''; $lastNode = ''; $lastExit = ''; $lastLoc = ''; $lastPending = ''
$exitUnreach = 0; $gd = New-GuardDecisionState
$ipapiUntil = [datetime]::MinValue; $ipinfoUntil = [datetime]::MinValue
$nextExit = Get-Date; $exitPS = $null; $exitH = $null; $wasPaused = $false
try {
    while ($true) {
        $loopStart = Get-Date
        if (-not (Test-SwitcherAlive)) { Write-Log 'STOP (switcher closed)'; break }
        $paused = Test-Path $PAUSE_FLAG
        if ($paused -ne $wasPaused) {
            if ($paused) { Write-Log 'PAUSED (bodyguard-off.flag present; no kills)' }
            else {
                Write-Log 'RESUMED'
                $lastLocal = ''; $lastNode = ''; $lastExit = ''; $lastLoc = ''; $lastPending = ''; $exitUnreach = 0; $gd = New-GuardDecisionState
                if (-not $exitH) { $nextExit = Get-Date }
            }
            $wasPaused = $paused
        }
        if ($paused) { Start-Sleep -Milliseconds 1000; continue }
        $ls = Get-LocalState
        $st = if ($ls.ok) { "LOCAL OK ($($ls.info))" } else { "LOCAL UNSAFE: $($ls.reason) ($($ls.info))" }
        if ($st -ne $lastLocal) { Write-Log $st; $lastLocal = $st }
        $now = Get-Date
        Update-SignalState $gd.local $(if ($ls.ok) { 'ok' } else { 'bad' }) $now $ls.reason

        $ns = $null
        if ($ls.ok) {
            $ns = Get-NodeState
            $st = if ($ns.ok) { "NODE OK $($ns.node) (mode=$($ns.mode))" } else { "NODE UNSAFE: $($ns.reason) leaf=$($ns.node)" }
            if ($st -ne $lastNode) {
                Write-Log $st; $lastNode = $st
                if ($ns.ok) { $nextExit = Get-Date }   # node changed -> verify exit right away
            }
            $nObs = if ($ns.ok) { 'ok' } elseif ($ns.unknown) { 'unknown' } else { 'bad' }
            Update-SignalState $gd.node $nObs $now "$($ns.reason) leaf=$($ns.node)"
        }

        # collect finished background exit check
        if ($exitH -and $exitH.IsCompleted) {
            $r = $exitPS.EndInvoke($exitH) | Select-Object -Last 1
            $exitPS.Dispose(); $exitPS = $null; $exitH = $null
            if ($r) {
                $ipapiUntil = $r.ipapiUntil; $ipinfoUntil = $r.ipinfoUntil
                if ($r.skipped) { $st = 'EXIT SKIPPED (both APIs in rate-limit backoff)'; $nextExit = (Get-Date).AddSeconds($EXIT_EVERY_SEC) }
                elseif ($r.unreachable) {
                    # couldn't measure (all of cloudflare/ip-api/ipinfo failed): NOT a kill by itself; debounced as 'unknown'
                    $exitUnreach++
                    $st = "EXIT UNREACHABLE x$exitUnreach (couldn't measure), retry in ${EXIT_RETRY_SEC}s"; $nextExit = (Get-Date).AddSeconds($EXIT_RETRY_SEC)
                    Update-SignalState $gd.exit 'unknown' (Get-Date) "exit unreachable x$exitUnreach (all egress APIs failed via proxy)"
                } elseif ($r.country -eq $COUNTRY_TARGET) {
                    $exitUnreach = 0; $st = "EXIT OK $($r.country) $($r.ip) via $($r.src)"; $nextExit = (Get-Date).AddSeconds($EXIT_EVERY_SEC)
                    Update-SignalState $gd.exit 'ok' (Get-Date)
                } else {
                    # measured and wrong: re-measure soon; kill only after consecutive wrong results
                    $exitUnreach = 0; $st = "EXIT WRONG COUNTRY $($r.country) $($r.ip) via $($r.src)"; $nextExit = (Get-Date).AddSeconds($EXIT_RETRY_SEC)
                    Update-SignalState $gd.exit 'bad' (Get-Date) $st
                }
                if ($st -ne $lastExit) { Write-Log $st; $lastExit = $st }
            }
        }
        # launch next exit check (only when local path is up)
        if ($ls.ok -and -not $exitH -and (Get-Date) -ge $nextExit) {
            $exitPS = [powershell]::Create().AddScript($EXIT_SCRIPT).AddArgument($ls.port).AddArgument($HTTP_TIMEOUT_SEC).AddArgument($ipapiUntil).AddArgument($ipinfoUntil)
            $exitH = $exitPS.BeginInvoke()
            $nextExit = (Get-Date).AddSeconds(3600)   # real schedule set when result arrives
        }

        $loc = Test-LocationSharingUnsafe
        $locSt = if ($loc.ok) { 'LOC OK' } else { "LOC UNSAFE: $($loc.reason)" }
        if ($locSt -ne $lastLoc) { Write-Log $locSt; $lastLoc = $locSt }
        Update-SignalState $gd.loc $(if ($loc.ok) { 'ok' } else { 'bad' }) (Get-Date) $loc.reason

        $dec = Get-GuardDecision $gd $DEBOUNCE (Get-Date)
        if ($dec.kill) { Stop-Claude $dec.reason }
        elseif ($dec.pending -ne $lastPending) {
            if ($dec.pending) { Write-Log "WAIT (debounce, no kill yet): $($dec.pending)" } elseif ($lastPending) { Write-Log 'WAIT cleared (recovered, nothing killed)' }
            $lastPending = $dec.pending
        }
        if ($dec.kill) { $lastPending = '' }

        $sleep = $LOOP_SEC - ((Get-Date) - $loopStart).TotalSeconds
        if ($sleep -gt 0.05) { Start-Sleep -Milliseconds ([int]($sleep * 1000)) }
    }
} finally {
    Write-Log "STOP bodyguard v3 pid=$PID"
    try { $mutex.ReleaseMutex() } catch {}
}