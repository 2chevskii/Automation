#!/usr/bin/env pwsh
#requires -psedition Core
#requires -version 6.0

using namespace System.IO

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
app_update %app-id%%branch%%validate%
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
    if ($null -eq $Username) {
      return 'anonymous'
    }

    return "$Username $Password"
  }

  function Get-SteamCmdDownloadUrl {
    param (
      [Parameter]
      [ValidateSet('windows', 'linux', 'osx')]
      [string] $Platform
    )

    return $STEAMCMD_DL_URL[$Platform]
  }

  function Get-SteamCmdArchiveName {
    param(
      [Parameter]
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

  function Get-InstallationPlatform {
    if ($IsWindows) {
      return 'windows'
    } elseif ($IsLinux) {
      return 'linux'
    } else {
      return 'osx'
    }
  }
}
process {

  Load-SteamCmdExitCodeFile


}
end {
}
