#requires -Version 5.1
<#
    Общее для всех окон FryBuffer: палитра, стили, стеклянные окна,
    цветные эмодзи и выбор эмодзи «как на телефоне».
#>

# --- Палитра -----------------------------------------------------------------
# Тёмная и светлая палитры, акцент выбирается отдельно.

$script:PalDark = @{
    Bg = '#0D1117'; Panel = '#161B22'; Field = '#0D1117'; Btn = '#21262D'; BtnHover = '#30363D'
    Line = '#30363D'; LineStrong = '#484F58'; Text = '#E6EDF3'; Sub = '#8B949E'; Hover = '#B1BAC4'
    Ok = '#3FB950'; Err = '#F85149'; Warn = '#D29922'; OnAccent = '#0D1117'; Shade = '#010409'
}
$script:PalLight = @{
    Bg = '#FFFFFF'; Panel = '#F6F8FA'; Field = '#FFFFFF'; Btn = '#F6F8FA'; BtnHover = '#EAEEF2'
    Line = '#D0D7DE'; LineStrong = '#AFB8C1'; Text = '#1F2328'; Sub = '#656D76'; Hover = '#6E7781'
    Ok = '#1A7F37'; Err = '#CF222E'; Warn = '#9A6700'; OnAccent = '#FFFFFF'; Shade = '#8C959F'
}
$script:AccentHex = @{
    blue   = @('#58A6FF', '#0969DA')
    green  = @('#3FB950', '#1A7F37')
    purple = @('#BC8CFF', '#8250DF')
    orange = @('#F0883E', '#BC4C00')
    pink   = @('#F778BA', '#BF3989')
}
$script:AccentNames = [ordered]@{ blue = 'Синий'; green = 'Зелёный'; purple = 'Фиолетовый'; orange = 'Оранжевый'; pink = 'Розовый' }

$script:Pal = $script:PalDark.Clone()
$script:IsLight = $false
$script:PaintedWindows = New-Object System.Collections.ArrayList

function Get-SystemLight {
    try {
        $v = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        return ([int]$v -eq 1)
    } catch { return $false }
}

function Update-Palette {
    param($Cfg)
    $light = $false
    switch ($Cfg.theme) {
        'light' { $light = $true }
        'dark'  { $light = $false }
        default { $light = Get-SystemLight }
    }
    $script:IsLight = $light
    if ($light) { $p = $script:PalLight.Clone() } else { $p = $script:PalDark.Clone() }
    $pair = $script:AccentHex[[string]$Cfg.accent]
    if (-not $pair) { $pair = $script:AccentHex.blue }
    if ($light) { $p.Accent = $pair[1] } else { $p.Accent = $pair[0] }
    $script:Pal = $p
}

function Get-Rgb([string]$Hex) {
    $t = $Hex.TrimStart('#')
    if ($t.Length -eq 8) { $t = $t.Substring(2) }
    return @([Convert]::ToInt32($t.Substring(0, 2), 16), [Convert]::ToInt32($t.Substring(2, 2), 16), [Convert]::ToInt32($t.Substring(4, 2), 16))
}

function New-Color([string]$Hex, [int]$Alpha = 255) {
    $c = Get-Rgb $Hex
    return [Windows.Media.Color]::FromArgb([byte]$Alpha, [byte]$c[0], [byte]$c[1], [byte]$c[2])
}

function New-Brush([string]$Hex, [int]$Alpha = 255) {
    $b = New-Object Windows.Media.SolidColorBrush (New-Color $Hex $Alpha)
    $b.Freeze()
    return $b
}

function ConvertTo-Abgr([string]$Hex, [int]$Alpha) {
    $c = Get-Rgb $Hex
    $v = [int64]$Alpha * 16777216 + [int64]$c[2] * 65536 + [int64]$c[1] * 256 + [int64]$c[0]
    if ($v -gt 2147483647) { $v -= 4294967296 }
    return [int]$v
}

function Set-WindowPalette {
    param($Win)
    $p = $script:Pal
    $r = $Win.Resources
    foreach ($k in 'Bg', 'Panel', 'Field', 'Btn', 'BtnHover', 'Line', 'LineStrong', 'Text', 'Sub', 'Ok', 'Err', 'Warn', 'OnAccent', 'Accent') {
        $r["B.$k"] = [Windows.Media.SolidColorBrush](New-Brush $p[$k])
    }
    $r['B.Hover']      = [Windows.Media.SolidColorBrush](New-Brush $p.Hover 0x1F)
    $r['B.Press']      = [Windows.Media.SolidColorBrush](New-Brush $p.Hover 0x33)
    $r['B.AccentSoft'] = [Windows.Media.SolidColorBrush](New-Brush $p.Accent 0x26)
    $r['B.ErrSoft']    = [Windows.Media.SolidColorBrush](New-Brush $p.Err 0x22)
    $r['B.OkSoft']     = [Windows.Media.SolidColorBrush](New-Brush $p.Ok 0x2A)
    $r['B.Glass']      = [Windows.Media.SolidColorBrush](New-Brush $p.Line 0xD0)
}

function Register-PaintedWindow {
    param($Win)
    [void]$script:PaintedWindows.Add($Win)
    $Win.Add_Closed({ param($s, $e) $script:PaintedWindows.Remove($s) })
}

function Update-AllWindowPalettes {
    foreach ($w in @($script:PaintedWindows)) {
        try { Set-WindowPalette $w; Set-Glass $w $w.Tag.Strength } catch { Write-ErrLog $_ 'перекраска окна' }
    }
}

# --- Стили -------------------------------------------------------------------

$script:Styles = @'
<Style TargetType="ToolTip">
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ToolTip">
        <Border Background="{DynamicResource B.Panel}" BorderBrush="{DynamicResource B.Line}" BorderThickness="1" CornerRadius="8" Padding="10,6" Margin="2">
          <ContentPresenter TextElement.Foreground="{DynamicResource B.Text}" TextElement.FontSize="12"/>
        </Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="Lbl" TargetType="TextBlock">
  <Setter Property="Foreground" Value="{DynamicResource B.Sub}"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="Margin" Value="0,14,0,6"/>
</Style>
<Style x:Key="H" TargetType="TextBlock">
  <Setter Property="Foreground" Value="{DynamicResource B.Text}"/>
  <Setter Property="FontSize" Value="14"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
</Style>
<Style x:Key="Hint" TargetType="TextBlock">
  <Setter Property="Foreground" Value="{DynamicResource B.Sub}"/>
  <Setter Property="FontSize" Value="11.5"/>
  <Setter Property="TextWrapping" Value="Wrap"/>
</Style>

<Style x:Key="Btn" TargetType="Button">
  <Setter Property="Background" Value="{DynamicResource B.Btn}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource B.Line}"/>
  <Setter Property="Foreground" Value="{DynamicResource B.Text}"/>
  <Setter Property="Padding" Value="14,6"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6">
          <Grid>
            <Border x:Name="Ov" CornerRadius="5" Background="{DynamicResource B.Hover}" Opacity="0"/>
            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ov" Property="Opacity" Value="1"/></Trigger>
          <Trigger Property="IsPressed" Value="True"><Setter TargetName="Ov" Property="Background" Value="{DynamicResource B.Press}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
<Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="{DynamicResource B.Accent}"/>
  <Setter Property="BorderBrush" Value="{DynamicResource B.Accent}"/>
  <Setter Property="Foreground" Value="{DynamicResource B.OnAccent}"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
</Style>
<Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="BorderBrush" Value="Transparent"/>
  <Setter Property="Foreground" Value="{DynamicResource B.Sub}"/>
</Style>
<Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Foreground" Value="{DynamicResource B.Err}"/>
</Style>
<Style x:Key="Round" TargetType="Button">
  <Setter Property="Width" Value="34"/>
  <Setter Property="Height" Value="34"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Focusable" Value="False"/>
  <Setter Property="Foreground" Value="{DynamicResource B.Text}"/>
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Grid Background="Transparent">
          <Ellipse x:Name="Bg" Fill="{TemplateBinding Background}"/>
          <Ellipse x:Name="Ov" Fill="{DynamicResource B.Hover}" Opacity="0"/>
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ov" Property="Opacity" Value="1"/></Trigger>
          <Trigger Property="IsPressed" Value="True"><Setter TargetName="Ov" Property="Fill" Value="{DynamicResource B.Press}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
<Style x:Key="Cell" TargetType="Button" BasedOn="{StaticResource Round}">
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Grid Background="Transparent">
          <Border x:Name="Ov" CornerRadius="8" Background="{DynamicResource B.Hover}" Opacity="0"/>
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ov" Property="Opacity" Value="1"/></Trigger>
          <Trigger Property="IsPressed" Value="True"><Setter TargetName="Ov" Property="Background" Value="{DynamicResource B.Press}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style TargetType="TextBox">
  <Setter Property="Foreground" Value="{DynamicResource B.Text}"/>
  <Setter Property="CaretBrush" Value="{DynamicResource B.Text}"/>
  <Setter Property="SelectionBrush" Value="{DynamicResource B.Accent}"/>
  <Setter Property="Padding" Value="9,6"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="TextBox">
        <Border x:Name="Bd" Background="{DynamicResource B.Field}" BorderBrush="{DynamicResource B.Line}" BorderThickness="1" CornerRadius="6">
          <Grid>
            <TextBlock x:Name="Ph" Text="{TemplateBinding Tag}" Foreground="{DynamicResource B.Sub}" Margin="{TemplateBinding Padding}" Padding="2,0,0,0" Visibility="Collapsed" IsHitTestVisible="False"/>
            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="Text" Value=""><Setter TargetName="Ph" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource B.Accent}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="Chip" TargetType="RadioButton">
  <Setter Property="Foreground" Value="{DynamicResource B.Text}"/>
  <Setter Property="Margin" Value="0,0,6,6"/>
  <Setter Property="Padding" Value="12,5"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="RadioButton">
        <Border x:Name="Bd" Background="{DynamicResource B.Btn}" BorderBrush="{DynamicResource B.Line}" BorderThickness="1" CornerRadius="14">
          <Grid>
            <Border x:Name="Ov" CornerRadius="13" Background="{DynamicResource B.Hover}" Opacity="0"/>
            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ov" Property="Opacity" Value="1"/></Trigger>
          <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource B.AccentSoft}"/>
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource B.Accent}"/>
            <Setter Property="Foreground" Value="{DynamicResource B.Accent}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="Dot" TargetType="RadioButton">
  <Setter Property="Width" Value="24"/>
  <Setter Property="Height" Value="24"/>
  <Setter Property="Margin" Value="3,3,9,3"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Foreground" Value="{DynamicResource B.Sub}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="RadioButton">
        <Grid Background="Transparent">
          <Ellipse x:Name="Ring" Margin="-4" Stroke="{DynamicResource B.Text}" StrokeThickness="2" Visibility="Collapsed"/>
          <Ellipse Fill="{TemplateBinding Background}" Stroke="{DynamicResource B.LineStrong}" StrokeThickness="1"/>
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="Ring" Property="Visibility" Value="Visible"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="Toggle" TargetType="CheckBox">
  <Setter Property="Foreground" Value="{DynamicResource B.Text}"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="CheckBox">
        <StackPanel Orientation="Horizontal" Background="Transparent">
          <Grid Width="34" Height="18" VerticalAlignment="Center">
            <Border x:Name="Tr" CornerRadius="9" Background="{DynamicResource B.LineStrong}"/>
            <Ellipse x:Name="Kn" Width="12" Height="12" HorizontalAlignment="Left" Margin="3,0" Fill="{DynamicResource B.Text}"/>
          </Grid>
          <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="Tr" Property="Background" Value="{DynamicResource B.Accent}"/>
            <Setter TargetName="Kn" Property="HorizontalAlignment" Value="Right"/>
            <Setter TargetName="Kn" Property="Fill" Value="{DynamicResource B.OnAccent}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="SliderFill" TargetType="RepeatButton">
  <Setter Property="OverridesDefaultStyle" Value="True"/>
  <Setter Property="Focusable" Value="False"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="RepeatButton">
        <Border Height="4" CornerRadius="2" Background="{DynamicResource B.Accent}"/>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
<Style x:Key="SliderBlank" TargetType="RepeatButton">
  <Setter Property="OverridesDefaultStyle" Value="True"/>
  <Setter Property="Focusable" Value="False"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="RepeatButton">
        <Border Background="Transparent"/>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
<Style TargetType="Slider">
  <Setter Property="Height" Value="22"/>
  <Setter Property="IsMoveToPointEnabled" Value="True"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Slider">
        <Grid Background="Transparent">
          <Border Height="4" CornerRadius="2" Background="{DynamicResource B.Line}" VerticalAlignment="Center"/>
          <Track x:Name="PART_Track" VerticalAlignment="Center">
            <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Style="{StaticResource SliderFill}"/></Track.DecreaseRepeatButton>
            <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Style="{StaticResource SliderBlank}"/></Track.IncreaseRepeatButton>
            <Track.Thumb>
              <Thumb>
                <Thumb.Template>
                  <ControlTemplate TargetType="Thumb">
                    <Ellipse Width="16" Height="16" Fill="{DynamicResource B.Text}" Stroke="{DynamicResource B.Accent}" StrokeThickness="3"/>
                  </ControlTemplate>
                </Thumb.Template>
              </Thumb>
            </Track.Thumb>
          </Track>
        </Grid>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style TargetType="ScrollBar">
  <Setter Property="Width" Value="8"/>
  <Setter Property="MinWidth" Value="8"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ScrollBar">
        <Track x:Name="PART_Track" IsDirectionReversed="True">
          <Track.Thumb>
            <Thumb>
              <Thumb.Template>
                <ControlTemplate TargetType="Thumb">
                  <Border CornerRadius="3" Background="{DynamicResource B.LineStrong}" Margin="1,2"/>
                </ControlTemplate>
              </Thumb.Template>
            </Thumb>
          </Track.Thumb>
        </Track>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="Row" TargetType="ListBoxItem">
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ListBoxItem">
        <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="8,5" Margin="0,0,0,2">
          <ContentPresenter/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource B.Hover}"/></Trigger>
          <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource B.AccentSoft}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@

function Get-SharedStyle([string]$Key) {
    <#
        Стиль для элемента, который ещё не вставлен в окно: FindResource
        ищет вверх по дереву, а у свежесозданного элемента дерева нет.
        Кисти внутри стиля — DynamicResource и найдутся уже в окне.
    #>
    if (-not $script:StyleDict) {
        $script:StyleDict = [Windows.Markup.XamlReader]::Parse(
            '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">' +
            $script:Styles + '</ResourceDictionary>')
    }
    return $script:StyleDict[$Key]
}

# Поле вокруг всплывающих окон под тень
$script:WinPad = 10

function New-WindowXaml {
    <#
        Окно без системной рамки. Тело подставляется внутрь Plate; Plate —
        подложка, рамка и скругление, Shade под ним — мягкая тень. Вокруг
        поле $script:WinPad под тень: скругление и тень рисует WPF с
        прозрачностью по пикселям, поэтому углы чистые на любом фоне.
    #>
    param([string]$Body, [double]$Radius = 12, [string]$Attrs = 'SizeToContent="WidthAndHeight"', [string]$Padding = '0')
    return @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        ShowInTaskbar="False" Topmost="True" UseLayoutRounding="True" SnapsToDevicePixels="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="{DynamicResource B.Text}"
        Title="FryBuffer" $Attrs>
  <Window.Resources>$($script:Styles)</Window.Resources>
  <Grid Margin="$($script:WinPad)">
    <Border x:Name="Shade" CornerRadius="$Radius" Background="{DynamicResource B.Bg}">
      <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Direction="270" Opacity="0.35" Color="Black"/></Border.Effect>
    </Border>
    <Border x:Name="Plate" CornerRadius="$Radius" BorderThickness="1" BorderBrush="{DynamicResource B.Glass}" Padding="$Padding">
$Body
    </Border>
  </Grid>
</Window>
"@
}

function Get-DpiScale($Visual) {
    try { return [Windows.Media.VisualTreeHelper]::GetDpi($Visual).DpiScaleX } catch { return 1.0 }
}

function Set-Glass {
    <#
        Подложка окна. Системное размытие (SetWindowCompositionAttribute)
        здесь не используется: оно не слушается скруглённой формы окна и
        на светлом фоне закрашивает вокруг пилюли прозрачный прямоугольник.
        Почти непрозрачная подложка с тенью выглядит чисто везде.
    #>
    param($Win, [double]$Strength = 0)
    $plate = $Win.FindName('Plate')
    if ($plate) { $plate.Background = New-Brush $script:Pal.Bg 0xF4 }
}
function New-GlassWindow {
    param([string]$Xaml, [double]$Radius = 12, [switch]$NoActivate, [switch]$AppWindow, [double]$Strength = 0.78)
    $w = [Windows.Markup.XamlReader]::Parse($Xaml)
    $w.Tag = @{ Radius = $Radius; NoActivate = [bool]$NoActivate; App = [bool]$AppWindow; Strength = $Strength }
    Set-WindowPalette $w
    Register-PaintedWindow $w
    $w.Add_SourceInitialized({
        param($s, $e)
        try {
            $h = (New-Object Windows.Interop.WindowInteropHelper $s).Handle
            if ($s.Tag.NoActivate) { [ClipNative]::MakeNoActivate($h) } elseif (-not $s.Tag.App) { [ClipNative]::MakeToolWindow($h) }
            Set-Glass $s $s.Tag.Strength
        } catch { Write-ErrLog $_ 'стекло окна' }
    })
    return $w
}

function Show-AppWindow {
    <#
        Все окна показываются через эту функцию. Если задан SnapshotDir,
        окно не показывается, а рисуется в PNG: так проверяется вёрстка
        без фокуса и мыши — проверка не должна мешать работе за машиной.
    #>
    param($Win, [switch]$Dialog)
    if ($script:SnapshotDir) { Save-WindowSnapshot $Win; return }
    if ($Dialog) { [void]$Win.ShowDialog() } else { $Win.Show() }
}

function Save-WindowSnapshot {
    param($Win, [string]$Name = '')
    $plate = $Win.FindName('Plate')
    if ($plate) { $plate.Background = New-Brush $script:Pal.Bg 0xF4 }
    $root = $Win.Content
    # У непоказанного окна смена видимости не помечает раскладку грязной,
    # и Measure возвращает старый размер — сбрасываем вручную по всему дереву
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count) {
        $el = $stack.Pop()
        if ($el -is [Windows.UIElement]) { $el.InvalidateMeasure() }
        if ($el -is [Windows.DependencyObject]) {
            foreach ($ch in [Windows.LogicalTreeHelper]::GetChildren($el)) { if ($ch -is [Windows.DependencyObject]) { $stack.Push($ch) } }
            if ($el -is [Windows.Media.Visual]) {
                for ($vi = 0; $vi -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($el); $vi++) { $stack.Push([Windows.Media.VisualTreeHelper]::GetChild($el, $vi)) }
            }
        }
    }
    if ($Win.SizeToContent -eq 'Manual' -or $Win.SizeToContent -eq 'Height') {
        $size = New-Object Windows.Size $Win.Width, $Win.Height
        if ($Win.SizeToContent -eq 'Height') { $size = New-Object Windows.Size $Win.Width, ([double]::PositiveInfinity) }
    } else {
        $size = New-Object Windows.Size ([double]::PositiveInfinity), ([double]::PositiveInfinity)
    }
    $root.Measure($size)
    $w = $root.DesiredSize.Width; $h = $root.DesiredSize.Height
    if ($Win.SizeToContent -eq 'Manual') { $w = $Win.Width; $h = $Win.Height }
    $root.Arrange((New-Object Windows.Rect 0, 0, $w, $h))
    # Второй проход: элементы, созданные шаблонами при первом, тоже раскладываются
    $root.Measure($size)
    $root.Arrange((New-Object Windows.Rect 0, 0, $w, $h))
    $k = 1.5
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($w * $k)), ([int]($h * $k)), (96 * $k), (96 * $k), ([Windows.Media.PixelFormats]::Pbgra32)
    # Подложка «экрана», чтобы прозрачные углы не сливались с белым
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    if (-not $script:SnapshotBare) { $dc.DrawRectangle((New-Brush '#6E7681'), $null, (New-Object Windows.Rect 0, 0, $w, $h)) }
    $dc.Close()
    $bmp.Render($dv)
    $bmp.Render($root)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $script:LastSnapWin = $Win
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $script:SnapshotNo++
    if (-not $Name) { $Name = $script:SnapshotName }
    $path = Join-Path $script:SnapshotDir ('{0:00}-{1}.png' -f $script:SnapshotNo, $Name)
    $fs = [IO.File]::Create($path)
    $enc.Save($fs)
    $fs.Close()
}

function Get-WorkAreaAt {
    <#
        Рабочая область монитора под точкой — в единицах WPF.
        Screen отдаёт физические пиксели, WPF меряет в 1/96 дюйма.
    #>
    param([double]$X, [double]$Y, [double]$Scale)
    $pt = New-Object Drawing.Point ([int]($X * $Scale)), ([int]($Y * $Scale))
    $wa = [Windows.Forms.Screen]::FromPoint($pt).WorkingArea
    return New-Object Windows.Rect ($wa.X / $Scale), ($wa.Y / $Scale), ($wa.Width / $Scale), ($wa.Height / $Scale)
}

function Get-CursorDip {
    param([double]$Scale)
    $p = [Windows.Forms.Cursor]::Position
    return New-Object Windows.Point ($p.X / $Scale), ($p.Y / $Scale)
}

function Get-ElementScreenRect {
    param($El, [double]$Scale)
    $a = $El.PointToScreen((New-Object Windows.Point 0, 0))
    $b = $El.PointToScreen((New-Object Windows.Point $El.ActualWidth, $El.ActualHeight))
    return New-Object Windows.Rect ([Math]::Min($a.X, $b.X) / $Scale), ([Math]::Min($a.Y, $b.Y) / $Scale), ([Math]::Abs($b.X - $a.X) / $Scale), ([Math]::Abs($b.Y - $a.Y) / $Scale)
}

function Move-NearRect {
    <#
        Ставит окно рядом с прямоугольником-якорем со стороны, обращённой
        внутрь экрана: у нижнего края — над ним, у левого — справа и т. д.
        Не даёт вылезти за рабочую область.
    #>
    param($Win, [Windows.Rect]$Anchor, [string]$Edge, [double]$Gap = 10)
    $sc = Get-DpiScale $Win
    $wa = Get-WorkAreaAt ($Anchor.X + $Anchor.Width / 2) ($Anchor.Y + $Anchor.Height / 2) $sc
    if ($Win.FindName('Shade')) { $Gap -= $script:WinPad }
    $w = $Win.ActualWidth; $h = $Win.ActualHeight
    $cx = $Anchor.X + $Anchor.Width / 2; $cy = $Anchor.Y + $Anchor.Height / 2
    switch ($Edge) {
        'top'   { $x = $cx - $w / 2; $y = $Anchor.Bottom + $Gap }
        'left'  { $x = $Anchor.Right + $Gap; $y = $cy - $h / 2 }
        'right' { $x = $Anchor.Left - $w - $Gap; $y = $cy - $h / 2 }
        default { $x = $cx - $w / 2; $y = $Anchor.Top - $h - $Gap }
    }
    $Win.Left = [Math]::Max($wa.Left + 6, [Math]::Min($x, $wa.Right - $w - 6))
    $Win.Top  = [Math]::Max($wa.Top + 6, [Math]::Min($y, $wa.Bottom - $h - 6))
}

# --- Эмодзи ------------------------------------------------------------------
# WPF рисует эмодзи шрифтом одноцветными контурами, поэтому берём готовые
# цветные картинки Noto из папки emoji/img. Имя файла — коды символов
# через дефис, как в каталоге.

if (-not $script:EmojiRoot) { $script:EmojiRoot = Join-Path $script:Root 'emoji' }
$script:EmojiImgDir = Join-Path $script:EmojiRoot 'img'
$script:EmojiCache  = @{}
$script:Catalog     = $null
$script:CatalogMap  = $null

function Get-EmojiKey([string]$E) {
    if (-not $E) { return $null }
    $parts = New-Object System.Collections.Generic.List[string]
    $i = 0
    try {
        while ($i -lt $E.Length) {
            $cp = [char]::ConvertToUtf32($E, $i)
            if ([char]::IsHighSurrogate($E[$i])) { $i += 2 } else { $i++ }
            $parts.Add(('{0:x}' -f $cp))
        }
    } catch { return $null }
    return ($parts -join '-')
}

function Get-EmojiCatalog {
    if (-not $script:Catalog) {
        $path = Join-Path $script:EmojiRoot 'catalog.json'
        $script:Catalog = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $map = @{}
        foreach ($t in $script:Catalog.tabs) {
            foreach ($it in $t.items) {
                $map[$it.k.Replace('-fe0f', '')] = $it.k
                if ($it.q) { $map[$it.q] = $it.k }
            }
        }
        $script:CatalogMap = $map
    }
    return $script:Catalog
}

function Get-EmojiImage([string]$E) {
    $key = Get-EmojiKey $E
    if (-not $key) { return $null }
    if ($script:EmojiCache.ContainsKey($key)) { return $script:EmojiCache[$key] }
    $path = Join-Path $script:EmojiImgDir "$key.png"
    if (-not (Test-Path -LiteralPath $path)) {
        # Символ, набранный руками, часто без невидимого FE0F — ищем по каталогу
        try {
            [void](Get-EmojiCatalog)
            $alt = $script:CatalogMap[$key.Replace('-fe0f', '')]
            if ($alt) { $path = Join-Path $script:EmojiImgDir "$alt.png" }
        } catch { }
    }
    $img = $null
    if (Test-Path -LiteralPath $path) {
        try {
            $img = New-Object Windows.Media.Imaging.BitmapImage
            $img.BeginInit()
            $img.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $img.UriSource = New-Object Uri $path
            $img.EndInit()
            $img.Freeze()
        } catch { $img = $null; Write-ErrLog $_ "картинка эмодзи $path" }
    }
    $script:EmojiCache[$key] = $img
    return $img
}

function New-EmojiVisual {
    <# Цветная картинка эмодзи, а если её нет — буква или сам символ шрифтом. #>
    param([string]$E, [double]$Px, [string]$Fallback = '')
    $src = Get-EmojiImage $E
    if ($src) {
        $im = New-Object Windows.Controls.Image
        $im.Source = $src
        $im.Width = $Px; $im.Height = $Px
        $im.IsHitTestVisible = $false
        [Windows.Media.RenderOptions]::SetBitmapScalingMode($im, [Windows.Media.BitmapScalingMode]::HighQuality)
        return $im
    }
    $tb = New-Object Windows.Controls.TextBlock
    $tb.IsHitTestVisible = $false
    $tb.HorizontalAlignment = 'Center'
    $tb.VerticalAlignment = 'Center'
    $tb.TextAlignment = 'Center'
    if ($E) {
        $tb.Text = $E
        $tb.FontFamily = 'Segoe UI Emoji'
        $tb.FontSize = $Px * 0.8
    } else {
        $t = ([string]$Fallback).Trim()
        if ($t) { $tb.Text = $t.Substring(0, 1).ToUpper() } else { $tb.Text = '?' }
        $tb.FontWeight = 'SemiBold'
        $tb.FontSize = $Px * 0.72
    }
    $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'B.Text')
    return $tb
}

function New-EmojiFromKey([string]$Key) {
    -join ($Key.Split('-') | ForEach-Object { [char]::ConvertFromUtf32([Convert]::ToInt32($_, 16)) })
}

# --- Выбор эмодзи ------------------------------------------------------------
# Как клавиатура телефона: вкладки категорий значками сверху, поиск по
# русским и английским словам, первой вкладкой — недавние.

$script:PickerXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/>
    <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>
  <TextBox x:Name="PkSearch" Grid.Row="0" Tag="Найти эмодзи: кот, ключ, server…"/>
  <StackPanel x:Name="PkTabs" Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,4"/>
  <ScrollViewer x:Name="PkScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <WrapPanel x:Name="PkGrid"/>
  </ScrollViewer>
  <TextBlock x:Name="PkName" Grid.Row="3" Style="{DynamicResource Hint}" Margin="2,6,0,0" Text=" "/>
</Grid>
'@

function New-EmojiPicker {
    <#
        Возвращает элемент выбора эмодзи. OnPick вызывается с (State, Emoji).
        В State можно положить что угодно своё — например, ссылку на кнопку,
        которой меняется значок: замыкания в обработчиках WPF не работают
        с функциями скрипта, поэтому контекст едет через Tag.
    #>
    param([scriptblock]$OnPick, [hashtable]$Context = @{}, [int]$Cols = 9, [double]$Cell = 34, [int]$Rows = 6)
    $root = [Windows.Markup.XamlReader]::Parse($script:PickerXaml)
    $st = @{
        Root = $root; OnPick = $OnPick; Context = $Context; Cell = $Cell; Tab = ''
        Search = $root.FindName('PkSearch'); Tabs = $root.FindName('PkTabs')
        Grid = $root.FindName('PkGrid'); Name = $root.FindName('PkName'); Scroll = $root.FindName('PkScroll')
    }
    $root.Tag = $st
    $st.Grid.Width = $Cols * $Cell
    $st.Scroll.Height = $Rows * $Cell
    $st.Scroll.Width = $Cols * $Cell + 10

    $cat = Get-EmojiCatalog
    $tabs = @(@{ id = 'recent'; name = 'Недавние'; icon = '1f552' }) + @($cat.tabs | ForEach-Object { @{ id = $_.id; name = $_.name; icon = $_.icon } })
    foreach ($t in $tabs) {
        $b = New-Object Windows.Controls.Primitives.ToggleButton
        $b.Width = 30; $b.Height = 30; $b.Margin = '0,0,2,0'
        $b.Cursor = 'Hand'; $b.Focusable = $false
        $b.ToolTip = $t.name
        if (-not $script:TabTemplate) {
            $script:TabTemplate = [Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="ToggleButton">
  <Grid Background="Transparent">
    <Border x:Name="Ov" CornerRadius="8" Background="{DynamicResource B.Hover}" Opacity="0"/>
    <Border x:Name="Bar" Height="2" Width="14" CornerRadius="1" VerticalAlignment="Bottom" Background="{DynamicResource B.Accent}" Opacity="0"/>
    <ContentPresenter x:Name="Cp" HorizontalAlignment="Center" VerticalAlignment="Center" Opacity="0.7"/>
  </Grid>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ov" Property="Opacity" Value="1"/></Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter TargetName="Bar" Property="Opacity" Value="1"/><Setter TargetName="Cp" Property="Opacity" Value="1"/></Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
'@)
        }
        $b.Template = $script:TabTemplate
        $b.Content = New-EmojiVisual (New-EmojiFromKey $t.icon) 18
        $b.Tag = @{ State = $st; Id = $t.id }
        $b.Add_Click({ param($s, $e) try { $s.Tag.State.Search.Text = ''; Show-PickerTab $s.Tag.State $s.Tag.Id } catch { Write-ErrLog $_ 'вкладка эмодзи' } })
        [void]$st.Tabs.Children.Add($b)
    }
    $st.Search.Tag = 'Найти эмодзи: кот, ключ, server…'
    $st.Search.Add_TextChanged({ param($s, $e) try { Update-PickerSearch $s.Parent.Tag } catch { Write-ErrLog $_ 'поиск эмодзи' } })

    if (@($script:Cfg.recentEmoji).Count -gt 0) { Show-PickerTab $st 'recent' } else { Show-PickerTab $st 'smileys' }
    return $root
}

function Set-PickerCells {
    param($St, $Items)
    $g = $St.Grid
    $g.Children.Clear()
    $px = [Math]::Round($St.Cell * 0.68)
    foreach ($it in $Items) {
        $b = New-Object Windows.Controls.Button
        $b.Style = Get-SharedStyle 'Cell'
        $b.Width = $St.Cell; $b.Height = $St.Cell
        $b.Content = New-EmojiVisual $it.e $px
        $b.Tag = @{ State = $St; E = $it.e; N = $it.n }
        $b.Add_MouseEnter({ param($s, $e) $s.Tag.State.Name.Text = $s.Tag.N })
        $b.Add_Click({
            param($s, $e)
            try {
                $t = $s.Tag
                Add-RecentEmoji $script:Cfg $t.E
                & $t.State.OnPick $t.State $t.E
            } catch { Write-ErrLog $_ 'выбор эмодзи' }
        })
        [void]$g.Children.Add($b)
    }
    $St.Scroll.ScrollToTop()
}

function Show-PickerTab {
    param($St, [string]$Id)
    $St.Tab = $Id
    foreach ($b in $St.Tabs.Children) { $b.IsChecked = ($b.Tag.Id -eq $Id) }
    if ($Id -eq 'recent') {
        $items = @($script:Cfg.recentEmoji | ForEach-Object { @{ e = $_; n = '' } })
        if ($items.Count -eq 0) { $St.Name.Text = 'Здесь появятся эмодзи, которые вы выбирали' }
    } else {
        $tab = (Get-EmojiCatalog).tabs | Where-Object { $_.id -eq $Id } | Select-Object -First 1
        $items = @($tab.items)
        $St.Name.Text = $tab.name
    }
    Set-PickerCells $St $items
}

function Update-PickerSearch {
    param($St)
    $q = $St.Search.Text.Trim().ToLowerInvariant()
    if (-not $q) {
        if ($St.Tab) { Show-PickerTab $St $St.Tab }
        return
    }
    foreach ($b in $St.Tabs.Children) { $b.IsChecked = $false }
    $words = $q.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    $found = New-Object System.Collections.ArrayList
    foreach ($t in (Get-EmojiCatalog).tabs) {
        foreach ($it in $t.items) {
            $hay = ($it.n + ' ' + $it.w).ToLowerInvariant()
            $all = $true
            foreach ($w in $words) { if (-not $hay.Contains($w)) { $all = $false; break } }
            if ($all) { [void]$found.Add($it); if ($found.Count -ge 160) { break } }
        }
        if ($found.Count -ge 160) { break }
    }
    if ($found.Count -eq 0) { $St.Name.Text = 'Ничего не нашлось. Попробуйте другое слово' } else { $St.Name.Text = ('Найдено: {0}' -f $found.Count) }
    Set-PickerCells $St $found
}

# --- Короткое уведомление ----------------------------------------------------

function Show-Toast {
    <# Пилюля «✓ Скопировано» у точки, сама гаснет. Фокус не забирает. #>
    param([string]$Text, [double]$X, [double]$Y)
    try {
        $body = @'
    <StackPanel Orientation="Horizontal" Margin="12,7,14,7">
      <ContentControl x:Name="TIcon" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBlock x:Name="TText" VerticalAlignment="Center" FontWeight="SemiBold"/>
    </StackPanel>
'@
        $w = New-GlassWindow (New-WindowXaml $body 17) -Radius 17 -NoActivate -Strength 0.86
        $w.ShowActivated = $false
        $w.FindName('TText').Text = $Text
        $w.FindName('TIcon').Content = New-EmojiVisual (New-EmojiFromKey '2705') 16
        $w.Left = -10000; $w.Top = -10000
        Show-AppWindow $w
        $w.UpdateLayout()
        $sc = Get-DpiScale $w
        $wa = Get-WorkAreaAt $X $Y $sc
        $w.Left = [Math]::Max($wa.Left + 6, [Math]::Min($X - $w.ActualWidth / 2, $wa.Right - $w.ActualWidth - 6))
        $w.Top  = [Math]::Max($wa.Top + 6, [Math]::Min($Y - $w.ActualHeight - 14, $wa.Bottom - $w.ActualHeight - 6))
        $an = New-Object Windows.Media.Animation.DoubleAnimation 1.0, 0.0, ([Windows.Duration][TimeSpan]::FromMilliseconds(350))
        $an.BeginTime = [TimeSpan]::FromMilliseconds(900)
        $w.BeginAnimation([Windows.UIElement]::OpacityProperty, $an)
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(1300)
        $t.Tag = $w
        $t.Add_Tick({ param($s, $e) $s.Stop(); try { $s.Tag.Close() } catch { } })
        $t.Start()
    } catch { Write-ErrLog $_ 'уведомление' }
}

# --- Запрос значений для {?Подпись} ------------------------------------------

function Show-PromptDialog {
    <#
        Окно с полем на каждую {?Подпись}. Возвращает хеш ответов или $null,
        если закрыли. Enter в последнем поле — готово, Esc — отмена.
    #>
    param([string[]]$Labels, [string]$Title, [Windows.Rect]$Anchor, [string]$Edge)
    $body = @'
    <StackPanel Margin="16,12,16,14" Width="300">
      <DockPanel Margin="0,0,0,2">
        <ContentControl x:Name="PIcon" DockPanel.Dock="Left" VerticalAlignment="Center" Margin="0,0,8,0"/>
        <TextBlock x:Name="PTitle" Style="{StaticResource H}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
      <StackPanel x:Name="PFields"/>
      <DockPanel Margin="0,14,0,0">
        <TextBlock DockPanel.Dock="Left" Style="{StaticResource Hint}" VerticalAlignment="Center" Text="Enter — скопировать, Esc — отмена"/>
        <Button x:Name="POk" Style="{StaticResource Primary}" HorizontalAlignment="Right" Content="Скопировать" IsDefault="True"/>
      </DockPanel>
    </StackPanel>
'@
    $w = New-GlassWindow (New-WindowXaml $body 12) -Radius 12 -Strength 0.9
    $w.FindName('PTitle').Text = $Title
    $w.FindName('PIcon').Content = New-EmojiVisual (New-EmojiFromKey '270f-fe0f') 18
    $fields = $w.FindName('PFields')
    $boxes = @{}
    foreach ($l in $Labels) {
        $lbl = New-Object Windows.Controls.TextBlock
        $lbl.Style = $w.FindResource('Lbl')
        $lbl.Text = $l
        $lbl.Margin = '0,10,0,5'
        [void]$fields.Children.Add($lbl)
        $tb = New-Object Windows.Controls.TextBox
        [void]$fields.Children.Add($tb)
        $boxes[$l] = $tb
    }
    $script:PromptState = @{ Ok = $false; Win = $w }
    $w.FindName('POk').Add_Click({ $script:PromptState.Ok = $true; $script:PromptState.Win.Close() })
    $w.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { $s.Close() } })
    $w.Add_MouseLeftButtonDown({ param($s, $e) try { $s.DragMove() } catch { } })
    $w.Left = -10000; $w.Top = -10000
    $w.Add_ContentRendered({
        param($s, $e)
        try {
            Move-NearRect $s $script:PromptState.Anchor $script:PromptState.Edge
            $first = $s.FindName('PFields').Children | Where-Object { $_ -is [Windows.Controls.TextBox] } | Select-Object -First 1
            if ($first) { [void]$first.Focus() }
        } catch { Write-ErrLog $_ 'окно запроса' }
    })
    $script:PromptState.Anchor = $Anchor
    $script:PromptState.Edge = $Edge
    Show-AppWindow $w -Dialog
    if (-not $script:PromptState.Ok) { return $null }
    $ans = @{}
    foreach ($l in $Labels) { $ans[$l] = $boxes[$l].Text }
    return $ans
}
