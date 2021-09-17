#!/usr/bin/env pwsh
#requires -modules PSColorizer
#requires -modules WriteAscii
#requires -modules 7Zip4PowerShell
#requires -psedition Core
#requires -version 6.0

using namespace System.IO
using namespace System.Diagnostics

[CmdletBinding(DefaultParameterSetName = 'AllParameterSets', PositionalBinding = $true)]
param (
  [Parameter(ParameterSetName = 'Interactive', Mandatory = $true)]
  [Alias('i')]
  [switch] $Interactive,

  [Parameter(ParameterSetName = 'NonInteractive', Mandatory = $false, Position = 0)]
  [Alias('app')]
  [int] $AppId,

  [Parameter(ParameterSetName = 'NonInteractive', Mandatory = $false, Position = 1)]
  [Alias('dir')]
  [string] $InstallDir,

  [Parameter()]
  [Alias('cid')]
  [string] $CmdInstallDir
)

begin {
  $script_info = @{
    name        = 'Automation/SteamCmd'
    dir         = $PSScriptRoot
    filename    = $MyInvocation.MyCommand.Source | Split-Path -Leaf
    version     = [semver]::new(4, 0, 0)
    license     = 'MIT'
    license_url = 'https://tldrlegal.com/l/mit'
    repo        = 'https://github.com/2chevskii/Automation/tree/master/SteamCMD'
    author      = '2CHEVSKII'
  }

  $download_url = @{
    win   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    linux = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
    osx   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz'
  }

  $steamcmd_exit_codes = @{
    0  = ($true, 'SUCCESS')
    1  = ($false, 'UNKNOWN ERROR')
    2  = ($false, 'ALREADY LOGGED IN')
    3  = ($false, 'NO CONNECTION')
    5  = ($false, 'INVALID PASSWORD')
    7  = ($true, 'INITIALIZED')
    8  = ($false, 'FAILED TO INSTALL')
    63 = ($false, 'STEAM GUARD REQUIRED')
  }

  $script_exit_codes = @{
    SUCCESS                      = 0
    STEAMCMD_INSTALLATION_FAILED = 1
    APP_INSTALLATION_FAILED      = 2
    INTERACTIVE_MODE_FAIL        = 4
  }

  $temp_dir = Join-Path -Path ([Path]::GetTempPath()) -ChildPath ($script_info.name.ToLower())
  $steamcmd_installed = $false
  [string]$steamcmd_installation_path = $null
  [string]$steamcmd_executable_path = $null
  [string]$current_os_type = $null

  $commands = @(
    @{
      name    = 'exit'
      aliases = 'quit', 'bail', 'logout'
      action  = { $should_exit = $true }
    },
    @{
      name    = 'help'
      aliases = @()
      action  = { Log-Info 'This is a {0} message' 'help' }
    }
  )

  function Write-ScriptInfo {
    Write-Ascii -InputObject "$($script_info.name) v$($script_info.version)"
    $width = $Host.UI.RawUI.WindowSize.Width
    $separator = [string]::new('=', $width)
    Write-Colorized $separator
    Write-Colorized "Author:     <magenta>$($script_info.author)</magenta>"
    Write-Colorized "Version:    <yellow>$($script_info.version)</yellow>"
    Write-Colorized "License:    $($script_info.license)/<blue>$($script_info.license_url)</blue>"
    Write-Colorized "Repository: <blue>$($script_info.repo)</blue>"
    Write-Colorized $separator
  }

  function Format-String {
    param (
      [string] $format,
      [object[]] $arguments
    )

    return [string]::Format($format, $arguments)
  }

  function Wrap-Color {
    param(
      [object] $arg,
      [System.ConsoleColor] $color
    )

    $color_str = $color.ToString()

    $str = $arg.ToString()

    return "<$color_str>$str</$color_str>"
  }

  function Log {
    param (
      [string]$format,
      [object[]] $arguments = @(),
      [System.ConsoleColor] $arguments_color = 'Cyan'
    )

    $array = @()
    foreach ($arg in $arguments) {
      $array += Wrap-Color $arg $arguments_color
    }

    $message = Format-String $format $array

    Write-Colorized $message
  }

  function Log-Info {
    param (
      [string]$format,
      [object[]]$arguments
    )

    Log "[   <gray>i</gray>   ] $format" $arguments Cyan
  }

  function Log-Success {
    param (
      [string] $format,
      [object[]] $arguments
    )

    Log "[   <green>✓</green>   ] $format" $arguments Green
  }

  function Log-Wait {
    param (
      [string] $format,
      [object[]] $arguments
    )

    Log "[  <yellow>~~~</yellow>  ] $format" $arguments Yellow
  }

  function Log-Warn {
    param (
      [string] $format,
      [object[]] $arguments
    )

    Log "[   <yellow>!</yellow>   ] $format" $arguments Yellow
  }

  function Log-Fail {
    param (
      [string] $format,
      [object[]] $arguments
    )

    Log "[   <red>✕</red>   ] $format" $arguments Red
  }

  function Log-Verbose {
    param (
      [string] $format,
      [object[]] $arguments
    )

    if ($VerbosePreference -eq 'SilentlyContinue') {
      return
    }

    Log "[<darkgray>VERBOSE</darkgray>] $format" $arguments DarkCyan
  }

  function Log-Debug {
    param (
      [string] $format,
      [object[]] $arguments
    )

    if ($DebugPreference -eq 'SilentlyContinue') {
      return
    }

    Log "[ <darkgreen>DEBUG</darkgreen> ] $format" $arguments DarkBlue
  }

  function Get-DownloadLink {
    param (
      [string] $os
    )

    switch ($os) {
      'win' {
        return $download_url.win
      }
      'linux' {
        return $download_url.linux
      }
      'osx' {
        return $download_url.osx
      }
    }
  }

  function Resolve-OsType {
    param (
      [string] $type_string
    )

    if ([string]::IsNullOrWhiteSpace($type_string)) {
      if ($IsWindows) {
        return 'win'
      } elseif ($IsLinux) {
        return 'linux'
      } else {
        return 'osx'
      }
    } else {
      switch -Wildcard ($type_string) {
        'win*' {
          return 'win'
        }
        { $PSItem -like 'lin*' -or $PSItem -like 'unix*' } {
          return 'linux'
        }
        { $PSItem -like 'osx' -or $PSItem -like 'mac*' -or $PSItem -like 'os?x' } {
          return 'osx'
        }
      }
    }
  }

  function Test-Installation {
    param(
      [string] $install_directory,
      [string] $os
    )

    Log-Verbose 'Checking current installation...'

    if (!(Test-Path $install_directory)) {
      Log-Verbose 'Install directory does not exist'
      return $false
    }

    $ex_paths = @()
    switch ($os) {
      'win' {
        $ex_paths += Join-Path $install_directory 'steamcmd.exe'
      }
      default {
        $ex_paths += Join-Path $install_directory 'steamcmd'
        $ex_paths += Join-Path $install_directory 'steamcmd.sh'
      }
    }

    foreach ($p in $ex_paths) {
      if (!(Test-Path $p)) {
        Log-Verbose 'File {0} not found' $p
        return $false
      }
    }
    Log-Success 'SteamCmd installation already exists at path {0}' $install_directory
    return $true
  }

  function Install-Steamcmd {
    param (
      [string] $install_directory,
      [string] $os
    )

    Log-Wait "Installing SteamCmd-{0} into '{1}', please wait..." @($os, $install_directory)
    if (!(Test-Installation $install_directory $os)) {
      $download_url = Get-DownloadLink $os
      $temp_installation_dir = Join-Path $temp_dir $os
      $archive_path = Join-Path $temp_installation_dir ($os -eq 'win' ? 'steamcmd.zip' : 'steamcmd.tar.gz')

      if (Test-Path $archive_path) {
        Log-Debug 'Removing old archive at {0}' $archive_path
      }

      if (!(Test-Path $temp_installation_dir)) {
        mkdir $temp_installation_dir
        Log-Debug 'Created temporary installation path at {0}'
      }

      try {
        Log-Wait 'Downloading steamcmd distribution from {0}...' $download_url
        Invoke-WebRequest -Uri $download_url -UseBasicParsing -OutFile $archive_path
      } catch {
        Log-Fail 'Failed to install SteamCmd: {0}' $_.Exception.Message
        return $false
      }

      try {
        Log-Wait 'Extracting distribution...'
        $target_temp_path = Join-Path -Path $temp_installation_dir -ChildPath 'steamcmd' -AdditionalChildPath 'install'
        $target_interm_path = Join-Path $temp_installation_dir 'steamcmd.tar'

        if (Test-Path $target_temp_path) {
          Log-Debug 'Removing {0}' $target_temp_path
          Get-Item $target_temp_path | Remove-Item -Recurse -Force
        }

        if (Test-Path $target_interm_path) {
          Log-Debug 'Removing {0}' $target_interm_path
          Get-Item $target_interm_path | Remove-Item -Recurse -Force
        }

        Expand-7Zip -ArchiveFileName $archive_path -TargetPath ($os -eq 'win' ? $target_temp_path : $target_interm_path)

        if ($os -ne 'win') {
          Expand-7Zip -ArchiveFileName $target_interm_path -TargetPath $target_temp_path
        }

        $dist = Get-ChildItem -Path $target_temp_path

        Log-Wait 'Moving extracted distribution into destination folder...'
        Log-Debug 'Items: {0}' ($dist | Select-Object -ExpandProperty Name | Format-List | Out-String)

        if (!(Test-Path $install_directory)) {
          mkdir $install_directory -Force
        }

        foreach ($item in $dist) {
          $item | Move-Item -Destination $install_directory -Force
        }
      } catch {
        Log-Fail 'Failed to install SteamCmd: {0}' $_.Exception.Message
        return $false
      }
    }

    Log-Success 'SteamCmd installation completed'
    return $true
  }

  function Get-ExecutablePath {
    param(
      [string] $installation_path,
      [string] $os
    )

    if ($os -eq 'win') {
      return Join-Path $installation_path 'steamcmd.exe'
    } else {
      return Join-Path $installation_path 'steamcmd.sh'
    }
  }

  function PrevLine {
    $x = $Host.UI.RawUI.CursorPosition.X
    $y = $Host.UI.RawUI.CursorPosition.Y

    $Host.UI.RawUI.CursorPosition = @{
      X = $x
      Y = $y - 1
    }
  }

  function Set-XPos {
    param(
      $x
    )

    $y = $Host.UI.RawUI.CursorPosition.Y

    $Host.UI.RawUI.CursorPosition = @{
      X = $x
      Y = $y
    }
  }

  function Redraw-Input {
    param (
      [string]$in,
      [System.ConsoleColor]$color
    )

    Set-XPos 10
    Write-Host -Object ([string]::new([char]' ', $Host.ui.RawUI.WindowSize.Width - 10)) -NoNewline
    Set-XPos 10
    if ($in.Length -gt 0) {
      Write-Colorized $in -DefaultColor $color
      PrevLine
      Set-XPos ($in.Length + 10)
    }
  }

  function Find-CommandDefinition {
    param(
      $name_or_alias
    )

    foreach ($cmd in $commands) {
      if ($cmd.name -eq $name_or_alias) {
        return $cmd
      }

      if ($cmd.aliases.Contains($name_or_alias)) {
        return $cmd
      }
    }

    return $null
  }

  function Get-UserCommand {
    Write-Colorized '[  <green>>>></green>  ] '
    PrevLine

    $readKeyOptions = 8 -bor 2
    $in = ''
    [object]$cmd = $null
    while ($true) {
      $color = 'Gray'

      $cmd = Find-CommandDefinition -name_or_alias ($in.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)?[0]?.ToLower())
      if ($cmd) {
        if ($cmd.name -eq 'exit') {
          $color = 'Red'
        } else {
          $color = 'Yellow'
        }
      }

      Redraw-Input $in $color

      $key = $Host.UI.RawUI.ReadKey($readKeyOptions)

      if ($key.VirtualKeyCode -eq 8) {
        if ($in.Length -gt 0) {
          $in = $in.Substring(0, $in.Length - 1)
        }
      } elseif ($key.VirtualKeyCode -eq 13) {
        break
      } else {
        $in += $key.Character.ToString()
      }
    }
    $Host.UI.WriteLine()
    return $cmd
  }

  function Run-Interactive {
    $should_exit = $false

    do {
      $command = Get-UserCommand
      Log-Info 'Got command {0}' ($command.name ?? '__empty__')

      if ($command.action) {
        Invoke-Command -ScriptBlock ($command.action) -NoNewScope
      }
    } until($should_exit)
  }

  function Run-Standard {

  }
}

process {
  Write-ScriptInfo

  Log-Debug 'Temp directory set to: {0}' $temp_dir
  $current_os_type = Resolve-OsType
  Log-Verbose 'OS type: {0}' $current_os_type
  $steamcmd_installation_path = [Path]::GetFullPath(($CmdInstallDir ? $CmdInstallDir : (Join-Path $script_info.dir 'steamcmd')))
  Log-Verbose 'SteamCmd installation directory set to {0}' $steamcmd_installation_path

  $steamcmd_installed = Install-Steamcmd -install_directory $steamcmd_installation_path -os $current_os_type

  if (!$steamcmd_installed) {
    Log-Fail 'Cannot process, SteamCmd is not installed and all the installation attempts failed.'
    exit $script_exit_codes.STEAMCMD_INSTALLATION_FAILED
  }

  $steamcmd_executable_path = Get-ExecutablePath $steamcmd_installation_path $current_os_type

  if (!(Test-Path $steamcmd_executable_path)) {
    Log-Fail 'SteamCmd executable was not found.'
    exit $script_exit_codes.STEAMCMD_INSTALLATION_FAILED
  }

  Log-Verbose 'SteamCmd executable found at: {0}' $steamcmd_executable_path

  if ($Interactive) {
    Log-Info 'Running in <yellow>interactive</yellow> mode...'
    Run-Interactive
  } else {
    Log-Info 'Running in <cyan>standard</cyan> mode...'
    Run-Standard
  }

  Log-Success 'Exiting script...'
  exit $script_exit_codes.SUCCESS
}
