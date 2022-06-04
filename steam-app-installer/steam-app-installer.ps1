#!/usr/bin/env pwsh
#requires -psedition Core
#requires -version 6.0

using namespace System.IO
using namespace System.Text

[CmdletBinding(
  DefaultParameterSetName = 'AllParameterSets',
  SupportsShouldProcess = $true,
  ConfirmImpact = 'Low',
  PositionalBinding = $true
)]
param(
  [Parameter(HelpMessage = 'Id of the app to install', Mandatory = $true, Position = 0)]
  [Alias('a', 'app')]
  [int] $AppId,

  [Parameter(
    HelpMessage = 'Directory to use for app installation',
    Position = 1
  )]
  [Alias('p', 'path')]
  [string] $InstallPath = "$([Path]::GetFullPath("$PWD/app_$AppId"))",

  # [Parameter(HelpMessage = 'Validate app installation (incremental upgrade)')]
  [Parameter(HelpMessage = 'Validate app installation (incremental upgrade)', ParameterSetName = 'Validate', Mandatory = $true)]
  [Parameter(HelpMessage = 'Validate app installation (incremental upgrade)', ParameterSetName = 'Branch-Validate', Mandatory = $true)]
  [switch] $Validate,

  # [Parameter(HelpMessage = 'Delete app files before installation (clean installation)')]
  [Parameter(HelpMessage = 'Delete app files before installation (clean installation)', ParameterSetName = 'Clean', Mandatory = $true)]
  [Parameter(HelpMessage = 'Delete app files before installation (clean installation)', ParameterSetName = 'Branch-Clean', Mandatory = $true)]
  [switch] $Clean,

  # [Parameter(HelpMessage = 'Use custom installation branch')]
  [Parameter(HelpMessage = 'Use custom installation branch', ParameterSetName = 'Branch', Mandatory = $true)]
  [Parameter(HelpMessage = 'Use custom installation branch', ParameterSetName = 'Branch-Clean', Mandatory = $true)]
  [Parameter(HelpMessage = 'Use custom installation branch', ParameterSetName = 'Branch-Validate', Mandatory = $true)]
  [Alias('b')]
  [string] $Branch = $null,

  # [Parameter(HelpMessage = 'Username for the custom branch')]
  [Parameter(HelpMessage = 'Username for the custom branch', ParameterSetName = 'Branch')]
  [Parameter(HelpMessage = 'Username for the custom branch', ParameterSetName = 'Branch-Clean')]
  [Parameter(HelpMessage = 'Username for the custom branch', ParameterSetName = 'Branch-Validate')]
  [Alias('u', 'user')]
  [string] $Username = $null,

  # [Parameter(HelpMessage = 'Password for the custom branch')]
  [Parameter(HelpMessage = 'Password for the custom branch', ParameterSetName = 'Branch')]
  [Parameter(HelpMessage = 'Password for the custom branch', ParameterSetName = 'Branch-Clean')]
  [Parameter(HelpMessage = 'Password for the custom branch', ParameterSetName = 'Branch-Validate')]
  [string] $Password = $null
)

begin {
  $BASE_TEMP_PATH = [Path]::Combine([Path]::GetTempPath(), 'steam-app-installer')
  $DOWNLOAD_PATH = [Path]::Combine($BASE_TEMP_PATH, 'dist')
  $CMD_INSTALL_PATH = [Path]::Combine($BASE_TEMP_PATH, 'steamcmd')
  $SCRIPT_PATH = [Path]::Combine($BASE_TEMP_PATH, 'startup.txt')

  $STEAMCMD_DL_URL = @{
    windows = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    linux   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
    osx     = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz'
  }

  $SCRIPT_TEMPLATE = @'
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
force_install_dir "%install-dir%"
login %login-string%
app_update %app-id% %branch% %validate%
quit
'@

  $STEAMCMD_EXIT_CODES_PATH = [Path]::GetFullPath("$PsScriptRoot/steamcmd_exit_codes.json")

  $global:STEAMCMD_EXIT_CODES_STORAGE = $null

  function Load-SteamCmdExitCodeFile {
    $json = Get-Content -Path $STEAMCMD_EXIT_CODES_PATH -Raw

    $global:STEAMCMD_EXIT_CODES_STORAGE = ConvertFrom-Json -InputObject $json -AsHashtable
  }

  function Get-SteamCmdExitCodeDescription {
    param(
      [string]$code
    )

    $entry = $STEAMCMD_EXIT_CODES_STORAGE[$code]

    return $entry.description
  }

  function Get-SteamCmdExitCodeStatus {
    param(
      [string]$code
    )

    $entry = $STEAMCMD_EXIT_CODES_STORAGE[$code]

    return $entry.success
  }

  function Get-LoginString {
    if (-not $Username) {
      return 'anonymous'
    }

    return "$Username $Password"
  }

  function Get-SteamCmdDownloadUrl {
    param (
      [ValidateSet('windows', 'linux', 'osx')]
      [string] $Platform
    )

    return $STEAMCMD_DL_URL[$Platform]
  }

  function Get-SteamCmdArchiveName {
    param(
      [ValidateSet('windows', 'linux', 'osx')]
      [string] $Platform
    )

    switch ($Platform) {
      windows {
        return 'steamcmd.zip'
      }
      Default {
        return 'steamcmd.tar.gz'
      }
    }
  }

  function Get-SteamCmdExecName {
    param(
      [ValidateSet('windows', 'linux', 'osx')]
      [string] $Platform
    )

    switch ($Platform) {
      windows {
        return 'steamcmd.exe'
      }
      Default {
        return 'steamcmd'
      }
    }
  }

  function Get-InstallationPlatform {
    if ($IsWindows) {
      return 'windows'
    } elseif ($IsLinux) {
      return 'linux'
    } else {
      return 'osx'
    }
  }

  function Install-SteamCmd {
    param(
      $dl_url,
      $arch_path
    )

    Write-Output 'Installing SteamCmd...'

    Write-Verbose 'Cleaning installation directory and old archives...'

    if (Test-Path -Path $CMD_INSTALL_PATH) {
      Get-ChildItem $CMD_INSTALL_PATH | Remove-Item -Force -Recurse
    }

    if (Test-Path -Path $arch_path) {
      Remove-Item $arch_path
    }

    Write-Verbose "Downloading SteamCmd distribution from $dl_url"

    Invoke-WebRequest -Uri $dl_url -UseBasicParsing -OutFile $arch_path

    Write-Verbose "Archive downloaded to $arch_path"

    Expand-Archive -Path $arch_path -DestinationPath $CMD_INSTALL_PATH

    Write-Verbose 'Cleaning unnecessary distribution files'

    Remove-Item -Path $arch_path

    Write-Output 'SteamCmd installed'
  }

  function Clean-InstallDir {
    Write-Output "Cleaning installation directory: $InstallPath"

    if (Test-Path -Path $InstallPath) {
      Remove-Item -Path $InstallPath -Force -Recurse
    }
  }

  function Compose-StartupScript {
    param($login_string)

    Write-Output 'Creating startup script...'

    $builder = [StringBuilder]::new($SCRIPT_TEMPLATE)

    $builder.Replace('%install-dir%', $InstallPath).
    Replace('%login-string%', $login_string).
    Replace('%app-id%', $AppId.ToString()).
    Replace('%branch%', ($Branch ? "-beta $Branch" : '')).
    Replace('%validate%', ($Validate ? 'validate' : ''))

    return $builder.ToString()
  }

  function Get-SteamCmdInvokePath {
    param($exec_name)

    return [Path]::Combine($CMD_INSTALL_PATH, $exec_name)
  }

  function Invoke-SteamCmd {
    param($exec_path)

    Write-Verbose "Installing app $AppId"

    Start-Process -FilePath $exec_path -ArgumentList "+runscript $SCRIPT_PATH" -NoNewWindow -Wait
  }
}
process {

  Load-SteamCmdExitCodeFile

  $installation_platform = Get-InstallationPlatform
  $steamcmd_arch_name = Get-SteamCmdArchiveName -Platform $installation_platform
  $steamcmd_exec_name = Get-SteamCmdExecName -Platform $installation_platform
  $steamcmd_download_url = $STEAMCMD_DL_URL[$installation_platform]

  $steamcmd_arch_path = Join-Path -Path $DOWNLOAD_PATH -ChildPath $steamcmd_arch_name
  $steamcmd_exec_path = Join-Path -Path $CMD_INSTALL_PATH -ChildPath $steamcmd_exec_name

  # Check if SteamCmd is installed

  Write-Verbose 'Creating working directories...'

  if (-not (Test-Path -Path $BASE_TEMP_PATH)) {
    New-Item -Path $BASE_TEMP_PATH -ItemType Directory
  }

  if (-not (Test-Path -Path $DOWNLOAD_PATH)) {
    New-Item -Path $DOWNLOAD_PATH -ItemType Directory
  }

  $steamcmd_installed = Test-Path -Path $steamcmd_exec_path

  if (-not $steamcmd_installed) {
    Install-SteamCmd $steamcmd_download_url $steamcmd_arch_path
  }
  $login_string = Get-LoginString

  Write-Verbose "Login string: $login_string"

  if ($Clean) {
    Clean-InstallDir
  }

  [string] $script = (Compose-StartupScript $login_string)[1]

  Write-Verbose "Emitting startup script to: $SCRIPT_PATH"

  $script | Out-File -FilePath $SCRIPT_PATH -Force -Encoding ascii

  Write-Output 'Starting app installation...'

  $exec_path = Get-SteamCmdInvokePath -exec_name (Get-SteamCmdExecName -Platform (Get-InstallationPlatform))

  Invoke-SteamCmd $exec_path
}
end {
}
