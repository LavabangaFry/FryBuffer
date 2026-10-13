#requires -Version 5.1
<#
    Рисует все окна FryBuffer в PNG, не показывая их на экране:
    меню у кружка, запрос значений, сетку, трей, настройки, уведомление.
    Нужен, чтобы проверять вёрстку и тему, не отнимая фокус и мышь
    у человека за машиной. Кнопки берутся из config.example.json,
    config.json не читается и не пишется.

    Запуск:  powershell -NoProfile -STA -File tools\snapshots.ps1 -Theme dark -Out <папка>
#>
param([ValidateSet('dark', 'light')][string]$Theme = 'dark', [string]$Out = (Join-Path $env:TEMP 'FryBuffer-snapshots'), [switch]$Bare)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:CfgPath = Join-Path $env:TEMP 'FryBuffer-snapshot-config.json'
$script:SnapshotDir = $Out
$script:SnapshotNo = 0
$script:SnapshotName = 'window'
# -Bare: прозрачный фон вокруг окна — для картинок в описании
$script:SnapshotBare = [bool]$Bare
New-Item -ItemType Directory -Force -Path $Out | Out-Null

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:Errors = 0
function Write-ErrLog { param($Err, [string]$Where) $script:Errors++; Write-Host "ОШИБКА [$Where] $Err" -ForegroundColor Red; if ($Err.InvocationInfo) { Write-Host $Err.InvocationInfo.PositionMessage } }
function Show-Err { param($Err, [string]$Where) Write-ErrLog $Err $Where }
function Save-Config { }

. (Join-Path $script:Root 'core.ps1')
. (Join-Path $script:Root 'native.ps1')
. (Join-Path $script:Root 'ui.ps1')
. (Join-Path $script:Root 'settings.ps1')

$script:Cfg = Read-ClipConfig (Join-Path $script:Root 'config.example.json')
$script:Cfg.theme = $Theme
$script:Cfg.recentEmoji = @(@('1f5a5-fe0f', '1f517', '1f4e7', '1f4ac') | ForEach-Object { New-EmojiFromKey $_ })
Update-Palette $script:Cfg
. (Join-Path $script:Root 'dock.ps1')
$script:Scale = 1.0
$script:HotkeyStatus = 'Win+Alt+V работает'
$script:Version = '2026.10.13 · снимок'
Rebuild-Dock

function Get-MenuBtn($Win, [string]$Act) { @($Win.FindName('MRow').Children | Where-Object { $_.Tag.Act -eq $Act })[0] }

function Snap([string]$Name, [scriptblock]$Body) {
    $script:SnapshotName = "$Theme-$Name"
    try { & $Body } catch { Write-ErrLog $_ $Name }
}

Snap 'prompt' { [void](Show-PromptDialog @('Номер заявки', 'Клиент') 'Совиный ответ' (New-Object Windows.Rect 700, 1100, 30, 30) 'bottom') }

Snap 'menu' { Show-ItemMenu 3 }
$menu = $script:LastSnapWin
Snap 'menu-colors' { Invoke-MenuAction (Get-MenuBtn $menu 'colors'); Save-WindowSnapshot $menu }
Snap 'menu-emoji' { Invoke-MenuAction (Get-MenuBtn $menu 'emoji'); Save-WindowSnapshot $menu }
Snap 'menu-emoji-smileys' { Show-PickerTab $menu.FindName('MPicker').Content.Tag 'smileys'; Save-WindowSnapshot $menu }
Snap 'menu-delete' { Invoke-MenuAction (Get-MenuBtn $menu 'emoji'); Invoke-MenuAction (Get-MenuBtn $menu 'del'); Save-WindowSnapshot $menu }
Snap 'panel-menu' { Show-PanelMenu }
Snap 'tray' { Show-TrayMenu }
Snap 'grid' { Show-QuickGrid }
Snap 'grid-search' { $script:GridWin.FindName('GSearch').Text = 'заяв'; Save-WindowSnapshot $script:GridWin }
Snap 'toast' { Show-Toast 'Скопировано — Ctrl+V' 500 500 }
Snap 'fan' { Open-Fan 0 }
Snap 'fan-menu' { Show-ItemMenu 0 1 }
Close-Fan -Now
Snap 'grid-kids' { $script:GridWin = $null; Show-QuickGrid; Show-GridKids $script:Cfg.items[0]; Save-WindowSnapshot $script:GridWin }
Snap 'settings-tree' { Open-Settings 0 -Child 1; Save-WindowSnapshot $script:SettingsWin }
Snap 'settings-items' { Select-SettingsItem (Find-SettingsRow 3); Save-WindowSnapshot $script:SettingsWin }
Snap 'settings-new' { Add-SettingsItem; Save-WindowSnapshot $script:SettingsWin }
Snap 'settings-close-armed' { Close-Settings; Save-WindowSnapshot $script:SettingsWin }
Snap 'settings-look' { $script:SettingsState.TabLook.IsChecked = $true; Save-WindowSnapshot $script:SettingsWin }

Write-Host ("Снимков: {0}, ошибок: {1}, папка: {2}" -f $script:SnapshotNo, $script:Errors, $Out)
exit $script:Errors
