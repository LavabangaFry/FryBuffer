#requires -Version 5.1
<#
    Собирает набор цветных эмодзи для FryBuffer: картинки и каталог
    с категориями и русскими названиями.

    Запускается один раз на машине с интернетом, результат лежит в
    репозитории (папка emoji). Сам виджет в сеть не ходит: на рабочем ПК
    интернета через прокси может не быть, и кнопки остались бы пустыми.

    Откуда что:
      картинки   — Noto Color Emoji 64 px из пакета emoji-datasource-google;
      категории  — emoji-datasource (тот же порядок, что на телефоне);
      названия   — CLDR, русские аннотации.

    Запуск:  powershell -NoProfile -File tools\build-emoji.ps1
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutDir = Join-Path $Root 'emoji'
$ImgDir = Join-Path $OutDir 'img'

$DataVer = '16.0.0'
$CldrVer = '48.2.0'
$Cdn     = 'https://cdn.jsdelivr.net/npm'

# Подкатегории, которые для кнопок не нужны и только раздувают выбор:
# профессии, семьи, спорт с человечками — это сотни почти одинаковых картинок.
$SkipSub = @(
    'skin-tone', 'person-role', 'person-sport', 'person-activity', 'family',
    'person-fantasy', 'person-resting', 'person', 'subdivision-flag',
    'zodiac', 'religion', 'place-religious'
)
# Из флагов стран оставляем немногие: 259 флагов сделали бы вкладку бесполезной
$KeepFlags = @('RU', 'AE', 'BY', 'KZ', 'UA', 'US', 'GB', 'DE', 'FR', 'CN', 'TR', 'IN')

# Порядок и названия вкладок — как на клавиатуре телефона
$Tabs = [ordered]@{
    'smileys'  = @{ name = 'Смайлы и люди';      icon = '1f600'; 'from' = @('Smileys & Emotion', 'People & Body') }
    'nature'   = @{ name = 'Животные и природа'; icon = '1f43b'; 'from' = @('Animals & Nature') }
    'food'     = @{ name = 'Еда и напитки';      icon = '1f354'; 'from' = @('Food & Drink') }
    'activity' = @{ name = 'Занятия';            icon = '26bd';  from = @('Activities') }
    'travel'   = @{ name = 'Путешествия';        icon = '1f697'; 'from' = @('Travel & Places') }
    'objects'  = @{ name = 'Предметы';           icon = '1f4a1'; 'from' = @('Objects') }
    'symbols'  = @{ name = 'Символы';            icon = '2764-fe0f'; 'from' = @('Symbols') }
    'flags'    = @{ name = 'Флаги';              icon = '1f3c1'; 'from' = @('Flags') }
}

function Get-Json([string]$Url) {
    $wc = New-Object Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    return ($wc.DownloadString($Url) | ConvertFrom-Json)
}

function ConvertTo-Char([string]$Unified) {
    -join ($Unified.Split('-') | ForEach-Object { [char]::ConvertFromUtf32([Convert]::ToInt32($_, 16)) })
}

Write-Host 'Каталог emoji-datasource…'
$all = Get-Json "$Cdn/emoji-datasource@$DataVer/emoji.json"
Write-Host 'Русские названия CLDR…'
$ru  = (Get-Json "$Cdn/cldr-annotations-full@$CldrVer/annotations/ru/annotations.json").annotations.annotations
$ruD = (Get-Json "$Cdn/cldr-annotations-derived-full@$CldrVer/annotationsDerived/ru/annotations.json").annotationsDerived.annotations

function Get-RuNote([string]$Char) {
    foreach ($src in @($ru, $ruD)) {
        foreach ($k in @($Char, $Char.Replace([string][char]0xFE0F, ''))) {
            $p = $src.PSObject.Properties[$k]
            if ($p) { return $p.Value }
        }
    }
    return $null
}

$cats = [ordered]@{}
foreach ($t in $Tabs.Keys) { $cats[$t] = New-Object System.Collections.ArrayList }

function Test-Keep($e) {
    if (-not $e.has_img_google) { return $false }
    if ($SkipSub -contains $e.subcategory) { return $false }
    if ($e.subcategory -ne 'country-flag') { return $true }
    # Флаг страны — пара региональных букв, из них и берём код
    $cc = -join ($e.unified.Split('-') | ForEach-Object { [char](([Convert]::ToInt32($_, 16)) - 0x1F1E6 + 65) })
    return ($KeepFlags -contains $cc)
}

$picked = $all | Where-Object { Test-Keep $_ } | Sort-Object sort_order

foreach ($e in $picked) {
    $tab = $null
    foreach ($t in $Tabs.Keys) { if ($Tabs[$t].from -contains $e.category) { $tab = $t; break } }
    if (-not $tab) { continue }

    $char = ConvertTo-Char $e.unified
    $note = Get-RuNote $char
    $name = ''
    $words = @()
    if ($note) {
        if ($note.tts) { $name = [string]@($note.tts)[0] }
        if ($note.default) { $words += @($note.default) }
    }
    if (-not $name) { $name = ([string]$e.name).ToLower() }
    $words += @($e.short_names | ForEach-Object { $_ -replace '_', ' ' })

    [void]$cats[$tab].Add([ordered]@{
        k = [IO.Path]::GetFileNameWithoutExtension($e.image)
        e = $char
        n = $name
        w = (($words | Select-Object -Unique) -join ' ')
        q = ([string]$e.non_qualified).ToLower()
    })
}

# --- Картинки: параллельно, иначе полторы тысячи запросов идут минутами -----
New-Item -ItemType Directory -Force -Path $ImgDir | Out-Null
Add-Type -AssemblyName System.Net.Http
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(30)

$keys = @($cats.Values | ForEach-Object { $_ } | ForEach-Object { $_.k })
$keys += @($Tabs.Values | ForEach-Object { $_.icon })
$keys = @($keys | Select-Object -Unique | Where-Object { -not (Test-Path (Join-Path $ImgDir "$_.png")) })
Write-Host ("Картинок к загрузке: {0}" -f $keys.Count)

$failed = @()
for ($i = 0; $i -lt $keys.Count; $i += 32) {
    $batch = $keys[$i..([Math]::Min($i + 31, $keys.Count - 1))]
    $tasks = @{}
    foreach ($k in $batch) { $tasks[$k] = $http.GetByteArrayAsync("$Cdn/emoji-datasource-google@$DataVer/img/google/64/$k.png") }
    foreach ($k in $batch) {
        try {
            $bytes = $tasks[$k].GetAwaiter().GetResult()
            [IO.File]::WriteAllBytes((Join-Path $ImgDir "$k.png"), $bytes)
        } catch { $failed += $k }
    }
    Write-Host ("  {0}/{1}" -f [Math]::Min($i + 32, $keys.Count), $keys.Count)
}

# Без картинки эмодзи в каталоге не нужен: в кнопке он был бы пустым кружком
foreach ($t in @($cats.Keys)) {
    $keep = @($cats[$t] | Where-Object { Test-Path (Join-Path $ImgDir "$($_.k).png") })
    $cats[$t] = $keep
}

$catalog = [ordered]@{
    source = "emoji-datasource-google $DataVer (Noto Color Emoji), CLDR $CldrVer"
    tabs   = @(foreach ($t in $Tabs.Keys) {
        [ordered]@{ id = $t; name = $Tabs[$t].name; icon = $Tabs[$t].icon; items = @($cats[$t]) }
    })
}
$json = $catalog | ConvertTo-Json -Depth 6 -Compress
[IO.File]::WriteAllText((Join-Path $OutDir 'catalog.json'), $json, (New-Object Text.UTF8Encoding($false)))

$total = ($cats.Values | ForEach-Object { @($_).Count } | Measure-Object -Sum).Sum
Write-Host ("Готово: {0} эмодзи в {1} вкладках" -f $total, $Tabs.Count)
if ($failed.Count) { Write-Warning ("Не скачались: {0}" -f ($failed -join ', ')) }
