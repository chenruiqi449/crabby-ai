<#
.SYNOPSIS
    Crabby AI — Native Windows GUI (WPF) v1.5
.DESCRIPTION
    Beautiful desktop chat interface using WPF. No browser, no web server, no extra dependencies.
    Just run it and chat.
    v1.5: Fixed input box focus, added settings panel, added conversation history viewer.
#>

param([string]$RootDir = "")

if (-not $RootDir) {
    try {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $RootDir = Split-Path -Parent $exePath
    } catch {}
}
if (-not $RootDir) { $RootDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RootDir) { $RootDir = $PSScriptRoot }
# Sanitize RootDir
if ($RootDir -match '[<>|"]') { $RootDir = $RootDir -replace '[<>|"]', '' }

# Ensure data directories exist
@("config", "memory", "skills") | ForEach-Object {
    $dir = Join-Path $RootDir $_
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
$ErrorActionPreference = "Stop"

# Load modules
. "$RootDir\src\LLM.ps1"
. "$RootDir\src\Memory.ps1"
. "$RootDir\src\Tools.ps1"
. "$RootDir\src\Skills.ps1"

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# ============================================================
# WPF Onboarding (replaces console Read-Host for -noConsole mode)
# ============================================================
function Show-WpfOnboard {
    param([string]$RootDir)

    $onboardXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Crabby AI Setup" Height="420" Width="460"
        WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen">
  <Border Background="#FAFAFA" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1">
    <StackPanel Margin="30,24,30,20">
      <TextBlock Text="&#x1F980; Crabby AI Setup" FontSize="22" FontWeight="Bold" Foreground="#1A1A1A" Margin="0,0,0,4"/>
      <TextBlock Text="First run - let's get you configured" FontSize="13" Foreground="#6B6B6B" Margin="0,0,0,20"/>

      <TextBlock Text="LLM Provider" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <ComboBox x:Name="CmbProvider" FontSize="13" Height="30" Margin="0,0,0,12">
        <ComboBoxItem Content="SiliconFlow" IsSelected="True"/>
        <ComboBoxItem Content="Zhipu"/>
        <ComboBoxItem Content="DeepSeek"/>
        <ComboBoxItem Content="OpenAI"/>
        <ComboBoxItem Content="Custom (OpenAI-compatible)"/>
      </ComboBox>

      <StackPanel x:Name="CustomPanel" Visibility="Collapsed" Margin="0,0,0,12">
        <TextBlock Text="Base URL" FontSize="12" Foreground="#6B6B6B" Margin="0,0,0,4"/>
        <TextBox x:Name="TxtBaseUrl" FontSize="13" Height="28" Margin="0,0,0,8"/>
        <TextBlock Text="Model Name" FontSize="12" Foreground="#6B6B6B" Margin="0,0,0,4"/>
        <TextBox x:Name="TxtModel" FontSize="13" Height="28"/>
      </StackPanel>

      <TextBlock Text="API Key" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <PasswordBox x:Name="TxtApiKey" FontSize="13" Height="28" Margin="0,0,0,12"/>

      <TextBlock Text="Your Name" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtUserName" FontSize="13" Height="28" Margin="0,0,0,20"/>

      <Button x:Name="BtnStart" Content="Start Chatting" FontSize="14" FontWeight="SemiBold"
              Height="36" Background="#E8653A" Foreground="White" BorderThickness="0"
              Cursor="Hand"/>
    </StackPanel>
  </Border>
</Window>
"@

    $onboardWin = [System.Windows.Markup.XamlReader]::Parse($onboardXaml)
    $cmbProvider = $onboardWin.FindName("CmbProvider")
    $customPanel = $onboardWin.FindName("CustomPanel")
    $txtBaseUrl = $onboardWin.FindName("TxtBaseUrl")
    $txtModel = $onboardWin.FindName("TxtModel")
    $txtApiKey = $onboardWin.FindName("TxtApiKey")
    $txtUserName = $onboardWin.FindName("TxtUserName")
    $btnStart = $onboardWin.FindName("BtnStart")

    $cmbProvider.Add_SelectionChanged({
        if ($cmbProvider.SelectedIndex -eq 4) {
            $customPanel.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $customPanel.Visibility = [System.Windows.Visibility]::Collapsed
        }
    })

    $script:OnboardResult = $null
    $btnStart.Add_Click({
        $providers = @(
            @{ name = "siliconflow"; base_url = "https://api.siliconflow.cn/v1"; model = "Qwen/Qwen3-8B" },
            @{ name = "zhipu"; base_url = "https://open.bigmodel.cn/api/paas/v4/"; model = "glm-4-flash" },
            @{ name = "deepseek"; base_url = "https://api.deepseek.com/v1"; model = "deepseek-chat" },
            @{ name = "openai"; base_url = "https://api.openai.com/v1"; model = "gpt-4o-mini" },
            @{ name = "custom"; base_url = ""; model = "" }
        )
        $idx = $cmbProvider.SelectedIndex
        $provider = $providers[$idx]

        $apiKey = $txtApiKey.Password
        $userName = $txtUserName.Text
        if (-not $userName) { $userName = "User" }

        if ($idx -eq 4) {
            $provider.base_url = $txtBaseUrl.Text
            $provider.model = $txtModel.Text
        }

        $script:OnboardResult = @{
            llm = @{
                provider = $provider.name
                api_key = $apiKey
                model = $provider.model
                base_url = $provider.base_url
                max_tokens = 1024
                temperature = 0.7
                repetition_penalty = 1.1
            }
            user = @{ name = $userName }
        }

        # Save settings
        $configDir = Join-Path $RootDir "config"
        if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory -Force | Out-Null }
        $script:OnboardResult | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RootDir "config\settings.json") -Encoding UTF8

        # Create default SOUL.md
        $soulPath = Join-Path $RootDir "config\SOUL.md"
        if (-not (Test-Path $soulPath)) {
            $defaultSoul = "You are Crabby, a personal AI assistant.`nYou are helpful, witty, and slightly snarky.`nYou speak concisely and naturally."
            Set-Content $soulPath $defaultSoul -Encoding UTF8
        }

        # Create default USER.md
        $userPath = Join-Path $RootDir "config\USER.md"
        if (-not (Test-Path $userPath)) {
            Set-Content $userPath "## User Profile`n- Name: $userName" -Encoding UTF8
        }

        # Create memory
        $memDir = Join-Path $RootDir "memory"
        if (-not (Test-Path $memDir)) { New-Item -Path $memDir -ItemType Directory -Force | Out-Null }
        $memFile = Join-Path $memDir "MEMORY.md"
        if (-not (Test-Path $memFile)) { Set-Content $memFile "# Crabby Memory`n" -Encoding UTF8 }

        $onboardWin.Close()
    })

    $onboardWin.ShowDialog() | Out-Null
    return $script:OnboardResult
}

# Load configuration
$settingsPath = Join-Path $RootDir "config\settings.json"
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    $Settings = $raw | ConvertFrom-Json
} else {
    $Settings = Show-WpfOnboard -RootDir $RootDir
    if (-not $Settings) {
        return
    }
}
$Soul = Get-CrabbySoul -RootDir $RootDir
$UserProfile = Get-CrabbyUserProfile -RootDir $RootDir

# ============================================================
# Helper: Build system prompt
# ============================================================
function Build-SystemPrompt {
    $Soul = Get-CrabbySoul -RootDir $RootDir
    $UserProfile = Get-CrabbyUserProfile -RootDir $RootDir
    return @"
$Soul

## User Profile
$UserProfile

## Memory
$(Get-CrabbyMemoryContent -RootDir $RootDir)

## Available Tools
$(Get-CrabbyToolsDescription)

## Instructions
- You are Crabby, a helpful AI assistant running locally on the user's Windows machine.
- You have FULL CONTROL of this computer via PowerShell. You can run any command, install software, manage files, configure system settings - anything the user can do in PowerShell, you can do too.
- The shell tool maintains a persistent session: working directory, variables, and imports persist across commands.
- When the user asks you to do something, DO IT directly using shell/file tools. Don't just give instructions - execute them.
- For dangerous operations, you will get a confirmation prompt. Tell the user what you're about to do and ask before using shell_confirm.
- Keep responses concise and natural, like chatting with a friend.
- Respond in the same language the user uses.
"@
}

# ============================================================
# Conversation State
# ============================================================

$script:Conversation = @(
    @{ role = "system"; content = (Build-SystemPrompt) }
)

# ============================================================
# XAML - Window Definition (v1.4)
# ============================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Crabby AI" Height="700" Width="1000"
        WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip"
        WindowStartupLocation="CenterScreen" MinWidth="600" MinHeight="450">

  <Window.Resources>
    <SolidColorBrush x:Key="BgPrimary" Color="#FAFAFA"/>
    <SolidColorBrush x:Key="BgSecondary" Color="#F5F5F5"/>
    <SolidColorBrush x:Key="TextPrimary" Color="#1A1A1A"/>
    <SolidColorBrush x:Key="TextSecondary" Color="#6B6B6B"/>
    <SolidColorBrush x:Key="TextMuted" Color="#9E9E9E"/>
    <SolidColorBrush x:Key="Accent" Color="#E8653A"/>
    <SolidColorBrush x:Key="AccentLight" Color="#F0845E"/>
    <SolidColorBrush x:Key="Success" Color="#2EAE6D"/>
    <SolidColorBrush x:Key="Border" Color="#E5E5E5"/>

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

    <Style x:Key="HistoryItemBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#6B6B6B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
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

    <Style x:Key="DialogBtn" TargetType="Button">
      <Setter Property="Background" Value="#E8653A"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#F0845E"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="DialogCancelBtn" TargetType="Button">
      <Setter Property="Background" Value="#EFEFEF"/>
      <Setter Property="Foreground" Value="#6B6B6B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E0E0E0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="MainBorder" Background="#FAFAFA" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1">
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
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Logo -->
          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="18,22,0,16">
            <Border Background="#E8653A" CornerRadius="10" Width="34" Height="34">
              <TextBlock Text="C" FontSize="18" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="Crabby AI" FontSize="16" FontWeight="Bold" Foreground="#1A1A1A"
                       VerticalAlignment="Center" Margin="10,0,0,0"/>
          </StackPanel>

          <!-- Actions -->
          <StackPanel Grid.Row="1" Margin="12,0,12,0">
            <Button x:Name="BtnNewChat" Style="{StaticResource SidebarBtn}" Content="+  New Chat" Margin="0,2"/>
            <Button x:Name="BtnHistory" Style="{StaticResource SidebarBtn}" Content="&#x1F4C1;  History" Margin="0,2"/>
            <Button x:Name="BtnSettings" Style="{StaticResource SidebarBtn}" Content="&#x2699;  Settings" Margin="0,2"/>
            <Button x:Name="BtnReset" Style="{StaticResource SidebarBtn}" Content="&#x21BB;  Clear Context" Margin="0,2"/>
          </StackPanel>

          <!-- History Panel (hidden by default) -->
          <Border Grid.Row="2" x:Name="HistoryPanel" Visibility="Collapsed" Margin="12,4,12,4"
                  Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E5E5" BorderThickness="1"
                  MaxHeight="300">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <Border Grid.Row="0" BorderBrush="#E5E5E5" BorderThickness="0,0,0,1" Padding="10,6">
                <TextBlock Text="Chat History" FontSize="11" FontWeight="SemiBold" Foreground="#9E9E9E"/>
              </Border>
              <ScrollViewer Grid.Row="1" x:Name="HistoryScroll" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="HistoryList" Margin="4"/>
              </ScrollViewer>
            </Grid>
          </Border>

          <!-- Status -->
          <StackPanel Grid.Row="4" Margin="16,0,16,16">
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="Model" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock x:Name="LblModel" Text="-" FontSize="11" Foreground="#6B6B6B" Margin="8,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="Version" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock Text="v1.5" FontSize="11" Foreground="#6B6B6B" Margin="8,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="Status" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock x:Name="LblStatus" Text="Ready" FontSize="11" Foreground="#2EAE6D" Margin="8,0,0,0"/>
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
              <TextBlock x:Name="LblSubtitle" Text="Your local AI assistant" FontSize="11" Foreground="#9E9E9E"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="BtnMinimize" Style="{StaticResource TitleBtn}" Content="-"/>
              <Button x:Name="BtnMaximize" Style="{StaticResource TitleBtn}" Content="[]"/>
              <Button x:Name="BtnClose" Style="{StaticResource TitleBtn}" Content="X"/>
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
                <TextBlock Text="C" FontSize="36" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock Text="Hey, I'm Crabby" FontSize="22" FontWeight="Bold" Foreground="#1A1A1A"
                         HorizontalAlignment="Center" Margin="0,0,0,8"/>
              <TextBlock Text="Your local AI assistant. I can run PowerShell, create documents, manage files and more."
                         FontSize="13" Foreground="#6B6B6B" HorizontalAlignment="Center"
                         TextWrapping="Wrap" MaxWidth="360" TextAlignment="Center" Margin="0,0,0,20"/>
              <WrapPanel HorizontalAlignment="Center">
                <Button x:Name="QuickSysInfo" Content="System Info" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickDoc" Content="Create Doc" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickWeather" Content="Weather" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickFiles" Content="List Files" Margin="3" Padding="10,6"
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
            <TextBlock Text="C" FontSize="14" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="TypingText" Text="Thinking..." FontSize="13" Foreground="#9E9E9E"
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
            <Border Grid.Column="0" x:Name="InputBorder" Background="#FFFFFF" CornerRadius="12"
                    BorderBrush="#E5E5E5" BorderThickness="1">
              <TextBox x:Name="InputBox" Background="Transparent" Foreground="#1A1A1A"
                       BorderThickness="0" Padding="14,10"
                       FontSize="14" AcceptsReturn="False" MaxLines="1"
                       CaretBrush="#E8653A" VerticalContentAlignment="Center"
                       IsReadOnly="False" Focusable="True" IsTabStop="True"/>
            </Border>
            <Button Grid.Column="1" x:Name="BtnSend" Style="{StaticResource SendBtn}" Margin="8,0,0,0">
              <TextBlock Text="Send" FontSize="13" FontWeight="SemiBold"/>
            </Button>
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
$MainBorder = $window.FindName("MainBorder")
$btnClose = $window.FindName("BtnClose")
$btnMinimize = $window.FindName("BtnMinimize")
$btnMaximize = $window.FindName("BtnMaximize")
$btnNewChat = $window.FindName("BtnNewChat")
$btnReset = $window.FindName("BtnReset")
$btnSettings = $window.FindName("BtnSettings")
$btnHistory = $window.FindName("BtnHistory")
$historyPanel = $window.FindName("HistoryPanel")
$historyList = $window.FindName("HistoryList")
$historyScroll = $window.FindName("HistoryScroll")

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

# Drag window - EXCLUDE input controls from triggering drag
$MainBorder.Add_MouseLeftButtonDown({
    $src = $_.OriginalSource
    # Skip drag if clicking on any input/control element
    if ($src -is [System.Windows.Controls.TextBox] -or
        $src -is [System.Windows.Controls.PasswordBox] -or
        $src -is [System.Windows.Controls.Button] -or
        $src -is [System.Windows.Controls.ComboBox] -or
        $src -is [System.Windows.Controls.ScrollViewer]) {
        return
    }
    if ($src -is [System.Windows.Controls.Border] -or
        $src -is [System.Windows.Controls.Grid] -or
        $src -is [System.Windows.Controls.StackPanel] -or
        $src -is [System.Windows.Controls.TextBlock]) {
        $window.DragMove()
    }
})

# ============================================================
# UI Helpers
# ============================================================

function Add-MessageBubble {
    param(
        [string]$Role,
        [string]$Text,
        [array]$Tools = @()
    )

    # Hide welcome
    $welcomePanel.Visibility = [System.Windows.Visibility]::Collapsed

    $container = New-Object System.Windows.Controls.StackPanel
    $container.Margin = "0,0,0,16"

    # Tool calls display
    foreach ($tool in $Tools) {
        $toolBorder = New-Object System.Windows.Controls.Border
        $toolBorder.Background = "#F5F5F5"
        $toolBorder.BorderBrush = "#E5E5E5"
        $toolBorder.BorderThickness = "1"
        $toolBorder.CornerRadius = "8"
        $toolBorder.Margin = "0,0,0,4"
        $toolBorder.Padding = "8,6"

        $toolPanel = New-Object System.Windows.Controls.StackPanel
        $toolPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $toolIcon = New-Object System.Windows.Controls.TextBlock
        $toolIcon.Text = ">"
        $toolIcon.FontSize = "12"
        $toolIcon.FontWeight = "Bold"
        $toolIcon.Foreground = "#E8653A"
        $toolIcon.Margin = "0,0,6,0"
        $toolIcon.VerticalAlignment = "Center"

        $toolName = New-Object System.Windows.Controls.TextBlock
        $toolName.Text = $tool.name
        $toolName.FontSize = "12"
        $toolName.Foreground = "#F0845E"
        $toolName.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $toolName.VerticalAlignment = "Center"

        $toolStatus = New-Object System.Windows.Controls.TextBlock
        $toolStatus.Text = " [ok]"
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
        $avatarImg.Text = "U"
        $avatarImg.FontSize = "13"
        $avatarImg.FontWeight = "Bold"
        $avatarImg.Foreground = "#6B6B6B"
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
        $avatarImg.Text = "C"
        $avatarImg.FontSize = "13"
        $avatarImg.FontWeight = "Bold"
        $avatarImg.Foreground = "White"
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

        if ($line -match '^```') {
            if ($inCodeBlock) {
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

        if ($line.Trim() -eq "") {
            $i++
            continue
        }

        if ($line -match '^### (.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Matches[1]
            $tb.FontSize = "14"
            $tb.FontWeight = "SemiBold"
            $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#1A1A1A" }
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
            $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#1A1A1A" }
            $tb.Margin = "0,8,0,2"
            $blocks += $tb
            $i++
            continue
        }

        if ($line -match '^[-*]\s+(.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "  $($Matches[1])"
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
        $lblStatus.Text = "Thinking..."
        $lblStatus.Foreground = "#E8A030"
        $typingPanel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $lblStatus.Text = "Ready"
        $lblStatus.Foreground = "#2EAE6D"
        $typingPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

# ============================================================
# Settings Dialog
# ============================================================

function Show-SettingsDialog {
    $settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Settings" Height="500" Width="460"
        WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner">
  <Border Background="#FAFAFA" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1">
    <StackPanel Margin="28,24">
      <TextBlock Text="Settings" FontSize="20" FontWeight="Bold" Foreground="#1A1A1A" Margin="0,0,0,20"/>

      <TextBlock Text="LLM Provider" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <ComboBox x:Name="CmbProvider" FontSize="13" Height="30" Margin="0,0,0,12">
        <ComboBoxItem Content="SiliconFlow"/>
        <ComboBoxItem Content="Zhipu"/>
        <ComboBoxItem Content="DeepSeek"/>
        <ComboBoxItem Content="OpenAI"/>
        <ComboBoxItem Content="Custom (OpenAI-compatible)"/>
      </ComboBox>

      <TextBlock Text="API Base URL" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtBaseUrl" FontSize="13" Height="28" Margin="0,0,0,12"
               IsReadOnly="False" Focusable="True"/>

      <TextBlock Text="Model Name" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtModel" FontSize="13" Height="28" Margin="0,0,0,12"
               IsReadOnly="False" Focusable="True"/>

      <TextBlock Text="API Key" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <PasswordBox x:Name="TxtApiKey" FontSize="13" Height="28" Margin="0,0,0,12"
                    Focusable="True"/>

      <TextBlock Text="Your Name" FontSize="13" FontWeight="SemiBold" Foreground="#1A1A1A" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtUserName" FontSize="13" Height="28" Margin="0,0,0,24"
               IsReadOnly="False" Focusable="True"/>

      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource DialogCancelBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnSave" Content="Save" Style="{StaticResource DialogBtn}"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
"@

    $dlg = [System.Windows.Markup.XamlReader]::Parse($settingsXaml)
    $dlg.Owner = $window

    $cmbProvider = $dlg.FindName("CmbProvider")
    $txtBaseUrl = $dlg.FindName("TxtBaseUrl")
    $txtModel = $dlg.FindName("TxtModel")
    $txtApiKey = $dlg.FindName("TxtApiKey")
    $txtUserName = $dlg.FindName("TxtUserName")
    $btnSave = $dlg.FindName("BtnSave")
    $btnCancel = $dlg.FindName("BtnCancel")

    # Populate current settings
    $providerMap = @{ "siliconflow" = 0; "zhipu" = 1; "deepseek" = 2; "openai" = 3; "custom" = 4 }
    $curProvider = $Settings.llm.provider
    if ($providerMap.ContainsKey($curProvider)) {
        $cmbProvider.SelectedIndex = $providerMap[$curProvider]
    }
    $txtBaseUrl.Text = $Settings.llm.base_url
    $txtModel.Text = $Settings.llm.model
    $txtApiKey.Password = $Settings.llm.api_key
    if ($Settings.user -and $Settings.user.name) {
        $txtUserName.Text = $Settings.user.name
    }

    $script:SettingsSaved = $false

    $btnCancel.Add_Click({ $dlg.Close() })

    $btnSave.Add_Click({
        $providers = @(
            @{ name = "siliconflow"; base_url = "https://api.siliconflow.cn/v1"; model = "Qwen/Qwen3-8B" },
            @{ name = "zhipu"; base_url = "https://open.bigmodel.cn/api/paas/v4/"; model = "glm-4-flash" },
            @{ name = "deepseek"; base_url = "https://api.deepseek.com/v1"; model = "deepseek-chat" },
            @{ name = "openai"; base_url = "https://api.openai.com/v1"; model = "gpt-4o-mini" },
            @{ name = "custom"; base_url = ""; model = "" }
        )
        $idx = $cmbProvider.SelectedIndex
        $provider = $providers[$idx]

        $newApiKey = $txtApiKey.Password
        if (-not $newApiKey) { $newApiKey = $Settings.llm.api_key }

        $newModel = $txtModel.Text
        if (-not $newModel) { $newModel = $provider.model }

        $newBaseUrl = $txtBaseUrl.Text
        if (-not $newBaseUrl) { $newBaseUrl = $provider.base_url }

        # For preset providers, override base_url with default unless custom
        if ($idx -ne 4) {
            $newBaseUrl = $provider.base_url
        }

        $newSettings = @{
            llm = @{
                provider = $provider.name
                api_key = $newApiKey
                model = $newModel
                base_url = $newBaseUrl
                max_tokens = 1024
                temperature = 0.7
                repetition_penalty = 1.1
            }
            user = @{ name = $txtUserName.Text }
        }

        $newSettings | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RootDir "config\settings.json") -Encoding UTF8

        # Update in-memory settings
        $script:Settings = $newSettings
        $script:SettingsSaved = $true

        $dlg.Close()
    })

    $dlg.ShowDialog() | Out-Null
    return $script:SettingsSaved
}

# ============================================================
# History Functions
# ============================================================

function Load-HistoryFiles {
    $convDir = Join-Path $RootDir "memory\conversations"
    $items = @()

    if (Test-Path $convDir) {
        $files = Get-ChildItem $convDir -Filter "*.md" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $preview = ""
            if ($content -match '\*\*User:\*\*\s+(.+?)(?:\r?\n)') {
                $preview = $Matches[1]
                if ($preview.Length -gt 35) {
                    $preview = $preview.Substring(0, 35) + "..."
                }
            }
            $items += @{
                date = $file.BaseName
                path = $file.FullName
                preview = $preview
            }
        }
    }
    return $items
}

function Refresh-HistoryList {
    $historyList.Children.Clear()
    $items = Load-HistoryFiles

    if ($items.Count -eq 0) {
        $noHistory = New-Object System.Windows.Controls.TextBlock
        $noHistory.Text = "No history yet"
        $noHistory.FontSize = "11"
        $noHistory.Foreground = "#9E9E9E"
        $noHistory.Margin = "8,12"
        $historyList.Children.Add($noHistory) | Out-Null
        return
    }

    foreach ($item in $items) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $window.Resources["HistoryItemBtn"]

        $sp = New-Object System.Windows.Controls.StackPanel

        $dateText = New-Object System.Windows.Controls.TextBlock
        $dateText.Text = $item.date
        $dateText.FontSize = "12"
        $dateText.FontWeight = "SemiBold"
        $dateText.Foreground = "#1A1A1A"
        $sp.Children.Add($dateText) | Out-Null

        if ($item.preview) {
            $previewText = New-Object System.Windows.Controls.TextBlock
            $previewText.Text = $item.preview
            $previewText.FontSize = "11"
            $previewText.Foreground = "#9E9E9E"
            $previewText.TextTrimming = "CharacterEllipsis"
            $previewText.MaxWidth = "170"
            $sp.Children.Add($previewText) | Out-Null
        }

        $btn.Content = $sp
        $filePath = $item.path
        $btn.Add_Click({
            param($sender, $e)
            Load-HistoryConversation -FilePath $sender.Tag
        })
        $btn.Tag = $filePath
        $historyList.Children.Add($btn) | Out-Null
    }
}

function Load-HistoryConversation {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) { return }

    $content = Get-Content $FilePath -Raw -Encoding UTF8

    # Clear current chat display
    $msgPanel.Children.Clear()
    $welcomePanel.Visibility = [System.Windows.Visibility]::Collapsed

    # Parse conversation entries separated by "## HH:MM:SS"
    $sections = $content -split '## \d{2}:\d{2}:\d{2}' | Where-Object { $_.Trim() -ne "" }

    foreach ($section in $sections) {
        # Extract user message
        if ($section -match '\*\*User:\*\*\s+(.+?)(?=\r?\n\r?\n\*\*Crabby:|\Z)') {
            $userMsg = $Matches[1].Trim()
            Add-MessageBubble -Role "user" -Text $userMsg
        }
        # Extract assistant response
        if ($section -match '\*\*Crabby:\*\*\s+([\s\S]+?)(?=\r?\n\r?\n|\Z)') {
            $assistantMsg = $Matches[1].Trim()
            Add-MessageBubble -Role "assistant" -Text $assistantMsg
        }
    }

    $msgScroll.ScrollToEnd()
    $lblSubtitle.Text = "Viewing: " + (Split-Path $FilePath -LeafBase)

    # Hide history panel after selecting
    $historyPanel.Visibility = [System.Windows.Visibility]::Collapsed
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

    Add-MessageBubble -Role "user" -Text $Message
    $script:Conversation += @{ role = "user"; content = $Message }

    # Process in background runspace
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

                # Save conversation to file
                Save-CrabbyConversation -RootDir $RootDir -UserMessage $Message -AssistantResponse $msg

                # Trim conversation if too long
                if ($script:Conversation.Count -gt 30) {
                    $systemMsg = $script:Conversation[0]
                    $recent = $script:Conversation | Select-Object -Last 28
                    $script:Conversation = @($systemMsg) + $recent
                }
            }
            catch {
                Add-MessageBubble -Role "assistant" -Text "Error: $($_.Exception.Message)"
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

# Send button click
$btnSend.Add_Click({
    $text = $inputBox.Text
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        Send-ChatMessage -Message $text
        $inputBox.Clear()
    }
})

# Enter to send - use PreviewKeyDown for reliable key capture
$inputBox.Add_PreviewKeyDown({
    if ($_.Key -eq "Return" -and -not $_.KeyboardDevice.Modifiers.HasFlag([System.Windows.Input.ModifierKeys]::Shift)) {
        $_.Handled = $true
        $text = $inputBox.Text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Send-ChatMessage -Message $text
            $inputBox.Clear()
        }
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
        @{ role = "system"; content = (Build-SystemPrompt) }
    )
    $msgPanel.Children.Clear()
    $msgPanel.Children.Add($welcomePanel) | Out-Null
    $welcomePanel.Visibility = [System.Windows.Visibility]::Visible
    $lblSubtitle.Text = "Your local AI assistant"
    $historyPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $inputBox.Focus()
})

# Reset context (same as new chat)
$btnReset.Add_Click({
    $script:Conversation = @(
        @{ role = "system"; content = (Build-SystemPrompt) }
    )
    $msgPanel.Children.Clear()
    $msgPanel.Children.Add($welcomePanel) | Out-Null
    $welcomePanel.Visibility = [System.Windows.Visibility]::Visible
    $lblSubtitle.Text = "Your local AI assistant"
    $historyPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $inputBox.Focus()
})

# Settings button
$btnSettings.Add_Click({
    $saved = Show-SettingsDialog
    if ($saved) {
        # Reload settings from disk
        $settingsPath = Join-Path $RootDir "config\settings.json"
        $raw = Get-Content $settingsPath -Raw -Encoding UTF8
        $script:Settings = $raw | ConvertFrom-Json

        # Update model label
        $lblModel.Text = $script:Settings.llm.model

        # Rebuild system prompt with new settings
        $script:Conversation = @(
            @{ role = "system"; content = (Build-SystemPrompt) }
        )

        Add-MessageBubble -Role "assistant" -Text "Settings saved. New conversation will use the updated configuration."
    }
})

# History button - toggle panel
$btnHistory.Add_Click({
    if ($historyPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
        $historyPanel.Visibility = [System.Windows.Visibility]::Collapsed
    } else {
        Refresh-HistoryList
        $historyPanel.Visibility = [System.Windows.Visibility]::Visible
    }
})

# Quick actions - populate input box and focus
$quickSysInfo.Add_Click({
    $inputBox.Text = "Show me the current system information"
    $inputBox.Focus()
})
$quickDoc.Add_Click({
    $inputBox.Text = "Create a todo list document for me"
    $inputBox.Focus()
})
$quickWeather.Add_Click({
    $inputBox.Text = "What's the weather like today"
    $inputBox.Focus()
})
$quickFiles.Add_Click({
    $inputBox.Text = "List files on my desktop"
    $inputBox.Focus()
})

# ============================================================
# Run
# ============================================================

# Ensure input box gets focus when window loads
$window.Add_Loaded({
    Start-Sleep -Milliseconds 100
    $inputBox.Dispatcher.Invoke([Action]{
        $inputBox.Focus()
    }, [System.Windows.Threading.DispatcherPriority]::Loaded)
})

$inputBox.Focus()
$window.ShowDialog() | Out-Null
