#!/usr/bin/env pwsh
#requires -psedition Core
#requires -version 6.0
#requires -modules PSColorizer

using namespace System
using namespace System.IO

[CmdletBinding(
  DefaultParameterSetName = 'AllParameterSets',
  SupportsShouldProcess = $true,
  ConfirmImpact = 'Low',
  PositionalBinding = $true
)]
param(
  [Parameter(HelpMessage = 'AppID of the target app', Mandatory = $false)]
  [Alias('app', 'id')]
  [AllowNull]
  [int] $AppId = 0,

  [Parameter(HelpMessage = 'Installation directory of the app', Mandatory = $false)]
  [Alias('dir', 'd', 'path')]
  [AllowNull]
  [int] $InstallDir = $null,

  [Parameter(HelpMessage = 'Validate installed files', Mandatory = $false, ParameterSetName = 'Validate')]
  [Alias('v')]
  [AllowNull]
  [switch] $Validate,

  [Parameter(HelpMessage = 'Clean installation', Mandatory = $false, ParameterSetName = 'Clean')]
  [Alias('c')]
  [AllowNull]
  [switch] $Clean,

  [Parameter(HelpMessage = 'Branch (beta) of the application', Mandatory = $false)]
  [AllowNull]
  [Alias('b')]
  [string] $Branch,

  [Parameter(HelpMessage = 'Username (default = anonymous), if login is required', Mandatory = $false)]
  [AllowNull]
  [Alias('u')]
  [string] $Username = 'anonymous',

  [Parameter(HelpMessage = 'Password, if login is required', Mandatory = $false)]
  [AllowNull]
  [Alias('p')]
  [string] $Password = $null
)

begin {
  $steamcmd_download_urls = @{
    windows = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    linux   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
    osx     = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz'
  }

  $script_template = @'
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
login %login-string%
force_install_dir %install-dir%
app_update %app-id% %branch% %validate%
quit
'@

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
  }

  $should_login = ![string]::IsNullOrWhiteSpace($Username) -and !($Username -like 'anonymous')
  $should_download_app = ($AppId -ne $null) -and ($AppId -ne 0)

  $temp_dir = [Path]::Combine([Path]::GetTempPath(), 'automation', 'steamcmd')
  $archives_dir = [Path]::Combine($temp_dir, 'archives')
  $steamcmd_install_dir = [Path]::Combine($temp_dir, 'steamcmd_install')

  function Get-LoginString {
    if (!$should_login) {
      return 'anonymous'
    } else {
      return "$Username $Password"
    }
  }

  function Resolve-InstallDir {
    return [Path]::GetFullPath($InstallDir)
  }

  function Clean-InstallDir {
    param($install_dir)

    if (Test-Path $install_dir) {
      $contents = Get-ChildItem $install_dir

      foreach ($item in $contents) {
        Remove-Item -Path ($item.FullName) -Recurse -Force
      }
    }
  }

}

process {

}

end {

}
