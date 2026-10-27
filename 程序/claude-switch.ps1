# Claude 账号切换器 - Windows 核心脚本
# 用法: powershell -NoProfile -File claude-switch.ps1 checkdetail|status|fix|switch A|B|version|checkupdate
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$script:AppVersion = '1.0.0'

# ============ 安装时可配置项(安装器自动改写) ============
$PROXY_MODE = "clash-verge"            # 代理客户端: clash-verge|sing-box|clashx|surge|wireguard|other|auto
$COUNTRY_TARGET = "US"                 # 默认; 会被 guard-settings.json 覆盖
$TZ_TARGET = "Pacific Standard Time"  # 默认; 可被 guard-settings.json 覆盖
$PROXY_GROUP = "Proxy"                # Clash 代理组名(规则置顶指向;全局模式下规则不生效,走 GLOBAL 所选节点)
$CLASH_MODE = "global"                 # 启动/修复时期望的 Clash 模式: rule|global|direct
# =======================================================

$BASE = Join-Path $env:USERPROFILE ".claude-switcher"

# 可打包配置: %USERPROFILE%\.claude-switcher\guard-settings.json
# 自动识别: { "auto": true }  — 首次检查时按当前出口写入 country（city 留空不用），然后 auto 变 false
# 手写示例: { "auto": false, "country":"US", "city":"Los Angeles", "timezone":"Pacific Standard Time", "node_match":"美国|USA|US", "ip_mode":"dynamic" }
function Get-GuardSettings {
    $f = Join-Path $BASE 'guard-settings.json'
    $d = @{
        auto        = $true
        country     = ''
        city        = ''
        timezone    = ''
        node_match  = ''
        ip_mode     = 'dynamic'
        browsers    = $null
        update_repo = ''
        update_url  = ''
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
        if ($j.update_repo) { $d.update_repo = [string]$j.update_repo }
        if ($j.update_url) { $d.update_url = [string]$j.update_url }
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
    if ($s.update_repo) { $obj.update_repo = [string]$s.update_repo }
    if ($s.update_url) { $obj.update_url = [string]$s.update_url }
    ($obj | ConvertTo-Json) | Out-File -Encoding utf8 $f
}

# 用当前出口自动填 country；city 始终留空（已不用）；时区保留本机或已有配置
function Update-GuardSettingsFromEgress($ip, $loc) {
    $s = Get-GuardSettings
    if (-not $s.auto) { return $s }
    if (-not $loc -and -not $ip) { return $s }
    try {
        if ($ip -and -not $loc) {
            $j = (& curl.exe -s --max-time 3 "https://ipinfo.io/$ip/json" 2>$null) | ConvertFrom-Json
            if (-not $loc -and $j.country) { $loc = [string]$j.country }
        }
    } catch {}
    if ($loc) { $s.country = $loc.ToUpper() }
    $s.city = ''   # city unused
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



$DATA = Join-Path $env:APPDATA "Claude"
$LOG  = Join-Path $BASE "claude-switch.log"
$CLASH_DIR = @(
    (Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev"),
    (Join-Path $env:LOCALAPPDATA "io.github.clash-verge-rev.clash-verge-rev")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $CLASH_DIR) { $CLASH_DIR = Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev" }
New-Item -ItemType Directory -Force -Path "$BASE\accounts" | Out-Null

function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File -Append -Encoding utf8 $LOG }

# 代理客户端显示名(供检查细节输出)
function Get-ProxyName {
    switch ($PROXY_MODE) {
        'clash-verge' { return 'Clash Verge' }
        'sing-box'    { return 'sing-box' }
        'clashx'      { return 'ClashX' }
        'surge'       { return 'Surge' }
        'wireguard'   { return 'WireGuard' }
        'other'       { return '其他代理客户端' }
        'auto'        { return '代理客户端(auto)' }
        default       { return $PROXY_MODE }
    }
}

# 代理客户端在线判定:按安装时识别的客户端分派;auto 任一命中即活,other 只依赖 TUN
function Test-ProxyAlive {
    switch ($PROXY_MODE) {
        'clash-verge' { return [bool](Get-Process -Name 'verge-mihomo' -ErrorAction SilentlyContinue) }
        'sing-box'    { return [bool](Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue) }
        'clashx'      { return [bool](Get-Process -Name 'ClashX' -ErrorAction SilentlyContinue) }
        'surge'       { return [bool](Get-Process -Name 'Surge' -ErrorAction SilentlyContinue) }
        'wireguard'   { return [bool](Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running') }
        'other'       { return $true }
        'auto' {
            if (Get-Process -Name 'verge-mihomo','sing-box','ClashX','Surge' -ErrorAction SilentlyContinue) { return $true }
            return [bool](Get-Service -Name 'WireGuardTunnel*' -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running')
        }
        default { return [bool](Get-Process -Name 'verge-mihomo' -ErrorAction SilentlyContinue) }
    }
}

# TUN 在线判定:198.18 假IP段优先,否则回退到任意 Up 状态的虚拟网卡(兼容 Astrill/WireGuard/OpenVPN 等)
function Get-TunStatus {
    # 必须看到真网卡或 198.18，不能只看 verge 开关（否则 DNS/UDP 假绿）
    if (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '198.18.*' }) {
        return @{ up = $true; detail = '198.18 假IP段' }
    }
    $nic = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and (
            $_.InterfaceDescription -match 'TAP|TUN|WireGuard|Wintun|Meta|Clash|mihomo|vergetun|sing-box|Mihomo' -or
            $_.Name -match 'Meta|Clash|mihomo|TUN|Wintun|Mihomo'
        )
    }
    if ($nic) {
        $n = ($nic | Select-Object -First 1).Name
        return @{ up = $true; detail = "虚拟网卡 $n" }
    }
    $flagOn = $false
    try {
        $verge = Join-Path $CLASH_DIR 'verge.yaml'
        if ((Test-Path $verge) -and (Select-String -LiteralPath $verge -Pattern '(?m)^\s*enable_tun_mode:\s*true\s*$' -Quiet)) {
            $flagOn = $true
        }
    } catch {}
    if ($flagOn) {
        return @{ up = $false; detail = '不安全·Clash写着开TUN但本机无虚拟网卡' }
    }
    return @{ up = $false; detail = '虚拟网卡未开' }
}

function Get-Egress {
    $trace = & curl.exe -s --max-time 4 "https://www.cloudflare.com/cdn-cgi/trace" 2>$null
    $ip  = (($trace -split "`n" | Where-Object { $_ -like 'ip=*' })  -replace 'ip=','').Trim()
    $loc = (($trace -split "`n" | Where-Object { $_ -like 'loc=*' }) -replace 'loc=','').Trim()
    return @{ ip = $ip; loc = $loc }
}

# STUN 探针(纯 .NET UDP,手工构造 RFC5389 报文)
function Get-StunPublicIP([string]$server, [int]$port, [int]$timeoutMs = 2000) {
    try { $addr = ([System.Net.Dns]::GetHostAddresses($server) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1) } catch { return $null }
    if (-not $addr) { return $null }
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = $timeoutMs
    try {
        $txn = New-Object byte[] 12; (New-Object Random).NextBytes($txn)
        $req = [byte[]](0x00, 0x01, 0x00, 0x00) + [byte[]](0x21, 0x12, 0xA4, 0x42) + $txn
        $udp.Connect($addr, $port)
        [void]$udp.Send($req, $req.Length)
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udp.Receive([ref]$remote)
        $pos = 20
        while ($pos + 4 -le $resp.Length) {
            $atype = ([int]$resp[$pos] -shl 8) -bor $resp[$pos + 1]
            $alen  = ([int]$resp[$pos + 2] -shl 8) -bor $resp[$pos + 3]
            if (($atype -eq 0x20 -or $atype -eq 0x01) -and $alen -ge 8 -and $resp[$pos + 5] -eq 0x01) {
                $ipBytes = @($resp[$pos + 8], $resp[$pos + 9], $resp[$pos + 10], $resp[$pos + 11])
                if ($atype -eq 0x20) {
                    $cookie = [byte[]](0x21, 0x12, 0xA4, 0x42)
                    for ($i = 0; $i -lt 4; $i++) { $ipBytes[$i] = $ipBytes[$i] -bxor $cookie[$i] }
                }
                return ($ipBytes -join '.')
            }
            $pos += 4 + $alen + ((4 - ($alen % 4)) % 4)
        }
    } catch { return $null } finally { $udp.Close() }
    return $null
}

function Test-WebRTC($exitIp) {
    # 快检:每个 STUN 最多 800ms,凑到 2 个不同 IP 或试完前 2 台就停
    $servers = @(@("stun.l.google.com", 19302), @("stun.cloudflare.com", 3478), @("stun.miwifi.com", 3478))
    $found = @()
    foreach ($s in $servers) {
        $r = Get-StunPublicIP $s[0] $s[1] 800
        if ($r -and ($found -notcontains $r)) { $found += $r }
        if ($found.Count -ge 2) { break }
    }
    if ($found.Count -eq 0) { return @{ code = 'ok'; detail = 'UDP不出网,零暴露' } }
    $leak = $found | Where-Object { $_ -ne $exitIp }
    if ($leak) { return @{ code = 'fail'; detail = "暴露非代理IP: $($leak -join ',')" } }
    return @{ code = 'ok'; detail = '仅暴露代理IP' }
}

function Test-RulesPinned { (Test-Path "$CLASH_DIR\clash-verge.yaml") -and (Select-String -Path "$CLASH_DIR\clash-verge.yaml" -Pattern "DOMAIN-SUFFIX,claude.ai,$PROXY_GROUP" -Quiet) -and (Select-String -Path "$CLASH_DIR\clash-verge.yaml" -Pattern "DST-PORT,3478," -Quiet) }


function Get-ClashMode {
    foreach ($p in @("$CLASH_DIR\config.yaml", "$CLASH_DIR\clash-verge.yaml")) {
        if (-not (Test-Path $p)) { continue }
        $m = Select-String -Path $p -Pattern '(?m)^mode:\s*(\S+)' | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value.Trim().Trim("'").Trim('"').ToLower() }
    }
    return ''
}


# ---------- 版本 / 检查更新 ----------
function Get-UpdateRepo {
    $s = Get-GuardSettings
    if ($s.update_url) {
        return @{ kind = 'url'; url = [string]$s.update_url; repo = '' }
    }
    $repo = if ($s.update_repo) { [string]$s.update_repo } else { 'mfksffitx-xi2/ClaudeGuard' }
    return @{ kind = 'repo'; url = ''; repo = $repo }
}

function Compare-AppVersion([string]$a, [string]$b) {
    $na = ($a -replace '^v','').Trim()
    $nb = ($b -replace '^v','').Trim()
    try {
        $va = [version]$na; $vb = [version]$nb
        if ($va -lt $vb) { return -1 }
        if ($va -gt $vb) { return 1 }
        return 0
    } catch {
        if ($na -eq $nb) { return 0 }
        if ($na -lt $nb) { return -1 }
        return 1
    }
}

function Invoke-CheckUpdate {
    $u = Get-UpdateRepo
    if ($u.kind -eq 'url') {
        try { Start-Process $u.url } catch {}
        return "UPDATE:已打开更新页"
    }
    $repo = $u.repo
    $api = "https://api.github.com/repos/$repo/releases/latest"
    $page = "https://github.com/$repo/releases"
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $api -Headers @{ 'User-Agent' = 'ClaudeGuard' } -TimeoutSec 12
        $j = $resp.Content | ConvertFrom-Json
        $tag = [string]$j.tag_name
        if (-not $tag) { return "UPDATE:还没有发布版" }
        $cmp = Compare-AppVersion $script:AppVersion $tag
        if ($cmp -lt 0) {
            $url = if ($j.html_url) { [string]$j.html_url } else { $page }
            try { Start-Process $url } catch { try { Start-Process $page } catch {} }
            return "UPDATE:有新版本 $tag（本机 $($script:AppVersion)），已打开下载页"
        }
        return "UPDATE:已是最新（$($script:AppVersion)）"
    } catch {
        $code = $null
        try { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } } catch {}
        if ($code -eq 404) { return "UPDATE:还没有发布版" }
        # 网络失败时仍给发布页入口
        try { Start-Process $page } catch {}
        return "UPDATE:还没有发布版（或暂时连不上 GitHub）"
    }
}

# ---------- 共享定位：系统 + 勾选浏览器 ----------
function Get-LocationSharingStatus {
    $bad = @()
    $parts = @()
    # 用户 ConsentStore
    $hkcu = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    $sysVal = ''
    try {
        if (Test-Path $hkcu) {
            $sysVal = [string](Get-ItemProperty -Path $hkcu -Name 'Value' -ErrorAction SilentlyContinue).Value
        }
    } catch {}
    if (-not $sysVal) { $sysVal = '(未写)' }
    $parts += "系统定位=$sysVal"
    if ($sysVal -eq 'Allow' -or $sysVal -eq 'Prompt') {
        $bad += '不安全·系统定位开着'
    }
    # 位置服务（能读就读，读不到不算红）
    try {
        $svc = Get-Service -Name 'lfsvc' -ErrorAction SilentlyContinue
        if ($svc) {
            $parts += ("位置服务=" + $svc.Status)
            if ($svc.Status -eq 'Running' -and ($sysVal -eq 'Allow' -or $sysVal -eq 'Prompt' -or $sysVal -eq '(未写)')) {
                # 服务在跑且用户未明确 Deny → 视为可共享
                if ($sysVal -ne 'Deny' -and ($bad -notcontains '不安全·系统定位开着')) {
                    $bad += '不安全·系统定位开着'
                }
            }
        }
    } catch {}

    $sel = @(Get-SelectedBrowsers)
    if ($sel.Count -eq 0) {
        $parts += '浏览器=没勾选'
    } else {
        foreach ($k in $sel) {
            $b = Get-BrowserInfo $k
            $geo = $null
            try {
                foreach ($pp in @(($b.policy -replace '^HKCU:', 'HKLM:'), $b.policy)) {
                    if ($null -eq $geo -and (Test-Path $pp)) {
                        $geo = (Get-ItemProperty -Path $pp -Name 'DefaultGeolocationSetting' -ErrorAction SilentlyContinue).DefaultGeolocationSetting
                    }
                }
            } catch {}
            $geoTxt = if ($null -eq $geo) { '未拦' } elseif ([int]$geo -eq 2) { '已拦' } elseif ([int]$geo -eq 1) { '允许' } else { "值$geo" }
            $parts += "$($b.name)定位=$geoTxt"
            if ($null -eq $geo -or [int]$geo -ne 2) {
                $bad += ("不安全·" + $b.name + " 允许定位")
            }
        }
    }

    if ($bad.Count -gt 0) {
        return @{ ok = $false; code = 'fail'; detail = ($bad -join '；') }
    }
    return @{ ok = $true; code = 'ok'; detail = ('已关（' + ($parts -join '，') + '）') }
}

function Disable-LocationSharing {
    "FIX:将关闭系统与浏览器定位（地图等应用会受影响）"
    # 系统用户 ConsentStore → Deny
    $hkcu = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    try {
        if (-not (Test-Path $hkcu)) { New-Item -Path $hkcu -Force | Out-Null }
        New-ItemProperty -Path $hkcu -Name 'Value' -Value 'Deny' -PropertyType String -Force | Out-Null
        "FIX:系统定位已关掉（用户层）"
    } catch {
        "FIX:系统定位没写上，请到 设置 → 隐私和安全性 → 位置 里关掉"
    }
    # 勾选浏览器：DefaultGeolocationSetting = 2（禁止网站要位置）
    $sel = @(Get-SelectedBrowsers)
    if ($sel.Count -eq 0) {
        "FIX:没勾选浏览器，浏览器定位跳过"
    } else {
        foreach ($k in $sel) {
            $b = Get-BrowserInfo $k
            try {
                if (-not (Test-Path $b.policy)) { New-Item -Path $b.policy -Force | Out-Null }
                New-ItemProperty -Path $b.policy -Name 'DefaultGeolocationSetting' -Value 2 -PropertyType DWord -Force | Out-Null
                "FIX:$($b.name) 已禁止网站请求定位（请退出再开一次浏览器才稳）"
            } catch {
                "FIX:$($b.name) 定位策略没写上"
            }
        }
    }
    # 尝试停位置服务（可能要管理员；失败只提示）
    try {
        $svc = Get-Service -Name 'lfsvc' -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            try {
                Stop-Service -Name 'lfsvc' -Force -ErrorAction Stop
                "FIX:位置服务已停"
            } catch {
                "FIX:位置服务还在跑（可能要管理员）。可到 设置 → 隐私和安全性 → 位置 关掉「位置服务」"
            }
        }
    } catch {}
}

function Invoke-CheckDetail {
    $__rt = Resolve-GuardTargets
    $COUNTRY_TARGET = $__rt.country
    $TZ_TARGET = $__rt.timezone
    $IP_MODE = $__rt.ip_mode
    $CITY_TARGET = $__rt.city
    if (Test-ProxyAlive) {
        if ($PROXY_MODE -eq 'other') { "代理软件=ok:$pname 已开（只看虚拟网卡）" }
        else { "代理软件=ok:$pname 运行中" }
    } else { "代理软件=fail:$pname 没开，请先启动" }

    $tun = Get-TunStatus
    if ($tun.up) {
        if ($tun.detail -eq '198.18 假IP段') { "虚拟网卡=ok:虚拟网卡已开" }
        else { "虚拟网卡=ok:虚拟网卡已开($($tun.detail))" }
    } else { "虚拟网卡=fail:$($tun.detail)" }

    $cm = Get-ClashMode
    if ($cm -eq $CLASH_MODE) { "全局模式=ok:已开全局" }
    elseif ($cm -eq 'rule') { "全局模式=fail:现在是「规则」，请改成「全局」" }
    elseif ($cm -eq 'direct') { "全局模式=fail:现在是「直连」，请改成「全局」" }
    elseif ($cm) { "全局模式=fail:当前不是全局，请在 Clash 选「全局」" }
    else { "全局模式=fail:读不到模式，请打开 Clash 看一下" }

    $e = Get-Egress
    if ((Get-GuardSettings).auto) {
        $null = Update-GuardSettingsFromEgress $e.ip $e.loc
        $__rt = Resolve-GuardTargets
        $COUNTRY_TARGET = $__rt.country
        $TZ_TARGET = $__rt.timezone
        $IP_MODE = $__rt.ip_mode
        $CITY_TARGET = $__rt.city
    }
    # city unused — country only
    if ($e.loc -eq $COUNTRY_TARGET) { "出口地区=ok:已在目标地区 $($e.ip)" } else { "出口地区=fail:现在像在 $($e.loc)，需要到 $COUNTRY_TARGET（现地址 $($e.ip)）" }

    $lastipFile = "$BASE\lastip.txt"
    $lastip = if (Test-Path $lastipFile) { (Get-Content $lastipFile -Raw).Trim() } else { '' }
    if (-not $e.ip) { "出口变动=fail:还没查到出口地址" }
    elseif (-not $lastip) { "出口变动=ok:第一次记录，没问题" }
    elseif ($e.ip -eq $lastip) { "出口变动=ok:和上次一样" }
    elseif ($IP_MODE -eq 'dynamic') { "出口变动=ok:地址有变化，属正常" }
    else { "出口变动=warn:出口地址变了" }
    if ($e.ip) { $e.ip | Out-File -Encoding ascii -NoNewline $lastipFile }

    $tz = (Get-TimeZone).Id
    if ($tz -eq $TZ_TARGET) { "时区=ok:$tz" } else { "时区=fail:现在是 $tz，要 $TZ_TARGET" }

    $cult = (Get-Culture).Name
    if ($cult -eq 'en-US') { "地区=ok:$cult" } else { "地区=fail:现在是 $cult，要 en-US" }

    $v6off = [bool](Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true })
    if (-not $v6off) { "IPv6=ok:已关闭" } else { "IPv6=fail:未关闭" }

    $dns = (Resolve-DnsName claude.ai -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    $dnsServer = ''
    try {
        $dnsServer = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses | Select-Object -First 1
    } catch {}
    $svr = if ($dnsServer) { $dnsServer } else { '未知DNS' }
    if ($dns -like '198.18.*') {
        "DNS=ok:已走代理隧道（假IP $dns）"
    } elseif ($dns) {
        # 未进 Clash 假 IP = 不安全，必须红，不许改黄糊弄
        "DNS=fail:不安全·DNS未进代理隧道（解析到 $dns，DNS服务器 $svr）"
    } else {
        "DNS=fail:不安全·DNS解析失败"
    }

    $w = Test-WebRTC $e.ip
    "WebRTC=$($w.code):$($w.detail)"

    Get-BrowserCheckLine

    $loc = Get-LocationSharingStatus
    "共享定位=$($loc.code):$($loc.detail)"

    # 保镖随切换器窗口开关:窗口开着=保镖进程在跑;不在跑只报 warn,不拦任何操作
    $bgp = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'claude-bodyguard\.ps1' -and $_.CommandLine -notmatch 'TestOnce' }
    if ($bgp -and (Test-Path "$BASE\bodyguard-off.flag")) { "保镖=warn:已暂停" }
    elseif ($bgp) { "保镖=ok:运行中" } else { "保镖=warn:未运行(随切换器窗口开启)" }

    if ($CLASH_MODE -eq 'global' -and (Get-ClashMode) -eq 'global') {
        if (Test-RulesPinned) { "规则置顶=ok:已置顶（开了全局时可忽略这项）" } else { "规则置顶=warn:未置顶（开了全局时可忽略）" }
    } elseif (Test-RulesPinned) { "规则置顶=ok:已置顶" } else { "规则置顶=fail:还没置顶，一键修复可处理" }

    # 客户端语言: Windows 端 Claude 跟随系统区域格式,地区检查已覆盖
    "客户端语言=ok:跟随系统"

    # 机房/住宅判定规则保留；界面只显示短词，不跟 AS 号、运营商英文名
    $org = ''
    try { $org = ((& curl.exe -s --max-time 3 "https://ipinfo.io/json" 2>$null) | ConvertFrom-Json).org } catch {}
    if (-not $org) { try { $j = ((& curl.exe -s --max-time 3 "http://ip-api.com/json/?fields=as,isp,org,hosting" 2>$null) | ConvertFrom-Json); $org = (($j.as, $j.isp, $j.org) -join ' ').Trim(); if ($j.hosting) { $org += ' hosting' } } catch {} }
    if (-not $org) { "线路类型=warn:查不到" }
    elseif ($org -match 'Comcast|AT&T|Verizon|Spectrum|Charter|Cox|T-Mobile|Cable|esidential|Residential|Home|宽带|电信|联通|移动家庭') { "线路类型=ok:住宅" }
    elseif ($org -match 'hosting|datacenter|Data Center|云|Cloud|VPS|IDC|Colo|机房') { "线路类型=warn:机房" }
    else { "线路类型=warn:机房" }

    $tmp1 = [IO.Path]::GetTempFileName(); $tmp2 = [IO.Path]::GetTempFileName()
    $p1 = Start-Process -FilePath curl.exe -ArgumentList @('-s','--max-time','4','-o','NUL','-w','%{http_code}','https://claude.ai/') -PassThru -NoNewWindow -RedirectStandardOutput $tmp1
    $p2 = Start-Process -FilePath curl.exe -ArgumentList @('-s','--max-time','4','-o','NUL','-w','%{http_code}','https://api.anthropic.com/v1/models') -PassThru -NoNewWindow -RedirectStandardOutput $tmp2
    $null = $p1.WaitForExit(5000); $null = $p2.WaitForExit(5000)
    $r1 = ((Get-Content $tmp1 -Raw -ErrorAction SilentlyContinue) + '').Trim(); if (-not $r1) { $r1 = '000' }
    $r2 = ((Get-Content $tmp2 -Raw -ErrorAction SilentlyContinue) + '').Trim(); if (-not $r2) { $r2 = '000' }
    Remove-Item $tmp1, $tmp2 -Force -ErrorAction SilentlyContinue
    if ($r1 -ne '000' -and $r2 -ne '000') { "Claude连通=ok:Claude 网站能连上" } else { "Claude连通=fail:Claude 网站连不上，先修好代理/全局/出口" }
}


function Set-YamlKey($path, $key, $value) {
    if (-not (Test-Path $path)) { return $false }
    $raw = Get-Content $path -Raw -Encoding utf8
    $pat = "(?m)^($key):\s*\S+"
    if ($raw -match $pat) {
        $new = [regex]::Replace($raw, $pat, "$key`: $value", 1)
        if ($new -eq $raw) { return $false }
        Copy-Item $path ($path + '.bak-guard-' + (Get-Date -Format 'yyyyMMddHHmmss')) -Force -ErrorAction SilentlyContinue
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($path, $new, $utf8)
        return $true
    }
    return $false
}

function Find-ClashVergeExe {
    # 先找常见安装位置，再看各个本地盘根目录下的「Clash Verge」文件夹
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Clash Verge\clash-verge.exe'),
        (Join-Path $env:ProgramFiles 'Clash Verge\clash-verge.exe')
    )
    foreach ($dr in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) { $cands += (Join-Path $dr.Root 'Clash Verge\clash-verge.exe') }
    foreach ($p in $cands) { if (Test-Path $p) { return $p } }
    foreach ($root in @("$env:LOCALAPPDATA\Programs")) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Include 'clash-verge.exe','Clash Verge.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Restart-ClashVerge {
    # 服务/内核常以 SYSTEM 跑，Stop-Process 杀不掉；优先重启服务，再拉 GUI
    $svcNames = @('clash-verge-service','Clash Verge Service','clash_verge_service')
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $svcNames -contains $_.Name -or $_.DisplayName -match 'Clash Verge' } | Select-Object -First 1
    if ($svc) {
        try { Restart-Service -Name $svc.Name -Force -ErrorAction Stop; "FIX:已重启服务 $($svc.Name)" | Out-Null } catch {
            try { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Start-Service -Name $svc.Name -ErrorAction SilentlyContinue } catch {}
        }
    }
    Get-Process -Name 'clash-verge','Clash Verge' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    # 再尝试结束内核（若仍残留）
    Get-Process -Name 'verge-mihomo','clash-meta','mihomo' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    $exe = Find-ClashVergeExe
    if ($exe) { Start-Process $exe; return $true }
    return $false
}


# ---------- 浏览器（Edge / Chrome）：按 guard-settings.json 的 browsers 勾选 ----------
$EXT_DIR_NAME = 'yingwen-quyu-ziti'
$EXT_EDGE_ID = 'helhndlfkiioglmnmjoodifemapocnfo'

function Get-BrowserInfo([string]$key) {
    switch ($key) {
        'edge'   { return @{ key = 'edge';   name = 'Edge';   udd = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data');  proc = 'msedge'; page = 'edge://extensions';   policy = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge' } }
        'chrome' { return @{ key = 'chrome'; name = 'Chrome'; udd = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'); proc = 'chrome'; page = 'chrome://extensions'; policy = 'HKCU:\SOFTWARE\Policies\Google\Chrome' } }
    }
    return $null
}

function Get-InstalledBrowsers {
    @('edge','chrome') | Where-Object { Test-Path (Get-BrowserInfo $_).udd }
}

# 没写 browsers 时 = 本机装了的都算；写了就只认勾选的
function Get-SelectedBrowsers {
    $s = Get-GuardSettings
    $list = if ($null -ne $s.browsers) { @($s.browsers) } else { @(Get-InstalledBrowsers) }
    return @($list | ForEach-Object { ([string]$_).ToLower() } | Where-Object { $_ -in @('edge','chrome') } | Select-Object -Unique)
}

function Read-JsonFileSafe([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Get-BrowserLangState($b) {
    $r = @{ installed = (Test-Path $b.udd); langs = ''; enFirst = $false; zhFirst = $false; ext = 'missing'; extPath = '' }
    if (-not $r.installed) { return $r }
    $prof = Join-Path $b.udd 'Default'
    $p  = Read-JsonFileSafe (Join-Path $prof 'Preferences')
    $sp = Read-JsonFileSafe (Join-Path $prof 'Secure Preferences')
    $ls = Read-JsonFileSafe (Join-Path $b.udd 'Local State')
    $langs = ''
    if ($p -and $p.intl) {
        if ($p.intl.accept_languages) { $langs = [string]$p.intl.accept_languages }
        elseif ($p.intl.selected_languages) { $langs = [string]$p.intl.selected_languages }
    }
    if (-not $langs -and $ls -and $ls.intl -and $ls.intl.app_locale) { $langs = [string]$ls.intl.app_locale }
    if (-not $langs) { $langs = (Get-UICulture).Name }
    $r.langs = $langs
    $first = (($langs -split ',')[0]).Trim()
    $r.enFirst = ($first -match '^en(-|$)')
    $r.zhFirst = ($first -match '^zh(-|$)')

    # 插件：Preferences / Secure Preferences 里的 extensions.settings，按文件夹名、插件名或 Edge 固定 ID 认
    $found = $false; $disabled = $false
    foreach ($src in @($p, $sp)) {
        if (-not $src -or -not $src.extensions -or -not $src.extensions.settings) { continue }
        foreach ($prop in $src.extensions.settings.PSObject.Properties) {
            $v = $prop.Value
            $path = [string]$v.path
            $isOurs = $false
            if ($prop.Name -eq $EXT_EDGE_ID) { $isOurs = $true }
            if ($path -and ((Split-Path $path -Leaf) -like "$EXT_DIR_NAME*")) { $isOurs = $true }
            if ($v.manifest -and ([string]$v.manifest.name) -like '*英文区域*') { $isOurs = $true }
            if (-not $isOurs -and $path -and [IO.Path]::IsPathRooted($path)) {
                $m = Read-JsonFileSafe (Join-Path $path 'manifest.json')
                if ($m -and ([string]$m.name) -like '*英文区域*') { $isOurs = $true }
            }
            if (-not $isOurs) { continue }
            if ($path -and [IO.Path]::IsPathRooted($path) -and -not (Test-Path -LiteralPath (Join-Path $path 'manifest.json'))) { continue }
            $found = $true
            if ($path) { $r.extPath = $path }
            if ($null -ne $v.state -and [int]$v.state -eq 0) { $disabled = $true }
            $dr = $v.disable_reasons
            if ($null -ne $dr) {
                $drs = @($dr | Where-Object { $null -ne $_ -and "$_" -ne '0' -and "$_" -ne '' })
                if ($drs.Count -gt 0) { $disabled = $true }
            }
        }
    }
    if ($found) { $r.ext = $(if ($disabled) { 'disabled' } else { 'on' }) }
    return $r
}

function Get-BrowserCheckLine {
    $sel = @(Get-SelectedBrowsers)
    if ($sel.Count -eq 0) { return "浏览器语言=warn:没勾选要检查的浏览器" }
    $parts = @(); $bad = @()
    foreach ($k in $sel) {
        $b = Get-BrowserInfo $k
        $st = Get-BrowserLangState $b
        if (-not $st.installed) { $bad += "不安全·没找到 $($b.name)"; continue }
        if ($st.zhFirst) { $bad += "不安全·$($b.name) 首选语言是中文" }
        elseif (-not $st.enFirst) { $bad += "不安全·$($b.name) 首选语言不是英文（$($st.langs)）" }
        if ($st.ext -eq 'missing') { $bad += "不安全·$($b.name) 没装英文区域插件" }
        elseif ($st.ext -eq 'disabled') { $bad += "不安全·$($b.name) 没开英文区域插件" }
        $extTxt = switch ($st.ext) { 'on' { '插件已开' } 'disabled' { '插件没开' } default { '插件没装' } }
        $parts += "$($b.name)：$($st.langs)，$extTxt"
    }
    if ($bad.Count -gt 0) { return ("浏览器语言=fail:" + ($bad -join '；')) }
    return ("浏览器语言=ok:通过（" + ($parts -join '；') + "）")
}

# 只改网页用的首选语言（intl.accept_languages / selected_languages），不碰浏览器界面语言
function Set-BrowserAcceptLanguage($b) {
    $pf = Join-Path $b.udd 'Default\Preferences'
    if (-not (Test-Path -LiteralPath $pf)) { return @{ ok = $false; detail = "$($b.name) 还没生成配置文件，先打开一次再关掉" } }
    $raw = [IO.File]::ReadAllText($pf, [Text.Encoding]::UTF8)
    $val = 'en-US,en'
    $new = $raw
    if ($new -match '"intl"\s*:\s*\{') {
        foreach ($key in @('accept_languages','selected_languages')) {
            $pat = '"' + $key + '"\s*:\s*"[^"]*"'
            if ($new -match $pat) { $new = [regex]::Replace($new, $pat, ('"' + $key + '":"' + $val + '"')) }
            else { $new = [regex]::Replace($new, '"intl"\s*:\s*\{', ('"intl":{"' + $key + '":"' + $val + '",'), 1) }
        }
        $new = $new -replace '("(?:accept|selected)_languages":"en-US,en"),\}', '$1}'
    } else {
        $new = [regex]::Replace($new, '^\s*\{', ('{"intl":{"accept_languages":"' + $val + '","selected_languages":"' + $val + '"},'), 1)
    }
    try { $null = $new | ConvertFrom-Json } catch { return @{ ok = $false; detail = "$($b.name) 配置文件改完校验不过，没写入" } }
    $bak = $pf + '.bak-guard-' + (Get-Date -Format 'yyyyMMddHHmmss')
    Copy-Item -LiteralPath $pf $bak -Force -ErrorAction SilentlyContinue
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($pf, $new, $utf8)
    return @{ ok = $true; detail = "$($b.name) 网页首选语言已改成 en-US,en（已备份原配置）" }
}

function Invoke-BrowserFix {
    $sel = @(Get-SelectedBrowsers)
    if ($sel.Count -eq 0) { "FIX:没勾选浏览器，浏览器这块跳过"; return }
    foreach ($k in $sel) {
        $b = Get-BrowserInfo $k
        if (-not (Test-Path $b.udd)) { "FIX:没找到 $($b.name)，跳过"; continue }
        $st = Get-BrowserLangState $b
        if ($st.enFirst) { "FIX:$($b.name) 网页首选语言已是英文（$($st.langs)），不用改" }
        elseif (Get-Process -Name $b.proc -ErrorAction SilentlyContinue) { "FIX:请先关掉 $($b.name) 再点一键修复（要把网页语言改成英文）" }
        else {
            $res = Set-BrowserAcceptLanguage $b
            "FIX:$($res.detail)"
        }
        if ($st.ext -ne 'on') {
            $extDir = Join-Path $BASE "extension\$EXT_DIR_NAME"
            $what = if ($st.ext -eq 'disabled') { '装了但没开' } else { '还没装' }
            "FIX:$($b.name) 的英文区域插件$what：在 $($b.name) 地址栏打开 $($b.page) → 打开「开发人员模式」→「加载解压缩的扩展」→ 选 $extDir"
        }
    }
}

function Set-BrowserWebRtcHardening([string[]]$keys = @('edge','chrome')) {
    # 不需管理员：给勾选的浏览器写用户策略，禁止非代理 UDP 暴露真 IP
    $policyVal = 'disable_non_proxied_udp'
    $paths = @($keys | ForEach-Object { (Get-BrowserInfo $_).policy } | Where-Object { $_ })
    $ok = @()
    foreach ($path in $paths) {
        try {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            New-ItemProperty -Path $path -Name 'WebRtcIPHandling' -Value $policyVal -PropertyType String -Force | Out-Null
            # 禁止把本地局域网 IP 塞进候选
            New-ItemProperty -Path $path -Name 'WebRtcLocalIpsAllowedUrls' -Value @() -PropertyType MultiString -Force -ErrorAction SilentlyContinue | Out-Null
            $ok += ($path -split '\\')[-1]
        } catch {}
    }
    return $ok
}

function Ensure-StunFirewallBlock {
    # 需管理员：拦常见 STUN 出站 UDP，避免家宽 IP 被捅出
    $name = 'ClaudeGuard-Block-STUN-UDP'
    $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -DisplayName $name -Enabled True -Action Block -ErrorAction SilentlyContinue
    } else {
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -Protocol UDP -RemotePort 3478,19302,19305 -Profile Any -ErrorAction SilentlyContinue | Out-Null
    }
}



function Ensure-ClashTunReal {
    # 旧版靠写 enable_tun_mode + 重启服务；这里同样，但以「出现虚拟网卡」为准
    $st = Get-TunStatus
    if ($st.up) { return @{ ok = $true; detail = $st.detail } }
    $verge = Join-Path $CLASH_DIR 'verge.yaml'
    if (Test-Path $verge) {
        $raw = Get-Content $verge -Raw -Encoding UTF8
        if ($raw -match '(?m)^enable_tun_mode:\s*false\s*$') {
            Copy-Item $verge ($verge + '.bak-tun-' + (Get-Date -Format 'yyyyMMddHHmmss')) -Force
            $raw2 = [regex]::Replace($raw, '(?m)^enable_tun_mode:\s*false\s*$', 'enable_tun_mode: true', 1)
            $utf8 = New-Object System.Text.UTF8Encoding $false
            [IO.File]::WriteAllText($verge, $raw2, $utf8)
        }
    }
    "FIX:正在重启 Clash 服务以拉起真虚拟网卡…"
    $okRestart = $false
    try { $okRestart = [bool](Restart-ClashVerge) } catch {}
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep 1
        $st = Get-TunStatus
        if ($st.up) { return @{ ok = $true; detail = $st.detail; restarted = $okRestart } }
    }
    return @{ ok = $false; detail = '重启后仍无 Mihomo/Wintun 网卡。请在 Clash 关掉再打开「虚拟网卡」（弹管理员就允许）'; restarted = $okRestart }
}

function Enable-ClashDnsFakeIp {
    # 对齐旧版思路：改配置后必须让 Clash 重载/重启才生效；旧版从未真正开 DNS，只清过缓存
    $dir = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
    $verge = Join-Path $dir 'verge.yaml'
    if (-not (Test-Path $verge)) { return @{ ok = $false; detail = '找不到 verge.yaml' } }
    $bak = Join-Path $dir ("verge.yaml.bak-dns-" + (Get-Date -Format 'yyyyMMddHHmmss'))
    Copy-Item -LiteralPath $verge -Destination $bak -Force
    $lines = Get-Content -LiteralPath $verge -Encoding UTF8
    $out = New-Object System.Collections.Generic.List[string]
    $inProfileDns = $false
    $changed = $false
    foreach ($line in $lines) {
        if ($line -match '^enable_dns_settings:\s*false\s*$') {
            $out.Add('enable_dns_settings: true'); $changed = $true; continue
        }
        if ($line -match '^profile_dns_settings:\s*$') { $inProfileDns = $true; $out.Add($line); continue }
        if ($inProfileDns) {
            if ($line -match '^\S') { $inProfileDns = $false }
            elseif ($line -match '^(\s+)enabled:\s*false\s*$') {
                $out.Add(($Matches[1] + 'enabled: true')); $changed = $true; continue
            }
        }
        $out.Add($line)
    }
    if ($changed) { Set-Content -LiteralPath $verge -Value $out -Encoding UTF8 }

    # 确保 dns_config 是 fake-ip（旧配置已有则不动）
    $dnsCfg = Join-Path $dir 'dns_config.yaml'
    if (Test-Path $dnsCfg) {
        $d = Get-Content $dnsCfg -Raw -Encoding UTF8
        if ($d -notmatch 'enhanced-mode:\s*fake-ip') {
            Copy-Item $dnsCfg ($dnsCfg + '.bak-guard') -Force -ErrorAction SilentlyContinue
        }
    }

    $tryResolve = {
        try { (Resolve-DnsName claude.ai -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress } catch { $null }
    }
    $dns = & $tryResolve
    if ($dns -like '198.18.*') {
        return @{ ok = $true; detail = "DNS已进代理隧道（$dns）"; bak = $bak }
    }

    # 同旧版：写完配置要重启 Clash，否则 DNS 假 IP 不进内核
    "FIX:DNS 开关已开，正在重启 Clash 让假 IP 生效（旧版修 TUN/全局也是这一步）…"
    $restarted = $false
    try { $restarted = [bool](Restart-ClashVerge) } catch { $restarted = $false }
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep 1
        if (-not (Test-ProxyAlive)) { continue }
        $dns = & $tryResolve
        if ($dns -like '198.18.*') {
            return @{ ok = $true; detail = "重启后DNS已进代理隧道（$dns）"; bak = $bak; restarted = $restarted }
        }
    }
    $dns = & $tryResolve
    return @{ ok = $false; detail = "重启后仍是 $dns（未进 198.18 假IP）。可在 Clash 设置确认「DNS 设置」开着，再开关一次虚拟网卡"; bak = $bak; restarted = $restarted }
}

function Invoke-ClashModeAndTunFix {
    # 不再写 yaml、不再强杀重启 Clash（会卡顿且经常改不生效）
    "FIX:请你在 Clash Verge 首页自己点这几下："
    "FIX:  1) 打开「虚拟网卡」（TUN）— WebRTC 的 UDP 也靠它拦"
    "FIX:  2) 代理模式点「全局」（不要留在「规则」）"
    "FIX:  3) 当前节点换成目标国家的（比如名字带「美国」或 🇺🇸 的）"
    "FIX:点完回到 Claude守护 再点「重新检查」"
}

function Invoke-Fix {
    $__rt = Resolve-GuardTargets
    $COUNTRY_TARGET = $__rt.country
    $TZ_TARGET = if ($__rt.timezone) { $__rt.timezone } else { 'Pacific Standard Time' }
    "FIX:开始修复（按本机实情改时区/地区；Clash 开关仍请手点）"

    if ($PROXY_MODE -eq 'clash-verge') {
        if (-not (Test-ProxyAlive)) {
            "FIX:Clash 没开，正在打开…"
            $cv = $(if ($__e = Find-ClashVergeExe) { Get-Item -LiteralPath $__e })
            if ($cv) { Start-Process $cv.FullName } else { "FIX:找不到 Clash Verge" }
        } else { "FIX:Clash 已在运行" }
    }

    # 真正改本机：时区 / 关 IPv6 / 清 DNS（弹一次管理员）
    $adminScript = @()
    $curTz = (Get-TimeZone).Id
    if ($curTz -ne $TZ_TARGET) {
        $adminScript += "Set-TimeZone -Id '$TZ_TARGET'"
        "FIX:本机时区现在是 $curTz，将改成 $TZ_TARGET"
    } else {
        "FIX:本机时区已是 $TZ_TARGET，不用改"
    }
    if (Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled }) {
        $adminScript += "Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -Confirm:`$false"
        "FIX:本机仍有网卡开着 IPv6，将关掉"
    } else {
        "FIX:本机 IPv6 已关，不用改"
    }
    $adminScript += "Clear-DnsClientCache"
    # WebRTC：拦 STUN 出站，避免家宽 IP 泄露（与浏览器策略双保险）
    $adminScript += @'
$n='ClaudeGuard-Block-STUN-UDP'
if (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue) { Set-NetFirewallRule -DisplayName $n -Enabled True -Action Block -EA SilentlyContinue }
else { New-NetFirewallRule -DisplayName $n -Direction Outbound -Action Block -Protocol UDP -RemotePort 3478,19302,19305 -Profile Any -EA SilentlyContinue | Out-Null }
'@
    "FIX:将加防火墙规则，拦住 WebRTC/STUN 出站（防家宽 IP 泄露）"
    if ($adminScript.Count -gt 0) {
        "FIX:写入本机设置（需要管理员授权）…"
        $tmp = "$env:TEMP\claude-fix-$([guid]::NewGuid().Guid).ps1"
        ($adminScript -join "`n") | Out-File -Encoding utf8 $tmp
        try {
            Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`""
            "FIX:本机时区/IPv6/DNS缓存 已执行"
        } catch { "FIX:管理员授权被取消，本机未改" }
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    # 真正改本机：地区格式 en-US
    $curCult = (Get-Culture).Name
    if ($curCult -ne 'en-US') {
        try {
            Set-Culture en-US
            "FIX:本机地区格式已从 $curCult 改成 en-US（新开的程序才生效）"
        } catch { "FIX:地区格式改失败: $($_.Exception.Message)" }
    } else {
        "FIX:本机地区格式已是 en-US，不用改"
    }

    # 浏览器 WebRTC 防泄露（HKCU，不弹管理员）— 只改勾选的浏览器
    $selB = @(Get-SelectedBrowsers)
    if ($selB.Count -gt 0) {
        $browsers = Set-BrowserWebRtcHardening $selB
        if ($browsers -and $browsers.Count -gt 0) {
            "FIX:已给浏览器加上 WebRTC 防泄露（$($browsers -join '、')）；请把这些浏览器全部退出再开一次才生效"
        } else {
            "FIX:浏览器 WebRTC 策略没写上，可再点一次一键修复"
        }
    }
    # 浏览器网页语言 → 英文；英文区域插件没装/没开就给步骤（不关浏览器、不要管理员）
    Invoke-BrowserFix

    # 关掉系统/浏览器共享定位
    Disable-LocationSharing

    # 先保证真 TUN（旧版也是写开关+重启；我们以出现虚拟网卡为准）
    $tunFix = Ensure-ClashTunReal
    if ($tunFix.ok) { "FIX:虚拟网卡已起来 — $($tunFix.detail)" }
    else { "FIX:虚拟网卡仍不安全 — $($tunFix.detail)" }

    # DNS 必须进代理隧道（假 IP）；失败保持不安全红灯，不改黄
    $dnsFix = Enable-ClashDnsFakeIp
    if ($dnsFix.ok) { "FIX:DNS 已进代理隧道 — $($dnsFix.detail)" }
    else { "FIX:DNS 仍不安全 — $($dnsFix.detail)" }

    # Clash 模式/TUN 仍请手点（不重写节点、不强杀）
    Invoke-ClashModeAndTunFix

    $e = Get-Egress
    if ($e.loc -eq $COUNTRY_TARGET) { "FIX:出口已是 $COUNTRY_TARGET ($($e.ip))" }
    else { "FIX:出口现在是 $($e.loc)，要 $COUNTRY_TARGET — 请在 Clash 换 $COUNTRY_TARGET 的节点" }

    "FIX:请彻底退出 Edge/Chrome 后再开；回 Claude守护 点「重新检查」。WebRTC 仍红就把 ippure 再测一遍发我"
    "FIX:修复流程结束"
}

function Invoke-Status {
    $cur = if (Test-Path "$BASE\current.txt") { (Get-Content "$BASE\current.txt" -Raw).Trim() } else { 'none' }
    $hasA = if (Test-Path "$BASE\accounts\A") { 1 } else { 0 }
    $hasB = if (Test-Path "$BASE\accounts\B") { 1 } else { 0 }
    "current=$cur hasA=$hasA hasB=$hasB"
}

function Stop-ClaudeApp {
    $p = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
    if (-not $p) { return $true }
    $p | Stop-Process -Force
    for ($i = 0; $i -lt 15; $i++) { if (-not (Get-Process -Name 'Claude' -ErrorAction SilentlyContinue)) { return $true }; Start-Sleep 1 }
    return $false
}

function Save-Account($name) {
    robocopy "$DATA" "$BASE\accounts\$name" /MIR /NFL /NDL /NJH /NJS | Out-Null
    Log "已存档账号$name"
}

function Start-ClaudeApp {
    $exe = @("$env:LOCALAPPDATA\AnthropicClaude\Claude.exe", "$env:LOCALAPPDATA\Programs\Claude\Claude.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { Start-Process $exe } else { Start-Process "shell:AppsFolder" -ErrorAction SilentlyContinue }
}

function Invoke-Switch($target) {
    $cur = if (Test-Path "$BASE\current.txt") { (Get-Content "$BASE\current.txt" -Raw).Trim() } else { 'none' }

    # 首次运行:收编当前登录为账号A
    if ($cur -eq 'none' -and (Test-Path $DATA) -and (Get-ChildItem $DATA -ErrorAction SilentlyContinue)) {
        if (-not (Stop-ClaudeApp)) { "FAIL:Claude 未能退出，请手动退出后重试"; return }
        Save-Account A
        $cur = 'A'; 'A' | Out-File -Encoding ascii -NoNewline "$BASE\current.txt"
        Log "首次运行:当前登录状态已收编为账号A"
        "NOTE:已将当前登录收编为账号A"
    }

    if ($cur -eq $target) { Start-ClaudeApp; "INFO:当前已是账号$target"; return }

    if (-not (Stop-ClaudeApp)) { "FAIL:Claude 未能退出，请手动退出后重试"; return }

    if ($cur -ne 'none' -and (Test-Path $DATA)) { Save-Account $cur }

    if (Test-Path "$BASE\accounts\$target") {
        Remove-Item $DATA -Recurse -Force -ErrorAction SilentlyContinue
        robocopy "$BASE\accounts\$target" "$DATA" /E /NFL /NDL /NJH /NJS | Out-Null
        Log "已载入账号$target 存档"
    } else {
        Remove-Item $DATA -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $DATA | Out-Null
        Log "账号$target 无存档，将以全新状态初始化"
    }
    $target | Out-File -Encoding ascii -NoNewline "$BASE\current.txt"
    Start-ClaudeApp
    Log "已切换到账号$target 并启动"
    "OK:已切换到账号$target"
}

if ($MyInvocation.InvocationName -ne '.') {
    switch ($args[0]) {
        'checkdetail' {
            $r = Invoke-CheckDetail
            $r | Out-File -Encoding utf8 "$BASE\last-check.txt"
            $r
        }
        'status' { Invoke-Status }
        'fix'    { Invoke-Fix }
        'switch' { Invoke-Switch $args[1] }
        'version' { $script:AppVersion }
        'checkupdate' { Invoke-CheckUpdate }
        default  { "用法: claude-switch.ps1 checkdetail|status|fix|switch A|B|version|checkupdate" }
    }
}
