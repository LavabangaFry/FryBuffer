#requires -Version 5.1
<#
    Ядро FryBuffer без окон: конфиг, шаблоны, разбор хоткея.
    Отделено от интерфейса, чтобы проверяться тестами без WPF.
#>

# --- Шаблоны -----------------------------------------------------------------
# {date} {time} {now:формат} {clipboard} {user} {computer} {ip}
# {n} {n:000} {guid} {rand:8} {?Подпись}; {{ и }} — буквальные скобки.
# Неизвестное в фигурных скобках остаётся как есть: в тексте кнопки вполне
# может оказаться JSON, и молча выкусывать из него куски нельзя.

$script:TplPattern = '\{\{|\}\}|\{(\?[^{}]+|[A-Za-z]+(?::[^{}]*)?)\}'

function Get-TemplatePrompts {
    param([string]$Text)
    $seen = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches([string]$Text, $script:TplPattern)) {
        $body = $m.Groups[1].Value
        if ($body.StartsWith('?')) {
            $label = $body.Substring(1).Trim()
            if ($label -and -not $seen.Contains($label)) { $seen.Add($label) }
        }
    }
    return , $seen.ToArray()
}

function Test-TemplateCounter {
    param([string]$Text)
    foreach ($m in [regex]::Matches([string]$Text, $script:TplPattern)) {
        if ($m.Groups[1].Value -match '^(?i)n(:|$)') { return $true }
    }
    return $false
}

function Test-TemplateClipboard {
    param([string]$Text)
    foreach ($m in [regex]::Matches([string]$Text, $script:TplPattern)) {
        if ($m.Groups[1].Value -match '^(?i)clipboard$') { return $true }
    }
    return $false
}

function New-RandomCode {
    param([int]$Length)
    # Без похожих друг на друга символов: код из кнопки часто диктуют голосом
    $abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $buf = New-Object byte[] $Length
    $rng.GetBytes($buf)
    $rng.Dispose()
    return -join ($buf | ForEach-Object { $abc[$_ % $abc.Length] })
}

function Expand-Template {
    <#
        Ctx — хеш с ключами Now, Clipboard, User, Computer, Ip, Counter, Answers.
        Ip может быть скриптблоком: адрес ищется только если он в тексте есть.
    #>
    param([string]$Text, [hashtable]$Ctx = @{})

    $now = Get-Date
    if ($Ctx.ContainsKey('Now') -and $Ctx.Now) { $now = [datetime]$Ctx.Now }
    $answers = @{}
    if ($Ctx.ContainsKey('Answers') -and $Ctx.Answers) { $answers = $Ctx.Answers }

    $eval = {
        param($m)
        $v = $m.Value
        if ($v -eq '{{') { return '{' }
        if ($v -eq '}}') { return '}' }
        $body = $m.Groups[1].Value
        if ($body.StartsWith('?')) {
            $label = $body.Substring(1).Trim()
            if ($answers.ContainsKey($label)) { return [string]$answers[$label] }
            return ''
        }
        $name = $body
        $arg = $null
        $i = $body.IndexOf(':')
        if ($i -ge 0) { $name = $body.Substring(0, $i); $arg = $body.Substring($i + 1) }
        try {
            switch ($name.ToLowerInvariant()) {
                'date'      { if ($arg) { return $now.ToString($arg) } else { return $now.ToString('dd.MM.yyyy') } }
                'time'      { if ($arg) { return $now.ToString($arg) } else { return $now.ToString('HH:mm') } }
                'now'       { if ($arg) { return $now.ToString($arg) } else { return $now.ToString('dd.MM.yyyy HH:mm') } }
                'clipboard' { return [string]$Ctx.Clipboard }
                'user'      { if ($Ctx.ContainsKey('User')) { return [string]$Ctx.User } else { return [Environment]::UserName } }
                'computer'  { if ($Ctx.ContainsKey('Computer')) { return [string]$Ctx.Computer } else { return [Environment]::MachineName } }
                'ip'        {
                    $ip = $Ctx.Ip
                    if ($ip -is [scriptblock]) { $ip = & $ip }
                    return [string]$ip
                }
                'n'         {
                    $n = 0
                    if ($Ctx.ContainsKey('Counter')) { $n = [int]$Ctx.Counter }
                    if ($arg) { return $n.ToString($arg) } else { return [string]$n }
                }
                'guid'      { if ($arg) { return [guid]::NewGuid().ToString($arg) } else { return [guid]::NewGuid().ToString() } }
                'rand'      {
                    $len = 8
                    if ($arg -match '^\d+$') { $len = [Math]::Max(1, [Math]::Min(128, [int]$arg)) }
                    return (New-RandomCode $len)
                }
                default     { return $v }
            }
        } catch {
            # Кривой формат даты или числа — оставляем подстановку как была,
            # чтобы ошибку было видно в результате, а не получить пустоту
            return $v
        }
    }
    return [regex]::Replace([string]$Text, $script:TplPattern, [System.Text.RegularExpressions.MatchEvaluator]$eval)
}

# --- Хоткей ------------------------------------------------------------------

function ConvertFrom-Hotkey {
    <#
        «Win+Alt+V» -> @{ Mods = 0x9; Vk = 0x56; Text = 'Win+Alt+V' }.
        Пустая строка — хоткей выключен, возвращается $null.
        Без модификатора не принимается: голая буква перехватила бы набор текста.
    #>
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if (-not $t) { return $null }
    $mods = 0
    $vk = 0
    $keyName = ''
    foreach ($raw in $t.Split('+')) {
        $p = $raw.Trim()
        switch -Regex ($p) {
            '^(?i)(ctrl|control)$' { $mods = $mods -bor 0x2; continue }
            '^(?i)alt$'            { $mods = $mods -bor 0x1; continue }
            '^(?i)shift$'          { $mods = $mods -bor 0x4; continue }
            '^(?i)win$'            { $mods = $mods -bor 0x8; continue }
            '^[A-Za-z0-9]$'        { $vk = [int][char]$p.ToUpperInvariant(); $keyName = $p.ToUpperInvariant(); continue }
            '^(?i)f([1-9]|1[0-2])$' { $vk = 0x6F + [int]$Matches[1]; $keyName = 'F' + $Matches[1]; continue }
            '^(?i)space$'          { $vk = 0x20; $keyName = 'Space'; continue }
            default                { throw "Непонятная клавиша в хоткее: «$p». Пример: Win+Alt+V" }
        }
    }
    if (-not $vk) { throw "В хоткее «$t» нет основной клавиши. Пример: Win+Alt+V" }
    if (-not $mods) { throw "Хоткею «$t» нужен модификатор: Ctrl, Alt, Shift или Win" }
    $names = @()
    if ($mods -band 0x2) { $names += 'Ctrl' }
    if ($mods -band 0x8) { $names += 'Win' }
    if ($mods -band 0x1) { $names += 'Alt' }
    if ($mods -band 0x4) { $names += 'Shift' }
    $names += $keyName
    return @{ Mods = $mods; Vk = $vk; Text = ($names -join '+') }
}

# --- Конфиг ------------------------------------------------------------------

$script:LabelColors = @('', '#58A6FF', '#3FB950', '#D29922', '#F0883E', '#F85149', '#BC8CFF', '#F778BA', '#8B949E')
$script:Accents     = @('blue', 'green', 'purple', 'orange', 'pink')

function New-ClipItem {
    <#
        Кнопка. children — вложенные кнопки того же вида; они раскрываются
        веером, если задержать мышь на кружке. Уровень вложенности один:
        у вложенной кнопки своих вложенных нет.
    #>
    param([string]$Name = '', [string]$Text = '', [string]$Icon = '', [string]$Color = '', [int]$Counter = 0)
    return [ordered]@{ name = $Name; text = $Text; icon = $Icon; color = $Color; counter = $Counter; children = (New-Object System.Collections.ArrayList) }
}

function Copy-ClipItemDeep {
    <# Копия кнопки вместе с вложенными, без общих ссылок с исходной. #>
    param($It, [switch]$KeepCounter)
    $cnt = 0
    if ($KeepCounter) { $cnt = [int]$It.counter }
    $c = New-ClipItem -Name ([string]$It.name) -Text ([string]$It.text) -Icon ([string]$It.icon) -Color ([string]$It.color) -Counter $cnt
    foreach ($ch in @($It.children)) {
        if ($null -ne $ch) { [void]$c.children.Add((Copy-ClipItemDeep $ch -KeepCounter:$KeepCounter)) }
    }
    return $c
}

function ConvertTo-ClipItem {
    param($Raw, [bool]$WithChildren = $true)
    $color = [string](Get-Prop $Raw 'color')
    if ($color -and $color -notmatch '^#[0-9A-Fa-f]{6}$') { $color = '' }
    $cnt = 0
    [void][int]::TryParse([string](Get-Prop $Raw 'counter'), [ref]$cnt)
    $it = New-ClipItem -Name ([string](Get-Prop $Raw 'name')) -Text ([string](Get-Prop $Raw 'text')) `
        -Icon ([string](Get-Prop $Raw 'icon')) -Color $color -Counter $cnt
    if ($WithChildren) {
        foreach ($ch in @(Get-Prop $Raw 'children')) {
            # Глубже одного уровня не идём: веер из веера у края экрана
            # не помещается, такие кнопки просто не читаются
            if ($null -ne $ch) { [void]$it.children.Add((ConvertTo-ClipItem $ch $false)) }
        }
    }
    return $it
}

function ConvertTo-ItemJson {
    param($It)
    $o = [ordered]@{ name = $It.name; text = $It.text; icon = $It.icon; color = $It.color; counter = [int]$It.counter }
    if ($It.children -and $It.children.Count -gt 0) {
        $o.children = @(foreach ($ch in $It.children) { ConvertTo-ItemJson $ch })
    }
    return $o
}

function Get-DefaultConfig {
    return [ordered]@{
        theme       = 'auto'
        accent      = 'blue'
        size        = 'M'
        edge        = 'bottom'
        offset      = 0.5
        screen      = ''
        glass       = 'acrylic'
        tint        = 0.6
        magnify     = $true
        hideDelay   = 450
        fanDelay    = 400
        mode        = 'auto'
        hotkey      = 'Win+Alt+V'
        lastVersion = ''
        recentEmoji = @()
        items       = (New-Object System.Collections.ArrayList)
    }
}

function Get-Prop($o, [string]$Name) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($Name)) { return $o[$Name] } else { return $null } }
    $p = $o.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-ClipConfig {
    <#
        Приводит прочитанное к рабочему виду: недопустимые значения молча
        заменяются на значения по умолчанию, а не роняют запуск — конфиг
        правят и руками, и опечатка не должна оставлять человека без кнопок.
    #>
    param($Raw)
    $c = Get-DefaultConfig
    $pick = {
        param($name, $allowed)
        $v = [string](Get-Prop $Raw $name)
        if ($allowed -contains $v) { $c[$name] = $v }
    }
    & $pick 'theme'  @('dark', 'light', 'auto')
    & $pick 'accent' $script:Accents
    & $pick 'size'   @('S', 'M', 'L')
    & $pick 'edge'   @('bottom', 'top', 'left', 'right')
    & $pick 'glass'  @('acrylic', 'blur', 'none')
    & $pick 'mode'   @('auto', 'pinned', 'hidden')

    $num = {
        param($name, [double]$min, [double]$max)
        $v = Get-Prop $Raw $name
        if ($null -ne $v -and "$v" -ne '') {
            $d = 0.0
            if ([double]::TryParse(([string]$v).Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
                $c[$name] = [Math]::Max($min, [Math]::Min($max, $d))
            }
        }
    }
    & $num 'offset' 0 1
    & $num 'tint' 0.1 1
    & $num 'hideDelay' 150 3000
    $c.hideDelay = [int]$c.hideDelay
    & $num 'fanDelay' 150 1500
    $c.fanDelay = [int]$c.fanDelay

    $mg = Get-Prop $Raw 'magnify'
    if ($null -ne $mg) { $c.magnify = [bool]$mg }
    $sc = Get-Prop $Raw 'screen'
    if ($null -ne $sc) { $c.screen = [string]$sc }
    $lv = Get-Prop $Raw 'lastVersion'
    if ($null -ne $lv) { $c.lastVersion = [string]$lv }

    $hk = Get-Prop $Raw 'hotkey'
    if ($null -ne $hk) {
        try {
            $parsed = ConvertFrom-Hotkey ([string]$hk)
            if ($parsed) { $c.hotkey = $parsed.Text } else { $c.hotkey = '' }
        } catch { }
    }

    $re = Get-Prop $Raw 'recentEmoji'
    if ($re) { $c.recentEmoji = @(@($re) | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -First 24) }

    foreach ($i in @(Get-Prop $Raw 'items')) {
        if ($null -eq $i) { continue }
        [void]$c.items.Add((ConvertTo-ClipItem $i $true))
    }
    return $c
}

function Read-ClipConfig {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return (Get-DefaultConfig) }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    if (-not $text.Trim()) { return (Get-DefaultConfig) }
    try {
        $raw = $text | ConvertFrom-Json
    } catch {
        throw "config.json не читается как JSON: $($_.Exception.Message). Исправьте файл или удалите его — будет создан заново."
    }
    return (ConvertTo-ClipConfig $raw)
}

function ConvertTo-ConfigJson {
    param($Cfg)
    $o = [ordered]@{}
    foreach ($k in $Cfg.Keys) { if ($k -ne 'items') { $o[$k] = $Cfg[$k] } }
    $o.recentEmoji = @($Cfg.recentEmoji)
    $o.items = @(foreach ($i in $Cfg.items) { ConvertTo-ItemJson $i })
    return ($o | ConvertTo-Json -Depth 8)
}

function Write-ClipConfig {
    <#
        Пишем во временный файл и подменяем: если процесс упадёт посреди
        записи, на диске останется прежний целый конфиг, а не половина.
        Прежняя версия остаётся рядом как config.json.bak.
    #>
    param([string]$Path, $Cfg)
    $json = ConvertTo-ConfigJson $Cfg
    $tmp = $Path + '.tmp'
    # Остаток прошлой неудачной записи бывает с атрибутом «только чтение» —
    # тогда WriteAllText отвечает тем же «Access denied», что и закрытая папка
    if (Test-Path -LiteralPath $tmp) {
        try { [IO.File]::SetAttributes($tmp, 'Normal'); [IO.File]::Delete($tmp) } catch { }
    }
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-Path -LiteralPath $Path)) {
        [IO.File]::Move($tmp, $Path)
        return
    }
    try {
        [IO.File]::Replace($tmp, $Path, $Path + '.bak')
    } catch {
        # ReplaceFile на сетевой шаре (H: на рабочем ПК) отвечает «Access
        # denied»: ей нужно право удалять файл и переносить его атрибуты,
        # а файловый сервер этого не даёт. Тогда без атомарности: копия в
        # .bak и запись поверх. Целый текст уже лежит в .tmp, так что сбой
        # посреди записи всё равно не оставит человека без кнопок.
        try { [IO.File]::Copy($Path, $Path + '.bak', $true) } catch { }
        [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
        try { [IO.File]::Delete($tmp) } catch { }
    }
}

# --- Где хранить config.json и лог -------------------------------------------

function Test-DirWritable {
    <#
        Пробная запись, а не чтение прав: права бывают в порядке, а запись
        всё равно режет «Контролируемый доступ к папкам» Защитника или
        файловый сервер. Проверить можно только попыткой.
    #>
    param([string]$Dir)
    $probe = Join-Path $Dir ('.write-test-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($probe, 'x')
        [IO.File]::Delete($probe)
        return $true
    } catch { return $false }
}

function Resolve-DataDir {
    <#
        Папка для config.json и лога. Обычно — рядом со скриптом: так папку
        можно унести целиком. Если туда писать нельзя (папку положил
        администратор, запись режет антивирус), — %APPDATA%\FryBuffer,
        и при первом переезде туда копируется прежний config.json, чтобы
        кнопки не пропали.
    #>
    param([string]$Root, [string]$AppData = $env:APPDATA, [string]$Example = '')
    if (Test-DirWritable $Root) { return $Root }
    $dir = Join-Path $AppData 'FryBuffer'
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $dst = Join-Path $dir 'config.json'
    if (-not (Test-Path -LiteralPath $dst)) {
        $src = Join-Path $Root 'config.json'
        # До переименования программа звалась clipbuttons и хранила
        # настройки в %APPDATA%\clipbuttons — их забираем, а не начинаем с нуля
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path (Join-Path $AppData 'clipbuttons') 'config.json' }
        if (-not (Test-Path -LiteralPath $src)) { $src = $Example; if (-not $src) { $src = Join-Path $Root 'config.example.json' } }
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst }
    }
    return $dir
}

# --- Автозапуск --------------------------------------------------------------
# Через HKCU\...\Run, а не ярлыком в shell:startup: ключ не требует прав
# администратора, не зависит от расположения папки «Автозагрузка» и
# проверяется одним чтением.

$script:RunKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunName = 'FryBuffer'

function Get-AutostartCommand {
    param([string]$Root, [string]$Exe = '')
    $exe = $Exe
    if (-not $exe) { $exe = Join-Path $Root 'FryBuffer.exe' }
    if (Test-Path -LiteralPath $exe) { return ('"{0}"' -f $exe) }
    return ('wscript.exe "{0}"' -f (Join-Path $Root 'FryBuffer.vbs'))
}

function Get-AutostartState {
    <#
        On — автозапуск стоит на эту папку; Other — стоит, но на другую
        копию (папку перенесли или их две), тогда в Other её команда.
    #>
    param([string]$Root, [string]$Key = $script:RunKey, [string]$Exe = '')
    $cur = $null
    try { $cur = [string](Get-ItemPropertyValue -Path $Key -Name $script:RunName -ErrorAction Stop) } catch { }
    if (-not $cur) { return @{ On = $false; Other = '' } }
    if (-not $Exe) { $Exe = Join-Path $Root 'FryBuffer.exe' }
    $exe = $Exe.ToLowerInvariant()
    $vbs = (Join-Path $Root 'FryBuffer.vbs').ToLowerInvariant()
    $low = $cur.ToLowerInvariant()
    if ($low.Contains($exe) -or $low.Contains($vbs)) { return @{ On = $true; Other = '' } }
    return @{ On = $false; Other = $cur }
}

function Set-Autostart {
    param([string]$Root, [bool]$On, [string]$Key = $script:RunKey, [string]$Exe = '')
    if ($On) {
        if (-not (Test-Path -LiteralPath $Key)) { [void](New-Item -Path $Key -Force) }
        Set-ItemProperty -Path $Key -Name $script:RunName -Value (Get-AutostartCommand $Root $Exe)
    } else {
        Remove-ItemProperty -Path $Key -Name $script:RunName -ErrorAction SilentlyContinue
    }
}

function Move-OldAutostart {
    <#
        Автозапуск, включённый ещё под именем clipbuttons, переписывается на
        FryBuffer и эту копию программы. Иначе при входе в Windows
        запускалась бы старая версия, а новая сменяла бы её только вручную.
        Возвращает $true, если было что переносить.
    #>
    param([string]$Root, [string]$Key = $script:RunKey, [string]$Exe = '')
    $old = $null
    try { $old = Get-ItemPropertyValue -Path $Key -Name 'clipbuttons' -ErrorAction Stop } catch { }
    if (-not $old) { return $false }
    Remove-ItemProperty -Path $Key -Name 'clipbuttons' -ErrorAction SilentlyContinue
    Set-Autostart $Root $true $Key $Exe
    return $true
}

function Add-RecentEmoji {
    param($Cfg, [string]$Emoji)
    if (-not $Emoji) { return }
    $list = @($Emoji) + @($Cfg.recentEmoji | Where-Object { $_ -ne $Emoji })
    $Cfg.recentEmoji = @($list | Select-Object -First 24)
}
