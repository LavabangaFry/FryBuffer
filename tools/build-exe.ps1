#requires -Version 5.1
<#
    Собирает FryBuffer.exe — всю программу одним файлом: скрипты, образец
    конфига и набор эмодзи вшиваются в exe как ресурсы. Заодно рисует
    значок launcher\FryBuffer.ico. Компилятор csc входит в .NET
    Framework 4, он есть в любой Windows 10/11; ни установки, ни интернета.

    exe в репозиторий не кладётся: 5 МБ на каждое изменение раздули бы
    историю. Собирается на месте после git pull.

    Запуск:  powershell -NoProfile -File tools\build-exe.ps1
#>

$ErrorActionPreference = 'Stop'
# Вывод по-русски должен читаться и в Git Bash, и в обычной консоли
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Src  = Join-Path $Root 'launcher\FryBuffer.cs'
$Ico  = Join-Path $Root 'launcher\FryBuffer.ico'
$Out  = Join-Path $Root 'FryBuffer.exe'
$Parts = 'FryBuffer.ps1', 'core.ps1', 'native.ps1', 'ui.ps1', 'settings.ps1', 'dock.ps1'
$Steps = 6
$Clock = [Diagnostics.Stopwatch]::StartNew()

function Step([int]$N, [string]$Text) {
    Write-Host ''
    Write-Host ("[{0}/{1}] {2}" -f $N, $Steps, $Text) -ForegroundColor Cyan
}
function Ok([string]$Text) { Write-Host "      $Text" -ForegroundColor Gray }
function Fail([string]$Text) {
    Write-Host ''
    Write-Host "ОШИБКА: $Text" -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.Drawing

function New-IconPng([int]$S) {
    # Тёмная пилюля-квадрат и три кружка цветов меток — тот же образ, что у панели
    $bmp = New-Object Drawing.Bitmap $S, $S
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $r = [Math]::Max(3, [int]($S * 0.28))
    $m = [Math]::Max(0, [int]($S * 0.03))
    $w = $S - 2 * $m - 1
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc($m, $m, 2 * $r, 2 * $r, 180, 90)
    $path.AddArc($m + $w - 2 * $r, $m, 2 * $r, 2 * $r, 270, 90)
    $path.AddArc($m + $w - 2 * $r, $m + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90)
    $path.AddArc($m, $m + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $path.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#161B22'))), $path)
    $pen = New-Object Drawing.Pen ([Drawing.ColorTranslator]::FromHtml('#30363D')), ([Math]::Max(1, $S / 32))
    $g.DrawPath($pen, $path)
    $d = $S * 0.24
    $gap = $S * 0.05
    $x0 = ($S - (3 * $d + 2 * $gap)) / 2
    $y = ($S - $d) / 2
    $i = 0
    foreach ($hex in '#3FB950', '#58A6FF', '#BC8CFF') {
        $b = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($hex))
        $g.FillEllipse($b, [single]($x0 + $i * ($d + $gap)), [single]$y, [single]$d, [single]$d)
        $b.Dispose()
        $i++
    }
    $g.Dispose()
    return $bmp
}

function ConvertTo-IcoEntry($Bmp) {
    <#
        Мелкие размеры — классическим BMP внутри ICO: PNG-записи меньше
        256 px понимает не всё (System.Drawing рисует их шумом). 256 px — PNG,
        иначе файл раздувается на четверть мегабайта.
    #>
    $s = $Bmp.Width
    $ms = New-Object IO.MemoryStream
    if ($s -ge 256) {
        $Bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
        return , $ms.ToArray()
    }
    $w = New-Object IO.BinaryWriter $ms
    $w.Write([uint32]40); $w.Write([int32]$s); $w.Write([int32]($s * 2))
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
    $w.Write([uint32]($s * $s * 4)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) {
            $c = $Bmp.GetPixel($x, $y)
            $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A)
        }
    }
    # Маска прозрачности не нужна при альфа-канале, но место под неё обязано быть
    $maskRow = [int]([Math]::Ceiling($s / 32.0) * 4)
    $w.Write((New-Object byte[] ($maskRow * $s)))
    $w.Flush()
    return , $ms.ToArray()
}

Write-Host 'FryBuffer — сборка exe' -ForegroundColor White
Write-Host "Папка: $Root" -ForegroundColor Gray

# --- 1. Версия ---------------------------------------------------------------
# Дата и номер последнего коммита: по ним в трее видно, что запущена
# именно эта сборка. «+правки» — в папке есть незакоммиченные изменения.
Step 1 'Версия'
$date = Get-Date -Format 'yyyy.MM.dd'
$hash = 'без-git'
$count = 0
$dirty = $false
try {
    $info = & git -C $Root log -1 '--format=%cd|%h' '--date=format:%Y.%m.%d' 2>$null
    if ($LASTEXITCODE -eq 0 -and $info) {
        $date, $hash = ([string]$info).Split('|')
        $count = [int](& git -C $Root rev-list --count HEAD 2>$null)
        $dirty = [bool](& git -C $Root status --porcelain --untracked-files=no 2>$null)
    }
} catch { }
$Version = "$date · $hash"
if ($dirty) { $Version += ' +правки' }
$FileVer = '{0}.{1}' -f $date, [Math]::Min(65535, $count)
Ok "$Version   (в свойствах файла: $FileVer)"
if ($hash -eq 'без-git') { Ok 'git не найден — версия по сегодняшней дате' }
if ($dirty) { Ok 'есть незакоммиченные изменения — они войдут в exe' }

# --- 2. Исходники ------------------------------------------------------------
# Синтаксическая ошибка в скрипте всплыла бы только при запуске exe —
# ловим её здесь, пока понятно, в каком файле и строке
Step 2 'Проверка исходников'
foreach ($f in $Parts + 'config.example.json', 'emoji\catalog.json', 'launcher\FryBuffer.cs') {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) { Fail "нет файла $f — клон неполный, сделайте git pull" }
}
foreach ($f in $Parts) {
    $tok = $null; $err = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $f), [ref]$tok, [ref]$err)
    if ($err.Count) { Fail ("{0}, строка {1}: {2}" -f $f, $err[0].Extent.StartLineNumber, $err[0].Message) }
}
$imgCount = (Get-ChildItem -LiteralPath (Join-Path $Root 'emoji\img') -Filter *.png).Count
Ok ("{0} скриптов без ошибок, эмодзи: {1}" -f $Parts.Count, $imgCount)

# --- 3. Значок ---------------------------------------------------------------
Step 3 'Значок'
$sizes = 16, 24, 32, 48, 64, 256
$entries = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($s in $sizes) {
    $b = New-IconPng $s
    $entries.Add((ConvertTo-IcoEntry $b))
    $b.Dispose()
}
$fs = [IO.File]::Create($Ico)
$bw = New-Object IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($k = 0; $k -lt $sizes.Count; $k++) {
    $s = $sizes[$k]
    if ($s -ge 256) { $bw.Write([byte]0); $bw.Write([byte]0) } else { $bw.Write([byte]$s); $bw.Write([byte]$s) }
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$entries[$k].Length); $bw.Write([uint32]$offset)
    $offset += $entries[$k].Length
}
foreach ($e in $entries) { $bw.Write($e) }
$bw.Close()
Ok ("launcher\FryBuffer.ico, размеры {0}" -f ($sizes -join ', '))

$stage = Join-Path ([IO.Path]::GetTempPath()) ('FryBuffer-build-' + [guid]::NewGuid().ToString('N'))
$zip = "$stage.zip"
$tmpOut = "$stage.exe"
New-Item -ItemType Directory -Path $stage | Out-Null
$restart = @()
try {
    # --- 4. Эмодзи ---------------------------------------------------------------
    # Одним архивом: 1300 отдельных ресурсов сборка переносит плохо, а
    # распаковать архив запускателю — одна строка
    Step 4 'Упаковка эмодзи'
    Copy-Item -LiteralPath (Join-Path $Root 'emoji\img') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $Root 'emoji\catalog.json') -Destination $stage
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, 'Fastest', $false)
    Ok ("архив {0:N1} МБ" -f ((Get-Item $zip).Length / 1MB))

    # --- 5. Компиляция -----------------------------------------------------------
    Step 5 'Компиляция'
    $verTxt = Join-Path $stage 'version.txt'
    [IO.File]::WriteAllText($verTxt, $Version, (New-Object Text.UTF8Encoding($false)))
    # Версия в свойствах exe: правый клик → Свойства → Подробно
    $verCs = Join-Path $stage 'version.cs'
    $esc = $Version.Replace('\', '\\').Replace('"', '\"')
    [IO.File]::WriteAllText($verCs, (@(
        'using System.Reflection;'
        ('[assembly: AssemblyVersion("{0}")]' -f $FileVer)
        ('[assembly: AssemblyFileVersion("{0}")]' -f $FileVer)
        ('[assembly: AssemblyInformationalVersion("{0}")]' -f $esc)
    ) -join "`r`n"), (New-Object Text.UTF8Encoding($true)))

    $cscArgs = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/codepage:65001',
        "/win32icon:$Ico", "/out:$tmpOut",
        '/reference:System.Windows.Forms.dll', '/reference:System.IO.Compression.dll',
        '/reference:System.IO.Compression.FileSystem.dll', ('/reference:' + [PSObject].Assembly.Location))
    foreach ($f in $Parts + 'config.example.json') { $cscArgs += ('/resource:{0},{1}' -f (Join-Path $Root $f), $f) }
    $cscArgs += ('/resource:{0},emoji.zip' -f $zip)
    $cscArgs += ('/resource:{0},version.txt' -f $verTxt)
    $cscArgs += $Src, $verCs

    $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (-not (Test-Path $csc)) { Fail "не найден компилятор $csc — нужен .NET Framework 4" }
    Ok $csc
    & $csc @cscArgs
    if ($LASTEXITCODE -ne 0) { Fail "компилятор завершился с кодом $LASTEXITCODE — подробности выше" }

    # --- 6. Проверка и замена ---------------------------------------------------
    Step 6 'Проверка и замена exe'
    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($tmpOut))
    $have = $asm.GetManifestResourceNames()
    $need = $Parts + 'config.example.json', 'emoji.zip', 'version.txt'
    $miss = @($need | Where-Object { $have -notcontains $_ })
    if ($miss.Count) { Fail ("в собранном exe нет ресурсов: {0}" -f ($miss -join ', ')) }
    Ok ("внутри все {0} ресурсов" -f $need.Count)

    # Если панель запущена из этого же exe, файл занят — закрываем её на
    # время замены и потом запускаем снова уже новую
    if (Test-Path -LiteralPath $Out) {
        $locked = $false
        try { $h = [IO.File]::Open($Out, 'Open', 'ReadWrite', 'None'); $h.Close() } catch { $locked = $true }
        if ($locked) {
            $restart = @(Get-CimInstance Win32_Process -Filter "Name='FryBuffer.exe'" | Where-Object { $_.ExecutablePath -eq $Out })
            if (-not $restart.Count) { Fail "$Out занят другой программой (антивирус, проводник?) — закройте её и соберите снова" }
            Ok ("панель запущена из этого exe (pid {0}) — закрываю на время замены" -f (($restart | ForEach-Object ProcessId) -join ', '))
            $restart | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
            for ($i = 0; $i -lt 50; $i++) {
                try { $h = [IO.File]::Open($Out, 'Open', 'ReadWrite', 'None'); $h.Close(); break } catch { Start-Sleep -Milliseconds 100 }
            }
        }
    }
    Copy-Item -LiteralPath $tmpOut -Destination $Out -Force
    Ok "заменён $Out"
} finally {
    if (Test-Path -LiteralPath $stage) { [IO.Directory]::Delete($stage, $true) }
    foreach ($f in $zip, $tmpOut) { if (Test-Path -LiteralPath $f) { [IO.File]::Delete($f) } }
}

if ($restart.Count) {
    Start-Process -FilePath $Out
    Ok 'панель запущена заново'
}

Write-Host ''
Write-Host ("Готово за {0:N1} с" -f $Clock.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("  файл:   {0}" -f $Out)
Write-Host ("  размер: {0:N1} МБ" -f ((Get-Item $Out).Length / 1MB))
Write-Host ("  версия: {0}" -f $Version)
Write-Host ''
Write-Host 'Запуск exe заменяет уже работающую панель. Версию видно в меню трея' -ForegroundColor Gray
Write-Host 'и в заголовке настроек, а после обновления всплывёт «FryBuffer обновлён».' -ForegroundColor Gray