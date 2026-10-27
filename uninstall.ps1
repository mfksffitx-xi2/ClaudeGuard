# Claude守护 卸载脚本（不需要管理员）
$ErrorActionPreference = 'Continue'

$DST = Join-Path $env:USERPROFILE '.claude-switcher'
function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

Say ''
Say '==== 卸载 Claude守护 ====' 'Cyan'
Say ''
if (-not (Test-Path -LiteralPath $DST)) { Say '没找到安装目录，可能已经卸载过了。' 'Yellow' }

# 先关掉正在运行的 Claude守护 和它的保镖
$procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'SwitcherUI\.ps1|claude-bodyguard\.ps1' -and $_.ProcessId -ne $PID }
if ($procs) {
    $a = Read-Host 'Claude守护 正在运行，要先把它关掉吗？(Y/N)'
    if ($a -match '^(y|Y|是)') {
        foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 500
    } else {
        Say '请先在托盘图标上右键 →「退出」，再重新运行卸载。' 'Yellow'
        exit 1
    }
}

# 删程序文件和运行记录（不动 accounts）
$files = @(
    'SwitcherUI.ps1', 'claude-switch.ps1', 'claude-bodyguard.ps1',
    'guard-settings.json', 'guard-settings.example-country.json',
    'last-check.txt', 'lastip.txt', 'proxy-mode.txt', 'bodyguard-off.flag',
    'bodyguard.log', 'bodyguard.log.old', 'claude-switch.log'
)
foreach ($f in $files) {
    $p = Join-Path $DST $f
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
}
foreach ($d in @('icons', 'extension')) {
    $p = Join-Path $DST $d
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
}

# 桌面快捷方式
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude守护.lnk'
if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue; Say '桌面快捷方式已删除。' }

# 账号资料：先问
$acc = Join-Path $DST 'accounts'
if (Test-Path -LiteralPath $acc) {
    Say ''
    Say '「accounts」里是你保存的 Claude 登录资料。' 'Yellow'
    $a = Read-Host '要一起删掉吗？删了就找不回来 (Y/N，默认不删)'
    if ($a -match '^(y|Y|是)') {
        Remove-Item -LiteralPath $acc -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $DST 'current.txt') -Force -ErrorAction SilentlyContinue
        Say '账号资料已删除。'
    } else {
        Say "账号资料保留在：$acc"
    }
}

# 一键修复加过的浏览器 WebRTC 设置：问一下要不要还原
Say ''
$a = Read-Host '要把一键修复给 Edge/Chrome 加的「WebRTC 防泄露」设置也去掉吗？(Y/N，默认保留)'
if ($a -match '^(y|Y|是)') {
    foreach ($k in @('HKCU:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Google\Chrome')) {
        Remove-ItemProperty -Path $k -Name 'WebRtcIPHandling', 'WebRtcLocalIpsAllowedUrls' -ErrorAction SilentlyContinue
    }
    Say '已去掉（浏览器重开后生效）。'
}

# 目录空了就删掉
if ((Test-Path -LiteralPath $DST) -and -not (Get-ChildItem -LiteralPath $DST -Force -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $DST -Force -ErrorAction SilentlyContinue
}

Say ''
Say '卸载完成。' 'Green'
Say '还剩两样要你自己处理（可不管）：'
Say '1) 浏览器插件：在 edge://extensions 或 chrome://extensions 里把「英文区域与字体探测限制」点「删除」'
Say '2) 一键修复改过的时区、地区格式、IPv6、防火墙规则不会自动改回，需要的话到 Windows 设置里改回来'
