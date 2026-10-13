#requires -Version 5.1
<#
    Тесты ядра FryBuffer: шаблоны, конфиг, хоткей. Без внешних модулей —
    в штатном PowerShell 5.1 Pester старый (3.4), а синтаксис 5.x с ним
    несовместим, поэтому проверки сделаны простыми функциями.

    Запуск:  powershell -NoProfile -File tests\run-tests.ps1
    Код выхода — число упавших проверок.
#>

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $Root 'core.ps1')

$script:Failed = 0
$script:Passed = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host "  ok   $Name"
    } catch {
        $script:Failed++
        Write-Host "  FAIL $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal($Expected, $Actual, [string]$What = '') {
    if ("$Expected" -cne "$Actual") { throw "$What ожидалось «$Expected», получено «$Actual»" }
}

function Assert-True($Value, [string]$What) {
    if (-not $Value) { throw "не выполнено: $What" }
}

function Assert-Throws([scriptblock]$Body, [string]$What) {
    $thrown = $false
    try { & $Body } catch { $thrown = $true }
    if (-not $thrown) { throw "ожидалось исключение: $What" }
}

$fixed = [datetime]'2026-10-07T14:05:09'
$ctx = @{ Now = $fixed; Clipboard = 'из буфера'; User = 'FryFryFry'; Computer = 'PC01'; Ip = '10.0.0.5'; Counter = 7 }

Write-Host 'Шаблоны'

Test-Case 'дата, время и формат' {
    Assert-Equal '07.10.2026' (Expand-Template '{date}' $ctx)
    Assert-Equal '14:05' (Expand-Template '{time}' $ctx)
    Assert-Equal '07.10.2026 14:05' (Expand-Template '{now}' $ctx)
    Assert-Equal '2026-10-07' (Expand-Template '{now:yyyy-MM-dd}' $ctx)
    Assert-Equal '14:05:09' (Expand-Template '{time:HH:mm:ss}' $ctx)
}

Test-Case 'буфер, пользователь, компьютер, адрес' {
    Assert-Equal 'из буфера / FryFryFry@PC01 / 10.0.0.5' (Expand-Template '{clipboard} / {user}@{computer} / {ip}' $ctx)
}

Test-Case 'имена подстановок без учёта регистра' {
    Assert-Equal '07.10.2026 FryFryFry' (Expand-Template '{DATE} {User}' $ctx)
}

Test-Case 'адрес ищется лениво, только если он в тексте' {
    $script:ipCalls = 0
    $lazy = @{ Ip = { $script:ipCalls++; '192.0.2.1' } }
    Assert-Equal 'без адреса' (Expand-Template 'без адреса' $lazy)
    Assert-Equal 0 $script:ipCalls 'вызовов поиска адреса'
    Assert-Equal '192.0.2.1' (Expand-Template '{ip}' $lazy)
    Assert-Equal 1 $script:ipCalls 'вызовов поиска адреса'
}

Test-Case 'счётчик и его формат' {
    Assert-Equal '№7' (Expand-Template '№{n}' $ctx)
    Assert-Equal 'INC-007' (Expand-Template 'INC-{n:000}' $ctx)
    Assert-True (Test-TemplateCounter 'x {n:000}') 'счётчик найден'
    Assert-True (-not (Test-TemplateCounter 'x {name}')) '{name} — не счётчик'
}

Test-Case 'guid и случайный код нужной длины' {
    Assert-True ((Expand-Template '{guid}' $ctx) -match '^[0-9a-f]{8}-[0-9a-f]{4}-') 'guid'
    Assert-True ((Expand-Template '{guid:N}' $ctx) -match '^[0-9a-f]{32}$') 'guid:N'
    Assert-Equal 6 (Expand-Template '{rand:6}' $ctx).Length 'длина {rand:6}'
    Assert-Equal 8 (Expand-Template '{rand}' $ctx).Length 'длина {rand}'
    Assert-Equal 128 (Expand-Template '{rand:5000}' $ctx).Length 'длина ограничена сверху'
}

Test-Case 'случайный код без похожих символов' {
    <#
        Код из кнопки часто диктуют голосом или переписывают с экрана:
        0/O и 1/l/I путаются, поэтому их в алфавите нет.
    #>
    $s = New-RandomCode 2000
    Assert-True ($s -cnotmatch '[0O1lI]') 'нет 0, O, 1, l, I'
}

Test-Case 'запросы при клике: порядок и без повторов' {
    $p = Get-TemplatePrompts 'Заявка {?Номер}, клиент {?Клиент}, ещё раз {?Номер}'
    Assert-Equal 2 $p.Count 'число полей'
    Assert-Equal 'Номер' $p[0]
    Assert-Equal 'Клиент' $p[1]
    $ans = $ctx.Clone(); $ans.Answers = @{ 'Номер' = 'INC-42'; 'Клиент' = 'ООО Ромашка' }
    Assert-Equal 'Заявка INC-42, клиент ООО Ромашка, ещё раз INC-42' (Expand-Template 'Заявка {?Номер}, клиент {?Клиент}, ещё раз {?Номер}' $ans)
}

Test-Case 'один запрос даёт массив, а не строку' {
    <#
        PowerShell разворачивает массив из одного элемента в скаляр, и
        тогда $p.Count у строки равен 1 случайно, а $p[0] — первая буква.
        Окно запроса рисовало поле «Н» вместо «Номер».
    #>
    $p = Get-TemplatePrompts 'x {?Номер}'
    Assert-True ($p -is [array]) 'тип — массив'
    Assert-Equal 'Номер' $p[0]
    Assert-Equal 0 (Get-TemplatePrompts 'без запросов').Count 'пустой массив'
}

Test-Case 'неизвестное и JSON остаются как есть' {
    Assert-Equal '{foo} {"a": 1}' (Expand-Template '{foo} {"a": 1}' $ctx)
}

Test-Case 'двойные скобки — буквальные' {
    Assert-Equal '{date} = 07.10.2026' (Expand-Template '{{date}} = {date}' $ctx)
}

Test-Case 'кривой формат даты не теряет текст' {
    Assert-Equal 'x {now:%} y' (Expand-Template 'x {now:%} y' $ctx)
}

Test-Case 'многострочный текст сохраняет переводы строк' {
    $t = "Добрый день!`r`nЗаявка от {date}`r`n--"
    Assert-Equal "Добрый день!`r`nЗаявка от 07.10.2026`r`n--" (Expand-Template $t $ctx)
}

Write-Host 'Хоткей'

Test-Case 'разбор и нормализация' {
    $h = ConvertFrom-Hotkey 'win+alt+v'
    Assert-Equal (0x8 -bor 0x1) $h.Mods 'модификаторы'
    Assert-Equal 0x56 $h.Vk 'клавиша'
    Assert-Equal 'Win+Alt+V' $h.Text
    Assert-Equal 'Ctrl+Shift+F5' (ConvertFrom-Hotkey 'Shift + Ctrl + f5').Text
    Assert-Equal 0x74 (ConvertFrom-Hotkey 'Ctrl+F5').Vk 'F5'
}

Test-Case 'пустой хоткей выключает' {
    Assert-True ($null -eq (ConvertFrom-Hotkey '  ')) 'null'
}

Test-Case 'без модификатора и с мусором — отказ' {
    Assert-Throws { ConvertFrom-Hotkey 'V' } 'голая буква'
    Assert-Throws { ConvertFrom-Hotkey 'Ctrl+Alt' } 'нет клавиши'
    Assert-Throws { ConvertFrom-Hotkey 'Ctrl+Enter' } 'неизвестная клавиша'
}

Write-Host 'Конфиг'

$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('FryBuffer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null

Test-Case 'нет файла — значения по умолчанию' {
    $c = Read-ClipConfig (Join-Path $tmpDir 'нет.json')
    Assert-Equal 'bottom' $c.edge
    Assert-Equal 0 $c.items.Count 'кнопок'
}

Test-Case 'запись и чтение без потерь, кириллица и эмодзи' {
    $p = Join-Path $tmpDir 'config.json'
    $c = Get-DefaultConfig
    $c.edge = 'right'; $c.offset = 0.25; $c.theme = 'light'
    [void]$c.items.Add((New-ClipItem -Name 'Шаблон ответа' -Text "Добрый день!`nЗаявка {?Номер}" -Icon ([char]::ConvertFromUtf32(0x1F4CC)) -Color '#3FB950' -Counter 3))
    Write-ClipConfig $p $c
    $r = Read-ClipConfig $p
    Assert-Equal 'right' $r.edge
    Assert-Equal 0.25 $r.offset
    Assert-Equal 1 $r.items.Count 'кнопок'
    Assert-Equal 'Шаблон ответа' $r.items[0].name
    Assert-Equal "Добрый день!`nЗаявка {?Номер}" $r.items[0].text
    Assert-Equal ([char]::ConvertFromUtf32(0x1F4CC)) $r.items[0].icon
    Assert-Equal 3 $r.items[0].counter
}

Test-Case 'одна кнопка остаётся массивом в JSON' {
    <#
        ConvertTo-Json в PowerShell 5.1 пишет массив из одного элемента
        объектом, если массив по дороге развернулся. После перезапуска
        items оказывался одним объектом, и вторая кнопка затирала первую.
    #>
    $p = Join-Path $tmpDir 'one.json'
    $c = Get-DefaultConfig
    [void]$c.items.Add((New-ClipItem -Name 'Одна' -Text 'x'))
    Write-ClipConfig $p $c
    $json = [IO.File]::ReadAllText($p)
    Assert-True ($json -match '"items":\s*\[') 'items записан массивом'
}

Test-Case 'прежняя версия остаётся в .bak' {
    $p = Join-Path $tmpDir 'bak.json'
    $c = Get-DefaultConfig
    $c.edge = 'top'; Write-ClipConfig $p $c
    $c.edge = 'left'; Write-ClipConfig $p $c
    Assert-Equal 'top' (Read-ClipConfig ($p + '.bak')).edge 'в .bak'
    Assert-Equal 'left' (Read-ClipConfig $p).edge 'в основном'
    Assert-True (-not (Test-Path ($p + '.tmp'))) 'временный файл убран'
}

Test-Case 'сохранение работает, когда подмена файла запрещена' {
    <#
        На рабочем ПК папка лежит на сетевом диске H:, и File.Replace там
        отвечает «Access to the path is denied». Дома на локальном диске
        это не воспроизводилось, а конфиг молча переставал сохраняться:
        терялись счётчики и правки. Здесь отказ подмены вызывается тем,
        что файл открыт без права на удаление — как держит его шара.
    #>
    $p = Join-Path $tmpDir 'share.json'
    $c = Get-DefaultConfig
    $c.edge = 'top'; Write-ClipConfig $p $c
    $hold = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite')
    try {
        $replaceFails = $false
        try { [IO.File]::WriteAllText("$p.probe", 'x'); [IO.File]::Replace("$p.probe", $p, $null) } catch { $replaceFails = $true }
        Assert-True $replaceFails 'условие теста: подмена файла должна отказывать'
        $c.edge = 'left'
        Write-ClipConfig $p $c
    } finally { $hold.Close() }
    Assert-Equal 'left' (Read-ClipConfig $p).edge 'новое значение записано'
    Assert-Equal 'top' (Read-ClipConfig ($p + '.bak')).edge 'прежнее — в .bak'
    Assert-True (-not (Test-Path ($p + '.tmp'))) 'временный файл убран'
}

Test-Case 'папка без права записи — конфиг переезжает в AppData с кнопками' {
    <#
        На одной из машин папку программы положили так, что создать в ней
        файл нельзя: config.json.tmp не создавался, и окно с ошибкой
        выскакивало на каждое сохранение. Права на папку при этом выглядят
        обычными — запрет ставит то Защитник, то владелец папки, поэтому
        проверяется пробной записью.
    #>
    $prog = Join-Path $tmpDir 'prog'
    $app = Join-Path $tmpDir 'appdata'
    New-Item -ItemType Directory -Path $prog, $app | Out-Null
    [IO.File]::WriteAllText((Join-Path $prog 'config.json'), '{"edge":"right","items":[{"name":"Старая кнопка","text":"t"}]}')
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls $prog /deny "${me}:(WD,AD)" | Out-Null
    try {
        Assert-True (-not (Test-DirWritable $prog)) 'условие теста: в папку не пишется'
        $dir = Resolve-DataDir $prog $app
        Assert-Equal (Join-Path $app 'FryBuffer') $dir 'папка данных'
        $c = Read-ClipConfig (Join-Path $dir 'config.json')
        Assert-Equal 'right' $c.edge 'настройки перенесены'
        Assert-Equal 'Старая кнопка' $c.items[0].name 'кнопки перенесены'
        Write-ClipConfig (Join-Path $dir 'config.json') $c
    } finally {
        & icacls $prog /remove:d $me | Out-Null
    }
    Assert-Equal $prog (Resolve-DataDir $prog $app) 'в доступную папку пишем рядом со скриптом'
}

Test-Case 'остаток .tmp «только для чтения» не мешает сохранению' {
    $p = Join-Path $tmpDir 'ro.json'
    $c = Get-DefaultConfig
    Write-ClipConfig $p $c
    [IO.File]::WriteAllText("$p.tmp", 'мусор')
    [IO.File]::SetAttributes("$p.tmp", 'ReadOnly')
    $c.edge = 'top'
    Write-ClipConfig $p $c
    Assert-Equal 'top' (Read-ClipConfig $p).edge
}

Test-Case 'автозапуск: включить, узнать свою и чужую копию, выключить' {
    $key = 'HKCU:\Software\FryBuffer-test-' + [guid]::NewGuid().ToString('N')
    $root = Join-Path $tmpDir 'prog2'
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        Assert-True (-not (Get-AutostartState $root $key).On) 'изначально выключен'
        Set-Autostart $root $true $key
        Assert-True (Get-AutostartState $root $key).On 'включён'
        Assert-True ((Get-ItemPropertyValue $key 'FryBuffer') -match 'wscript\.exe .*FryBuffer\.vbs') 'без exe — через vbs'
        [IO.File]::WriteAllText((Join-Path $root 'FryBuffer.exe'), '')
        Set-Autostart $root $true $key
        Assert-Equal ('"{0}"' -f (Join-Path $root 'FryBuffer.exe')) (Get-ItemPropertyValue $key 'FryBuffer') 'с exe — через exe'
        $other = Get-AutostartState (Join-Path $tmpDir 'другая-копия') $key
        Assert-True (-not $other.On) 'чужая копия не считается своей'
        Assert-True ($other.Other -match 'prog2') 'видно, какая копия стоит'
        Set-Autostart $root $false $key
        Assert-True (-not (Get-AutostartState $root $key).On) 'выключен'
    } finally {
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'вложенные кнопки сохраняются и читаются' {
    $p = Join-Path $tmpDir 'tree.json'
    $c = Get-DefaultConfig
    $main = New-ClipItem -Name 'Основной сервер' -Text '10.0.0.1' -Icon 'x'
    [void]$main.children.Add((New-ClipItem -Name 'Резервный' -Text '10.0.0.2' -Color '#3FB950' -Counter 5))
    [void]$main.children.Add((New-ClipItem -Name 'Тестовый' -Text '10.0.0.3'))
    [void]$c.items.Add($main)
    [void]$c.items.Add((New-ClipItem -Name 'Без детей' -Text 't'))
    Write-ClipConfig $p $c
    $r = Read-ClipConfig $p
    Assert-Equal 2 $r.items[0].children.Count 'вложенных у первой'
    Assert-Equal 'Резервный' $r.items[0].children[0].name
    Assert-Equal '#3FB950' $r.items[0].children[0].color
    Assert-Equal 5 $r.items[0].children[0].counter 'счётчик вложенной'
    Assert-Equal 0 $r.items[1].children.Count 'у второй вложенных нет'
    Assert-True ([IO.File]::ReadAllText($p) -notmatch '"children":\s*\[\s*\]') 'пустой children не пишется'
}

Test-Case 'одна вложенная кнопка остаётся массивом' {
    <#
        Та же ловушка PowerShell 5.1, что с items: массив из одного
        элемента ConvertTo-Json пишет объектом. После перезапуска единственная
        вложенная кнопка превращалась бы в поля родителя.
    #>
    $p = Join-Path $tmpDir 'one-child.json'
    $c = Get-DefaultConfig
    $m = New-ClipItem -Name 'Родитель'
    [void]$m.children.Add((New-ClipItem -Name 'Единственная' -Text 'x'))
    [void]$c.items.Add($m)
    Write-ClipConfig $p $c
    Assert-True ([IO.File]::ReadAllText($p) -match '"children":\s*\[') 'children записан массивом'
    Assert-Equal 'Единственная' (Read-ClipConfig $p).items[0].children[0].name
}

Test-Case 'глубже одного уровня не читается' {
    $raw = '{"items":[{"name":"a","children":[{"name":"b","children":[{"name":"c"}]}]}]}' | ConvertFrom-Json
    $c = ConvertTo-ClipConfig $raw
    Assert-Equal 'b' $c.items[0].children[0].name
    Assert-Equal 0 $c.items[0].children[0].children.Count 'третий уровень отброшен'
}

Test-Case 'копия кнопки не делит вложенные с оригиналом' {
    $m = New-ClipItem -Name 'Родитель' -Counter 3
    [void]$m.children.Add((New-ClipItem -Name 'Ребёнок' -Counter 7))
    $c = Copy-ClipItemDeep $m
    $c.children[0].name = 'Изменён'
    Assert-Equal 'Ребёнок' $m.children[0].name 'оригинал не тронут'
    Assert-Equal 0 $c.counter 'счётчик копии с нуля'
    Assert-Equal 7 (Copy-ClipItemDeep $m -KeepCounter).children[0].counter 'с -KeepCounter счётчик сохраняется'
}

Test-Case 'задержка веера в пределах' {
    Assert-Equal 400 (Get-DefaultConfig).fanDelay 'по умолчанию'
    Assert-Equal 1500 (ConvertTo-ClipConfig ('{"fanDelay":99999}' | ConvertFrom-Json)).fanDelay 'сверху'
    Assert-Equal 150 (ConvertTo-ClipConfig ('{"fanDelay":1}' | ConvertFrom-Json)).fanDelay 'снизу'
}

Test-Case 'автозапуск под старым именем clipbuttons переезжает на FryBuffer' {
    <#
        После переименования запись Run «clipbuttons» указывала бы на
        старый exe: при входе запускалась бы прежняя версия, и обновление
        «не работало» бы до ручного перезапуска.
    #>
    $key = 'HKCU:\Software\FryBuffer-test-' + [guid]::NewGuid().ToString('N')
    $root = Join-Path $tmpDir 'prog3'
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        New-Item -Path $key -Force | Out-Null
        Set-ItemProperty -Path $key -Name 'clipbuttons' -Value '"C:\old\clipbuttons.exe"'
        Assert-True (Move-OldAutostart $root $key) 'перенос выполнен'
        Assert-True (Get-AutostartState $root $key).On 'FryBuffer стоит в автозапуске'
        $left = $null
        try { $left = Get-ItemPropertyValue $key 'clipbuttons' -ErrorAction Stop } catch { }
        Assert-True (-not $left) 'старая запись убрана'
        Assert-True (-not (Move-OldAutostart $root $key)) 'повторно переносить нечего'
    } finally {
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'стиль и радужный цвет обводки сохраняются' {
    $p = Join-Path $tmpDir 'ring.json'
    $c = Get-DefaultConfig
    [void]$c.items.Add((New-ClipItem -Name 'Точки' -Color 'rainbow' -Ring 'dotted'))
    [void]$c.items.Add((New-ClipItem -Name 'Обычная' -Color '#3FB950'))
    $c.items[0].children.Add((New-ClipItem -Name 'Двойная' -Ring 'double')) | Out-Null
    Write-ClipConfig $p $c
    $r = Read-ClipConfig $p
    Assert-Equal 'rainbow' $r.items[0].color 'радужный цвет'
    Assert-Equal 'dotted' $r.items[0].ring 'стиль точками'
    Assert-Equal 'solid' $r.items[1].ring 'по умолчанию сплошная'
    Assert-Equal 'double' $r.items[0].children[0].ring 'стиль у вложенной'
    Assert-True ([IO.File]::ReadAllText($p) -notmatch '"ring":\s*"solid"') 'сплошная в конфиг не пишется'
    Assert-Equal 'dotted' (Copy-ClipItemDeep $r.items[0]).ring 'копия сохраняет стиль'
}

Test-Case 'неизвестный стиль и цвет обводки сбрасываются' {
    $raw = '{"items":[{"name":"a","ring":"zigzag","color":"rainbowish"}]}' | ConvertFrom-Json
    $c = ConvertTo-ClipConfig $raw
    Assert-Equal 'solid' $c.items[0].ring 'стиль'
    Assert-Equal '' $c.items[0].color 'цвет'
}

Test-Case 'файл с BOM от блокнота читается' {
    $p = Join-Path $tmpDir 'bom.json'
    [IO.File]::WriteAllText($p, '{"edge":"left","items":[{"name":"Блокнот","text":"t"}]}', (New-Object Text.UTF8Encoding($true)))
    $r = Read-ClipConfig $p
    Assert-Equal 'left' $r.edge
    Assert-Equal 'Блокнот' $r.items[0].name
}

Test-Case 'опечатки в конфиге не роняют запуск' {
    $raw = '{"edge":"diagonal","size":"XXL","offset":"7","tint":"0,3","hideDelay":5,"hotkey":"Enter","items":[{"name":"a","color":"red","counter":"abc"},null]}' | ConvertFrom-Json
    $c = ConvertTo-ClipConfig $raw
    Assert-Equal 'bottom' $c.edge 'край по умолчанию'
    Assert-Equal 'M' $c.size 'размер по умолчанию'
    Assert-Equal 1 $c.offset 'offset зажат в 0..1'
    Assert-Equal 0.3 $c.tint 'запятая как разделитель'
    Assert-Equal 150 $c.hideDelay 'нижняя граница задержки'
    Assert-Equal 'Win+Alt+V' $c.hotkey 'плохой хоткей не принят'
    Assert-Equal 1 $c.items.Count 'null-кнопка пропущена'
    Assert-Equal '' $c.items[0].color 'цвет не из #RRGGBB сброшен'
    Assert-Equal 0 $c.items[0].counter 'счётчик'
}

Test-Case 'битый JSON — понятная ошибка, а не пустой конфиг' {
    $p = Join-Path $tmpDir 'broken.json'
    [IO.File]::WriteAllText($p, '{ "items": [ ')
    $msg = ''
    try { Read-ClipConfig $p | Out-Null } catch { $msg = $_.Exception.Message }
    Assert-True ($msg -match 'config\.json') 'в сообщении назван файл'
}

Test-Case 'недавние эмодзи: без повторов, не больше 24' {
    $c = Get-DefaultConfig
    1..30 | ForEach-Object { Add-RecentEmoji $c "e$_" }
    Add-RecentEmoji $c 'e10'
    Assert-Equal 24 $c.recentEmoji.Count 'размер'
    Assert-Equal 'e10' $c.recentEmoji[0] 'последний — первым'
    Assert-Equal 1 @($c.recentEmoji | Where-Object { $_ -eq 'e10' }).Count 'без повторов'
}

Remove-Item -Recurse -Force $tmpDir

Write-Host ''
Write-Host ("Итого: {0} прошло, {1} упало" -f $script:Passed, $script:Failed)
exit $script:Failed
