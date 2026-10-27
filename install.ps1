# Claude守护 安装脚本（不需要管理员，不加开机自启，不加计划任务）
$ErrorActionPreference = 'Stop'

$SRC     = Join-Path $PSScriptRoot '程序'
$EXT_SRC = Join-Path $PSScriptRoot '浏览器插件\yingwen-quyu-ziti'
$DST     = Join-Path $env:USERPROFILE '.claude-switcher'
$EXT_DST = Join-Path $DST 'extension\yingwen-quyu-ziti'
$PROGRAM_FILES = @('SwitcherUI.ps1', 'claude-switch.ps1', 'claude-bodyguard.ps1', 'guard-settings.example-country.json')
$ICON_FILES    = @('app.ico', 'app-icon-128.png', 'app-icon-256.png')

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

Say ''
Say '==== 安装 Claude守护 ====' 'Cyan'
Say ''

if (-not (Test-Path (Join-Path $SRC 'SwitcherUI.ps1'))) {
    Say '找不到「程序」文件夹。请先把整个压缩包解压出来，再双击「安装.bat」。' 'Red'
    exit 1
}

# 正在运行的 Claude守护 要先退出，否则还是旧版本
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'SwitcherUI\.ps1' }
if ($running) {
    Say 'Claude守护 正在运行。请先在右下角托盘图标上右键 →「退出」，然后按回车继续。' 'Yellow'
    [void](Read-Host '退出后按回车')
}

try {
    New-Item -ItemType Directory -Force -Path $DST | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DST 'icons') | Out-Null
    New-Item -ItemType Directory -Force -Path $EXT_DST | Out-Null

    foreach ($f in $PROGRAM_FILES) {
        Copy-Item -LiteralPath (Join-Path $SRC $f) -Destination (Join-Path $DST $f) -Force
    }
    foreach ($f in $ICON_FILES) {
        $p = Join-Path $SRC "icons\$f"
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $DST "icons\$f") -Force }
    }
    # 设置文件：已经有就保留（重装不丢设置）
    $gs = Join-Path $DST 'guard-settings.json'
    if (Test-Path -LiteralPath $gs) { Say '已有的出口设置保留不动。' }
    else { Copy-Item -LiteralPath (Join-Path $SRC 'guard-settings.json') -Destination $gs -Force }

    # 浏览器插件放到固定位置
    if (Test-Path -LiteralPath $EXT_SRC) {
        Get-ChildItem -LiteralPath $EXT_SRC -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $EXT_DST $_.Name) -Force
        }
    }

    # 账号文件夹：不存在才新建，存在绝不覆盖
    $acc = Join-Path $DST 'accounts'
    if (-not (Test-Path -LiteralPath $acc)) { New-Item -ItemType Directory -Force -Path $acc | Out-Null }

    # 去掉“从网上下载”的标记，免得 PowerShell 拦
    Get-ChildItem -LiteralPath $DST -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike (Join-Path $acc '*') } |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }
} catch {
    Say ('复制文件出错：' + $_.Exception.Message) 'Red'
    exit 1
}

# 桌面快捷方式（隐藏黑窗口启动）
$ui   = Join-Path $DST 'SwitcherUI.ps1'
$ico  = Join-Path $DST 'icons\app.ico'
$ps   = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnkArgs = "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ui`""
try {
    $desk = [Environment]::GetFolderPath('Desktop')
    $lnk  = Join-Path $desk 'Claude守护.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = $ps
    $sc.Arguments = $lnkArgs
    $sc.WorkingDirectory = $DST
    $sc.WindowStyle = 7
    if (Test-Path -LiteralPath $ico) { $sc.IconLocation = "$ico,0" }
    $sc.Description = 'Claude守护'
    $sc.Save()
    Say "桌面快捷方式已建好：$lnk" 'Green'
} catch {
    Say ('建桌面快捷方式失败：' + $_.Exception.Message) 'Yellow'
}

Say ''
Say "安装完成，程序在：$DST" 'Green'
Say ''
Say '---- 还要你自己做一次：装浏览器插件「英文区域与字体探测限制」 ----' 'Cyan'
Say "插件文件夹：$EXT_DST"
Say '1) 打开 Edge 或 Chrome，在地址栏输入 edge://extensions （Chrome 输入 chrome://extensions）回车'
Say '2) 打开页面上的「开发人员模式」（Chrome 叫「开发者模式」）开关'
Say '3) 点「加载解压缩的扩展」（Chrome 叫「加载已解压的扩展程序」）'
Say '4) 选上面那个插件文件夹，确定'
Say '装好后不要移动、删除这个文件夹。'
Say 'Edge 如果弹出「关闭开发人员模式扩展」，点「保留」或右上角的叉，不要点「关闭」。'
Say ''
Say '---- Clash 那边请手动点 ----' 'Cyan'
Say '打开 Clash Verge：打开「虚拟网卡」(TUN) → 模式选「全局」→ 选你要的国家的节点'
Say ''

$ans = Read-Host '现在打开 Claude守护 吗？(Y/N)'
if ($ans -match '^(y|Y|是)') {
    Start-Process -FilePath $ps -ArgumentList $lnkArgs -WorkingDirectory $DST -WindowStyle Hidden
    Say '已打开，稍等几秒窗口就会出来。'
}
