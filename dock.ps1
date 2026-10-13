#requires -Version 5.1
<#
    Панель FryBuffer: окно с кружками у края экрана, анимация,
    перетаскивание, меню-пилюли, сетка по хоткею и значок в трее.
    Подключается из FryBuffer.ps1 после чтения конфига.
#>

# --- Состояние панели --------------------------------------------------------

$script:P          = 0.0       # 0 — точки у края, 1 — раскрыта
$script:Want       = 0.0
$script:OutSince   = -1        # когда мышь ушла с панели, мс TickCount
$script:Hold       = 0         # открытые меню и окна держат панель раскрытой
$script:Circles    = New-Object System.Collections.ArrayList
$script:G          = $null
$script:Press      = $null
$script:Hover      = -1
$script:TipLock    = 0
$script:WaveOrigin = 0.0
$script:Scale      = 1.0
$script:ThemeLight = $script:IsLight
$script:WaSig      = ''

$script:Sizes = @{
    S = @{ d = 20; gap = 3; emo = 12 }
    M = @{ d = 24; gap = 4; emo = 15 }
    L = @{ d = 30; gap = 5; emo = 19 }
}
$script:Pad    = 7     # запас вокруг кружков: под увеличение, тень и точки-метку
$script:Margin = 8     # полоса у края экрана: здесь живут точки
$script:DotPx  = 5

# --- Окно панели -------------------------------------------------------------

$script:DockXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        ShowInTaskbar="False" Topmost="True" ShowActivated="False" UseLayoutRounding="False"
        Title="FryBuffer" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Grid x:Name="Root">
    <Canvas x:Name="Layer"/>
  </Grid>
</Window>
'@

$script:Dock    = [Windows.Markup.XamlReader]::Parse($script:DockXaml)
$script:Layer   = $script:Dock.FindName('Layer')
$script:DockRoot = $script:Dock.FindName('Root')
$script:Dock.Left = -10000
$script:Dock.Top  = -10000
Set-WindowPalette $script:Dock

function Get-DockHwnd { (New-Object Windows.Interop.WindowInteropHelper $script:Dock).Handle }

function Get-DockScreen {
    $all = [Windows.Forms.Screen]::AllScreens
    $s = $all | Where-Object { $_.DeviceName -eq $script:Cfg.screen } | Select-Object -First 1
    if (-not $s) { $s = [Windows.Forms.Screen]::PrimaryScreen }
    return $s
}

function Get-DockWorkArea {
    $wa = (Get-DockScreen).WorkingArea
    $k = $script:Scale
    return New-Object Windows.Rect ($wa.X / $k), ($wa.Y / $k), ($wa.Width / $k), ($wa.Height / $k)
}

function ConvertTo-WinXY {
    <# Из координат «вдоль края / от края» в координаты окна панели. #>
    param([double]$Main, [double]$Cff)
    $g = $script:G
    switch ($g.edge) {
        'top'   { return @($Main, $Cff) }
        'left'  { return @($Cff, $Main) }
        'right' { return @(($g.winW - $Cff), $Main) }
        default { return @($Main, ($g.winH - $Cff)) }
    }
}

function ConvertTo-MainCff {
    param([double]$X, [double]$Y)
    $g = $script:G
    switch ($g.edge) {
        'top'   { return @($X, $Y) }
        'left'  { return @($Y, $X) }
        'right' { return @($Y, ($g.winW - $X)) }
        default { return @($X, ($g.winH - $Y)) }
    }
}

function Update-Geometry {
    $sz = $script:Sizes[$script:Cfg.size]
    if (-not $sz) { $sz = $script:Sizes.M }
    $d = $sz.d; $gap = $sz.gap; $pad = $script:Pad; $m = $script:Margin
    $vertical = @('left', 'right') -contains $script:Cfg.edge
    $wa = Get-DockWorkArea
    $n = [Math]::Max(1, $script:Cfg.items.Count)
    if ($vertical) { $avail = $wa.Height - 40 } else { $avail = $wa.Width - 40 }
    $perLine = [Math]::Max(1, [Math]::Floor(($avail - 2 * $pad + $gap) / ($d + $gap)))
    $lines = [Math]::Ceiling($n / $perLine)
    $cols = [Math]::Min($n, $perLine)
    $capMain = 2 * $pad + $cols * $d + ($cols - 1) * $gap
    $capCross = 2 * $pad + $lines * $d + ($lines - 1) * $gap
    $winMain = $capMain
    $winCross = $capCross + $m
    if ($vertical) { $winW = $winCross; $winH = $winMain } else { $winW = $winMain; $winH = $winCross }

    $script:G = @{
        d = $d; gap = $gap; emo = $sz.emo; pad = $pad; margin = $m; edge = $script:Cfg.edge; vertical = $vertical
        perLine = $perLine; lines = $lines; capMain = $capMain; capCross = $capCross
        winW = $winW; winH = $winH; wa = $wa; n = $n
    }
    $slots = @()
    $dots = @()
    for ($k = 0; $k -lt $n; $k++) {
        $line = [Math]::Floor($k / $perLine)
        $pos = $k % $perLine
        $main = $pad + $pos * ($d + $gap) + $d / 2
        $slots += , (ConvertTo-WinXY $main ($m + $pad + $line * ($d + $gap) + $d / 2))
        $dots += , (ConvertTo-WinXY $main ($m / 2))
    }
    $script:G.slots = $slots
    $script:G.dots = $dots
}

function Set-DockPosition {
    $g = $script:G
    $wa = $g.wa
    $w = $script:Dock
    $off = [double]$script:Cfg.offset
    if ($g.vertical) {
        $top = $wa.Top + $off * $wa.Height - $g.winH / 2
        $w.Top = [Math]::Max($wa.Top + 4, [Math]::Min($top, $wa.Bottom - $g.winH - 4))
        if ($g.edge -eq 'left') { $w.Left = $wa.Left } else { $w.Left = $wa.Right - $g.winW }
    } else {
        $left = $wa.Left + $off * $wa.Width - $g.winW / 2
        $w.Left = [Math]::Max($wa.Left + 4, [Math]::Min($left, $wa.Right - $g.winW - 4))
        if ($g.edge -eq 'top') { $w.Top = $wa.Top } else { $w.Top = $wa.Bottom - $g.winH }
    }
}

function Get-RingBrush([string]$Color) {
    if ($Color) { return (New-Brush $Color) }
    return (New-Brush $script:Pal.LineStrong)
}

function Get-InwardAngle {
    <# Направление «внутрь экрана» от края панели, в градусах экрана (0 — вправо, 90 — вниз). #>
    switch ($script:Cfg.edge) { 'top' { 90 } 'left' { 0 } 'right' { 180 } default { -90 } }
}

function New-CircleVisual {
    <#
        Кружок кнопки без привязки к окну: заливка с тенью, обводка цветом
        метки, эмодзи, вспышка «скопировано». У кнопки с вложенными — точки
        по внешней кромке со стороны экрана, по одной на вложенную, но не
        больше пяти: видно, что здесь что-то спрятано.
    #>
    param($Item, [double]$D, [double]$EmoPx)
    $root = New-Object Windows.Controls.Grid
    $root.Width = $D; $root.Height = $D
    $root.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $sc = New-Object Windows.Media.ScaleTransform 1, 1
    $tr = New-Object Windows.Media.TranslateTransform 0, 0
    $tg = New-Object Windows.Media.TransformGroup
    $tg.Children.Add($sc); $tg.Children.Add($tr)
    $root.RenderTransform = $tg

    $body = New-Object Windows.Controls.Grid
    $fill = New-Object Windows.Shapes.Ellipse
    $fill.Fill = New-Brush $script:Pal.Btn 0xF8
    # Подложки под кружками нет, поэтому лёгкая тень: без неё тёмный
    # кружок теряется на тёмных обоях, светлый — на светлых
    $sh = New-Object Windows.Media.Effects.DropShadowEffect
    $sh.BlurRadius = 5; $sh.ShadowDepth = 1; $sh.Opacity = 0.45; $sh.Direction = 270
    $sh.Color = [Windows.Media.Colors]::Black
    $fill.Effect = $sh
    [void]$body.Children.Add($fill)
    $ring = New-Object Windows.Shapes.Ellipse
    $ring.StrokeThickness = 1.5
    $color = ''
    if ($Item) { $color = [string]$Item.color }
    $ring.Stroke = Get-RingBrush $color
    $ring.IsHitTestVisible = $false
    [void]$body.Children.Add($ring)
    if ($Item) {
        $emo = New-EmojiVisual ([string]$Item.icon) $EmoPx ([string]$Item.name)
    } else {
        $emo = New-EmojiVisual (New-EmojiFromKey '2795') $EmoPx
    }
    $emo.HorizontalAlignment = 'Center'; $emo.VerticalAlignment = 'Center'
    [void]$body.Children.Add($emo)

    $kids = 0
    if ($Item -and $Item.children) { $kids = $Item.children.Count }
    if ($kids -gt 0) {
        $cv = New-Object Windows.Controls.Canvas
        $cv.IsHitTestVisible = $false
        $n = [Math]::Min(5, $kids)
        $r = $D / 2 + 3
        $dotD = 3.2
        $base = Get-InwardAngle
        for ($k = 0; $k -lt $n; $k++) {
            $a = ($base + ($k - ($n - 1) / 2) * 22) * [Math]::PI / 180
            $el = New-Object Windows.Shapes.Ellipse
            $el.Width = $dotD; $el.Height = $dotD
            if ($color) { $el.Fill = New-Brush $color } else { $el.Fill = New-Brush $script:Pal.Sub }
            [Windows.Controls.Canvas]::SetLeft($el, $D / 2 + $r * [Math]::Cos($a) - $dotD / 2)
            [Windows.Controls.Canvas]::SetTop($el, $D / 2 + $r * [Math]::Sin($a) - $dotD / 2)
            [void]$cv.Children.Add($el)
        }
        [void]$body.Children.Add($cv)
    }
    [void]$root.Children.Add($body)

    $flash = New-Object Windows.Shapes.Ellipse
    $flash.Fill = New-Brush $script:Pal.Ok
    $flash.Opacity = 0
    $flash.IsHitTestVisible = $false
    $check = New-EmojiVisual (New-EmojiFromKey '2714-fe0f') $EmoPx
    $check.HorizontalAlignment = 'Center'; $check.VerticalAlignment = 'Center'
    $check.Opacity = 0
    return @{ El = $root; Sc = $sc; Tr = $tr; Body = $body; Flash = $flash; Check = $check; Ring = $ring; Color = $color }
}

function New-Circle {
    param($Item, [int]$Index)
    $g = $script:G
    $d = $g.d
    $v = New-CircleVisual $Item $d $g.emo

    # Точка, в которую кружок сжимается в покое. Тёмная обводка — чтобы
    # её было видно и на светлых обоях, и на тёмных.
    $dot = New-Object Windows.Shapes.Ellipse
    if ($v.Color) { $dot.Fill = New-Brush $v.Color } else { $dot.Fill = New-Brush $script:Pal.Sub }
    $dot.Stroke = New-Brush $script:Pal.Shade 0x99
    $dot.StrokeThickness = $d / $script:DotPx * 0.9
    $dot.IsHitTestVisible = $false
    [void]$v.El.Children.Add($dot)
    [void]$v.El.Children.Add($v.Flash)
    [void]$v.El.Children.Add($v.Check)

    [void]$script:Layer.Children.Add($v.El)
    $v.Dot = $dot
    $v.Idx = $Index
    $v.Item = $Item
    $v.SX = $script:G.slots[$Index][0]; $v.SY = $script:G.slots[$Index][1]
    $v.M = 1.0; $v.LX = -1e9; $v.LY = -1e9; $v.LS = -1.0; $v.LO = -1.0
    return $v
}
function Rebuild-Dock {
    try {
        Update-Geometry
        $g = $script:G
        $script:Layer.Children.Clear()
        $script:Circles.Clear()
        $script:Dock.Width = $g.winW
        $script:Dock.Height = $g.winH
        $script:DockRoot.Width = $g.winW
        $script:DockRoot.Height = $g.winH
        if ($script:Cfg.items.Count -eq 0) {
            [void]$script:Circles.Add((New-Circle $null 0))
        } else {
            for ($i = 0; $i -lt $script:Cfg.items.Count; $i++) {
                [void]$script:Circles.Add((New-Circle $script:Cfg.items[$i] $i))
            }
        }
        Set-DockPosition
        $script:WaSig = Get-WaSignature
        if ($script:SnapshotDir) { }
        elseif ($script:Cfg.mode -eq 'hidden') { $script:Dock.Hide() } elseif (-not $script:Dock.IsVisible) { $script:Dock.Show() }
        Update-TrayIcon
        Step-Dock -Force
    } catch { Write-ErrLog $_ 'сборка панели' }
}

function Get-WaSignature {
    try { return ((Get-DockScreen).WorkingArea.ToString() + '|' + [Windows.Forms.Screen]::AllScreens.Count) } catch { return '' }
}

# --- Анимация ----------------------------------------------------------------

function Get-EaseBack([double]$T) {
    $c1 = 1.25; $c3 = $c1 + 1; $u = $T - 1
    return 1 + $c3 * $u * $u * $u + $c1 * $u * $u
}

function Get-DisplayOrder {
    <# Порядок слотов при перетаскивании: остальные кружки расступаются. #>
    $n = $script:Circles.Count
    $order = @(0..($n - 1))
    $pr = $script:Press
    if ($pr -and $pr.Kind -eq 'item' -and $pr.Moved -and $null -ne $pr.Target -and $pr.Index -ge 0) {
        $list = New-Object System.Collections.ArrayList
        foreach ($i in $order) { if ($i -ne $pr.Index) { [void]$list.Add($i) } }
        $list.Insert([Math]::Min($pr.Target, $list.Count), $pr.Index)
        $slotOf = New-Object int[] $n
        for ($s = 0; $s -lt $n; $s++) { $slotOf[$list[$s]] = $s }
        return $slotOf
    }
    return $order
}

function Get-NearestSlot {
    param([double]$X, [double]$Y)
    $best = 0; $bd = [double]::MaxValue
    for ($k = 0; $k -lt $script:G.slots.Count; $k++) {
        $s = $script:G.slots[$k]
        $dd = ($s[0] - $X) * ($s[0] - $X) + ($s[1] - $Y) * ($s[1] - $Y)
        if ($dd -lt $bd) { $bd = $dd; $best = $k }
    }
    return $best
}

function Find-CircleAt {
    param([double]$X, [double]$Y)
    $r = $script:G.d * 0.6
    foreach ($c in $script:Circles) {
        $cx = $c.LX + $script:G.d / 2; $cy = $c.LY + $script:G.d / 2
        if ((($cx - $X) * ($cx - $X) + ($cy - $Y) * ($cy - $Y)) -le ($r * $r)) { return $c.Idx }
    }
    return -1
}

function Step-Dock {
    param([switch]$Force)
    $g = $script:G
    if (-not $g -or -not $script:Dock.IsVisible) { return }
    $w = $script:Dock
    $cur = Get-CursorDip $script:Scale
    $lx = $cur.X - $w.Left; $ly = $cur.Y - $w.Top
    $mc = ConvertTo-MainCff $lx $ly
    $main = $mc[0]; $cff = $mc[1]
    $now = [Environment]::TickCount

    # --- куда стремимся: раскрыться или спрятаться
    $inEdge = ($cff -ge -8) -and ($cff -le ($g.margin + 6)) -and ($main -ge -12) -and ($main -le ($g.capMain + 12))
    $inPanel = ($cff -ge -8) -and ($cff -le ($g.margin + $g.capCross + 16)) -and ($main -ge -16) -and ($main -le ($g.capMain + 16))
    if ($script:Cfg.mode -eq 'pinned' -or $script:Hold -gt 0 -or $script:Press -or $script:Fan) {
        $want = 1.0
        $script:OutSince = -1
    } elseif ($script:Want -lt 0.5) {
        if ($inEdge) { $want = 1.0 } else { $want = 0.0 }
        $script:OutSince = -1
    } elseif ($inPanel) {
        $want = 1.0
        $script:OutSince = -1
    } else {
        if ($script:OutSince -lt 0) { $script:OutSince = $now }
        if (($now - $script:OutSince) -ge $script:Cfg.hideDelay) { $want = 0.0 } else { $want = 1.0 }
    }
    if ($want -gt 0.5 -and $script:Want -lt 0.5 -and $script:P -lt 0.05) {
        # Волна идёт от того места, куда подвели мышь
        $script:WaveOrigin = [Math]::Max(0, [Math]::Min($main, $g.capMain))
    }
    $script:Want = $want

    $p = $script:P
    if ($want -gt $p) { $p += ($want - $p) * 0.2 } else { $p += ($want - $p) * 0.17 }
    if ([Math]::Abs($want - $p) -lt 0.004) { $p = $want }
    $moving = ($p -ne $script:P) -or $Force
    $script:P = $p

    # --- кружки
    $d = $g.d
    $n = $script:Circles.Count
    $stagger = 0.0
    if ($n -gt 1) { $stagger = 0.4 }
    $maxDist = 1.0
    foreach ($s in $g.slots) {
        if ($g.vertical) { $sm = $s[1] } else { $sm = $s[0] }
        $maxDist = [Math]::Max($maxDist, [Math]::Abs($sm - $script:WaveOrigin))
    }
    $slotOf = Get-DisplayOrder
    $pr = $script:Press
    $dragging = $pr -and $pr.Kind -eq 'item' -and $pr.Moved
    $magOn = $script:Cfg.magnify -and $p -gt 0.95 -and $inPanel -and -not $dragging
    $dotScale = $script:DotPx / $d

    foreach ($c in $script:Circles) {
        $slot = $g.slots[$slotOf[$c.Idx]]
        $tx = $slot[0]; $ty = $slot[1]
        if ($dragging -and $c.Idx -eq $pr.Index) { $tx = $lx; $ty = $ly }
        $c.SX += ($tx - $c.SX) * 0.35
        $c.SY += ($ty - $c.SY) * 0.35
        if ([Math]::Abs($tx - $c.SX) -lt 0.05) { $c.SX = $tx }
        if ([Math]::Abs($ty - $c.SY) -lt 0.05) { $c.SY = $ty }

        if ($g.vertical) { $sm = $slot[1] } else { $sm = $slot[0] }
        $f = [Math]::Abs($sm - $script:WaveOrigin) / $maxDist
        $t = 1.0
        if ($stagger -gt 0) { $t = ($p - $stagger * $f) / (1 - $stagger) }
        $t = [Math]::Max(0.0, [Math]::Min(1.0, $t))
        $eb = Get-EaseBack $t

        $dot = $g.dots[$c.Idx]
        $x = $dot[0] + ($c.SX - $dot[0]) * $eb
        $y = $dot[1] + ($c.SY - $dot[1]) * $eb

        $mt = 1.0
        if ($magOn) {
            $dx = $lx - $slot[0]; $dy = $ly - $slot[1]
            $q = [Math]::Sqrt($dx * $dx + $dy * $dy) / (1.6 * $d)
            if ($q -lt 1) { $mt = 1 + 0.2 * (1 - $q * $q) }
        }
        if ($dragging -and $c.Idx -eq $pr.Index) { $mt = 1.18 }
        $c.M += ($mt - $c.M) * 0.35
        if ([Math]::Abs($mt - $c.M) -lt 0.002) { $c.M = $mt }
        $s = ($dotScale + (1 - $dotScale) * $eb) * $c.M

        $px = $x - $d / 2; $py = $y - $d / 2
        if ([Math]::Abs($px - $c.LX) -gt 0.04 -or [Math]::Abs($py - $c.LY) -gt 0.04) {
            $c.Tr.X = $px; $c.Tr.Y = $py; $c.LX = $px; $c.LY = $py
        }
        if ([Math]::Abs($s - $c.LS) -gt 0.002) { $c.Sc.ScaleX = $s; $c.Sc.ScaleY = $s; $c.LS = $s }
        $o = [Math]::Max(0.0, [Math]::Min(1.0, $t * 2.2 - 0.25))
        if ([Math]::Abs($o - $c.LO) -gt 0.01) {
            $c.Body.Opacity = $o
            $c.Dot.Opacity = 1 - $o
            $c.LO = $o
        }
        if ($dragging -and $c.Idx -eq $pr.Index) { [Windows.Controls.Panel]::SetZIndex($c.El, 10) }
    }

    # --- подсказка над кружком под мышью
    $hov = -1
    if ($p -gt 0.95 -and -not $script:Press -and $script:Hold -eq 0) { $hov = Find-CircleAt $lx $ly }
    if ($hov -ne $script:Hover) { $script:HoverSince = $now }

    # --- веер: задержка на кружке с вложенными раскрывает их
    if ($hov -ge 0 -and $script:Cfg.items.Count -gt $hov -and $script:Cfg.items[$hov].children.Count -gt 0 -and
        ($now - $script:HoverSince) -ge $script:Cfg.fanDelay -and
        (-not $script:Fan -or $script:Fan.Parent -ne $hov -or $script:Fan.Want -lt 0.5)) {
        Open-Fan $hov
        $script:HoverSince = $now
    }
    $fanTip = Step-Fan $cur $now $hov

    if ($fanTip) {
        $script:Hover = $hov
    } elseif ($hov -ne $script:Hover) {
        $script:Hover = $hov
        if ($now -ge $script:TipLock) { Update-Tip $hov }
    } elseif ($hov -lt 0 -and $script:TipWin.IsVisible -and $now -ge $script:TipLock -and -not $script:Fan) {
        $script:TipWin.Hide()
    }

    # Редкий опрос, пока всё спрятано и спокойно: незачем крутить 60 кадров
    $busy = $moving -or $p -gt 0 -or $script:Press -or $script:Fan
    if ($busy) { $iv = 15 } else { $iv = 60 }
    if ($script:Timer.Interval.TotalMilliseconds -ne $iv) { $script:Timer.Interval = [TimeSpan]::FromMilliseconds($iv) }
}

# --- Подсказка ---------------------------------------------------------------

$script:TipBody = @'
    <StackPanel Margin="11,6,12,7" MaxWidth="340">
      <TextBlock x:Name="TipName" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
      <TextBlock x:Name="TipText" Foreground="{DynamicResource B.Sub}" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,1,0,0"/>
    </StackPanel>
'@
$script:TipWin = New-GlassWindow (New-WindowXaml $script:TipBody 9) -Radius 9 -NoActivate -Strength 0.88
$script:TipWin.ShowActivated = $false
$script:TipWin.IsHitTestVisible = $false

function Get-TipText($It) {
    $prev = Get-Preview $It.text
    if (-not $prev) {
        if ($It.children -and $It.children.Count -gt 0) { $prev = 'Клик — показать вложенные' }
        else { $prev = 'Текст не задан — правый клик, «Изменить»' }
    }
    if ($It.children -and $It.children.Count -gt 0 -and $It.text) { $prev += "  ·  задержите мышь: ещё $($It.children.Count)" }
    return $prev
}

function Get-Preview([string]$Text) {
    $first = (([string]$Text) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $first) { return '' }
    $first = $first.Trim()
    if ($first.Length -gt 60) { $first = $first.Substring(0, 60) + '…' }
    return $first
}

function Show-TipFor {
    param([int]$Idx, [string]$Name, [string]$Text)
    $c = $script:Circles | Where-Object { $_.Idx -eq $Idx } | Select-Object -First 1
    if (-not $c) { return }
    $d = $script:G.d
    $r = New-Object Windows.Rect ($script:Dock.Left + $c.SX - $d / 2), ($script:Dock.Top + $c.SY - $d / 2), $d, $d
    Show-TipAt $r $Name $Text
}

function Show-TipAt {
    param([Windows.Rect]$Rect, [string]$Name, [string]$Text)
    $tn = $script:TipWin.FindName('TipName'); $tt = $script:TipWin.FindName('TipText')
    $tn.Text = $Name
    $tt.Text = $Text
    if ($Name) { $tn.Visibility = 'Visible' } else { $tn.Visibility = 'Collapsed' }
    if ($Text) { $tt.Visibility = 'Visible' } else { $tt.Visibility = 'Collapsed' }
    if (-not $script:TipWin.IsVisible) { $script:TipWin.Left = -10000; $script:TipWin.Show() }
    $script:TipWin.UpdateLayout()
    Move-NearRect $script:TipWin $Rect $script:G.edge 12
}

function Update-Tip {
    param([int]$Idx)
    try {
        if ($Idx -lt 0) { $script:TipWin.Hide(); return }
        if ($script:Cfg.items.Count -eq 0) { Show-TipFor $Idx 'Добавить кнопку' 'Откроются настройки'; return }
        $it = $script:Cfg.items[$Idx]
        Show-TipFor $Idx ([string]$it.name) (Get-TipText $it)
    } catch { Write-ErrLog $_ 'подсказка' }
}

# --- Копирование -------------------------------------------------------------

function Get-LocalIp {
    try {
        $nics = [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' }
        # Сначала адаптер со шлюзом: у VPN и виртуальных сетей его обычно нет
        foreach ($wantGw in @($true, $false)) {
            foreach ($n in $nics) {
                $props = $n.GetIPProperties()
                $hasGw = @($props.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' }).Count -gt 0
                if ($wantGw -and -not $hasGw) { continue }
                $a = $props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                if ($a) { return $a.Address.ToString() }
            }
        }
    } catch { Write-ErrLog $_ 'поиск IP' }
    return ''
}

function Set-ClipText([string]$Text) {
    # Буфер бывает занят другой программой на долю секунды — пробуем повторно
    [Windows.Forms.Clipboard]::SetDataObject($Text, $true, 10, 60)
}

function Start-Flash {
    param($Circle)
    if (-not $Circle) { return }
    $an = New-Object Windows.Media.Animation.DoubleAnimation 0.9, 0.0, ([Windows.Duration][TimeSpan]::FromMilliseconds(650))
    $Circle.Flash.BeginAnimation([Windows.UIElement]::OpacityProperty, $an)
    $an2 = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $an2.Duration = [Windows.Duration][TimeSpan]::FromMilliseconds(750)
    [void]$an2.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame 1.0, ([Windows.Media.Animation.KeyTime][TimeSpan]::FromMilliseconds(60))))
    [void]$an2.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame 1.0, ([Windows.Media.Animation.KeyTime][TimeSpan]::FromMilliseconds(500))))
    [void]$an2.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame 0.0, ([Windows.Media.Animation.KeyTime][TimeSpan]::FromMilliseconds(750))))
    $Circle.Check.BeginAnimation([Windows.UIElement]::OpacityProperty, $an2)
}

function Restore-Foreground([IntPtr]$Hwnd) {
    try { if ($Hwnd -ne [IntPtr]::Zero -and [ClipNative]::IsWindow($Hwnd)) { [void][ClipNative]::SetForegroundWindow($Hwnd) } } catch { }
}

function Invoke-ClipItem {
    <#
        Раскрывает шаблон и кладёт результат в буфер. Anchor — где спросить
        значения для {?…}, если они в тексте есть. Возвращает $true, если
        что-то скопировано.
    #>
    param($Item, [Windows.Rect]$Anchor, [string]$Edge, [IntPtr]$PrevFg = [IntPtr]::Zero)
    if (-not $Item) { return $false }
    $it = $Item
    $text = [string]$it.text
    if (-not $text) {
        Show-Toast 'Текст не задан' ($Anchor.X + $Anchor.Width / 2) $Anchor.Y
        return $false
    }
    $answers = @{}
    $labels = Get-TemplatePrompts $text
    if ($labels.Count -gt 0) {
        if ($PrevFg -eq [IntPtr]::Zero) { $PrevFg = [ClipNative]::GetForegroundWindow() }
        $script:Hold++
        try {
            $title = [string]$it.name
            if (-not $title) { $title = 'Заполните поля' }
            $answers = Show-PromptDialog $labels $title $Anchor $Edge
        } finally { $script:Hold-- }
        Restore-Foreground $PrevFg
        if ($null -eq $answers) { return $false }
    }
    $useCounter = Test-TemplateCounter $text
    $ctx = @{ Answers = $answers; Ip = { Get-LocalIp } }
    if ($useCounter) { $ctx.Counter = [int]$it.counter + 1 }
    if (Test-TemplateClipboard $text) {
        try { $ctx.Clipboard = [Windows.Forms.Clipboard]::GetText() } catch { $ctx.Clipboard = '' }
    }
    $out = Expand-Template $text $ctx
    try {
        Set-ClipText $out
    } catch {
        Write-ErrLog $_ 'буфер обмена'
        Show-Toast 'Буфер обмена занят другой программой' ($Anchor.X + $Anchor.Width / 2) $Anchor.Y
        return $false
    }
    if ($useCounter) { $it.counter = [int]$it.counter + 1; Save-Config }
    return $true
}

function Invoke-DockCircle {
    param([int]$Idx)
    if ($script:Cfg.items.Count -eq 0) { Open-Settings -1 -NewItem; return }
    $c = $script:Circles | Where-Object { $_.Idx -eq $Idx } | Select-Object -First 1
    $it = $script:Cfg.items[$Idx]
    # Кнопка-папка без своего текста: клик сразу раскрывает вложенные
    if (-not [string]$it.text -and $it.children.Count -gt 0) { Open-Fan $Idx; return }
    $d = $script:G.d
    $r = New-Object Windows.Rect ($script:Dock.Left + $c.SX - $d / 2), ($script:Dock.Top + $c.SY - $d / 2), $d, $d
    if (Invoke-ClipItem $it $r $script:G.edge) {
        Start-Flash $c
        $script:TipLock = [Environment]::TickCount + 900
        Show-TipFor $Idx '' 'Скопировано'
    }
}

# --- Веер вложенных кнопок ---------------------------------------------------
# Задержали мышь на кружке с вложенными — они раскрываются дугой внутрь
# экрана, как радиальное меню в играх. Отдельное прозрачное окно поверх
# панели: в окне панели места под дугу нет, оно — полоска у края.

$script:Fan = $null
$script:HoverSince = 0

$script:FanXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        ShowInTaskbar="False" Topmost="True" ShowActivated="False" UseLayoutRounding="False" Title="FryBuffer">
  <Canvas x:Name="Layer"/>
</Window>
'@

function Get-FanLayout {
    <#
        Центры вложенных кружков на дуге вокруг (Cx, Cy). Дуга ±65° от
        направления внутрь экрана: шире — крайние кружки ложатся на соседей
        по панели. До семи на первой дуге, остальные на следующих, подальше.
        Если у угла экрана дуга не помещается, она поворачивается в сторону
        свободного места.
    #>
    param([double]$Cx, [double]$Cy, [int]$N, [double]$D, [Windows.Rect]$Wa)
    $theta = 65 * [Math]::PI / 180
    $step = $D + 6
    $k1 = [Math]::Min($N, 7)
    $r1 = [Math]::Max(2.5 * $D, ($k1 - 1) * $step / (2 * $theta))
    $rings = @()
    $left = $N; $r = $r1
    while ($left -gt 0) {
        $cap = [Math]::Floor(2 * $theta * $r / $step) + 1
        if ($rings.Count -eq 0) { $cap = $k1 }
        $k = [Math]::Min($left, $cap)
        $rings += , @($r, $k)
        $left -= $k
        $r += $D + 8
    }
    $base = Get-InwardAngle
    $m = $D / 2 + 4
    $best = $null
    foreach ($shift in 0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75) {
        $pts = @()
        foreach ($ring in $rings) {
            $rr = $ring[0]; $k = $ring[1]
            $span = 0.0
            if ($k -gt 1) { $span = [Math]::Min(2 * $theta, ($k - 1) * $step / $rr) }
            for ($j = 0; $j -lt $k; $j++) {
                $a = ($base + $shift) * [Math]::PI / 180
                if ($k -gt 1) { $a += -$span / 2 + $j * $span / ($k - 1) }
                $pts += , @(($Cx + $rr * [Math]::Cos($a)), ($Cy + $rr * [Math]::Sin($a)))
            }
        }
        if (-not $best) { $best = $pts }
        $ok = $true
        foreach ($q in $pts) {
            if ($q[0] -lt $Wa.Left + $m -or $q[0] -gt $Wa.Right - $m -or $q[1] -lt $Wa.Top + $m -or $q[1] -gt $Wa.Bottom - $m) { $ok = $false; break }
        }
        if ($ok) { return , $pts }
    }
    return , $best
}

function Open-Fan {
    param([int]$Idx)
    try {
        Close-Fan -Now
        $parent = $script:Cfg.items[$Idx]
        if (-not $parent -or $parent.children.Count -eq 0) { return }
        $g = $script:G
        $d = $g.d
        $slot = $g.slots[$Idx]
        $cx = $script:Dock.Left + $slot[0]; $cy = $script:Dock.Top + $slot[1]
        $pts = Get-FanLayout $cx $cy $parent.children.Count $d $g.wa
        $pad = $d / 2 + 12
        $minX = $cx; $maxX = $cx; $minY = $cy; $maxY = $cy; $rmax = 0.0
        foreach ($q in $pts) {
            $minX = [Math]::Min($minX, $q[0]); $maxX = [Math]::Max($maxX, $q[0])
            $minY = [Math]::Min($minY, $q[1]); $maxY = [Math]::Max($maxY, $q[1])
            $rmax = [Math]::Max($rmax, [Math]::Sqrt(($q[0] - $cx) * ($q[0] - $cx) + ($q[1] - $cy) * ($q[1] - $cy)))
        }
        $w = [Windows.Markup.XamlReader]::Parse($script:FanXaml)
        $w.Left = $minX - $pad; $w.Top = $minY - $pad
        $w.Width = $maxX - $minX + 2 * $pad; $w.Height = $maxY - $minY + 2 * $pad
        $layer = $w.FindName('Layer')
        $layer.Width = $w.Width; $layer.Height = $w.Height
        $list = New-Object System.Collections.ArrayList
        for ($j = 0; $j -lt $parent.children.Count; $j++) {
            $v = New-CircleVisual $parent.children[$j] $d $g.emo
            [void]$v.El.Children.Add($v.Flash)
            [void]$v.El.Children.Add($v.Check)
            [void]$layer.Children.Add($v.El)
            $v.Pos = $j
            $v.Item = $parent.children[$j]
            $v.TX = $pts[$j][0] - $w.Left; $v.TY = $pts[$j][1] - $w.Top
            $v.OX = $cx - $w.Left; $v.OY = $cy - $w.Top
            $v.M = 1.0; $v.LX = -1e9; $v.LY = -1e9; $v.LS = -1.0; $v.LO = -1.0
            [void]$list.Add($v)
        }
        $script:Fan = @{
            Win = $w; Parent = $Idx; Circles = $list; P = 0.0; Want = 1.0; Cx = $cx; Cy = $cy; Rmax = $rmax
            OutSince = -1; OtherSince = -1; CloseAt = 0; Hover = -1
        }
        $w.Add_SourceInitialized({ param($s, $e) try { [ClipNative]::MakeNoActivate((New-Object Windows.Interop.WindowInteropHelper $s).Handle) } catch { } })
        $w.Add_MouseLeftButtonUp({
            param($s, $e)
            try {
                $pt = $e.GetPosition($s)
                $j = Find-FanChildAt $pt.X $pt.Y
                if ($j -ge 0) { Invoke-FanChild $j }
            } catch { Write-ErrLog $_ 'веер: клик' }
        })
        $w.Add_MouseRightButtonUp({
            param($s, $e)
            try {
                $pt = $e.GetPosition($s)
                $j = Find-FanChildAt $pt.X $pt.Y
                if ($j -ge 0) { Show-ItemMenu $script:Fan.Parent $j }
            } catch { Write-ErrLog $_ 'веер: правый клик' }
        })
        $script:TipWin.Hide()
        if ($script:SnapshotDir) {
            Update-FanVisual 1.0 -1
            Show-AppWindow $w
            return
        }
        $w.Show()
    } catch { Write-ErrLog $_ 'веер' }
}

function Close-Fan {
    param([switch]$Now)
    $f = $script:Fan
    if (-not $f) { return }
    if ($Now) {
        $script:Fan = $null
        try { $f.Win.Close() } catch { }
        $script:HoverSince = [Environment]::TickCount
    } else {
        $f.Want = 0.0
    }
}

function Find-FanChildAt {
    param([double]$X, [double]$Y)
    $f = $script:Fan
    if (-not $f -or $f.P -lt 0.6) { return -1 }
    $r = $script:G.d * 0.62
    foreach ($c in $f.Circles) {
        if ((($c.TX - $X) * ($c.TX - $X) + ($c.TY - $Y) * ($c.TY - $Y)) -le ($r * $r)) { return $c.Pos }
    }
    return -1
}

function Get-FanChildRect([int]$Pos) {
    $f = $script:Fan
    $c = $f.Circles[$Pos]
    $d = $script:G.d
    return New-Object Windows.Rect ($f.Win.Left + $c.TX - $d / 2), ($f.Win.Top + $c.TY - $d / 2), $d, $d
}

function Invoke-FanChild {
    param([int]$Pos)
    $f = $script:Fan
    $c = $f.Circles[$Pos]
    $r = Get-FanChildRect $Pos
    if (Invoke-ClipItem $c.Item $r $script:G.edge) {
        Start-Flash $c
        $script:TipLock = [Environment]::TickCount + 900
        Show-TipAt $r '' 'Скопировано'
        # Веер держится, пока видна вспышка, — иначе непонятно, что сработало
        if ($script:Fan) { $script:Fan.CloseAt = [Environment]::TickCount + 650 }
    }
}

function Update-FanVisual {
    param([double]$P, [int]$Hov)
    $f = $script:Fan
    $d = $script:G.d
    $n = $f.Circles.Count
    $stagger = 0.0
    if ($n -gt 1) { $stagger = 0.35 }
    for ($i = 0; $i -lt $n; $i++) {
        $c = $f.Circles[$i]
        $t = 1.0
        if ($stagger -gt 0) { $t = ($P - $stagger * $i / ($n - 1)) / (1 - $stagger) }
        $t = [Math]::Max(0.0, [Math]::Min(1.0, $t))
        $eb = Get-EaseBack $t
        $mt = 1.0
        if ($i -eq $Hov -and $script:Cfg.magnify) { $mt = 1.18 }
        $c.M += ($mt - $c.M) * 0.35
        if ([Math]::Abs($mt - $c.M) -lt 0.002) { $c.M = $mt }
        $x = $c.OX + ($c.TX - $c.OX) * $eb - $d / 2
        $y = $c.OY + ($c.TY - $c.OY) * $eb - $d / 2
        $s = (0.25 + 0.75 * $eb) * $c.M
        if ([Math]::Abs($x - $c.LX) -gt 0.04 -or [Math]::Abs($y - $c.LY) -gt 0.04) { $c.Tr.X = $x; $c.Tr.Y = $y; $c.LX = $x; $c.LY = $y }
        if ([Math]::Abs($s - $c.LS) -gt 0.002) { $c.Sc.ScaleX = $s; $c.Sc.ScaleY = $s; $c.LS = $s }
        $o = [Math]::Min(1.0, $t * 2.5)
        if ([Math]::Abs($o - $c.LO) -gt 0.01) { $c.El.Opacity = $o; $c.LO = $o }
    }
}

function Step-Fan {
    <#
        Кадр веера. Веер держится, пока мышь на нём или на родителе (с
        запасом на путь между ними); уходит, если мышь ушла совсем или
        задержалась на другом кружке панели. Возвращает $true, если мышь
        над вложенным кружком, — тогда подсказку показывает веер.
    #>
    param([Windows.Point]$Cur, [int]$Now, [int]$DockHov)
    $f = $script:Fan
    if (-not $f) { return $false }
    $w = $f.Win
    $lx = $Cur.X - $w.Left; $ly = $Cur.Y - $w.Top
    $hov = Find-FanChildAt $lx $ly
    $dx = $Cur.X - $f.Cx; $dy = $Cur.Y - $f.Cy
    $inside = ($hov -ge 0) -or ([Math]::Sqrt($dx * $dx + $dy * $dy) -le ($f.Rmax + $script:G.d * 0.7))
    if ($f.Want -gt 0.5) {
        if ($f.CloseAt -gt 0) {
            if ($Now -ge $f.CloseAt) { $f.Want = 0.0 }
        } elseif ($script:Hold -gt 0) {
            $f.OutSince = -1
        } elseif ($DockHov -ge 0 -and $DockHov -ne $f.Parent) {
            if ($f.OtherSince -lt 0) { $f.OtherSince = $Now }
            if (($Now - $f.OtherSince) -gt 180) { $f.Want = 0.0 }
        } elseif ($inside) {
            $f.OutSince = -1; $f.OtherSince = -1
        } else {
            if ($f.OutSince -lt 0) { $f.OutSince = $Now }
            if (($Now - $f.OutSince) -gt 300) { $f.Want = 0.0 }
        }
        if ($script:P -lt 0.5) { $f.Want = 0.0 }
    }
    $p = $f.P
    $p += ($f.Want - $p) * 0.25
    if ([Math]::Abs($f.Want - $p) -lt 0.01) { $p = $f.Want }
    $f.P = $p
    if ($f.Want -lt 0.5) { $hov = -1 }
    Update-FanVisual $p $hov

    if ($hov -ne $f.Hover) {
        $f.Hover = $hov
        if ($Now -ge $script:TipLock) {
            if ($hov -ge 0) {
                $it = $f.Circles[$hov].Item
                Show-TipAt (Get-FanChildRect $hov) ([string]$it.name) (Get-TipText $it)
            } else {
                $script:TipWin.Hide()
            }
        }
    }
    if ($p -le 0 -and $f.Want -lt 0.5) { Close-Fan -Now; return $false }
    return ($hov -ge 0)
}
# --- Мышь на панели ----------------------------------------------------------

$script:Dock.Add_MouseLeftButtonDown({
    param($s, $e)
    try {
        $pt = $e.GetPosition($script:Dock)
        $idx = Find-CircleAt $pt.X $pt.Y
        # Ctrl + перетаскивание любого кружка двигает всю панель: фона между
        # кружками нет, ухватиться больше не за что
        $kind = 'panel'
        $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
        if ($idx -ge 0 -and -not $ctrl) { $kind = 'item' }
        if ($idx -lt 0 -and -not $ctrl) { return }
        $cur = Get-CursorDip $script:Scale
        $script:Press = @{ Kind = $kind; Index = $idx; X = $pt.X; Y = $pt.Y; SX = $cur.X; SY = $cur.Y; L = $script:Dock.Left; T = $script:Dock.Top; Moved = $false; Target = $null }
        [void]$script:Dock.CaptureMouse()
        $script:TipWin.Hide()
    } catch { Write-ErrLog $_ 'нажатие' }
})

$script:Dock.Add_MouseMove({
    param($s, $e)
    try {
        $pr = $script:Press
        if (-not $pr) { return }
        $cur = Get-CursorDip $script:Scale
        $dx = $cur.X - $pr.SX; $dy = $cur.Y - $pr.SY
        if (-not $pr.Moved -and ($dx * $dx + $dy * $dy) -gt 25) { $pr.Moved = $true }
        if (-not $pr.Moved) { return }
        if ($pr.Kind -eq 'item' -and $script:Cfg.items.Count -gt 1) {
            $pt = $e.GetPosition($script:Dock)
            $pr.Target = Get-NearestSlot $pt.X $pt.Y
        } elseif ($pr.Kind -eq 'panel' -or $script:Cfg.items.Count -le 1) {
            # Всю панель можно утащить к любому краю любого монитора
            $pr.Kind = 'panel'
            $script:Dock.Left = $pr.L + $dx
            $script:Dock.Top = $pr.T + $dy
        }
    } catch { Write-ErrLog $_ 'перетаскивание' }
})

function Complete-PanelDrag {
    $cur = Get-CursorDip $script:Scale
    $k = $script:Scale
    $scr = [Windows.Forms.Screen]::FromPoint((New-Object Drawing.Point ([int]($cur.X * $k)), ([int]($cur.Y * $k))))
    $wa = $scr.WorkingArea
    $wa = New-Object Windows.Rect ($wa.X / $k), ($wa.Y / $k), ($wa.Width / $k), ($wa.Height / $k)
    $dist = @{
        bottom = $wa.Bottom - $cur.Y; top = $cur.Y - $wa.Top
        left = $cur.X - $wa.Left; right = $wa.Right - $cur.X
    }
    $edge = ($dist.GetEnumerator() | Sort-Object Value | Select-Object -First 1).Key
    $script:Cfg.edge = $edge
    $script:Cfg.screen = $scr.DeviceName
    if (@('left', 'right') -contains $edge) { $off = ($cur.Y - $wa.Top) / $wa.Height } else { $off = ($cur.X - $wa.Left) / $wa.Width }
    $script:Cfg.offset = [Math]::Round([Math]::Max(0, [Math]::Min(1, $off)), 3)
    Save-Config
    Rebuild-Dock
}

$script:Dock.Add_MouseLeftButtonUp({
    param($s, $e)
    $pr = $script:Press
    $script:Press = $null
    try { $script:Dock.ReleaseMouseCapture() } catch { }
    if (-not $pr) { return }
    try {
        if (-not $pr.Moved) {
            if ($pr.Kind -eq 'item') { Invoke-DockCircle $pr.Index }
            return
        }
        if ($pr.Kind -eq 'panel') { Complete-PanelDrag; return }
        if ($null -ne $pr.Target -and $pr.Target -ne $pr.Index) {
            $it = $script:Cfg.items[$pr.Index]
            $script:Cfg.items.RemoveAt($pr.Index)
            $script:Cfg.items.Insert($pr.Target, $it)
            Save-Config
            Rebuild-Dock
        } else {
            Step-Dock -Force
        }
    } catch { Write-ErrLog $_ 'отпускание' }
})

$script:Dock.Add_LostMouseCapture({
    # Захват мог уйти без отпускания кнопки (Alt+Tab посреди перетаскивания)
    if ($script:Press -and [Windows.Input.Mouse]::LeftButton -ne "Pressed") { $script:Press = $null }
})

$script:Dock.Add_MouseRightButtonUp({
    param($s, $e)
    try {
        $pt = $e.GetPosition($script:Dock)
        $idx = Find-CircleAt $pt.X $pt.Y
        if ($script:SettingsWin) { Open-Settings $idx; return }
        $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
        if ($idx -ge 0 -and $script:Cfg.items.Count -gt 0 -and -not $ctrl) { Show-ItemMenu $idx } else { Show-PanelMenu }
    } catch { Write-ErrLog $_ 'правый клик' }
})

# --- Меню-пилюля у кружка ----------------------------------------------------
# Вместо списка — ряд круглых значков, как на телефоне. Цвет и эмодзи
# раскрываются тут же, под рядом, без отдельных окон.

$script:MenuBody = @'
    <StackPanel Margin="6">
      <StackPanel x:Name="MRow" Orientation="Horizontal" HorizontalAlignment="Center"/>
      <TextBlock x:Name="MNote" Style="{StaticResource Hint}" HorizontalAlignment="Center" Margin="8,4,8,2" Visibility="Collapsed"/>
      <WrapPanel x:Name="MColors" HorizontalAlignment="Center" Margin="6,6,6,2" Visibility="Collapsed"/>
      <ContentControl x:Name="MPicker" Margin="6,6,6,4" Visibility="Collapsed"/>
    </StackPanel>
'@

function New-MenuButton {
    param($Win, [string]$Key, [string]$Tip, [string]$Act, $Data)
    $b = New-Object Windows.Controls.Button
    $b.Style = $Win.FindResource('Round')
    $b.Content = New-EmojiVisual (New-EmojiFromKey $Key) 20
    $b.ToolTip = $Tip
    $b.Tag = @{ Act = $Act; Data = $Data; Win = $Win }
    $b.Add_Click({ param($s, $e) try { Invoke-MenuAction $s } catch { Write-ErrLog $_ 'действие меню' } })
    return $b
}

function Open-Popup {
    <# Общие правила для меню: держат панель раскрытой, закрываются при уходе фокуса. #>
    param($Win, [Windows.Rect]$Anchor, [string]$Edge)
    $Win.Tag.Anchor = $Anchor
    $Win.Tag.Edge = $Edge
    $Win.Tag.PrevFg = [ClipNative]::GetForegroundWindow()
    $Win.Tag.KeepFg = $false
    $script:Hold++
    $Win.Add_Deactivated({ param($s, $e) try { if ($s.IsVisible) { $s.Close() } } catch { } })
    $Win.Add_Closed({
        param($s, $e)
        $script:Hold = [Math]::Max(0, $script:Hold - 1)
        if (-not $s.Tag.KeepFg) { Restore-Foreground $s.Tag.PrevFg }
    })
    $Win.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $s.Close() } })
    $Win.Add_SizeChanged({ param($s, $e) try { Move-NearRect $s $s.Tag.Anchor $s.Tag.Edge } catch { } })
    $Win.Left = -10000; $Win.Top = -10000
    Show-AppWindow $Win
    [void]$Win.Activate()
}

function Get-CircleRect([int]$Idx) {
    $c = $script:Circles | Where-Object { $_.Idx -eq $Idx } | Select-Object -First 1
    $d = $script:G.d
    if (-not $c) { $cur = Get-CursorDip $script:Scale; return New-Object Windows.Rect $cur.X, $cur.Y, 1, 1 }
    return New-Object Windows.Rect ($script:Dock.Left + $c.SX - $d / 2), ($script:Dock.Top + $c.SY - $d / 2), $d, $d
}

function Show-ItemMenu {
    <#
        Меню у кружка. Child >= 0 — у вложенного кружка веера: тогда правится
        список вложенных этого родителя, а не кнопки панели.
    #>
    param([int]$Idx, [int]$Child = -1)
    $script:TipWin.Hide()
    $w = New-GlassWindow (New-WindowXaml $script:MenuBody 23) -Radius 23 -Strength 0.86
    if ($Child -ge 0) {
        $w.Tag.List = $script:Cfg.items[$Idx].children
        $w.Tag.Pos = $Child
        $anchor = Get-FanChildRect $Child
    } else {
        $w.Tag.List = $script:Cfg.items
        $w.Tag.Pos = $Idx
        $anchor = Get-CircleRect $Idx
    }
    $w.Tag.Parent = $Idx
    $w.Tag.Child = $Child
    $it = $w.Tag.List[$w.Tag.Pos]
    $row = $w.FindName('MRow')
    [void]$row.Children.Add((New-MenuButton $w '270f-fe0f' 'Изменить' 'edit' $null))
    [void]$row.Children.Add((New-MenuButton $w '1f600' 'Сменить эмодзи' 'emoji' $null))
    [void]$row.Children.Add((New-MenuButton $w '1f3a8' 'Цвет обводки' 'colors' $null))
    [void]$row.Children.Add((New-MenuButton $w '1f4cb' 'Дублировать' 'dup' $null))
    if ($Child -lt 0) { [void]$row.Children.Add((New-MenuButton $w '1f4c2' 'Добавить вложенную (раскроется веером)' 'addchild' $null)) }
    [void]$row.Children.Add((New-MenuButton $w '1f5d1-fe0f' 'Удалить' 'del' $null))

    $colors = $w.FindName('MColors')
    foreach ($hex in $script:LabelColors) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $w.FindResource('Dot')
        $rb.GroupName = 'mc'
        if ($hex) { $rb.Background = New-Brush $hex } else { $rb.Background = New-Brush $script:Pal.Btn; $rb.Content = '×'; $rb.ToolTip = 'Без цвета' }
        if ($hex -eq [string]$it.color) { $rb.IsChecked = $true }
        $rb.Tag = @{ Hex = $hex; Win = $w }
        $rb.Add_Click({
            param($s, $e)
            try {
                $mw = $s.Tag.Win
                $mw.Tag.List[$mw.Tag.Pos].color = $s.Tag.Hex
                Save-Config
                $mw.Close()
                Close-Fan -Now
                Rebuild-Dock
            } catch { Write-ErrLog $_ 'цвет кнопки' }
        })
        [void]$colors.Children.Add($rb)
    }
    Open-Popup $w $anchor $script:G.edge
}
function Show-PanelMenu {
    $script:TipWin.Hide()
    $w = New-GlassWindow (New-WindowXaml $script:MenuBody 23) -Radius 23 -Strength 0.86
    $row = $w.FindName('MRow')
    [void]$row.Children.Add((New-MenuButton $w '2795' 'Новая кнопка' 'new' $null))
    [void]$row.Children.Add((New-MenuButton $w '2699-fe0f' 'Настройки' 'settings' $null))
    if ($script:Cfg.mode -eq 'pinned') {
        [void]$row.Children.Add((New-MenuButton $w '1f4cc' 'Открепить: прятать к краю' 'unpin' $null))
    } else {
        [void]$row.Children.Add((New-MenuButton $w '1f4cc' 'Закрепить открытой' 'pin' $null))
    }
    [void]$row.Children.Add((New-MenuButton $w '1f648' 'Скрыть панель (останется Win+Alt+V и трей)' 'hide' $null))
    $cur = Get-CursorDip $script:Scale
    Open-Popup $w (New-Object Windows.Rect ($cur.X - 4), ($cur.Y - 4), 8, 8) $script:G.edge
}

function Invoke-MenuAction {
    param($Btn)
    $t = $Btn.Tag
    $w = $t.Win
    switch ($t.Act) {
        'edit'     { $w.Tag.KeepFg = $true; $w.Close(); Close-Fan -Now; Open-Settings $w.Tag.Parent -Child $w.Tag.Child }
        'addchild' { $w.Tag.KeepFg = $true; $w.Close(); Close-Fan -Now; Open-Settings $w.Tag.Parent -NewChild }
        'settings' { $w.Tag.KeepFg = $true; $w.Close(); Open-Settings -1 }
        'new'      { $w.Tag.KeepFg = $true; $w.Close(); Open-Settings -1 -NewItem }
        'pin'      { $w.Close(); $script:Cfg.mode = 'pinned'; Save-Config; Rebuild-Dock }
        'unpin'    { $w.Close(); $script:Cfg.mode = 'auto'; Save-Config; Rebuild-Dock }
        'hide'     { $w.Close(); $script:Cfg.mode = 'hidden'; Save-Config; Rebuild-Dock }
        'dup'      {
            $list = $w.Tag.List; $i = $w.Tag.Pos
            $list.Insert($i + 1, (Copy-ClipItemDeep $list[$i]))
            Save-Config
            $w.Close()
            Close-Fan -Now
            Rebuild-Dock
        }
        'del'      {
            # Удаление — со второго нажатия: промах по соседнему значку
            # не должен стоить кнопки с длинным шаблоном
            $list = $w.Tag.List; $i = $w.Tag.Pos
            if ($w.Tag.DelArmed) {
                $list.RemoveAt($i)
                Save-Config
                $w.Close()
                Close-Fan -Now
                Rebuild-Dock
            } else {
                $w.Tag.DelArmed = $true
                $Btn.Background = New-Brush $script:Pal.Err 0x40
                $note = $w.FindName('MNote')
                $name = [string]$list[$i].name
                $what = 'удалить'
                if ($name) { $what = "удалить «$name»" }
                $kids = $list[$i].children.Count
                if ($kids -gt 0) { $what += " вместе с вложенными ($kids)" }
                $note.Text = "Нажмите ещё раз, чтобы $what"
                $note.Visibility = 'Visible'
            }
        }
        'colors'   {
            $p = $w.FindName('MColors')
            if ($p.Visibility -eq 'Visible') { $p.Visibility = 'Collapsed' } else { $p.Visibility = 'Visible'; $w.FindName('MPicker').Visibility = 'Collapsed' }
        }
        'emoji'    {
            $host_ = $w.FindName('MPicker')
            if ($host_.Visibility -eq 'Visible') { $host_.Visibility = 'Collapsed'; Update-MenuShape $w; return }
            if (-not $host_.Content) {
                $host_.Content = New-EmojiPicker -OnPick {
                    param($st, $em)
                    $mw = $st.Context.Win
                    $mw.Tag.List[$mw.Tag.Pos].icon = $em
                    Save-Config
                    $mw.Close()
                    Close-Fan -Now
                    Rebuild-Dock
                } -Context @{ Win = $w } -Cols 9 -Cell 34 -Rows 6
            }
            $w.FindName('MColors').Visibility = 'Collapsed'
            $host_.Visibility = 'Visible'
            $search = $host_.Content.FindName('PkSearch')
            if ($search) { [void]$search.Focus() }
            Update-MenuShape $w
        }
    }
}
function Update-MenuShape {
    <# Пилюля с раскрытым выбором эмодзи — уже карточка: углы мягче. #>
    param($Win)
    $r = 23
    if ($Win.FindName('MPicker').Visibility -eq 'Visible') { $r = 16 }
    $Win.Tag.Radius = $r
    $Win.FindName('Plate').CornerRadius = New-Object Windows.CornerRadius $r
    $Win.FindName('Shade').CornerRadius = New-Object Windows.CornerRadius $r
}

# --- Сетка у курсора по Win+Alt+V --------------------------------------------

$script:GridBody = @'
    <StackPanel Margin="12,12,12,10">
      <TextBox x:Name="GSearch" Tag="Поиск по кнопкам…" Margin="0,0,0,10"/>
      <WrapPanel x:Name="GCells"/>
      <TextBlock x:Name="GEmpty" Style="{StaticResource Hint}" Margin="4,6" Visibility="Collapsed" Text="Ничего не нашлось"/>
      <Border x:Name="GKidsBox" Visibility="Collapsed" Margin="0,8,0,0" Padding="0,8,0,0" BorderThickness="0,1,0,0" BorderBrush="{DynamicResource B.Line}">
        <StackPanel>
          <TextBlock x:Name="GKidsTitle" Style="{StaticResource Hint}" Margin="4,0,0,4"/>
          <WrapPanel x:Name="GKids"/>
        </StackPanel>
      </Border>
      <TextBlock Style="{StaticResource Hint}" Margin="2,8,0,0" Text="1–9 — сразу, стрелки и Enter — выбрать, пробел — вложенные, Esc — закрыть"/>
    </StackPanel>
'@

function New-GridCell {
    <# Ячейка сетки: кружок 44 px, номер для быстрого выбора и подпись. #>
    param($Win, $It, [int]$Num = -1, [string]$ParentName = '')
    $b = New-Object Windows.Controls.Button
    $b.Style = $Win.FindResource('Cell')
    $b.Width = 72; $b.Height = 78
    $sp = New-Object Windows.Controls.StackPanel
    $v = New-CircleVisual $It 44 26
    $v.El.Margin = '0,4,0,0'
    if ($Num -ge 0) {
        $badge = New-Object Windows.Controls.Border
        $badge.Width = 16; $badge.Height = 16
        $badge.CornerRadius = 8
        $badge.HorizontalAlignment = 'Right'; $badge.VerticalAlignment = 'Top'
        $badge.Margin = '0,-4,-6,0'
        $badge.Background = New-Brush $script:Pal.Panel
        $badge.BorderBrush = New-Brush $script:Pal.Line
        $badge.BorderThickness = 1
        $numTb = New-Object Windows.Controls.TextBlock
        $numTb.Text = [string](($Num + 1) % 10)
        $numTb.FontSize = 10
        $numTb.HorizontalAlignment = 'Center'; $numTb.VerticalAlignment = 'Center'
        $numTb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Sub')
        $badge.Child = $numTb
        [void]$v.El.Children.Add($badge)
    }
    [void]$sp.Children.Add($v.El)
    $lbl = New-Object Windows.Controls.TextBlock
    $name = [string]$It.name
    if (-not $name) { $name = Get-Preview $It.text }
    $lbl.Text = $name
    $lbl.FontSize = 11
    $lbl.Margin = '0,5,0,0'
    $lbl.MaxWidth = 66
    $lbl.TextTrimming = 'CharacterEllipsis'
    $lbl.TextAlignment = 'Center'
    $lbl.HorizontalAlignment = 'Center'
    $lbl.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Sub')
    [void]$sp.Children.Add($lbl)
    $b.Content = $sp
    $tip = Get-TipText $It
    if ($ParentName) { $tip = "$ParentName › $tip" }
    $b.ToolTip = $tip
    $b.Tag = @{ Item = $It; Ring = $v.Ring; Hay = ($ParentName + ' ' + $name + ' ' + $It.text).ToLowerInvariant(); Child = [bool]$ParentName }
    $b.Add_Click({ param($s, $e) try { Invoke-GridCell $s.Tag.Item } catch { Write-ErrLog $_ 'сетка: клик' } })
    return $b
}

function Show-QuickGrid {
    try {
        if ($script:GridWin) { $script:GridWin.Close(); return }
        if ($script:Cfg.items.Count -eq 0) { Open-Settings -1 -NewItem; return }
        $prev = [ClipNative]::GetForegroundWindow()
        $w = New-GlassWindow (New-WindowXaml $script:GridBody 16) -Radius 16 -Strength 0.86
        $w.Tag.PrevFg = $prev
        $w.Tag.Sel = 0
        $w.Tag.Visible = @()
        $w.Tag.KidsOf = $null
        $script:GridWin = $w
        $cells = $w.FindName('GCells')
        $cols = [Math]::Min(6, [Math]::Max(3, $script:Cfg.items.Count))
        $cells.Width = $cols * 72
        $w.FindName('GKids').Width = $cols * 72
        for ($i = 0; $i -lt $script:Cfg.items.Count; $i++) {
            $it = $script:Cfg.items[$i]
            $num = -1
            if ($i -lt 10) { $num = $i }
            $b = New-GridCell $w $it $num
            if ($it.children.Count -gt 0) {
                # Задержка на родителе показывает вложенные ниже, как веер на панели
                $b.Add_MouseEnter({ param($s, $e) try { Start-GridKidsTimer $s.Tag.Item } catch { } })
                $b.Add_MouseLeave({ param($s, $e) try { if ($script:GridKidsTimer) { $script:GridKidsTimer.Stop() } } catch { } })
            }
            [void]$cells.Children.Add($b)
        }
        # Вложенные тоже в сетке, но видны только при поиске
        foreach ($it in $script:Cfg.items) {
            foreach ($ch in $it.children) {
                $pn = [string]$it.name
                if (-not $pn) { $pn = '…' }
                $b = New-GridCell $w $ch -1 $pn
                $b.Visibility = 'Collapsed'
                [void]$cells.Children.Add($b)
            }
        }
        $w.FindName('GSearch').Add_TextChanged({ param($s, $e) try { Update-GridFilter } catch { Write-ErrLog $_ 'сетка: поиск' } })
        $w.Add_PreviewKeyDown({ param($s, $e) try { Invoke-GridKey $e } catch { Write-ErrLog $_ 'сетка: клавиши' } })
        $w.Add_Deactivated({ param($s, $e) try { if ($s.IsVisible) { $s.Close() } } catch { } })
        $w.Add_Closed({ $script:GridWin = $null; if ($script:GridKidsTimer) { $script:GridKidsTimer.Stop() } })
        $w.Add_ContentRendered({
            param($s, $e)
            try {
                $cur = Get-CursorDip $script:Scale
                $sc = Get-DpiScale $s
                $wa = Get-WorkAreaAt $cur.X $cur.Y $sc
                $s.Left = [Math]::Max($wa.Left + 8, [Math]::Min($cur.X - $s.ActualWidth / 2, $wa.Right - $s.ActualWidth - 8))
                $s.Top = [Math]::Max($wa.Top + 8, [Math]::Min($cur.Y - 40, $wa.Bottom - $s.ActualHeight - 8))
                [void]$s.Activate()
                [void]$s.FindName('GSearch').Focus()
            } catch { Write-ErrLog $_ 'сетка: показ' }
        })
        $w.Left = -10000; $w.Top = -10000
        Update-GridFilter
        Show-AppWindow $w
        [void]$w.Activate()
    } catch { Write-ErrLog $_ 'сетка' }
}

function Start-GridKidsTimer {
    param($Item)
    if (-not $script:GridKidsTimer) {
        $script:GridKidsTimer = New-Object Windows.Threading.DispatcherTimer
        $script:GridKidsTimer.Add_Tick({
            param($s, $e)
            $s.Stop()
            try { if ($script:GridWin) { Show-GridKids $s.Tag } } catch { Write-ErrLog $_ 'сетка: вложенные' }
        })
    }
    $script:GridKidsTimer.Stop()
    $script:GridKidsTimer.Interval = [TimeSpan]::FromMilliseconds($script:Cfg.fanDelay)
    $script:GridKidsTimer.Tag = $Item
    $script:GridKidsTimer.Start()
}

function Show-GridKids {
    <# Вложенные выбранного родителя — отдельным рядом под сеткой. #>
    param($Parent)
    $w = $script:GridWin
    $box = $w.FindName('GKidsBox')
    $kids = $w.FindName('GKids')
    if ($null -eq $Parent -or $w.Tag.KidsOf -eq $Parent) {
        $box.Visibility = 'Collapsed'; $w.Tag.KidsOf = $null
        return
    }
    $kids.Children.Clear()
    foreach ($ch in $Parent.children) { [void]$kids.Children.Add((New-GridCell $w $ch -1 ([string]$Parent.name))) }
    $title = [string]$Parent.name
    if (-not $title) { $title = 'Вложенные' }
    $w.FindName('GKidsTitle').Text = $title + ' ›'
    $box.Visibility = 'Visible'
    $w.Tag.KidsOf = $Parent
}

function Update-GridFilter {
    $w = $script:GridWin
    $q = $w.FindName('GSearch').Text.Trim().ToLowerInvariant()
    $vis = @()
    foreach ($b in $w.FindName('GCells').Children) {
        if ($b.Tag.Child) { $ok = [bool]$q -and $b.Tag.Hay.Contains($q) } else { $ok = (-not $q) -or $b.Tag.Hay.Contains($q) }
        if ($ok) { $b.Visibility = 'Visible'; $vis += , $b } else { $b.Visibility = 'Collapsed' }
    }
    $w.Tag.Visible = $vis
    $w.Tag.Sel = 0
    if ($vis.Count -eq 0) { $w.FindName('GEmpty').Visibility = 'Visible' } else { $w.FindName('GEmpty').Visibility = 'Collapsed' }
    Update-GridSelection
}

function Get-GridSelected {
    $w = $script:GridWin
    if ($w.Tag.Visible.Count -eq 0) { return $null }
    return $w.Tag.Visible[[Math]::Min($w.Tag.Sel, $w.Tag.Visible.Count - 1)]
}

function Update-GridSelection {
    $w = $script:GridWin
    $sel = Get-GridSelected
    foreach ($b in $w.FindName('GCells').Children) {
        if ([object]::ReferenceEquals($b, $sel)) {
            $b.Tag.Ring.Stroke = New-Brush $script:Pal.Accent
            $b.Tag.Ring.StrokeThickness = 2.5
        } else {
            $b.Tag.Ring.Stroke = Get-RingBrush ([string]$b.Tag.Item.color)
            $b.Tag.Ring.StrokeThickness = 1.5
        }
    }
}

function Invoke-GridKey {
    param($E)
    $w = $script:GridWin
    $search = $w.FindName('GSearch')
    $k = $E.Key.ToString()
    if ($k -eq 'Escape') { $E.Handled = $true; $w.Close(); return }
    if ($k -eq 'Return') {
        $E.Handled = $true
        $sel = Get-GridSelected
        if ($sel) { Invoke-GridCell $sel.Tag.Item }
        return
    }
    if ($k -eq 'Space' -and -not $search.Text) {
        $E.Handled = $true
        $sel = Get-GridSelected
        if ($sel -and $sel.Tag.Item.children.Count -gt 0) { Show-GridKids $sel.Tag.Item }
        return
    }
    if ($k -match '^(D|NumPad)([0-9])$' -and -not $search.Text) {
        $E.Handled = $true
        $n = [int]$Matches[2]
        if ($n -eq 0) { $n = 10 }
        if ($n -le $script:Cfg.items.Count) { Invoke-GridCell $script:Cfg.items[$n - 1] }
        return
    }
    $cols = [Math]::Max(1, [Math]::Floor($w.FindName('GCells').Width / 72))
    $delta = @{ Left = -1; Right = 1; Up = -$cols; Down = $cols }[$k]
    if ($delta) {
        $E.Handled = $true
        $cnt = $w.Tag.Visible.Count
        if ($cnt -gt 0) { $w.Tag.Sel = [Math]::Max(0, [Math]::Min($cnt - 1, $w.Tag.Sel + $delta)) }
        Update-GridSelection
    }
}

function Invoke-GridCell {
    param($Item)
    $w = $script:GridWin
    $prev = $w.Tag.PrevFg
    $r = New-Object Windows.Rect $w.Left, $w.Top, $w.ActualWidth, $w.ActualHeight
    # Кнопка-папка без своего текста: вместо копирования — показать вложенные
    if (-not [string]$Item.text -and $Item.children.Count -gt 0) { Show-GridKids $Item; return }
    $w.Close()
    $cur = Get-CursorDip $script:Scale
    if (Invoke-ClipItem $Item (New-Object Windows.Rect ($r.X + $r.Width / 2 - 1), ($r.Y + $r.Height / 2), 2, 2) 'bottom' $prev) {
        # Фокус возвращается в окно, где был курсор: сразу можно Ctrl+V
        Restore-Foreground $prev
        Show-Toast 'Скопировано — Ctrl+V' $cur.X $cur.Y
    }
}
# --- Трей --------------------------------------------------------------------

$script:TrayHandle = [IntPtr]::Zero

function New-TrayIcon {
    $bmp = New-Object Drawing.Bitmap 32, 32
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    if ($script:Cfg.mode -eq 'hidden') { $hex = '#6E7681' } else { $hex = $script:Pal.Accent }
    $rgb = Get-Rgb $hex
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $r = 18
    $path.AddArc(1, 1, $r, $r, 180, 90); $path.AddArc(31 - $r, 1, $r, $r, 270, 90)
    $path.AddArc(31 - $r, 31 - $r, $r, $r, 0, 90); $path.AddArc(1, 31 - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $br = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]))
    $g.FillPath($br, $path)
    $wb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(245, 13, 17, 23))
    foreach ($x in 5, 13, 21) { $g.FillEllipse($wb, $x, 12, 7, 7) }
    $g.Dispose(); $br.Dispose(); $wb.Dispose(); $path.Dispose()
    $h = $bmp.GetHicon()
    $bmp.Dispose()
    return @{ Icon = [Drawing.Icon]::FromHandle($h); Handle = $h }
}

function Update-TrayIcon {
    if (-not $script:Tray) { return }
    try {
        $n = New-TrayIcon
        $old = $script:TrayHandle
        $script:Tray.Icon = $n.Icon
        $script:TrayHandle = $n.Handle
        # Icon.FromHandle хэндл сам не освобождает — без этого утечка GDI
        if ($old -ne [IntPtr]::Zero) { [void][ClipNative]::DestroyIcon($old) }
        $tip = "FryBuffer $($script:Version)"
        if ($script:Cfg.mode -eq 'hidden') { $tip += ' — скрыта' }
        $script:Tray.Text = $tip.Substring(0, [Math]::Min(63, $tip.Length))
    } catch { Write-ErrLog $_ 'значок в трее' }
}

$script:TrayBody = @'
    <StackPanel x:Name="TItems" Margin="6" MinWidth="250"/>
'@

function Add-TrayRow {
    param($Win, [string]$Key, [string]$Text, [string]$Act, [string]$Hint = '')
    $b = New-Object Windows.Controls.Button
    $b.Style = $Win.FindResource('Ghost')
    $b.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'B.Text')
    $b.HorizontalContentAlignment = 'Stretch'
    $b.Padding = '10,7'
    $dp = New-Object Windows.Controls.DockPanel
    $ic = New-EmojiVisual (New-EmojiFromKey $Key) 18
    $ic.Margin = '0,0,11,0'
    [Windows.Controls.DockPanel]::SetDock($ic, 'Left')
    [void]$dp.Children.Add($ic)
    if ($Hint) {
        $h = New-Object Windows.Controls.TextBlock
        $h.Text = $Hint
        $h.FontSize = 11.5
        $h.Margin = '14,0,0,0'
        $h.VerticalAlignment = 'Center'
        $h.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Sub')
        [Windows.Controls.DockPanel]::SetDock($h, 'Right')
        [void]$dp.Children.Add($h)
    }
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    $t.VerticalAlignment = 'Center'
    [void]$dp.Children.Add($t)
    $b.Content = $dp
    $b.Tag = @{ Act = $Act; Win = $Win }
    $b.Add_Click({ param($s, $e) try { Invoke-TrayAction $s.Tag.Act $s.Tag.Win } catch { Show-Err $_ 'меню в трее' } })
    [void]$Win.FindName('TItems').Children.Add($b)
}

function Add-TraySep($Win) {
    $r = New-Object Windows.Shapes.Rectangle
    $r.Height = 1
    $r.Margin = '10,4'
    $r.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'B.Line')
    [void]$Win.FindName('TItems').Children.Add($r)
}

function Show-TrayMenu {
    if ($script:TrayMenu) { $script:TrayMenu.Close(); return }
    $w = New-GlassWindow (New-WindowXaml $script:TrayBody 12) -Radius 12 -Strength 0.86
    $script:TrayMenu = $w
    $ver = New-Object Windows.Controls.TextBlock
    $ver.Text = "FryBuffer  ·  $($script:Version)"
    $ver.FontSize = 11
    $ver.Margin = '12,4,12,6'
    $ver.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Sub')
    [void]$w.FindName('TItems').Children.Add($ver)
    Add-TraySep $w
    if ($script:Cfg.mode -eq 'hidden') { Add-TrayRow $w '1f441-fe0f' 'Показать панель' 'toggle' } else { Add-TrayRow $w '1f648' 'Скрыть панель' 'toggle' }
    if ($script:Cfg.mode -eq 'pinned') { Add-TrayRow $w '1f4cc' 'Прятать к краю' 'unpin' } else { Add-TrayRow $w '1f4cc' 'Закрепить открытой' 'pin' }
    Add-TrayRow $w '1f522' 'Сетка у курсора' 'grid' $script:Cfg.hotkey
    Add-TraySep $w
    Add-TrayRow $w '2795' 'Новая кнопка…' 'new'
    Add-TrayRow $w '2699-fe0f' 'Настройки…' 'settings'
    Add-TrayRow $w '1f4dd' 'Открыть config.json' 'config'
    Add-TrayRow $w '1f4c2' 'Папка панели' 'folder'
    $as = Get-AutostartState $script:Root -Exe $script:ExePath
    if ($as.On) { Add-TrayRow $w '2705' 'Запускать вместе с Windows' 'autostart' 'вкл' } else { Add-TrayRow $w '2b1c' 'Запускать вместе с Windows' 'autostart' 'выкл' }
    Add-TraySep $w
    Add-TrayRow $w '1f504' 'Перезапустить' 'restart'
    Add-TrayRow $w '1f6aa' 'Выход' 'exit'
    $w.Add_Deactivated({ param($s, $e) try { if ($s.IsVisible) { $s.Close() } } catch { } })
    $w.Add_Closed({ $script:TrayMenu = $null })
    $w.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $s.Close() } })
    $w.Left = -10000; $w.Top = -10000
    Show-AppWindow $w
    $w.UpdateLayout()
    $cur = Get-CursorDip $script:Scale
    $wa = Get-WorkAreaAt $cur.X $cur.Y (Get-DpiScale $w)
    $w.Left = [Math]::Max($wa.Left + 8, [Math]::Min($cur.X - $w.ActualWidth / 2, $wa.Right - $w.ActualWidth - 8))
    if ($cur.Y -gt ($wa.Top + $wa.Height / 2)) { $w.Top = $wa.Bottom - $w.ActualHeight - 8 } else { $w.Top = $wa.Top + 8 }
    [void]$w.Activate()
}

function Invoke-TrayAction {
    param([string]$Act, $Win)
    if ($Win) { $Win.Close() }
    switch ($Act) {
        'toggle'   { if ($script:Cfg.mode -eq 'hidden') { $script:Cfg.mode = 'auto' } else { $script:Cfg.mode = 'hidden' }; Save-Config; Rebuild-Dock }
        'pin'      { $script:Cfg.mode = 'pinned'; Save-Config; Rebuild-Dock }
        'unpin'    { $script:Cfg.mode = 'auto'; Save-Config; Rebuild-Dock }
        'grid'     { Show-QuickGrid }
        'new'      { Open-Settings -1 -NewItem }
        'settings' { Open-Settings -1 }
        'config'   { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:CfgPath) }
        'folder'   { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:Root) }
        'restart'  {
            # Перезапуск отдаём отдельному скрипту: он выжидает, пока этот
            # процесс отпустит мьютекс, иначе новый экземпляр сразу выйдет
            $exe = $script:ExePath
            if (Test-Path -LiteralPath $exe) { Start-Process $exe -ArgumentList '--restart' }
            else { Start-Process wscript.exe -ArgumentList ('"{0}"' -f (Join-Path $script:Root 'FryBuffer-restart.vbs')) }
            Stop-App
        }
        'autostart' {
            $on = -not (Get-AutostartState $script:Root -Exe $script:ExePath).On
            Set-Autostart $script:Root $on -Exe $script:ExePath
            $cur = Get-CursorDip $script:Scale
            if ($on) { Show-Toast 'Будет запускаться вместе с Windows' $cur.X $cur.Y } else { Show-Toast 'Автозапуск выключен' $cur.X $cur.Y }
        }
        'exit'     { Stop-App }
    }
}

# --- Хоткей ------------------------------------------------------------------

$script:HotkeyStatus = ''

function Register-AppHotkey {
    <# Возвращает текст состояния для окна настроек. #>
    try {
        $script:Hotkey.Unregister()
        if (-not $script:Cfg.hotkey) { $script:HotkeyStatus = 'Хоткей выключен'; return $script:HotkeyStatus }
        $h = ConvertFrom-Hotkey $script:Cfg.hotkey
        if ($script:Hotkey.Register($h.Mods, $h.Vk)) {
            $script:HotkeyStatus = "$($h.Text) работает"
        } else {
            $script:HotkeyStatus = "$($h.Text) уже занят другой программой — выберите другой"
            Write-ErrLog $script:HotkeyStatus 'хоткей'
        }
    } catch {
        $script:HotkeyStatus = $_.Exception.Message
        Write-ErrLog $_ 'хоткей'
    }
    return $script:HotkeyStatus
}
