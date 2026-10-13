#requires -Version 5.1
<#
    FryBuffer — ряд круглых эмодзи-кнопок у края экрана.
    В покое у края видны только цветные точки; подвели мышь — точки
    волной раскрываются в кружки. Клик кладёт текст кнопки в буфер обмена.
    Win+Alt+V открывает те же кнопки сеткой у курсора.
#>

$ErrorActionPreference = 'Stop'

# Два способа запуска. Из FryBuffer.exe: скрипты лежат в exe, запускатель
# кладёт в $ClipHost папку exe, тексты частей и папку с эмодзи. Из папки
# (FryBuffer.vbs, разработка): всё рядом с этим файлом.
if ($global:ClipHost) {
    $script:Root      = $ClipHost.Root
    $script:ExePath   = $ClipHost.Exe
    $script:EmojiRoot = $ClipHost.EmojiDir
    $script:Example   = $ClipHost.Example
} else {
    $script:Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
    $script:ExePath   = Join-Path $script:Root 'FryBuffer.exe'
    $script:EmojiRoot = Join-Path $script:Root 'emoji'
    $script:Example   = Join-Path $script:Root 'config.example.json'
}

function Get-AppVersion {
    <#
        Версия — дата и номер коммита, из которого собрано: «2026.10.13 ·
        fd34ccc». Её видно в трее, в настройках и в логе — по ней понятно,
        что запущено именно то, что собирали. В exe версию вшивает сборка,
        из папки она берётся у git; «+правки» — есть незакоммиченные изменения.
    #>
    if ($global:ClipHost -and $ClipHost.Version) { return [string]$ClipHost.Version }
    try {
        $info = & git -C $script:Root log -1 '--format=%cd|%h' '--date=format:%Y.%m.%d' 2>$null
        if ($LASTEXITCODE -eq 0 -and $info) {
            $parts = ([string]$info).Split('|')
            $v = "$($parts[0]) · $($parts[1])"
            $dirty = & git -C $script:Root status --porcelain --untracked-files=no 2>$null
            if ($dirty) { $v += ' +правки' }
            return "$v, из папки"
        }
    } catch { }
    return 'из папки'
}

function Get-Part([string]$Name) {
    <#
        Часть программы для подключения через точку. Возвращается скриптблок
        или путь, а подключает вызывающий: точка внутри функции определила
        бы всё в области этой функции, и после её выхода оно бы пропало.
    #>
    if ($global:ClipHost) { return [scriptblock]::Create([string]$ClipHost.Parts[$Name]) }
    return (Join-Path $script:Root $Name)
}

$script:CfgPath = Join-Path $script:Root 'config.json'
$script:LogPath = Join-Path $script:Root 'FryBuffer-error.log'
$script:Version = Get-AppVersion

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# --- Ошибки ------------------------------------------------------------------
# Необработанное исключение в обработчике WPF роняет процесс диалогом .NET
# без полезных подробностей. Пишем причину в файл рядом и показываем человеку.

function Write-ErrLog {
    param($Err, [string]$Where)
    try {
        $msg = if ($Err -is [System.Management.Automation.ErrorRecord]) {
            "$($Err.Exception.Message)`r`n$($Err.InvocationInfo.PositionMessage)"
        } else { [string]$Err }
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value ("{0} [{1}] [{2}] {3}" -f (Get-Date -Format 's'), $script:Version, $Where, $msg)
    } catch { }
}

function Show-Err {
    param($Err, [string]$Where)
    Write-ErrLog $Err $Where
    try {
        $text = if ($Err -is [System.Management.Automation.ErrorRecord]) { $Err.Exception.Message } else { [string]$Err }
        [void][Windows.Forms.MessageBox]::Show(
            $text + [Environment]::NewLine + [Environment]::NewLine + ('Подробности записаны в ' + $script:LogPath),
            "FryBuffer $($script:Version) — $Where", 'OK', 'Error')
    } catch { }
}

# Любая ошибка при запуске — в лог и человеку, а не тихий выход процесса
trap {
    Show-Err $_ 'запуск'
    exit 1
}

# --- Один экземпляр ----------------------------------------------------------
# Второй запуск из автозагрузки и руками дал бы две панели, которые
# перетирают друг другу config.json.

# Новый запуск сменяет уже работающую панель, а не тихо выходит: иначе
# после обновления exe на экране оставалась прежняя версия, и казалось,
# что обновление не сработало. Работающая панель следит за событием
# «уступи» и закрывается, новая дожидается мьютекса.
# Работающая версия под старым именем clipbuttons тоже уступает место:
# у неё своё событие и свой мьютекс. Ждём её выхода, чтобы две панели
# не писали в один config.json.
try {
    $oldEv = $null
    if ([Threading.EventWaitHandle]::TryOpenExisting('Local\clipbuttons-takeover', [ref]$oldEv)) {
        [void]$oldEv.Set()
        $oldMx = $null
        for ($i = 0; $i -lt 50 -and [Threading.Mutex]::TryOpenExisting('Local\clipbuttons', [ref]$oldMx); $i++) {
            $oldMx.Dispose(); Start-Sleep -Milliseconds 100
        }
        $oldEv.Dispose()
    }
} catch { }
$script:Takeover = New-Object Threading.EventWaitHandle($false, 'ManualReset', 'Local\FryBuffer-takeover')
$script:Mutex = New-Object Threading.Mutex($false, 'Local\FryBuffer')
$got = $false
try { $got = $script:Mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
if (-not $got) {
    [void]$script:Takeover.Set()
    try { $got = $script:Mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { exit 0 }
}
[void]$script:Takeover.Reset()

try {
    . (Get-Part 'core.ps1')
    . (Get-Part 'native.ps1')
    . (Get-Part 'ui.ps1')
    . (Get-Part 'settings.ps1')
} catch {
    Show-Err $_ 'загрузка'
    exit 1
}

# Конфиг и лог — рядом со скриптом, а если туда писать нельзя — в %APPDATA%
$script:DataDir = Resolve-DataDir $script:Root -Example $script:Example
$script:CfgPath = Join-Path $script:DataDir 'config.json'
$script:LogPath = Join-Path $script:DataDir 'FryBuffer-error.log'

# Без этого Windows растягивает окно картинкой и всё мылится на 125–150 %
[void][ClipNative]::SetProcessDPIAware()

# --- Конфиг ------------------------------------------------------------------
# Свежий клон приходит без config.json: он не в git, в нём личные тексты.

if (-not (Test-Path -LiteralPath $script:CfgPath)) {
    $example = $script:Example
    if (Test-Path -LiteralPath $example) { Copy-Item -LiteralPath $example -Destination $script:CfgPath }
}
try {
    $script:Cfg = Read-ClipConfig $script:CfgPath
} catch {
    # Битый файл не перезаписываем молча — откладываем в сторону, чтобы
    # можно было достать оттуда тексты кнопок
    $broken = $script:CfgPath -replace '\.json$', ('.broken-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try { Move-Item -LiteralPath $script:CfgPath -Destination $broken } catch { }
    Show-Err ("$($_.Exception.Message)`r`n`r`nФайл отложен как $([IO.Path]::GetFileName($broken)), панель запущена с чистыми настройками.") 'конфиг'
    $script:Cfg = Get-DefaultConfig
}

function Save-Config {
    try { Write-ClipConfig $script:CfgPath $script:Cfg; return } catch { $first = $_ }
    # Папка перестала принимать запись уже после запуска (антивирус,
    # отобрали права) — переезжаем в %APPDATA% молча, без окна на каждое
    # сохранение: окно здесь выскакивало на каждый клик со счётчиком
    $dir = Join-Path $env:APPDATA 'FryBuffer'
    if ($script:DataDir -ne $dir) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
            Write-ClipConfig (Join-Path $dir 'config.json') $script:Cfg
            $script:DataDir = $dir
            $script:CfgPath = Join-Path $dir 'config.json'
            $script:LogPath = Join-Path $dir 'FryBuffer-error.log'
            Write-ErrLog $first "сохранение в папку программы не удалось, настройки теперь в $dir"
            try {
                $cur = Get-CursorDip $script:Scale
                Show-Toast 'Папка программы закрыта для записи — настройки теперь в %APPDATA%\FryBuffer' $cur.X $cur.Y
            } catch { }
            return
        } catch { $first = $_ }
    }
    Show-Err $first 'сохранение config.json'
}

Update-Palette $script:Cfg

. (Get-Part 'dock.ps1')

# --- Запуск и выход ----------------------------------------------------------

function Stop-App {
    try { $script:Timer.Stop(); $script:SlowTimer.Stop() } catch { }
    try { $script:Hotkey.Dispose() } catch { }
    try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
    try { if ($script:TrayHandle -ne [IntPtr]::Zero) { [void][ClipNative]::DestroyIcon($script:TrayHandle) } } catch { }
    try { $script:Mutex.ReleaseMutex() } catch { }
    [Windows.Application]::Current.Shutdown()
}

try {
    $app = New-Object Windows.Application
    $app.ShutdownMode = 'OnExplicitShutdown'
    $app.Add_DispatcherUnhandledException({
        param($s, $e)
        Write-ErrLog $e.Exception 'необработанная ошибка'
        $e.Handled = $true
    })

    $g0 = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:Scale = $g0.DpiX / 96.0
    $g0.Dispose()

    $script:Dock.Add_SourceInitialized({
        try { [ClipNative]::MakeNoActivate((Get-DockHwnd)) } catch { Write-ErrLog $_ 'окно панели' }
    })

    $script:Tray = New-Object Windows.Forms.NotifyIcon
    $script:Tray.Visible = $true
    $script:Tray.Add_MouseUp({
        param($s, $e)
        try {
            if ($e.Button -eq 'Left') { Invoke-TrayAction 'toggle' $null }
            elseif ($e.Button -eq 'Right') { Show-TrayMenu }
        } catch { Show-Err $_ 'трей' }
    })

    $script:Hotkey = New-Object ClipHotkey
    $script:Hotkey.Add_Pressed({ try { Show-QuickGrid } catch { Write-ErrLog $_ 'хоткей: сетка' } })
    [void](Register-AppHotkey)
    try {
        if (Move-OldAutostart $script:Root -Exe $script:ExePath) { Write-ErrLog 'автозапуск перенесён с clipbuttons на FryBuffer' 'переименование' }
    } catch { Write-ErrLog $_ 'перенос автозапуска' }

    $script:Timer = New-Object Windows.Threading.DispatcherTimer
    $script:Timer.Interval = [TimeSpan]::FromMilliseconds(15)
    $script:Timer.Add_Tick({
        # Запустили новую копию — уступаем ей место
        if ($script:Takeover.WaitOne(0)) { Stop-App; return }
        try { Step-Dock } catch { Write-ErrLog $_ 'кадр панели' }
    })

    # Редкие проверки: сменилась тема Windows, разрешение или панель задач
    $script:SlowTimer = New-Object Windows.Threading.DispatcherTimer
    $script:SlowTimer.Interval = [TimeSpan]::FromSeconds(3)
    $script:SlowTimer.Add_Tick({
        try {
            if ($script:Cfg.theme -eq 'auto' -and (Get-SystemLight) -ne $script:IsLight) {
                Update-Palette $script:Cfg
                Update-AllWindowPalettes
                Set-WindowPalette $script:Dock
                Rebuild-Dock
            } elseif ((Get-WaSignature) -ne $script:WaSig) {
                Rebuild-Dock
            }
        } catch { Write-ErrLog $_ 'фоновая проверка' }
    })

    Rebuild-Dock
    if ($script:Cfg.mode -ne 'hidden') { $script:Dock.Show() }
    $script:Timer.Start()
    $script:SlowTimer.Start()

    # Запустилась другая версия, чем в прошлый раз, — сказать об этом:
    # так видно, что обновление действительно применилось
    if ([string]$script:Cfg.lastVersion -ne $script:Version) {
        $first = -not [string]$script:Cfg.lastVersion
        $script:Cfg.lastVersion = $script:Version
        Save-Config
        $vt = New-Object Windows.Threading.DispatcherTimer
        $vt.Interval = [TimeSpan]::FromSeconds(1.5)
        $vt.Tag = $first
        $vt.Add_Tick({
            param($s, $e)
            $s.Stop()
            try {
                $wa = Get-DockWorkArea
                if ($s.Tag) { $msg = "FryBuffer $($script:Version)" } else { $msg = "FryBuffer обновлён: $($script:Version)" }
                Show-Toast $msg ($wa.Left + $wa.Width / 2) ($wa.Bottom - 50)
            } catch { Write-ErrLog $_ 'уведомление о версии' }
        })
        $vt.Start()
    }

    # Каталог эмодзи — 1300 записей; читаем заранее, чтобы первое открытие
    # выбора эмодзи не подвисало
    $warm = New-Object Windows.Threading.DispatcherTimer
    $warm.Interval = [TimeSpan]::FromSeconds(2)
    $warm.Add_Tick({ param($s, $e) $s.Stop(); try { [void](Get-EmojiCatalog) } catch { Write-ErrLog $_ 'каталог эмодзи' } })
    $warm.Start()

    [void]$app.Run()
} catch {
    Show-Err $_ 'запуск'
} finally {
    try { $script:Mutex.ReleaseMutex() } catch { }
}
