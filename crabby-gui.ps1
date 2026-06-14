<#
.SYNOPSIS
    Crabby AI — Native Windows GUI (WPF)
.DESCRIPTION
    Beautiful desktop chat interface using WPF. No browser, no web server, no extra dependencies.
    Just run it and chat.
#>

param([string]$RootDir = "")

if (-not $RootDir) { $RootDir = $PSScriptRoot }
$ErrorActionPreference = "Stop"

# Load modules
. "$RootDir\src\LLM.ps1"
. "$RootDir\src\Memory.ps1"
. "$RootDir\src\Tools.ps1"
. "$RootDir\src\Skills.ps1"

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# Load configuration
$Settings = Get-CrabbySettings -RootDir $RootDir
$Soul = Get-CrabbySoul -RootDir $RootDir
$UserProfile = Get-CrabbyUserProfile -RootDir $RootDir

# ============================================================
# Conversation State
# ============================================================

$script:Conversation = @(
    @{ role = "system"; content = @"
$Soul

## User Profile
$UserProfile

## Memory
$(Get-CrabbyMemoryContent -RootDir $RootDir)

## Available Tools
$(Get-CrabbyToolsDescription)

## Instructions
- You are Crabby, a helpful AI assistant running locally on the user's Windows machine.
- You have FULL CONTROL of this computer via PowerShell. You can run any command, install software, manage files, configure system settings — anything the user can do in PowerShell, you can do too.
- The shell tool maintains a persistent session: working directory, variables, and imports persist across commands.
- When the user asks you to do something, DO IT directly using shell/file tools. Don't just give instructions — execute them.
- For dangerous operations, you will get a confirmation prompt. Tell the user what you're about to do and ask before using shell_confirm.
- Keep responses concise and natural, like chatting with a friend.
- Respond in the same language the user uses.
"@
    }
)

# ============================================================
# XAML — Window Definition
# ============================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Crabby AI" Height="700" Width="1000"
        WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip"
        WindowStartupLocation="CenterScreen" MinWidth="600" MinHeight="450">

  <Window.Resources>
    <!-- Colors — Light Theme -->
    <SolidColorBrush x:Key="BgPrimary" Color="#FAFAFA"/>
    <SolidColorBrush x:Key="BgSecondary" Color="#F5F5F5"/>
    <SolidColorBrush x:Key="BgTertiary" Color="#EFEFEF"/>
    <SolidColorBrush x:Key="BgHover" Color="#E8E8E8"/>
    <SolidColorBrush x:Key="TextPrimary" Color="#1A1A1A"/>
    <SolidColorBrush x:Key="TextSecondary" Color="#6B6B6B"/>
    <SolidColorBrush x:Key="TextMuted" Color="#9E9E9E"/>
    <SolidColorBrush x:Key="Accent" Color="#E8653A"/>
    <SolidColorBrush x:Key="AccentLight" Color="#F0845E"/>
    <SolidColorBrush x:Key="Success" Color="#2EAE6D"/>
    <SolidColorBrush x:Key="Border" Color="#E5E5E5"/>

    <!-- Button Style -->
    <Style x:Key="SidebarBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#6B6B6B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8E8E8"/>
                <Setter Property="Foreground" Value="#1A1A1A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Title Button Style -->
    <Style x:Key="TitleBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#6B6B6B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8E8E8"/>
                <Setter Property="Foreground" Value="#1A1A1A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Send Button Style -->
    <Style x:Key="SendBtn" TargetType="Button">
      <Setter Property="Background" Value="#E8653A"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#F0845E"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Background" Value="#D5D5D5"/>
                <Setter Property="Foreground" Value="#9E9E9E"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <!-- Main Border (window chrome) -->
  <Border Background="#FAFAFA" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1"
          MouseLeftButtonDown="Border_MouseLeftButtonDown">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="220" MinWidth="180"/>
        <ColumnDefinition Width="1"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- ====== SIDEBAR ====== -->
      <Border Grid.Column="0" Background="#F5F5F5" CornerRadius="12,0,0,12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Logo -->
          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="18,22,0,16">
            <Border Background="#E8653A" CornerRadius="10" Width="34" Height="34">
              <TextBlock Text="🦀" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="Crabby AI" FontSize="16" FontWeight="Bold" Foreground="#1A1A1A"
                       VerticalAlignment="Center" Margin="10,0,0,0"/>
          </StackPanel>

          <!-- Actions -->
          <StackPanel Grid.Row="1" Margin="12,0,12,0">
            <Button x:Name="BtnNewChat" Style="{StaticResource SidebarBtn}" Content="✦  新对话" Margin="0,2"/>
            <Button x:Name="BtnReset" Style="{StaticResource SidebarBtn}" Content="↻  清除上下文" Margin="0,2"/>
          </StackPanel>

          <!-- Status -->
          <StackPanel Grid.Row="3" Margin="16,0,16,16">
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="模型" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock x:Name="LblModel" Text="—" FontSize="11" Foreground="#6B6B6B" Margin="8,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="版本" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock Text="v1.3" FontSize="11" Foreground="#6B6B6B" Margin="8,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="状态" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock x:Name="LblStatus" Text="就绪" FontSize="11" Foreground="#2EAE6D" Margin="8,0,0,0"/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>

      <!-- Divider -->
      <Border Grid.Column="1" Background="#E5E5E5"/>

      <!-- ====== MAIN AREA ====== -->
      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title Bar -->
        <Border Grid.Row="0" Background="#F5F5F5" CornerRadius="0,12,0,0" Padding="20,10">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" VerticalAlignment="Center">
              <TextBlock Text="Crabby AI" FontSize="14" FontWeight="SemiBold" Foreground="#1A1A1A"/>
              <TextBlock x:Name="LblSubtitle" Text="你的本地 AI 助手" FontSize="11" Foreground="#9E9E9E"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="BtnMinimize" Style="{StaticResource TitleBtn}" Content="─"/>
              <Button x:Name="BtnMaximize" Style="{StaticResource TitleBtn}" Content="□"/>
              <Button x:Name="BtnClose" Style="{StaticResource TitleBtn}" Content="✕"/>
            </StackPanel>
          </Grid>
        </Border>

        <!-- Messages Area -->
        <ScrollViewer Grid.Row="1" x:Name="MsgScroll" VerticalScrollBarVisibility="Auto"
                      Padding="24,16" Background="#FAFAFA">
          <StackPanel x:Name="MsgPanel">
            <!-- Welcome -->
            <StackPanel x:Name="WelcomePanel" HorizontalAlignment="Center" VerticalAlignment="Center"
                        Margin="0,80,0,0">
              <Border Background="#E8653A" CornerRadius="20" Width="72" Height="72" HorizontalAlignment="Center"
                      Margin="0,0,0,16">
                <TextBlock Text="🦀" FontSize="36" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock Text="嘿，我是 Crabby" FontSize="22" FontWeight="Bold" Foreground="#1A1A1A"
                         HorizontalAlignment="Center" Margin="0,0,0,8"/>
              <TextBlock Text="你的本地 AI 助手，可以控制 PowerShell、创建文档、管理文件。"
                         FontSize="13" Foreground="#6B6B6B" HorizontalAlignment="Center"
                         TextWrapping="Wrap" MaxWidth="360" TextAlignment="Center" Margin="0,0,0,20"/>
              <WrapPanel HorizontalAlignment="Center">
                <Button x:Name="QuickSysInfo" Content="查看系统信息" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickDoc" Content="创建文档" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickWeather" Content="查天气" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickFiles" Content="查看文件" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
              </WrapPanel>
            </StackPanel>
          </StackPanel>
        </ScrollViewer>

        <!-- Typing Indicator (hidden by default) -->
        <StackPanel x:Name="TypingPanel" Grid.Row="1" VerticalAlignment="Bottom"
                    Orientation="Horizontal" Margin="32,0,0,16" Visibility="Collapsed">
          <Border Background="#E8653A" CornerRadius="10" Width="28" Height="28" Margin="0,0,8,0">
            <TextBlock Text="🦀" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="TypingText" Text="思考中..." FontSize="13" Foreground="#9E9E9E"
                     VerticalAlignment="Center"/>
        </StackPanel>

        <!-- Input Area -->
        <Border Grid.Row="2" Background="#F5F5F5" BorderBrush="#E5E5E5" BorderThickness="0,1,0,0"
                Padding="20,14,20,20">
          <Grid MaxWidth="760">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="#FFFFFF" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1"
                    x:Name="InputBorder">
              <TextBox x:Name="InputBox" Background="Transparent" Foreground="#1A1A1A"
                       BorderThickness="0" Padding="14,10"
                       FontSize="14" AcceptsReturn="False" MaxLines="1"
                       CaretBrush="#E8653A" VerticalContentAlignment="Center"/>
            </Border>
            <Button Grid.Column="1" x:Name="BtnSend" Style="{StaticResource SendBtn}" Content="➤" Margin="8,0,0,0"/>
          </Grid>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

# ============================================================
# Load Window
# ============================================================

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)

# Get controls
$inputBox = $window.FindName("InputBox")
$btnSend = $window.FindName("BtnSend")
$msgPanel = $window.FindName("MsgPanel")
$msgScroll = $window.FindName("MsgScroll")
$welcomePanel = $window.FindName("WelcomePanel")
$typingPanel = $window.FindName("TypingPanel")
$typingText = $window.FindName("TypingText")
$lblStatus = $window.FindName("LblStatus")
$lblModel = $window.FindName("LblModel")
$inputBorder = $window.FindName("InputBorder")
$lblSubtitle = $window.FindName("LblSubtitle")

# Title bar buttons
$btnClose = $window.FindName("BtnClose")
$btnMinimize = $window.FindName("BtnMinimize")
$btnMaximize = $window.FindName("BtnMaximize")
$btnNewChat = $window.FindName("BtnNewChat")
$btnReset = $window.FindName("BtnReset")

# Quick action buttons
$quickSysInfo = $window.FindName("QuickSysInfo")
$quickDoc = $window.FindName("QuickDoc")
$quickWeather = $window.FindName("QuickWeather")
$quickFiles = $window.FindName("QuickFiles")

# Set model label
$lblModel.Text = $Settings.llm.model

# ============================================================
# Window Chrome Events
# ============================================================

$btnClose.Add_Click({ $window.Close() })
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

$script:IsMaximized = $false
$btnMaximize.Add_Click({
    if ($script:IsMaximized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
        $script:IsMaximized = $false
    } else {
        $window.WindowState = [System.Windows.WindowState]::Maximized
        $script:IsMaximized = $true
    }
})

# Drag window
$window.Add_MouseLeftButtonDown({
    if ($_.OriginalSource -is [System.Windows.Controls.Border] -or
        $_.OriginalSource -is [System.Windows.Controls.Grid] -or
        $_.OriginalSource -is [System.Windows.Controls.StackPanel] -or
        $_.OriginalSource -is [System.Windows.Controls.TextBlock]) {
        $window.DragMove()
    }
})

# ============================================================
# UI Helpers
# ============================================================

function Add-MessageBubble {
    param(
        [string]$Role,     # "user" or "assistant"
        [string]$Text,
        [array]$Tools = @()
    )

    # Hide welcome
    $welcomePanel.Visibility = [System.Windows.Visibility]::Collapsed

    $container = New-Object System.Windows.Controls.StackPanel
    $container.Margin = "0,0,0,16"

    # Tool calls
    foreach ($tool in $Tools) {
        $toolBorder = New-Object System.Windows.Controls.Border
        $toolBorder.Background = "#F5F5F5"
        $toolBorder.BorderBrush = "#E5E5E5"
        $toolBorder.BorderThickness = "1"
        $toolBorder.CornerRadius = "8"
        $toolBorder.Margin = "0,0,0,4"
        $toolBorder.Padding = "8,6"
        $toolBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        $toolPanel = New-Object System.Windows.Controls.StackPanel
        $toolPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $toolIcon = New-Object System.Windows.Controls.TextBlock
        $toolIcon.Text = "⚙️"
        $toolIcon.FontSize = "12"
        $toolIcon.Margin = "0,0,6,0"
        $toolIcon.VerticalAlignment = "Center"

        $toolName = New-Object System.Windows.Controls.TextBlock
        $toolName.Text = $tool.name
        $toolName.FontSize = "12"
        $toolName.Foreground = "#F0845E"
        $toolName.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $toolName.VerticalAlignment = "Center"

        $toolStatus = New-Object System.Windows.Controls.TextBlock
        $toolStatus.Text = " ✓"
        $toolStatus.FontSize = "11"
        $toolStatus.Foreground = "#3ECF8E"
        $toolStatus.Margin = "6,0,0,0"
        $toolStatus.VerticalAlignment = "Center"

        $toolPanel.Children.Add($toolIcon) | Out-Null
        $toolPanel.Children.Add($toolName) | Out-Null
        $toolPanel.Children.Add($toolStatus) | Out-Null
        $toolBorder.Child = $toolPanel
        $container.Children.Add($toolBorder) | Out-Null
    }

    # Message row: avatar + bubble
    $row = New-Object System.Windows.Controls.DockPanel

    # Avatar
    $avatar = New-Object System.Windows.Controls.Border
    if ($Role -eq "user") {
        $avatar.Background = "#E5E5E5"
        $avatar.Width = "28"
        $avatar.Height = "28"
        $avatar.CornerRadius = "8"
        $avatar.Margin = "0,0,8,0"
        $avatarImg = New-Object System.Windows.Controls.TextBlock
        $avatarImg.Text = "👤"
        $avatarImg.FontSize = "14"
        $avatarImg.HorizontalAlignment = "Center"
        $avatarImg.VerticalAlignment = "Center"
        $avatar.Child = $avatarImg
        [System.Windows.Controls.DockPanel]::SetDock($avatar, [System.Windows.Controls.Dock]::Right)
    } else {
        $avatar.Background = "#E8653A"
        $avatar.Width = "28"
        $avatar.Height = "28"
        $avatar.CornerRadius = "8"
        $avatar.Margin = "0,0,8,0"
        $avatarImg = New-Object System.Windows.Controls.TextBlock
        $avatarImg.Text = "🦀"
        $avatarImg.FontSize = "14"
        $avatarImg.HorizontalAlignment = "Center"
        $avatarImg.VerticalAlignment = "Center"
        $avatar.Child = $avatarImg
        [System.Windows.Controls.DockPanel]::SetDock($avatar, [System.Windows.Controls.Dock]::Left)
    }

    # Bubble
    $bubble = New-Object System.Windows.Controls.Border
    $bubble.CornerRadius = "12"
    $bubble.Padding = "12,10"
    $bubble.MaxWidth = "560"

    if ($Role -eq "user") {
        $bubble.Background = "#E8653A"
        [System.Windows.Controls.DockPanel]::SetDock($bubble, [System.Windows.Controls.Dock]::Right)
    } else {
        $bubble.Background = "#FFFFFF"
        $bubble.BorderBrush = "#E5E5E5"
        $bubble.BorderThickness = "1"
    }

    # Render content
    $contentPanel = New-Object System.Windows.Controls.StackPanel

    # Simple markdown-to-XAML rendering
    $blocks = Render-MarkdownToBlocks -Text $Text -IsUser ($Role -eq "user")

    foreach ($block in $blocks) {
        $contentPanel.Children.Add($block) | Out-Null
    }

    $bubble.Child = $contentPanel

    $row.Children.Add($avatar) | Out-Null
    $row.Children.Add($bubble) | Out-Null

    if ($Role -eq "user") {
        $row.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    } else {
        $row.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    }

    $container.Children.Add($row) | Out-Null
    $msgPanel.Children.Add($container) | Out-Null

    # Scroll to bottom
    $msgScroll.Dispatcher.Invoke([Action]{
        $msgScroll.ScrollToEnd()
    }, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Render-MarkdownToBlocks {
    param([string]$Text, [bool]$IsUser = $false)

    $blocks = @()
    $lines = $Text -split "`n"
    $i = 0
    $inCodeBlock = $false
    $codeLines = @()

    while ($i -lt $lines.Count) {
        $line = $lines[$i]

        # Code block start/end
        if ($line -match '^```') {
            if ($inCodeBlock) {
                # End code block
                $codeBlock = New-Object System.Windows.Controls.Border
                $codeBlock.Background = "#F5F5F5"
                $codeBlock.BorderBrush = "#E5E5E5"
                $codeBlock.BorderThickness = "1"
                $codeBlock.CornerRadius = "8"
                $codeBlock.Padding = "10"
                $codeBlock.Margin = "0,4"

                $codeText = New-Object System.Windows.Controls.TextBlock
                $codeText.Text = ($codeLines -join "`n")
                $codeText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
                $codeText.FontSize = "12"
                $codeText.Foreground = "#1A1A1A"
                $codeText.TextWrapping = [System.Windows.TextWrapping]::Wrap

                $codeBlock.Child = $codeText
                $blocks += $codeBlock

                $codeLines = @()
                $inCodeBlock = $false
            } else {
                $inCodeBlock = $true
            }
            $i++
            continue
        }

        if ($inCodeBlock) {
            $codeLines += $line
            $i++
            continue
        }

        # Skip empty lines
        if ($line.Trim() -eq "") {
            $i++
            continue
        }

        # Headings
        if ($line -match '^### (.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Matches[1]
            $tb.FontSize = "14"
            $tb.FontWeight = "SemiBold"
            $tb.Foreground = "#1A1A1A"
            $tb.Margin = "0,8,0,2"
            $blocks += $tb
            $i++
            continue
        }
        if ($line -match '^## (.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Matches[1]
            $tb.FontSize = "15"
            $tb.FontWeight = "SemiBold"
            $tb.Foreground = "#1A1A1A"
            $tb.Margin = "0,8,0,2"
            $blocks += $tb
            $i++
            continue
        }

        # List items
        if ($line -match '^[-*]\s+(.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "• $($Matches[1])"
            $tb.FontSize = "13"
            $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#1A1A1A" }
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tb.Margin = "2,1"
            $blocks += $tb
            $i++
            continue
        }

        if ($line -match '^\d+\.\s+(.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $line
            $tb.FontSize = "13"
            $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#1A1A1A" }
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tb.Margin = "2,1"
            $blocks += $tb
            $i++
            continue
        }

        # Regular text (strip markdown bold/italic markers for display)
        $display = $line -replace '\*\*(.+?)\*\*', '$1'
        $display = $display -replace '\*(.+?)\*', '$1'
        $display = $display -replace '`(.+?)`', '$1'

        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $display
        $tb.FontSize = "13"
        $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#6B6B6B" }
        $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tb.Margin = "0,1"
        $blocks += $tb
        $i++
    }

    # Unclosed code block
    if ($inCodeBlock -and $codeLines.Count -gt 0) {
        $codeBlock = New-Object System.Windows.Controls.Border
        $codeBlock.Background = "#F5F5F5"
        $codeBlock.BorderBrush = "#E5E5E5"
        $codeBlock.BorderThickness = "1"
        $codeBlock.CornerRadius = "8"
        $codeBlock.Padding = "10"
        $codeBlock.Margin = "0,4"

        $codeText = New-Object System.Windows.Controls.TextBlock
        $codeText.Text = ($codeLines -join "`n")
        $codeText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $codeText.FontSize = "12"
        $codeText.Foreground = "#1A1A1A"
        $codeText.TextWrapping = [System.Windows.TextWrapping]::Wrap

        $codeBlock.Child = $codeText
        $blocks += $codeBlock
    }

    return $blocks
}

function Set-Processing {
    param([bool]$On)
    $btnSend.IsEnabled = -not $On
    $inputBox.IsEnabled = -not $On

    if ($On) {
        $lblStatus.Text = "思考中..."
        $lblStatus.Foreground = "#E8A030"
        $typingPanel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $lblStatus.Text = "就绪"
        $lblStatus.Foreground = "#2EAE6D"
        $typingPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

# ============================================================
# Chat Logic
# ============================================================

$script:IsProcessing = $false

function Send-ChatMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message) -or $script:IsProcessing) { return }

    $script:IsProcessing = $true
    Set-Processing $true

    # Add user message
    Add-MessageBubble -Role "user" -Text $Message

    $script:Conversation += @{ role = "user"; content = $Message }

    # Process in background
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("Settings", $Settings)
    $runspace.SessionStateProxy.SetVariable("Conversation", $script:Conversation)
    $runspace.SessionStateProxy.SetVariable("RootDir", $RootDir)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    $ps.AddScript({
        $maxRounds = 8
        $round = 0
        $toolEvents = @()
        $assistantMsg = ""
        $conv = $Conversation

        while ($round -lt $maxRounds) {
            $round++
            $result = Invoke-CrabbyChat -Settings $Settings -Conversation $conv -SupportTools $true

            if ($result.ToolCalls) {
                $conv += @{ role = "assistant"; content = $result.Content; tool_calls = $result.ToolCalls }

                foreach ($toolCall in $result.ToolCalls) {
                    $toolName = $toolCall.function.name
                    $toolArgs = $toolCall.function.arguments

                    $toolResult = Invoke-CrabbyTool -Name $toolName -Arguments $toolArgs -RootDir $RootDir

                    $shortResult = if ($toolResult.Length -gt 300) { $toolResult.Substring(0, 300) + "..." } else { $toolResult }
                    $toolEvents += @{ name = $toolName; result = $shortResult }

                    $conv += @{
                        role = "tool"
                        tool_call_id = $toolCall.id
                        content = $toolResult
                    }
                }
            } else {
                $assistantMsg = $result.Content
                $conv += @{ role = "assistant"; content = $assistantMsg }
                break
            }
        }

        if ($round -ge $maxRounds -and -not $assistantMsg) {
            $assistantMsg = "[Max tool rounds reached]"
        }

        return @{ message = $assistantMsg; tools = $toolEvents; conversation = $conv }
    }) | Out-Null

    $asyncResult = $ps.BeginInvoke()

    # Poll for completion on UI thread
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    $timer.Add_Tick({
        if ($asyncResult.IsCompleted) {
            $timer.Stop()

            try {
                $result = $ps.EndInvoke($asyncResult)

                $msg = $result[0].message
                $tools = $result[0].tools
                $script:Conversation = $result[0].conversation

                Add-MessageBubble -Role "assistant" -Text $msg -Tools $tools

                # Save conversation
                Save-CrabbyConversation -RootDir $RootDir -UserMessage $Message -AssistantResponse $msg

                # Trim conversation if too long
                if ($script:Conversation.Count -gt 30) {
                    $systemMsg = $script:Conversation[0]
                    $recent = $script:Conversation | Select-Object -Last 28
                    $script:Conversation = @($systemMsg) + $recent
                }
            }
            catch {
                Add-MessageBubble -Role "assistant" -Text "❌ 出错了: $($_.Exception.Message)"
            }
            finally {
                $ps.Dispose()
                $runspace.Close()
                $runspace.Dispose()
                $script:IsProcessing = $false
                Set-Processing $false
                $inputBox.Focus()
            }
        }
    })

    $timer.Start()
}

# ============================================================
# Event Bindings
# ============================================================

# Send button
$btnSend.Add_Click({
    Send-ChatMessage -Message $inputBox.Text
    $inputBox.Text = ""
})

# Enter to send
$inputBox.Add_KeyDown({
    if ($_.Key -eq "Enter" -and -not $_.ShiftKey) {
        $_.Handled = $true
        Send-ChatMessage -Message $inputBox.Text
        $inputBox.Text = ""
    }
})

# Focus highlight
$inputBox.Add_GotFocus({
    $inputBorder.BorderBrush = "#E8653A"
})
$inputBox.Add_LostFocus({
    $inputBorder.BorderBrush = "#E5E5E5"
})

# New chat
$btnNewChat.Add_Click({
    $script:Conversation = @(
        @{ role = "system"; content = $script:Conversation[0].content }
    )
    $msgPanel.Children.Clear()
    $msgPanel.Children.Add($welcomePanel) | Out-Null
    $welcomePanel.Visibility = [System.Windows.Visibility]::Visible
})

# Reset context
$btnReset.Add_Click({
    $script:Conversation = @(
        @{ role = "system"; content = $script:Conversation[0].content }
    )
    $msgPanel.Children.Clear()
    $msgPanel.Children.Add($welcomePanel) | Out-Null
    $welcomePanel.Visibility = [System.Windows.Visibility]::Visible
})

# Quick actions
$quickSysInfo.Add_Click({ Send-ChatMessage -Message "查看当前系统信息" })
$quickDoc.Add_Click({ Send-ChatMessage -Message "帮我创建一个待办事项文档" })
$quickWeather.Add_Click({ Send-ChatMessage -Message "今天天气怎么样" })
$quickFiles.Add_Click({ Send-ChatMessage -Message "列出桌面上的文件" })

# ============================================================
# Run
# ============================================================

$inputBox.Focus()
$window.ShowDialog() | Out-Null
