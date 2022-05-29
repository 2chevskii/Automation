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
    Position = 1,
    Mandatory = $true
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
}
process {
}
end {
}
