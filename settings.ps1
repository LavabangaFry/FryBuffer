#requires -Version 5.1
<#
    Окно настроек FryBuffer. Как в homedash: «Сохранить» окно не
    закрывает, вид панели меняется сразу, пока двигаешь ползунок, а
    «Закрыть» без сохранения возвращает всё как было.
#>

$script:SettingsWin = $null

$script:SettingsBody = @'
<Grid>
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/>
    <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>

  <Border x:Name="STitle" Grid.Row="0" Background="Transparent" Padding="18,12,10,10">
    <DockPanel>
      <Button x:Name="SClose" DockPanel.Dock="Right" Style="{StaticResource Ghost}" Width="32" Height="30" Padding="0" Content="✕" ToolTip="Закрыть"/>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,12,0">
        <RadioButton x:Name="TabItems" Style="{StaticResource Chip}" GroupName="tabs" Content="Кнопки" IsChecked="True" Margin="0,0,6,0"/>
        <RadioButton x:Name="TabLook" Style="{StaticResource Chip}" GroupName="tabs" Content="Вид и поведение" Margin="0"/>
      </StackPanel>
      <ContentControl x:Name="SLogo" VerticalAlignment="Center" Margin="0,0,10,0"/>
      <TextBlock Text="FryBuffer" Style="{StaticResource H}" FontSize="16" VerticalAlignment="Center"/>
      <TextBlock x:Name="SVersion" Style="{StaticResource Hint}" VerticalAlignment="Center" Margin="10,2,0,0"/>
    </DockPanel>
  </Border>

  <Grid x:Name="PageItems" Grid.Row="1" Margin="18,4,18,0">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="300"/>
      <ColumnDefinition Width="20"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>
    <DockPanel Grid.Column="0">
      <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,4">
        <Button x:Name="BNew" Style="{StaticResource Btn}" Content="+ Новая" Padding="10,5" Margin="0,0,6,6" ToolTip="Новая кнопка на панели"/>
        <Button x:Name="BChild" Style="{StaticResource Btn}" Content="+ Вложенная" Padding="10,5" Margin="0,0,6,6" ToolTip="Вложенная кнопка: раскроется веером, если задержать мышь на родителе"/>
        <Button x:Name="BDup" Style="{StaticResource Btn}" Content="Копия" Padding="10,5" Margin="0,0,6,6"/>
        <Button x:Name="BUp" Style="{StaticResource Btn}" Content="↑" Padding="10,5" Margin="0,0,6,6" ToolTip="Раньше в ряду"/>
        <Button x:Name="BDown" Style="{StaticResource Btn}" Content="↓" Padding="10,5" Margin="0,0,6,6" ToolTip="Позже в ряду"/>
        <Button x:Name="BNest" Style="{StaticResource Btn}" Content="В группу" Padding="10,5" Margin="0,0,6,6"/>
        <Button x:Name="BDel" Style="{StaticResource Danger}" Content="Удалить" Padding="10,5" Margin="0,0,0,6"/>
      </WrapPanel>
      <Border Background="{DynamicResource B.Panel}" BorderBrush="{DynamicResource B.Line}" BorderThickness="1" CornerRadius="8" Padding="4">
        <ListBox x:Name="LItems" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
      </Border>
    </DockPanel>

    <ScrollViewer x:Name="EScroll" Grid.Column="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <StackPanel x:Name="Editor" Margin="0,0,10,10">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid x:Name="EPreview" Width="46" Height="46" Margin="0,0,14,0" VerticalAlignment="Bottom"/>
          <StackPanel Grid.Column="1">
            <TextBlock Style="{StaticResource Lbl}" Text="Название — видно в подсказке над кружком" Margin="0,0,0,6"/>
            <TextBox x:Name="EName" Tag="Например: Единорог-сервер"/>
          </StackPanel>
        </Grid>
        <TextBlock Style="{StaticResource Lbl}" Text="Текст, который копируется"/>
        <TextBox x:Name="EText" Height="92" AcceptsReturn="True" AcceptsTab="True" TextWrapping="Wrap"
                 VerticalScrollBarVisibility="Auto" FontFamily="Cascadia Mono, Consolas" FontSize="12.5"
                 Tag="Текст или шаблон: Заявка {?Номер} от {date}"/>
        <WrapPanel x:Name="ETokens" Margin="0,8,0,0"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Так будет скопировано"/>
        <Border Background="{DynamicResource B.Panel}" BorderBrush="{DynamicResource B.Line}" BorderThickness="1" CornerRadius="6" Padding="10,7">
          <TextBlock x:Name="EResult" FontFamily="Cascadia Mono, Consolas" FontSize="12.5" TextWrapping="Wrap" MaxHeight="74" TextTrimming="CharacterEllipsis"/>
        </Border>
        <TextBlock Style="{StaticResource Lbl}" Text="Цвет обводки и точки у края"/>
        <WrapPanel x:Name="EColors"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Стиль обводки"/>
        <WrapPanel x:Name="ERings"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Эмодзи"/>
        <ContentControl x:Name="EPicker" HorizontalAlignment="Left"/>
      </StackPanel>
    </ScrollViewer>
    <StackPanel x:Name="EEmpty" Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Center" Visibility="Collapsed">
      <ContentControl x:Name="EEmptyIcon" HorizontalAlignment="Center"/>
      <TextBlock Style="{StaticResource H}" HorizontalAlignment="Center" Margin="0,12,0,4" Text="Заведите первого светлячка"/>
      <TextBlock Style="{StaticResource Hint}" HorizontalAlignment="Center" TextAlignment="Center" MaxWidth="320"
                 Text="Кнопка — это светлячок у края экрана: эмодзи в кружке и текст, который по клику ляжет в буфер обмена."/>
      <Button x:Name="BNew2" Style="{StaticResource Primary}" Content="+ Новая кнопка" HorizontalAlignment="Center" Margin="0,14,0,0"/>
    </StackPanel>
  </Grid>

  <ScrollViewer x:Name="PageLook" Grid.Row="1" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <Grid Margin="18,0,18,10">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="28"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <TextBlock Style="{StaticResource Lbl}" Text="Тема" Margin="0,4,0,6"/>
        <WrapPanel x:Name="RTheme"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Акцент"/>
        <WrapPanel x:Name="RAccent"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Размер кружков"/>
        <WrapPanel x:Name="RSize"/>
        <CheckBox x:Name="CMagnify" Style="{StaticResource Toggle}" Content="Увеличивать кружок под мышью" Margin="0,18,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="2">
        <TextBlock Style="{StaticResource Lbl}" Text="Край экрана" Margin="0,4,0,6"/>
        <WrapPanel x:Name="REdge"/>
        <TextBlock Style="{StaticResource Hint}" Text="Ctrl + перетаскивание любого кружка уносит всю панель к другому краю или монитору."/>
        <TextBlock Style="{StaticResource Lbl}" Text="Положение вдоль края"/>
        <Slider x:Name="SOffset" Minimum="0" Maximum="1" SmallChange="0.01" LargeChange="0.1"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Поведение"/>
        <WrapPanel x:Name="RMode"/>
        <CheckBox x:Name="CAutostart" Style="{StaticResource Toggle}" Content="Запускать вместе с Windows" Margin="0,10,0,0"/>
        <TextBlock x:Name="VAutostart" Style="{StaticResource Hint}" Margin="44,4,0,0" Text="Применяется сразу, без «Сохранить»"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Через сколько прятаться, когда мышь ушла"/>
        <DockPanel>
          <TextBlock x:Name="VDelay" DockPanel.Dock="Right" Width="58" TextAlignment="Right" Foreground="{DynamicResource B.Sub}" VerticalAlignment="Center"/>
          <Slider x:Name="SDelay" Minimum="150" Maximum="2000" SmallChange="50" LargeChange="250"/>
        </DockPanel>
        <TextBlock Style="{StaticResource Lbl}" Text="Через сколько раскрывать вложенные веером"/>
        <DockPanel>
          <TextBlock x:Name="VFan" DockPanel.Dock="Right" Width="58" TextAlignment="Right" Foreground="{DynamicResource B.Sub}" VerticalAlignment="Center"/>
          <Slider x:Name="SFan" Minimum="150" Maximum="1500" SmallChange="50" LargeChange="100"/>
        </DockPanel>
        <TextBlock Style="{StaticResource Lbl}" Text="Сетка кнопок у курсора"/>
        <DockPanel>
          <Button x:Name="BHotkey" DockPanel.Dock="Right" Style="{StaticResource Btn}" Content="Применить" Margin="8,0,0,0"/>
          <TextBox x:Name="SHotkey" Tag="Win+Alt+V; пусто — выключить"/>
        </DockPanel>
        <TextBlock x:Name="VHotkey" Style="{StaticResource Hint}" Margin="0,6,0,0"/>
        <TextBlock Style="{StaticResource Lbl}" Text="Файлы"/>
        <WrapPanel>
          <Button x:Name="BCfg" Style="{StaticResource Btn}" Content="Открыть config.json" Margin="0,0,8,0"/>
          <Button x:Name="BDir" Style="{StaticResource Btn}" Content="Папка панели"/>
        </WrapPanel>
      </StackPanel>
    </Grid>
  </ScrollViewer>

  <Border Grid.Row="2" BorderBrush="{DynamicResource B.Line}" BorderThickness="0,1,0,0" Padding="18,10,18,12">
    <DockPanel>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="SCancel" Style="{StaticResource Btn}" Content="Закрыть" Margin="0,0,8,0"/>
        <Button x:Name="SSave" Style="{StaticResource Primary}" Content="Сохранить" Padding="18,6"/>
      </StackPanel>
      <TextBlock x:Name="SStatus" Style="{StaticResource Hint}" VerticalAlignment="Center" Text="Порядок удобно менять прямо на панели: перетащите кружок."/>
    </DockPanel>
  </Border>
</Grid>
'@

$script:Tokens = @(
    @('Дата',         '{date}',     'Сегодняшняя дата: 07.10.2026. Свой формат: {date:yyyy-MM-dd}'),
    @('Время',        '{time}',     'Текущее время: 14:05'),
    @('Дата и время', '{now}',      '07.10.2026 14:05. Свой формат: {now:dd MMMM, HH:mm}'),
    @('Буфер',        '{clipboard}', 'То, что лежит в буфере обмена в момент клика'),
    @('Логин',        '{user}',     'Имя пользователя Windows'),
    @('Компьютер',    '{computer}', 'Имя этого компьютера'),
    @('IP',           '{ip}',       'Адрес этого компьютера в локальной сети'),
    @('Спросить…',    '{?Вопрос}',  'При клике появится поле ввода с этой подписью'),
    @('Счётчик',      '{n}',        'Растёт на 1 при каждом копировании. С нулями: {n:000}'),
    @('GUID',         '{guid}',     'Новый уникальный идентификатор каждый раз'),
    @('Код',          '{rand:8}',   'Случайные 8 символов без похожих 0/O и 1/l')
)

function Copy-ClipItem($It) {
    <# Рабочая копия для окна настроек; _src — ссылка на живую кнопку, чтобы при сохранении не потерять счётчик. #>
    $c = New-ClipItem -Name ([string]$It.name) -Text ([string]$It.text) -Icon ([string]$It.icon) -Color ([string]$It.color) -Counter ([int]$It.counter) -Ring ([string]$It.ring)
    $c['_src'] = $It
    foreach ($ch in @($It.children)) { if ($null -ne $ch) { [void]$c.children.Add((Copy-ClipItem $ch)) } }
    return $c
}

function Find-SettingsRow {
    <# Номер строки списка для кнопки панели Idx или её вложенной Child. #>
    param([int]$Idx, [int]$Child = -1)
    $S = $script:SettingsState
    if ($Idx -lt 0 -or $Idx -ge $S.Items.Count) { return -1 }
    $target = $S.Items[$Idx]
    if ($Child -ge 0 -and $Child -lt $target.children.Count) { $target = $target.children[$Child] }
    for ($r = 0; $r -lt $S.Rows.Count; $r++) { if ([object]::ReferenceEquals($S.Rows[$r].Item, $target)) { return $r } }
    return -1
}

function Open-Settings {
    param([int]$Idx = -1, [int]$Child = -1, [switch]$NewItem, [switch]$NewChild)
    try {
        if ($script:SettingsWin) {
            $S = $script:SettingsState
            if ($NewItem) { Add-SettingsItem }
            elseif ($NewChild -and $Idx -ge 0) { Select-SettingsItem (Find-SettingsRow $Idx); Add-SettingsChild }
            elseif ($Idx -ge 0) { Select-SettingsItem (Find-SettingsRow $Idx $Child) }
            $script:SettingsWin.Activate() | Out-Null
            return
        }
        $w = New-GlassWindow (New-WindowXaml $script:SettingsBody 12 'Width="960" Height="740"') -Radius 12 -AppWindow -Strength 0.9
        $w.Topmost = $false
        $w.ShowInTaskbar = $true
        $w.Title = 'FryBuffer — настройки'
        $w.WindowStartupLocation = 'CenterScreen'
        $script:SettingsWin = $w

        $names = 'STitle', 'SVersion', 'SClose', 'TabItems', 'TabLook', 'SLogo', 'PageItems', 'PageLook', 'LItems', 'BNew', 'BNew2', 'BChild', 'BDup', 'BUp', 'BDown', 'BNest', 'BDel',
                 'EScroll', 'Editor', 'EEmpty', 'EEmptyIcon', 'EPreview', 'EName', 'EText', 'ETokens', 'EResult', 'EColors', 'ERings', 'EPicker',
                 'RTheme', 'RAccent', 'RSize', 'CMagnify', 'REdge', 'SOffset', 'RMode', 'SDelay', 'VDelay', 'SFan', 'VFan',
                 'CAutostart', 'VAutostart', 'SHotkey', 'BHotkey', 'VHotkey', 'BCfg', 'BDir', 'SCancel', 'SSave', 'SStatus'
        $S = @{ Win = $w; Loading = $false; Dirty = $false; CloseArmed = $false; DelArmed = $false; Sel = -1; Ip = $null; Rows = @() }
        foreach ($n in $names) { $S[$n] = $w.FindName($n) }
        $script:SettingsState = $S

        # Слепок на момент открытия: «Закрыть» без сохранения вернёт вид к нему
        $S.Snapshot = ConvertTo-ConfigJson $script:Cfg
        $S.Items = New-Object System.Collections.ArrayList
        foreach ($it in $script:Cfg.items) { [void]$S.Items.Add((Copy-ClipItem $it)) }

        $S.SLogo.Content = New-EmojiVisual (New-EmojiFromKey '1f4cb') 20
        $S.SVersion.Text = $script:Version
        $S.EEmptyIcon.Content = New-EmojiVisual (New-EmojiFromKey '1f984') 40

        Initialize-SettingsItems
        Initialize-SettingsLook

        $S.STitle.Add_MouseLeftButtonDown({ try { $script:SettingsWin.DragMove() } catch { } })
        $S.TabItems.Add_Checked({ $script:SettingsState.PageItems.Visibility = 'Visible'; $script:SettingsState.PageLook.Visibility = 'Collapsed' })
        $S.TabLook.Add_Checked({ $script:SettingsState.PageItems.Visibility = 'Collapsed'; $script:SettingsState.PageLook.Visibility = 'Visible' })
        $S.SSave.Add_Click({ try { Save-Settings } catch { Show-Err $_ 'сохранение настроек' } })
        $S.SCancel.Add_Click({ try { Close-Settings } catch { Show-Err $_ 'закрытие настроек' } })
        $S.SClose.Add_Click({ try { Close-Settings } catch { Show-Err $_ 'закрытие настроек' } })
        $w.Add_PreviewKeyDown({
            param($s, $e)
            if ($e.Key -eq 'Escape') { $e.Handled = $true; Close-Settings }
            elseif ($e.Key -eq 'S' -and [Windows.Input.Keyboard]::Modifiers -eq 'Control') { $e.Handled = $true; Save-Settings }
        })
        $w.Add_Closed({
            $script:SettingsWin = $null
            $script:SettingsState = $null
            $script:Hold = [Math]::Max(0, $script:Hold - 1)
        })

        # Пока настройки открыты, панель раскрыта: видно, что меняешь
        $script:Hold++
        Show-AppWindow $w
        [void]$w.Activate()

        if ($NewItem) { Add-SettingsItem }
        elseif ($NewChild -and $Idx -ge 0) { Select-SettingsItem (Find-SettingsRow $Idx); Add-SettingsChild }
        elseif ($Idx -ge 0) { Select-SettingsItem (Find-SettingsRow $Idx $Child) }
        elseif ($S.Rows.Count -gt 0) { Select-SettingsItem 0 }
        else { Select-SettingsItem -1 }
    } catch { Show-Err $_ 'окно настроек' }
}

function Set-Dirty {
    $S = $script:SettingsState
    if (-not $S -or $S.Loading) { return }
    $S.Dirty = $true
    $S.SStatus.Text = 'Есть несохранённые изменения'
    $S.SStatus.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Warn')
    Reset-CloseArm
}

function Reset-CloseArm {
    $S = $script:SettingsState
    if ($S.CloseArmed) {
        $S.CloseArmed = $false
        $S.SCancel.Content = 'Закрыть'
        $S.SCancel.Style = $S.Win.FindResource('Btn')
    }
}

# --- Кнопки: список и редактор -----------------------------------------------

function New-MiniCircle {
    param($It, [double]$D, [double]$Emo)
    $g = New-Object Windows.Controls.Grid
    $g.Width = $D; $g.Height = $D
    $el = New-Object Windows.Shapes.Ellipse
    $el.Fill = New-Brush $script:Pal.Btn
    [void]$g.Children.Add($el)
    foreach ($sh_ in (New-RingShapes ([string]$It.color) ([string]$It.ring) $D).Shapes) { [void]$g.Children.Add($sh_) }
    $v = New-EmojiVisual ([string]$It.icon) $Emo ([string]$It.name)
    $v.HorizontalAlignment = 'Center'; $v.VerticalAlignment = 'Center'
    [void]$g.Children.Add($v)
    return $g
}

function Set-ListRow {
    param($Row, $It, [int]$Level = 0)
    $Row.Children.Clear()
    # Вложенные — с отступом и линией-веткой под своим родителем
    $Row.Margin = New-Object Windows.Thickness (22 * $Level), 0, 0, 0
    $d = 28; $emo = 17
    if ($Level -gt 0) { $d = 24; $emo = 15 }
    $c = New-MiniCircle $It $d $emo
    $c.Margin = '0,0,10,0'
    [Windows.Controls.DockPanel]::SetDock($c, 'Left')
    [void]$Row.Children.Add($c)
    if ($It.children -and $It.children.Count -gt 0) {
        $k = New-Object Windows.Controls.Border
        $k.CornerRadius = 8
        $k.Padding = '6,1'
        $k.VerticalAlignment = 'Center'
        $k.Margin = '6,0,0,0'
        $k.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'B.AccentSoft')
        $kt = New-Object Windows.Controls.TextBlock
        $kt.Text = '+' + $It.children.Count
        $kt.FontSize = 11
        $kt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Accent')
        $k.Child = $kt
        $k.ToolTip = "Вложенных: $($It.children.Count)"
        [Windows.Controls.DockPanel]::SetDock($k, 'Right')
        [void]$Row.Children.Add($k)
    }
    $sp = New-Object Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    $n = New-Object Windows.Controls.TextBlock
    $name = [string]$It.name
    if (-not $name) { $name = 'Без названия' }
    $n.Text = $name
    $n.TextTrimming = 'CharacterEllipsis'
    $n.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Text')
    [void]$sp.Children.Add($n)
    $p = New-Object Windows.Controls.TextBlock
    $prev = Get-Preview $It.text
    if (-not $prev) { $prev = 'текст не задан' }
    $p.Text = $prev
    $p.FontSize = 11.5
    $p.TextTrimming = 'CharacterEllipsis'
    $p.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Sub')
    [void]$sp.Children.Add($p)
    [void]$Row.Children.Add($sp)
}

function Update-SettingsList {
    <#
        Список — дерево, разложенное в строки: родитель, под ним его
        вложенные. Каждая строка помнит, в каком списке и на каком месте
        лежит её кнопка, — по этому работают «↑ ↓», удаление и перенос.
    #>
    $S = $script:SettingsState
    $S.Loading = $true
    try {
        $S.LItems.Items.Clear()
        $rows = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $S.Items.Count; $i++) {
            $it = $S.Items[$i]
            [void]$rows.Add(@{ Item = $it; List = $S.Items; Pos = $i; Level = 0; Parent = $null })
            for ($j = 0; $j -lt $it.children.Count; $j++) {
                [void]$rows.Add(@{ Item = $it.children[$j]; List = $it.children; Pos = $j; Level = 1; Parent = $it })
            }
        }
        $S.Rows = $rows
        foreach ($r in $rows) {
            $row = New-Object Windows.Controls.DockPanel
            Set-ListRow $row $r.Item $r.Level
            [void]$S.LItems.Items.Add($row)
        }
    } finally { $S.Loading = $false }
}

function Get-RowOf {
    <# Строка списка, где лежит кнопка: после перестановок номер строки меняется. #>
    param($Item)
    $S = $script:SettingsState
    for ($r = 0; $r -lt $S.Rows.Count; $r++) { if ([object]::ReferenceEquals($S.Rows[$r].Item, $Item)) { return $r } }
    return -1
}
function Initialize-SettingsItems {
    $S = $script:SettingsState
    Update-SettingsList
    $S.LItems.Add_SelectionChanged({
        $S = $script:SettingsState
        if ($S.Loading) { return }
        try { Select-SettingsItem $S.LItems.SelectedIndex } catch { Write-ErrLog $_ 'выбор кнопки' }
    })
    $S.EName.Add_TextChanged({ try { Update-FromEditor 'name' } catch { Write-ErrLog $_ 'название' } })
    $S.EText.Add_TextChanged({ try { Update-FromEditor 'text' } catch { Write-ErrLog $_ 'текст' } })

    foreach ($t in $script:Tokens) {
        $b = New-Object Windows.Controls.Button
        $b.Style = $S.Win.FindResource('Btn')
        $b.Padding = '9,3'
        $b.Margin = '0,0,6,6'
        $b.FontSize = 12
        $b.Content = $t[0]
        $b.ToolTip = "$($t[1]) — $($t[2])"
        $b.Tag = $t[1]
        $b.Add_Click({
            param($s, $e)
            try {
                $tb = $script:SettingsState.EText
                $tok = [string]$s.Tag
                $at = $tb.SelectionStart
                $tb.SelectedText = $tok
                if ($tok -eq '{?Вопрос}') {
                    # Подпись сразу выделена — её остаётся только перепечатать
                    $tb.Select($at + 2, 6)
                } else {
                    $tb.Select($at + $tok.Length, 0)
                }
                [void]$tb.Focus()
            } catch { Write-ErrLog $_ 'вставка подстановки' }
        })
        [void]$S.ETokens.Children.Add($b)
    }

    foreach ($st in $script:RingNames.Keys) {
        $rb = New-RingChip $S.Win $st '' 'ering'
        $rb.Tag = $st
        $rb.Add_Checked({ param($s, $e) try { Update-FromEditor 'ring' ([string]$s.Tag) } catch { Write-ErrLog $_ 'стиль обводки' } })
        [void]$S.ERings.Children.Add($rb)
    }
    foreach ($hex in $script:LabelColors) {
        $rb = New-ColorDot $S.Win $hex 'ecolor'
        $rb.Tag = $hex
        $rb.Add_Checked({ param($s, $e) try { Update-FromEditor 'color' ([string]$s.Tag) } catch { Write-ErrLog $_ 'цвет' } })
        [void]$S.EColors.Children.Add($rb)
    }

    $S.EPicker.Content = New-EmojiPicker -OnPick {
        param($st, $em)
        Update-FromEditor 'icon' $em
    } -Cols 12 -Cell 32 -Rows 5

    $S.BNew.Add_Click({ try { Add-SettingsItem } catch { Show-Err $_ 'новая кнопка' } })
    $S.BNew2.Add_Click({ try { Add-SettingsItem } catch { Show-Err $_ 'новая кнопка' } })
    $S.BChild.Add_Click({ try { Add-SettingsChild } catch { Show-Err $_ 'вложенная кнопка' } })
    $S.BDup.Add_Click({
        try {
            $S = $script:SettingsState
            if ($S.Sel -lt 0) { return }
            $r = $S.Rows[$S.Sel]
            $c = Copy-ClipItemDeep $r.Item
            $r.List.Insert($r.Pos + 1, $c)
            Update-SettingsList
            Select-SettingsItem (Get-RowOf $c)
            Set-Dirty
        } catch { Show-Err $_ 'копия кнопки' }
    })
    $S.BUp.Add_Click({ try { Move-SettingsItem -1 } catch { Show-Err $_ 'порядок' } })
    $S.BDown.Add_Click({ try { Move-SettingsItem 1 } catch { Show-Err $_ 'порядок' } })
    $S.BNest.Add_Click({ try { Switch-SettingsNesting } catch { Show-Err $_ 'группа' } })
    $S.BDel.Add_Click({
        try {
            $S = $script:SettingsState
            if ($S.Sel -lt 0) { return }
            $r = $S.Rows[$S.Sel]
            if (-not $S.DelArmed) {
                $S.DelArmed = $true
                $kids = $r.Item.children.Count
                if ($kids -gt 0) { $S.BDel.Content = "Удалить с вложенными ($kids)?" } else { $S.BDel.Content = 'Точно удалить?' }
                return
            }
            $r.List.RemoveAt($r.Pos)
            $next = $S.Sel
            Update-SettingsList
            Select-SettingsItem ([Math]::Min($next, $S.Rows.Count - 1))
            Set-Dirty
        } catch { Show-Err $_ 'удаление кнопки' }
    })
}
function Reset-DelArm {
    $S = $script:SettingsState
    if ($S.DelArmed) { $S.DelArmed = $false; $S.BDel.Content = 'Удалить' }
}

function Edit-NewName {
    $S = $script:SettingsState
    $S.Win.Dispatcher.BeginInvoke([Action] {
        $tb = $script:SettingsState.EName
        [void]$tb.Focus()
        $tb.SelectAll()
    }, 'Input') | Out-Null
}

function Add-SettingsItem {
    $S = $script:SettingsState
    $S.TabItems.IsChecked = $true
    $it = New-ClipItem -Name 'Новый светлячок' -Icon (New-EmojiFromKey '2728')
    [void]$S.Items.Add($it)
    Update-SettingsList
    Select-SettingsItem (Get-RowOf $it)
    Set-Dirty
    Edit-NewName
}

function Add-SettingsChild {
    <# Вложенная — к выбранной кнопке панели, а если выбрана вложенная — к её родителю. #>
    $S = $script:SettingsState
    $S.TabItems.IsChecked = $true
    if ($S.Sel -lt 0) { Add-SettingsItem; return }
    $r = $S.Rows[$S.Sel]
    $parent = $r.Item
    if ($r.Level -gt 0) { $parent = $r.Parent }
    $it = New-ClipItem -Name 'Новый зверёк' -Icon (New-EmojiFromKey '1f43e')
    [void]$parent.children.Add($it)
    Update-SettingsList
    Select-SettingsItem (Get-RowOf $it)
    Set-Dirty
    Edit-NewName
}

function Move-SettingsItem {
    param([int]$Dir)
    $S = $script:SettingsState
    if ($S.Sel -lt 0) { return }
    $r = $S.Rows[$S.Sel]
    $j = $r.Pos + $Dir
    if ($j -lt 0 -or $j -ge $r.List.Count) { return }
    $r.List.RemoveAt($r.Pos)
    $r.List.Insert($j, $r.Item)
    Update-SettingsList
    Select-SettingsItem (Get-RowOf $r.Item)
    Set-Dirty
}

function Switch-SettingsNesting {
    <#
        Вложенная — «На панель»: встаёт на панель сразу за своим родителем.
        Кнопка панели — «В группу»: становится вложенной у кнопки слева.
        Уровень один, поэтому кнопку со своими вложенными в группу не убрать.
    #>
    $S = $script:SettingsState
    if ($S.Sel -lt 0) { return }
    $r = $S.Rows[$S.Sel]
    if ($r.Level -gt 0) {
        $pi = $S.Items.IndexOf($r.Parent)
        $r.List.RemoveAt($r.Pos)
        $S.Items.Insert($pi + 1, $r.Item)
    } else {
        if ($r.Pos -eq 0 -or $r.Item.children.Count -gt 0) { return }
        $S.Items.RemoveAt($r.Pos)
        [void]$S.Items[$r.Pos - 1].children.Add($r.Item)
    }
    Update-SettingsList
    Select-SettingsItem (Get-RowOf $r.Item)
    Set-Dirty
}

function Select-SettingsItem {
    param([int]$Idx)
    $S = $script:SettingsState
    Reset-DelArm
    $S.Sel = $Idx
    $has = $Idx -ge 0 -and $Idx -lt $S.Rows.Count
    if ($has) {
        $S.EScroll.Visibility = 'Visible'; $S.EEmpty.Visibility = 'Collapsed'
    } else {
        $S.EScroll.Visibility = 'Collapsed'; $S.EEmpty.Visibility = 'Visible'
    }
    foreach ($b in 'BDup', 'BUp', 'BDown', 'BDel', 'BChild', 'BNest') { $S[$b].IsEnabled = $has }
    if (-not $has) { return }
    $r = $S.Rows[$Idx]
    $it = $r.Item
    if ($r.Level -gt 0) {
        $S.BNest.Content = 'На панель'
        $S.BNest.ToolTip = 'Сделать обычной кнопкой панели — встанет сразу за родителем'
        $S.BNest.IsEnabled = $true
    } else {
        $S.BNest.Content = 'В группу'
        if ($r.Item.children.Count -gt 0) {
            $S.BNest.ToolTip = 'У этой кнопки свои вложенные, а уровень вложенности один'
            $S.BNest.IsEnabled = $false
        } elseif ($r.Pos -eq 0) {
            $S.BNest.ToolTip = 'Нет кнопки выше, к которой вложить'
            $S.BNest.IsEnabled = $false
        } else {
            $S.BNest.ToolTip = 'Вложить в кнопку выше: раскроется веером, если задержать на ней мышь'
            $S.BNest.IsEnabled = $true
        }
    }
    $S.Loading = $true
    try {
        if ($S.LItems.SelectedIndex -ne $Idx) { $S.LItems.SelectedIndex = $Idx }
        $S.LItems.ScrollIntoView($S.LItems.SelectedItem)
        $S.EName.Text = [string]$it.name
        $S.EText.Text = [string]$it.text
        foreach ($rb in $S.EColors.Children) { $rb.IsChecked = ([string]$rb.Tag -eq [string]$it.color) }
        $ring = [string]$it.ring
        if (-not $ring) { $ring = 'solid' }
        foreach ($rb in $S.ERings.Children) { $rb.IsChecked = ([string]$rb.Tag -eq $ring) }
    } finally { $S.Loading = $false }
    Update-EditorPreview
}
function Update-FromEditor {
    param([string]$Field, $Value)
    $S = $script:SettingsState
    if (-not $S -or $S.Loading -or $S.Sel -lt 0) { return }
    $r = $S.Rows[$S.Sel]
    $it = $r.Item
    switch ($Field) {
        'name'  { $it.name = $S.EName.Text }
        'text'  { $it.text = $S.EText.Text }
        'color' { $it.color = [string]$Value }
        'icon'  { $it.icon = [string]$Value }
        'ring'  { $it.ring = [string]$Value }
    }
    Set-ListRow $S.LItems.Items[$S.Sel] $it $r.Level
    Update-EditorPreview
    Reset-DelArm
    Set-Dirty
}

function Update-EditorPreview {
    $S = $script:SettingsState
    if ($S.Sel -lt 0 -or $S.Sel -ge $S.Rows.Count) { return }
    $it = $S.Rows[$S.Sel].Item
    $S.EPreview.Children.Clear()
    [void]$S.EPreview.Children.Add((New-MiniCircle $it 46 28))
    $text = [string]$it.text
    if (-not $text) { $S.EResult.Text = '—'; return }
    $ans = @{}
    foreach ($l in (Get-TemplatePrompts $text)) { $ans[$l] = "‹$l›" }
    if ($null -eq $S.Ip) { $S.Ip = Get-LocalIp }
    $ctx = @{ Answers = $ans; Counter = ([int]$it.counter + 1); Clipboard = '‹буфер обмена›'; Ip = $S.Ip }
    $S.EResult.Text = Expand-Template $text $ctx
}

# --- Вид и поведение ---------------------------------------------------------
# Всё здесь применяется к панели сразу; на диск — по «Сохранить».

function Add-SettingsChips {
    param($Panel, $Pairs, [string]$Current, [string]$Key)
    foreach ($p in $Pairs) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $script:SettingsWin.FindResource('Chip')
        $rb.GroupName = $Key
        $rb.Content = $p[0]
        $rb.Tag = @{ Key = $Key; Value = $p[1] }
        if ($p.Count -gt 2) { $rb.ToolTip = $p[2] }
        if ([string]$p[1] -eq $Current) { $rb.IsChecked = $true }
        $rb.Add_Checked({ param($s, $e) try { Set-LookValue $s.Tag.Key $s.Tag.Value } catch { Write-ErrLog $_ 'вид' } })
        [void]$Panel.Children.Add($rb)
    }
}

function Set-LookValue {
    param([string]$Key, $Value)
    $S = $script:SettingsState
    if (-not $S -or $S.Loading) { return }
    $script:Cfg[$Key] = $Value
    if ($Key -eq 'theme' -or $Key -eq 'accent') {
        Update-Palette $script:Cfg
        Update-AllWindowPalettes
        Set-WindowPalette $script:Dock
        Update-SettingsColors
    }
    if ($Key -eq 'glass') { Update-AllWindowPalettes }
    if ($Key -eq 'edge') { $script:Cfg.offset = 0.5; $S.Loading = $true; $S.SOffset.Value = 0.5; $S.Loading = $false }
    Rebuild-Dock
    Set-Dirty
}

function Update-SettingsColors {
    # Кружки в списке и предпросмотре нарисованы кистями палитры — перерисовать
    $S = $script:SettingsState
    for ($i = 0; $i -lt $S.Rows.Count; $i++) { Set-ListRow $S.LItems.Items[$i] $S.Rows[$i].Item $S.Rows[$i].Level }
    Update-EditorPreview
}

function Initialize-SettingsLook {
    $S = $script:SettingsState
    $c = $script:Cfg
    $S.Loading = $true
    try {
        Add-SettingsChips $S.RTheme @(@('Как в Windows', 'auto'), @('Тёмная', 'dark'), @('Светлая', 'light')) $c.theme 'theme'
        Add-SettingsChips $S.RSize @(@('Мелкие', 'S'), @('Обычные', 'M'), @('Крупные', 'L')) $c.size 'size'
        Add-SettingsChips $S.REdge @(@('Снизу', 'bottom'), @('Сверху', 'top'), @('Слева', 'left'), @('Справа', 'right')) $c.edge 'edge'
        Add-SettingsChips $S.RMode @(
            @('Выезжает при наведении', 'auto', 'В покое у края только точки'),
            @('Всегда открыта', 'pinned', 'Кружки видны всё время'),
            @('Скрыта', 'hidden', 'Только сетка по хоткею и меню в трее')
        ) $c.mode 'mode'

        foreach ($k in $script:AccentNames.Keys) {
            $rb = New-Object Windows.Controls.RadioButton
            $rb.Style = $S.Win.FindResource('Dot')
            $rb.GroupName = 'accent'
            $pair = $script:AccentHex[$k]
            if ($script:IsLight) { $rb.Background = New-Brush $pair[1] } else { $rb.Background = New-Brush $pair[0] }
            $rb.ToolTip = $script:AccentNames[$k]
            $rb.Tag = @{ Key = 'accent'; Value = $k }
            if ($k -eq $c.accent) { $rb.IsChecked = $true }
            $rb.Add_Checked({ param($s, $e) try { Set-LookValue 'accent' $s.Tag.Value } catch { Write-ErrLog $_ 'акцент' } })
            [void]$S.RAccent.Children.Add($rb)
        }

        $S.SOffset.Value = [double]$c.offset
        $S.SDelay.Value = [double]$c.hideDelay
        $S.VDelay.Text = ('{0} мс' -f [int]$c.hideDelay)
        $S.SFan.Value = [double]$c.fanDelay
        $S.VFan.Text = ('{0} мс' -f [int]$c.fanDelay)
        $S.CMagnify.IsChecked = [bool]$c.magnify
        $S.SHotkey.Text = [string]$c.hotkey
        $S.VHotkey.Text = $script:HotkeyStatus
    } finally { $S.Loading = $false }

    $S.SOffset.Add_ValueChanged({
        $S = $script:SettingsState
        if ($S.Loading) { return }
        $script:Cfg.offset = [Math]::Round($S.SOffset.Value, 3)
        Set-DockPosition
        Set-Dirty
    })
    $S.SDelay.Add_ValueChanged({
        $S = $script:SettingsState
        if ($S.Loading) { return }
        $v = [int]([Math]::Round($S.SDelay.Value / 50) * 50)
        $S.VDelay.Text = ('{0} мс' -f $v)
        $script:Cfg.hideDelay = $v
        Set-Dirty
    })
    Update-AutostartToggle
    $S.CAutostart.Add_Click({
        try {
            Set-Autostart $script:Root ([bool]$script:SettingsState.CAutostart.IsChecked) -Exe $script:ExePath
            Update-AutostartToggle
        } catch { Show-Err $_ 'автозапуск' }
    })
    $S.SFan.Add_ValueChanged({
        $S = $script:SettingsState
        if ($S.Loading) { return }
        $v = [int]([Math]::Round($S.SFan.Value / 50) * 50)
        $S.VFan.Text = ('{0} мс' -f $v)
        $script:Cfg.fanDelay = $v
        Set-Dirty
    })
    $S.CMagnify.Add_Click({
        $script:Cfg.magnify = [bool]$script:SettingsState.CMagnify.IsChecked
        Set-Dirty
    })
    $S.BHotkey.Add_Click({ try { Set-SettingsHotkey } catch { Write-ErrLog $_ 'хоткей' } })
    $S.SHotkey.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Set-SettingsHotkey } })
    $S.BCfg.Add_Click({ Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:CfgPath) })
    $S.BDir.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:Root) })
}

function Set-SettingsHotkey {
    $S = $script:SettingsState
    try {
        $h = ConvertFrom-Hotkey $S.SHotkey.Text
        if ($h) { $script:Cfg.hotkey = $h.Text; $S.SHotkey.Text = $h.Text } else { $script:Cfg.hotkey = '' }
        $S.VHotkey.Text = Register-AppHotkey
        Update-TrayIcon
        Set-Dirty
    } catch {
        $S.VHotkey.Text = $_.Exception.Message
    }
}

# --- Сохранение и закрытие ---------------------------------------------------

function ConvertFrom-WorkItem {
    <#
        Рабочая копия -> живая кнопка. Пока окно было открыто, счётчики
        могли вырасти кликами по панели: берётся больший из двух.
    #>
    param($W)
    $cnt = [int]$W.counter
    if ($W.Contains('_src') -and $W['_src']) { $cnt = [Math]::Max($cnt, [int]$W['_src'].counter) }
    $n = New-ClipItem -Name ([string]$W.name) -Text ([string]$W.text) -Icon ([string]$W.icon) -Color ([string]$W.color) -Counter $cnt -Ring ([string]$W.ring)
    foreach ($ch in $W.children) { [void]$n.children.Add((ConvertFrom-WorkItem $ch)) }
    $W['_src'] = $n
    $W.counter = $cnt
    return $n
}

function Save-Settings {
    $S = $script:SettingsState
    $list = New-Object System.Collections.ArrayList
    foreach ($w in $S.Items) { [void]$list.Add((ConvertFrom-WorkItem $w)) }
    $script:Cfg.items = $list
    Save-Config
    $S.Snapshot = ConvertTo-ConfigJson $script:Cfg
    $S.Dirty = $false
    Reset-CloseArm
    $S.SStatus.Text = 'Сохранено в ' + (Get-Date -Format 'HH:mm:ss')
    $S.SStatus.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Ok')
    Close-Fan -Now
    Rebuild-Dock
}
function Close-Settings {
    $S = $script:SettingsState
    if (-not $S) { return }
    if ($S.Dirty -and -not $S.CloseArmed) {
        # Закрытие с несохранённым — со второго нажатия, как удаление
        $S.CloseArmed = $true
        $S.SCancel.Content = 'Закрыть без сохранения'
        $S.SCancel.Style = $S.Win.FindResource('Danger')
        $S.SStatus.Text = 'Изменения не сохранены. Ещё раз «Закрыть» — выйти без них'
        return
    }
    if ($S.Dirty) {
        # Вид панели менялся вживую — возвращаем сохранённый
        # Кнопки правились в рабочей копии и в живой конфиг не попадали —
        # они остаются как есть, со счётчиками; откатывается только вид
        $snap = ConvertTo-ClipConfig ($S.Snapshot | ConvertFrom-Json)
        foreach ($k in @($snap.Keys)) { if ($k -ne 'items' -and $k -ne 'recentEmoji') { $script:Cfg[$k] = $snap[$k] } }
        Update-Palette $script:Cfg
        Update-AllWindowPalettes
        Set-WindowPalette $script:Dock
        [void](Register-AppHotkey)
        Rebuild-Dock
    } else {
        # Недавние эмодзи копятся и без явного сохранения
        Save-Config
    }
    $S.Win.Close()
}

function Update-AutostartToggle {
    <# Переключатель показывает то, что на самом деле записано в реестре. #>
    $S = $script:SettingsState
    $st = Get-AutostartState $script:Root -Exe $script:ExePath
    $S.CAutostart.IsChecked = $st.On
    if ($st.Other) {
        $S.VAutostart.Text = "Сейчас при входе запускается другая копия: $($st.Other). Включите, чтобы запускалась эта."
    } else {
        $S.VAutostart.Text = 'Применяется сразу, без «Сохранить»'
    }
}
