# Claude守护 - Windows 界面 (WPF + 托盘)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$BASE = "$env:USERPROFILE\.claude-switcher"
$CORE = "$BASE\claude-switch.ps1"
$BODYGUARD = "$BASE\claude-bodyguard.ps1"
$script:reallyExit = $false
$script:bgStopped = $false

function Get-BodyguardProcs {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'claude-bodyguard\.ps1' -and $_.CommandLine -notmatch 'TestOnce' }
}
function Start-Bodyguard {
    if (Get-BodyguardProcs) { return }
    $a = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$BODYGUARD`" -ParentPid $PID"
    Start-Process -FilePath "$env:WINDIR\System32\conhost.exe" -ArgumentList $a -WindowStyle Hidden -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) { if (Get-BodyguardProcs) { break }; Start-Sleep -Milliseconds 150 }
}
function Get-OtherGuardUIs {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'SwitcherUI\.ps1' }
}
function Stop-Bodyguard {
    if ($script:bgStopped) { return }; $script:bgStopped = $true
    if (Get-OtherGuardUIs) { return }
    $p = @(Get-BodyguardProcs)
    foreach ($x in $p) { Stop-Process -Id $x.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($p.Count -gt 0) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') STOP (Claude守护 closed) pids=$(($p | ForEach-Object { $_.ProcessId }) -join ',')" | Out-File -Append -Encoding utf8 "$BASE\bodyguard.log" }
}

Remove-Item "$BASE\bodyguard-off.flag" -Force -ErrorAction SilentlyContinue
Start-Bodyguard

# 显式 Application，避免 Hide 后被当成“最后窗口关闭”把进程杀掉（托盘一起没）
if ($null -eq [System.Windows.Application]::Current) {
    $script:wpfApp = New-Object System.Windows.Application
} else {
    $script:wpfApp = [System.Windows.Application]::Current
}
$script:wpfApp.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude守护" Width="460" SizeToContent="Height" MinHeight="640" MaxHeight="1100" ResizeMode="CanMinimize"
        WindowStartupLocation="CenterScreen" Background="#FF0F1117" Foreground="White"
        ShowInTaskbar="True">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <DockPanel Grid.Row="0" Margin="0,0,0,14" LastChildFill="False">
            <Border Width="40" Height="40" CornerRadius="10" DockPanel.Dock="Left" ClipToBounds="True" Background="#FF1A1B26">
                <Image x:Name="AppLogo" Stretch="UniformToFill" SnapsToDevicePixels="True"/>
            </Border>
            <StackPanel Margin="12,0,0,0" VerticalAlignment="Center" DockPanel.Dock="Left">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Claude守护" FontSize="18" FontWeight="SemiBold"/>
                    <TextBlock x:Name="AppVer" Text="v1.0.0" FontSize="12" Foreground="#99FFFFFF" VerticalAlignment="Bottom" Margin="8,0,0,2"/>
                </StackPanel>
                <TextBlock x:Name="SubTitle" Text="安全检查 · 托盘常驻" FontSize="11" Foreground="#99FFFFFF" Margin="0,2,0,0"/>
            </StackPanel>
            <Border x:Name="StatusPill" DockPanel.Dock="Right" Padding="10,5" CornerRadius="10" Background="#1AFFFFFF" VerticalAlignment="Center">
                <TextBlock x:Name="StatusText" Text="检查中" FontSize="11" FontWeight="SemiBold" Foreground="#FFFB923C"/>
            </Border>
        </DockPanel>

        <Border Grid.Row="1" CornerRadius="14" Background="#14FFFFFF" BorderBrush="#1AFFFFFF" BorderThickness="1" Padding="6,4">
            <ListBox x:Name="CheckList" Background="Transparent" BorderThickness="0" Foreground="#F2FFFFFF" FontSize="13"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.VerticalScrollBarVisibility="Disabled">
                <ListBox.ItemContainerStyle>
                    <Style TargetType="ListBoxItem">
                        <Setter Property="Padding" Value="0"/>
                        <Setter Property="Margin" Value="0"/>
                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                        <Setter Property="Focusable" Value="False"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ListBoxItem">
                                    <Border Padding="8,6" Background="Transparent">
                                        <ContentPresenter/>
                                    </Border>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </ListBox.ItemContainerStyle>
                <ListBox.ItemTemplate>
                    <DataTemplate>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="108"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="22"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="{Binding Name}" VerticalAlignment="Center" Foreground="#E6FFFFFF"/>
                            <TextBlock Grid.Column="1" Text="{Binding Detail}" ToolTip="{Binding Detail}" VerticalAlignment="Center" Foreground="#8CFFFFFF" FontSize="11" TextTrimming="CharacterEllipsis" Margin="8,0,8,0"/>
                            <TextBlock Grid.Column="2" Text="{Binding Icon}" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{Binding Color}" FontSize="13" FontWeight="Bold"/>
                        </Grid>
                    </DataTemplate>
                </ListBox.ItemTemplate>
            </ListBox>
        </Border>

        <StackPanel Grid.Row="2" Margin="0,14,0,0">
            <Border CornerRadius="12" Background="#14FFFFFF" BorderBrush="#1AFFFFFF" BorderThickness="1" Padding="12,10" Margin="0,0,0,12">
                <StackPanel>
                    <TextBlock Text="出口设置" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                    <Grid Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="72"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="大洲" VerticalAlignment="Center" Foreground="#CCFFFFFF" FontSize="12"/>
                        <ComboBox x:Name="CboRegion" Grid.Column="1" Height="30" FontSize="12"/>
                    </Grid>
                    <Grid Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="72"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="国家" VerticalAlignment="Center" Foreground="#CCFFFFFF" FontSize="12"/>
                        <ComboBox x:Name="CboCountry" Grid.Column="1" Height="30" FontSize="12"/>
                    </Grid>
                    <Grid Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="72"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="浏览器" VerticalAlignment="Center" Foreground="#CCFFFFFF" FontSize="12"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                            <CheckBox x:Name="ChkEdge" Content="Edge" Foreground="#CCFFFFFF" FontSize="12" VerticalAlignment="Center"/>
                            <CheckBox x:Name="ChkChrome" Content="Chrome" Foreground="#CCFFFFFF" FontSize="12" VerticalAlignment="Center" Margin="18,0,0,0"/>
                            <TextBlock Text="（勾上的会一起检查和修复）" Foreground="#66FFFFFF" FontSize="10" VerticalAlignment="Center" Margin="10,0,0,0"/>
                        </StackPanel>
                    </Grid>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <CheckBox x:Name="ChkAuto" Content="下次检查时自动认当前出口" Foreground="#CCFFFFFF" FontSize="11" VerticalAlignment="Center"/>
                        <Button x:Name="BtnSaveSettings" Grid.Column="1" Content="保存设置" Height="30" Padding="12,0" Margin="8,0,0,0" FontSize="12" FontWeight="SemiBold" Foreground="White" Background="#FF4F46E5" BorderThickness="0" Cursor="Hand"/>
                    </Grid>
                    <TextBlock Text="出口IP要和付款地址城市一致" FontSize="10" Foreground="#66FFFFFF" Margin="0,8,0,0" TextWrapping="Wrap"/>
                </StackPanel>
            </Border>
            <TextBlock x:Name="Banner" Text="" FontSize="12" Foreground="#FFF87171" Margin="0,0,0,10" TextWrapping="Wrap" TextAlignment="Center"/>
            <UniformGrid Columns="3" Rows="1">
                <Button x:Name="BtnFix" Content="一键修复" Height="42" Margin="0,0,4,0" FontWeight="SemiBold" Foreground="White" BorderThickness="0" Cursor="Hand">
                    <Button.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#FF6366F1" Offset="0"/>
                            <GradientStop Color="#FF9333EA" Offset="1"/>
                        </LinearGradientBrush>
                    </Button.Background>
                </Button>
                <Button x:Name="BtnRefresh" Content="重新检查" Height="42" Margin="4,0,4,0" FontWeight="SemiBold" Foreground="White" Background="#FF374151" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnCheckUpdate" Content="检查更新" Height="42" Margin="4,0,0,0" FontWeight="SemiBold" Foreground="White" Background="#FF374151" BorderThickness="0" Cursor="Hand"/>
            </UniformGrid>
            <TextBlock Text="关闭窗口会进托盘，点托盘图标「退出」才真正关掉" FontSize="10" Foreground="#66FFFFFF" HorizontalAlignment="Center" Margin="0,12,0,0" TextWrapping="Wrap" TextAlignment="Center"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

# 自定义图标（窗口 / 标题栏大图 / 托盘）

# Taskbar: use shortcut shield icon instead of PowerShell blue icon
try {
    Add-Type -Namespace ClaudeGuard -Name AppId -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
"@ -ErrorAction Stop
    [ClaudeGuard.AppId]::SetCurrentProcessExplicitAppUserModelID('ClaudeGuard.Switcher.1')
} catch {}

$ICON_DIR = Join-Path $BASE 'icons'
$ICO_PATH = Join-Path $ICON_DIR 'app.ico'
$PNG_PATH = Join-Path $ICON_DIR 'app-icon-128.png'
function Set-GuardIcons {
    try {
        if (Test-Path $PNG_PATH) {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.UriSource = [Uri]::new((Resolve-Path $PNG_PATH).Path)
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.EndInit()
            $bmp.Freeze()
            $logo = $win.FindName('AppLogo')
            if ($logo) { $logo.Source = $bmp }
            $win.Icon = $bmp
        }
    } catch {}
}
Set-GuardIcons

$script:regionOrder = @('亚洲','欧洲','北美','南美','大洋洲','中东','非洲')

$script:countryChoices = @(
    [pscustomobject]@{ Code='TH'; Label='泰国 (TH)'; Region='亚洲'; Tz='SE Asia Standard Time'; Node='泰国|Thai|TH' },
    [pscustomobject]@{ Code='SG'; Label='新加坡 (SG)'; Region='亚洲'; Tz='Singapore Standard Time'; Node='新加坡|Singapore|SG' },
    [pscustomobject]@{ Code='JP'; Label='日本 (JP)'; Region='亚洲'; Tz='Tokyo Standard Time'; Node='日本|Japan|JP' },
    [pscustomobject]@{ Code='KR'; Label='韩国 (KR)'; Region='亚洲'; Tz='Korea Standard Time'; Node='韩国|Korea|KR' },
    [pscustomobject]@{ Code='HK'; Label='香港 (HK)'; Region='亚洲'; Tz='China Standard Time'; Node='香港|Hong Kong|HK' },
    [pscustomobject]@{ Code='TW'; Label='台湾 (TW)'; Region='亚洲'; Tz='Taipei Standard Time'; Node='台湾|Taiwan|TW' },
    [pscustomobject]@{ Code='MY'; Label='马来西亚 (MY)'; Region='亚洲'; Tz='Singapore Standard Time'; Node='马来|Malaysia|MY' },
    [pscustomobject]@{ Code='PH'; Label='菲律宾 (PH)'; Region='亚洲'; Tz='Singapore Standard Time'; Node='菲律宾|Philippines|PH' },
    [pscustomobject]@{ Code='VN'; Label='越南 (VN)'; Region='亚洲'; Tz='SE Asia Standard Time'; Node='越南|Vietnam|VN' },
    [pscustomobject]@{ Code='ID'; Label='印尼 (ID)'; Region='亚洲'; Tz='SE Asia Standard Time'; Node='印尼|Indonesia|ID' },
    [pscustomobject]@{ Code='IN'; Label='印度 (IN)'; Region='亚洲'; Tz='India Standard Time'; Node='印度|India|IN' },
    [pscustomobject]@{ Code='CN'; Label='中国 (CN)'; Region='亚洲'; Tz='China Standard Time'; Node='中国|China|CN' },
    [pscustomobject]@{ Code='MO'; Label='澳门 (MO)'; Region='亚洲'; Tz='China Standard Time'; Node='澳门|Macao|Macau|MO' },
    [pscustomobject]@{ Code='KH'; Label='柬埔寨 (KH)'; Region='亚洲'; Tz='SE Asia Standard Time'; Node='柬埔寨|Cambodia|KH' },
    [pscustomobject]@{ Code='LA'; Label='老挝 (LA)'; Region='亚洲'; Tz='SE Asia Standard Time'; Node='老挝|Laos|LA' },
    [pscustomobject]@{ Code='GB'; Label='英国 (GB)'; Region='欧洲'; Tz='GMT Standard Time'; Node='英国|UK|London|GB' },
    [pscustomobject]@{ Code='DE'; Label='德国 (DE)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='德国|Germany|DE' },
    [pscustomobject]@{ Code='FR'; Label='法国 (FR)'; Region='欧洲'; Tz='Romance Standard Time'; Node='法国|France|FR' },
    [pscustomobject]@{ Code='NL'; Label='荷兰 (NL)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='荷兰|Netherlands|NL' },
    [pscustomobject]@{ Code='IT'; Label='意大利 (IT)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='意大利|Italy|IT' },
    [pscustomobject]@{ Code='ES'; Label='西班牙 (ES)'; Region='欧洲'; Tz='Romance Standard Time'; Node='西班牙|Spain|ES' },
    [pscustomobject]@{ Code='SE'; Label='瑞典 (SE)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='瑞典|Sweden|SE' },
    [pscustomobject]@{ Code='CH'; Label='瑞士 (CH)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='瑞士|Switzerland|CH' },
    [pscustomobject]@{ Code='PL'; Label='波兰 (PL)'; Region='欧洲'; Tz='Central European Standard Time'; Node='波兰|Poland|PL' },
    [pscustomobject]@{ Code='TR'; Label='土耳其 (TR)'; Region='欧洲'; Tz='Turkey Standard Time'; Node='土耳其|Turkey|TR' },
    [pscustomobject]@{ Code='IE'; Label='爱尔兰 (IE)'; Region='欧洲'; Tz='GMT Standard Time'; Node='爱尔兰|Ireland|IE' },
    [pscustomobject]@{ Code='FI'; Label='芬兰 (FI)'; Region='欧洲'; Tz='FLE Standard Time'; Node='芬兰|Finland|FI' },
    [pscustomobject]@{ Code='NO'; Label='挪威 (NO)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='挪威|Norway|NO' },
    [pscustomobject]@{ Code='AT'; Label='奥地利 (AT)'; Region='欧洲'; Tz='W. Europe Standard Time'; Node='奥地利|Austria|AT' },
    [pscustomobject]@{ Code='BE'; Label='比利时 (BE)'; Region='欧洲'; Tz='Romance Standard Time'; Node='比利时|Belgium|BE' },
    [pscustomobject]@{ Code='PT'; Label='葡萄牙 (PT)'; Region='欧洲'; Tz='GMT Standard Time'; Node='葡萄牙|Portugal|PT' },
    [pscustomobject]@{ Code='CZ'; Label='捷克 (CZ)'; Region='欧洲'; Tz='Central Europe Standard Time'; Node='捷克|Czech|CZ' },
    [pscustomobject]@{ Code='RO'; Label='罗马尼亚 (RO)'; Region='欧洲'; Tz='GTB Standard Time'; Node='罗马尼亚|Romania|RO' },
    [pscustomobject]@{ Code='US'; Label='美国 (US)'; Region='北美'; Tz='Pacific Standard Time'; Node='美国|USA|US' },
    [pscustomobject]@{ Code='CA'; Label='加拿大 (CA)'; Region='北美'; Tz='Eastern Standard Time'; Node='加拿大|Canada|CA' },
    [pscustomobject]@{ Code='MX'; Label='墨西哥 (MX)'; Region='北美'; Tz='Central Standard Time (Mexico)'; Node='墨西哥|Mexico|MX' },
    [pscustomobject]@{ Code='BR'; Label='巴西 (BR)'; Region='南美'; Tz='E. South America Standard Time'; Node='巴西|Brazil|BR' },
    [pscustomobject]@{ Code='AR'; Label='阿根廷 (AR)'; Region='南美'; Tz='Argentina Standard Time'; Node='阿根廷|Argentina|AR' },
    [pscustomobject]@{ Code='CL'; Label='智利 (CL)'; Region='南美'; Tz='Pacific SA Standard Time'; Node='智利|Chile|CL' },
    [pscustomobject]@{ Code='CO'; Label='哥伦比亚 (CO)'; Region='南美'; Tz='SA Pacific Standard Time'; Node='哥伦比亚|Colombia|CO' },
    [pscustomobject]@{ Code='AU'; Label='澳大利亚 (AU)'; Region='大洋洲'; Tz='AUS Eastern Standard Time'; Node='澳洲|澳大利亚|Australia|AU' },
    [pscustomobject]@{ Code='NZ'; Label='新西兰 (NZ)'; Region='大洋洲'; Tz='New Zealand Standard Time'; Node='新西兰|New Zealand|NZ' },
    [pscustomobject]@{ Code='AE'; Label='阿联酋 (AE)'; Region='中东'; Tz='Arabian Standard Time'; Node='阿联酋|UAE|Dubai|AE' },
    [pscustomobject]@{ Code='IL'; Label='以色列 (IL)'; Region='中东'; Tz='Israel Standard Time'; Node='以色列|Israel|IL' },
    [pscustomobject]@{ Code='SA'; Label='沙特 (SA)'; Region='中东'; Tz='Arab Standard Time'; Node='沙特|Saudi|SA' },
    [pscustomobject]@{ Code='QA'; Label='卡塔尔 (QA)'; Region='中东'; Tz='Arab Standard Time'; Node='卡塔尔|Qatar|QA' },
    [pscustomobject]@{ Code='ZA'; Label='南非 (ZA)'; Region='非洲'; Tz='South Africa Standard Time'; Node='南非|South Africa|ZA' },
    [pscustomobject]@{ Code='EG'; Label='埃及 (EG)'; Region='非洲'; Tz='Egypt Standard Time'; Node='埃及|Egypt|EG' },
    [pscustomobject]@{ Code='NG'; Label='尼日利亚 (NG)'; Region='非洲'; Tz='W. Central Africa Standard Time'; Node='尼日利亚|Nigeria|NG' }
)

function Read-UiGuardSettings {
    $f = Join-Path $BASE 'guard-settings.json'
    $d = @{ auto = $false; country = 'US'; city = ''; timezone = 'Pacific Standard Time'; node_match = ''; ip_mode = 'dynamic'; browsers = $null; update_repo = ''; update_url = '' }
    if (-not (Test-Path $f)) { return $d }
    try {
        $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $j.auto) { $d.auto = [bool]$j.auto }
        if ($j.country) { $d.country = ([string]$j.country).ToUpper() }
        if ($null -ne $j.city) { $d.city = [string]$j.city }
        if ($j.timezone) { $d.timezone = [string]$j.timezone }
        if ($null -ne $j.node_match) { $d.node_match = [string]$j.node_match }
        if ($j.ip_mode) { $d.ip_mode = ([string]$j.ip_mode).ToLower() }
        if ($j.PSObject.Properties.Name -contains 'browsers') { $d.browsers = @(@($j.browsers) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() }) }
        if ($j.update_repo) { $d.update_repo = [string]$j.update_repo }
        if ($j.update_url) { $d.update_url = [string]$j.update_url }
    } catch {}
    return $d
}

function Write-UiGuardSettings($s) {
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

function Update-SettingsSubtitle {
    $s = Read-UiGuardSettings
    $label = if ($s.auto) { '自动识别出口' } elseif ($s.country) { [string]$s.country } else { '' }
    if ($label) { $win.FindName('SubTitle').Text = ("安全检查 · " + $label + " · 托盘常驻") }
}

function Fill-CountryCombo([string]$region, [string]$preferCode) {
    $cbo = $win.FindName('CboCountry')
    $cbo.Items.Clear()
    $list = @($script:countryChoices | Where-Object { $_.Region -eq $region })
    if (-not $list.Count) { $list = @($script:countryChoices) }
    foreach ($c in $list) { [void]$cbo.Items.Add($c.Label) }
    $hit = $list | Where-Object { $_.Code -eq $preferCode } | Select-Object -First 1
    if ($hit) { $cbo.SelectedItem = $hit.Label }
    elseif ($cbo.Items.Count -gt 0) { $cbo.SelectedIndex = 0 }
}

function Load-SettingsToUi {
    $cboR = $win.FindName('CboRegion')
    $chk = $win.FindName('ChkAuto')
    $script:loadingSettings = $true
    try {
        if (-not $cboR.Items.Count) {
            foreach ($r in $script:regionOrder) { [void]$cboR.Items.Add($r) }
        }
        $s = Read-UiGuardSettings
        $hit = $script:countryChoices | Where-Object { $_.Code -eq $s.country } | Select-Object -First 1
        if (-not $hit) { $hit = $script:countryChoices[0] }
        $cboR.SelectedItem = $hit.Region
        Fill-CountryCombo $hit.Region $hit.Code
        $chk.IsChecked = [bool]$s.auto
        $bsel = if ($null -ne $s.browsers) { @($s.browsers) } else { @(Get-InstalledBrowsers) }
        $win.FindName('ChkEdge').IsChecked = ($bsel -contains 'edge')
        $win.FindName('ChkChrome').IsChecked = ($bsel -contains 'chrome')
        Update-SettingsSubtitle
    } finally {
        $script:loadingSettings = $false
    }
}

function Save-SettingsFromUi([switch]$Quiet) {
    $cbo = $win.FindName('CboCountry')
    $chk = $win.FindName('ChkAuto')
    $label = [string]$cbo.SelectedItem
    $hit = $script:countryChoices | Where-Object { $_.Label -eq $label } | Select-Object -First 1
    if (-not $hit) { $hit = $script:countryChoices[0] }
    $s = Read-UiGuardSettings
    $s.auto = [bool]$chk.IsChecked
    $s.country = $hit.Code
    $s.city = ''   # city unused; keep key empty for bodyguard compat
    $s.timezone = $hit.Tz
    $s.node_match = $hit.Node
    if (-not $s.ip_mode) { $s.ip_mode = 'dynamic' }
    $bsel = @()
    if ($win.FindName('ChkEdge').IsChecked) { $bsel += 'edge' }
    if ($win.FindName('ChkChrome').IsChecked) { $bsel += 'chrome' }
    $s.browsers = $bsel
    Write-UiGuardSettings $s
    Update-SettingsSubtitle
    if (-not $Quiet) {
        $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x22,0xC5,0x5E))
        $win.FindName('Banner').Text = ("已保存：期望出口 " + $hit.Label)
    }
}

$rows = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$win.FindName('CheckList').ItemsSource = $rows
$checkNames = @('代理软件','虚拟网卡','全局模式','出口地区','出口变动','时区','地区','IPv6','DNS','WebRTC','浏览器语言','共享定位','保镖','规则置顶','客户端语言','线路类型','Claude连通')

function Set-Status($text, $rgb) {
    $win.FindName('StatusText').Text = $text
    $c = [System.Windows.Media.Color]::FromRgb($rgb[0], $rgb[1], $rgb[2])
    $win.FindName('StatusText').Foreground = New-Object System.Windows.Media.SolidColorBrush $c
    $bg = [System.Windows.Media.Color]::FromArgb(40, $rgb[0], $rgb[1], $rgb[2])
    $win.FindName('StatusPill').Background = New-Object System.Windows.Media.SolidColorBrush $bg
}

$script:coreLoaded = $false
$script:checking = $false
$script:checkStartedAt = $null

# MUST load at script top-level: loading inside a function drops Invoke-Fix when the function returns
if (-not (Test-Path -LiteralPath $CORE)) { throw "missing core: $CORE" }
. $CORE
if (-not (Get-Command Invoke-Fix -ErrorAction SilentlyContinue)) { throw 'dot-source claude-switch.ps1 but Invoke-Fix missing' }
$script:coreLoaded = $true
try {
    $ver = if ($script:AppVersion) { [string]$script:AppVersion } else { '1.0.0' }
    $av = $win.FindName('AppVer')
    if ($av) { $av.Text = ('v' + ($ver -replace '^v','')) }
} catch {}

function Ensure-CoreLoaded {
    if (-not $script:coreLoaded) { throw 'core not loaded' }
    if (-not (Get-Command Invoke-Fix -ErrorAction SilentlyContinue)) {
        . $CORE
        if (-not (Get-Command Invoke-Fix -ErrorAction SilentlyContinue)) { throw 'reload still missing Invoke-Fix' }
        $script:coreLoaded = $true
    }
}

function Invoke-Core([string[]]$coreArgs) {
    switch ($coreArgs[0]) {
        'checkdetail' {
            Ensure-CoreLoaded
            $r = Invoke-CheckDetail
            $r | Out-File -Encoding utf8 "$BASE\last-check.txt"
            return (($r | Out-String).Trim())
        }
        'fix' {
            # child process for fix - avoids WPF event scope dropping functions
            $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $CORE fix 2>&1
            return ($out | Out-String).Trim()
        }
        'status' {
            Ensure-CoreLoaded
            return ((Invoke-Status | Out-String).Trim())
        }
        default {
            $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $CORE @coreArgs 2>&1
            return ($out | Out-String).Trim()
        }
    }
}

function Apply-CheckOutput([string]$out) {
    $allOk = $true; $matched = 0
    $okIcon = [string][char]0x2713
    $warnIcon = [string][char]0x26A0
    $badIcon = [string][char]0x2717
    foreach ($line in ($out -split "`n")) {
        $line = $line.Trim()
        $kv = $line -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $st = @($kv[1].Trim() -split ':', 2)
        $st[0] = $st[0].Trim()
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if ($rows[$i].Name -eq $kv[0]) {
                $matched++
                $d = if ($st.Count -gt 1) { $st[1] } else { '' }
                switch ($st[0]) {
                    'ok'   { $rows[$i] = [pscustomobject]@{ Name = $rows[$i].Name; Detail = $d; Icon = $okIcon; Color = '#FF22C55E' } }
                    'warn' { $rows[$i] = [pscustomobject]@{ Name = $rows[$i].Name; Detail = $d; Icon = $warnIcon; Color = '#FFFACC15' } }
                    default { $rows[$i] = [pscustomobject]@{ Name = $rows[$i].Name; Detail = $d; Icon = $badIcon; Color = '#FFF87171' }; $allOk = $false }
                }
                break
            }
        }
    }
    if ($matched -lt $checkNames.Count) {
        Set-Status '检查未过' @(0xF8,0x71,0x71)
        $win.FindName('Banner').Text = "检查结果不完整($matched/$($checkNames.Count))，请点重新检查"
    } elseif ($allOk) {
        Set-Status '环境安全' @(0x22,0xC5,0x5E)
        $win.FindName('Banner').Text = ''
    } else {
        Set-Status '检查未过' @(0xF8,0x71,0x71)
        $win.FindName('Banner').Text = '有几项还没通过，可点「一键修复」，或自己在 Clash 里改完再点「重新检查」'
    }
    Update-BodyguardRow
    Update-TrayTip
}

function Set-CheckButtonsEnabled([bool]$on) {
    # 检查中也不再灰掉按钮（WPF 禁用态会整片发白看不清）
    foreach ($n in @('BtnFix','BtnRefresh','BtnCheckUpdate')) {
        $b = $win.FindName($n)
        if ($b) { $b.IsEnabled = $true }
    }
}

function Stop-CheckJob {
    try { if ($script:checkPoll) { $script:checkPoll.Stop() } } catch {}
    try {
        if ($script:checkPS) {
            $script:checkPS.Stop()
            $script:checkPS.Dispose()
        }
    } catch {}
    $script:checkPS = $null
    $script:checkHandle = $null
    $script:checking = $false
    $script:checkStartedAt = $null
}

function Refresh-Checks {
    if ($script:checking) {
        # 允许强制重开：先停掉卡住的检查
        Stop-CheckJob
    }
    $script:checking = $true
    $script:checkStartedAt = Get-Date
    $rows.Clear()
    foreach ($n in $checkNames) { $rows.Add([pscustomobject]@{ Name = $n; Detail = ''; Icon = [char]0x2026; Color = '#FF6B7280' }) }
    Set-Status '检查中' @(0xFB,0x92,0x3C)
    $win.FindName('Banner').Text = '正在后台检查，界面可先用…'
    $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x9C,0xA3,0xAF))
    Set-CheckButtonsEnabled $true
    Update-TrayTip

    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($corePath, $basePath)
        $ErrorActionPreference = 'Continue'
        . $corePath
        $r = Invoke-CheckDetail
        $r | Out-File -Encoding utf8 (Join-Path $basePath 'last-check.txt')
        return (($r | Out-String).Trim())
    }).AddArgument($CORE).AddArgument($BASE)

    $script:checkPS = $ps
    $script:checkHandle = $ps.BeginInvoke()
    if ($script:checkPoll) { try { $script:checkPoll.Stop() } catch {} }
    $script:checkPoll = New-Object System.Windows.Threading.DispatcherTimer
    $script:checkPoll.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:checkPoll.Add_Tick({
        $timedOut = $false
        if ($script:checkStartedAt -and ((Get-Date) - $script:checkStartedAt).TotalSeconds -gt 25) {
            $timedOut = $true
        }
        if (-not $timedOut -and $script:checkHandle -and -not $script:checkHandle.IsCompleted) { return }
        $script:checkPoll.Stop()
        try {
            if ($timedOut) {
                try { $script:checkPS.Stop() } catch {}
                Set-Status '检查未过' @(0xF8,0x71,0x71)
                $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
                $win.FindName('Banner').Text = '检查超时（约25秒），可再点重新检查'
            } else {
                $out = ($script:checkPS.EndInvoke($script:checkHandle) | Out-String).Trim()
                Apply-CheckOutput $out
            }
        } catch {
            Set-Status '检查未过' @(0xF8,0x71,0x71)
            $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
            $win.FindName('Banner').Text = "检查失败: $($_.Exception.Message)"
        } finally {
            try { $script:checkPS.Dispose() } catch {}
            $script:checkPS = $null
            $script:checkHandle = $null
            $script:checking = $false
            $script:checkStartedAt = $null
            Set-CheckButtonsEnabled $true
        }
    })
    $script:checkPoll.Start()
}

function Update-BodyguardRow {
    $alive = [bool](Get-BodyguardProcs)
    $paused = Test-Path "$BASE\bodyguard-off.flag"
    $okIcon = [string][char]0x2713
    $warnIcon = [string][char]0x26A0
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ($rows[$i].Name -eq '保镖' -and $rows[$i].Icon -ne ([string][char]0x2026)) {
            $r = if ($alive -and -not $paused) { [pscustomobject]@{ Name = '保镖'; Detail = '运行中'; Icon = $okIcon; Color = '#FF22C55E' } }
                 elseif ($alive) { [pscustomobject]@{ Name = '保镖'; Detail = '已暂停'; Icon = $warnIcon; Color = '#FFFACC15' } }
                 else { [pscustomobject]@{ Name = '保镖'; Detail = '未运行'; Icon = $warnIcon; Color = '#FFFACC15' } }
            if ($rows[$i].Detail -ne $r.Detail) { $rows[$i] = $r }
            break
        }
    }
}



function Update-TrayTip {
    $st = $win.FindName('StatusText').Text
    if ($notify) { $notify.Text = ("Claude守护 · " + $st) }
}

# 托盘：用隐藏 WinForms 窗体挂消息，避免只有 WPF 时图标不出现/点不了
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:trayForm = New-Object System.Windows.Forms.Form
$script:trayForm.Text = 'Claude守护'
$script:trayForm.ShowInTaskbar = $false
$script:trayForm.FormBorderStyle = 'FixedToolWindow'
$script:trayForm.Opacity = 0
$script:trayForm.Size = New-Object System.Drawing.Size(0, 0)
$script:trayForm.Location = New-Object System.Drawing.Point(-2000, -2000)
$script:trayForm.StartPosition = 'Manual'
$script:trayForm.WindowState = 'Minimized'

$notify = New-Object System.Windows.Forms.NotifyIcon
try {
    if (Test-Path $ICO_PATH) {
        $notify.Icon = New-Object System.Drawing.Icon($ICO_PATH)
    } else {
        $notify.Icon = [System.Drawing.SystemIcons]::Shield
    }
} catch {
    $notify.Icon = [System.Drawing.SystemIcons]::Shield
}
$notify.Text = 'Claude守护'
$notify.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $menu.Items.Add('打开窗口')
$miCheck = $menu.Items.Add('重新检查')
[void]$menu.Items.Add('-')
$miExit = $menu.Items.Add('退出')
$notify.ContextMenuStrip = $menu
$miOpen.add_Click({ $win.Dispatcher.Invoke([action]{ Show-MainWindow }) })
$miCheck.add_Click({ $win.Dispatcher.Invoke([action]{ Show-MainWindow; Refresh-Checks }) })
$miExit.add_Click({ $win.Dispatcher.Invoke([action]{ Exit-GuardApp }) })
$notify.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $win.Dispatcher.Invoke([action]{ Show-MainWindow })
    }
})

$script:loadingSettings = $false
$win.FindName('CboRegion').Add_SelectionChanged({
    if ($script:loadingSettings) { return }
    $reg = [string]$win.FindName('CboRegion').SelectedItem
    if (-not $reg) { return }
    $curLabel = [string]$win.FindName('CboCountry').SelectedItem
    $cur = $script:countryChoices | Where-Object { $_.Label -eq $curLabel } | Select-Object -First 1
    $prefer = if ($cur -and $cur.Region -eq $reg) { $cur.Code } else { '' }
    Fill-CountryCombo $reg $prefer
})
$win.FindName('BtnRefresh').Add_Click({ Refresh-Checks })
$win.FindName('BtnCheckUpdate').Add_Click({
  try {
    $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
    $win.FindName('Banner').Text = '正在检查更新…'
    $win.Dispatcher.Invoke([action]{}, 'Render')
    $out = Invoke-Core @('checkupdate')
    $msg = ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
    if ($msg -match '^UPDATE:') { $msg = $msg -replace '^UPDATE:','' }
    if (-not $msg) { $msg = '检查更新完成' }
    $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x22,0xC5,0x5E))
    $win.FindName('Banner').Text = $msg
  } catch {
    $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
    $win.FindName('Banner').Text = ('检查更新失败：' + $_.Exception.Message)
  }
})
$win.FindName('BtnSaveSettings').Add_Click({ Save-SettingsFromUi; Refresh-Checks })
Load-SettingsToUi
$win.FindName('BtnFix').Add_Click({
  try {
    Set-Status '请手动点' @(0xFB,0x92,0x3C)
    $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFB,0x92,0x3C))
    $win.FindName('Banner').Text = '请在 Clash 点：虚拟网卡开 → 全局 → 目标国家节点；点完再「重新检查」'
    $win.Dispatcher.Invoke([action]{}, 'Render')
    $out = Invoke-Core @('fix')
    $tips = @($out -split "`n" | Where-Object { $_ -match '^FIX:' } | ForEach-Object { $_ -replace '^FIX:','' } | Select-Object -First 6)
    if ($tips.Count -gt 0) {
      $win.FindName('Banner').Text = ($tips -join ' · ').Trim()
    } else {
      $win.FindName('Banner').Text = '请在 Clash 点：虚拟网卡开 → 全局 → 目标国家节点；点完再「重新检查」'
    }
    Refresh-Checks
  } catch {
    Set-Status '修复出错' @(0xF8,0x71,0x71)
    $win.FindName('Banner').Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF8,0x71,0x71))
    $win.FindName('Banner').Text = ('修复失败：' + $_.Exception.Message)
  }
})

$win.Add_Closing({
    param($sender, $e)
    if (-not $script:reallyExit) {
        $e.Cancel = $true
        $win.ShowInTaskbar = $false
        $win.Hide()
        try {
            $notify.BalloonTipTitle = 'Claude守护'
            $notify.BalloonTipText = '已在托盘运行。右键图标可退出。'
            $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
            $notify.ShowBalloonTip(2500)
        } catch {}
    }
})

function Show-MainWindow {
    $win.ShowInTaskbar = $true
    $win.Show()
    $win.WindowState = 'Normal'
    $win.Activate()
    $win.Topmost = $true
    $win.Topmost = $false
}

function Exit-GuardApp {
    $script:reallyExit = $true
    try { $bgTimer.Stop() } catch {}
    try { $notify.Visible = $false; $notify.Dispose() } catch {}
    try { $script:trayForm.Close() } catch {}
    Stop-Bodyguard
    try { $win.Close() } catch {}
    try { $script:wpfApp.Shutdown() } catch {}
    [Environment]::Exit(0)
}

# redefine earlier stubs if present - remove duplicate Show-MainWindow / Exit-GuardApp from head
$win.Add_ContentRendered({
    try {
        $sf = Join-Path $BASE 'guard-settings.json'
        if (Test-Path $sf) {
            $j = Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json
            $label = if ($j.auto) { '自动识别出口' } elseif ($j.country) { [string]$j.country } else { '' }
            if ($label) { $win.FindName('SubTitle').Text = ("安全检查 · " + $label + " · 托盘常驻") }
        }
    } catch {}
    $win.Dispatcher.BeginInvoke([action]{ Refresh-Checks }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
})
$bgTimer = New-Object System.Windows.Threading.DispatcherTimer
$bgTimer.Interval = [TimeSpan]::FromSeconds(5)
$bgTimer.Add_Tick({ if (-not (Get-BodyguardProcs)) { Start-Bodyguard }; Update-BodyguardRow; Update-TrayTip })
$bgTimer.Start()

# 先露出托盘宿主，再开主窗
$script:trayForm.Show()
$script:trayForm.Hide()
$win.Show()
try {
    [void]$script:wpfApp.Run()
} finally {
    try { $bgTimer.Stop() } catch {}
    try { $notify.Visible = $false; $notify.Dispose() } catch {}
    try { $script:trayForm.Dispose() } catch {}
    Stop-Bodyguard
}
