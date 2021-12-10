#!/usr/bin/env pwsh
#requires -psedition Core
#requires -version 6.0
#requires -modules PSColorizer

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

$script_template = @'
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
login %login-string%
force_install_dir %install-dir%
app_update %app-id% %branch% %validate%
quit
'@

$should_login = ![string]::IsNullOrWhiteSpace($Username) -and !($Username -like 'anonymous')
$should_download_app = ($AppId -ne $null) -and ($AppId -ne 0)

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
