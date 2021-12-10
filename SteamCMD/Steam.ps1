#!/usr/bin/env pwsh
#requires -psedition Core
#requires -version 6.0
#requires -modules PSColorizer

using namespace System
using namespace System.IO
using namespace System.Text

[CmdletBinding(
  DefaultParameterSetName = 'AllParameterSets',
  SupportsShouldProcess = $true,
  ConfirmImpact = 'Low',
  PositionalBinding = $true
)]
param(
  [Parameter(HelpMessage = 'AppID of the target app', Mandatory = $false)]
  [Alias('app', 'id')]
  [int] $AppId = 0,

  [Parameter(HelpMessage = 'Installation directory of the app', Mandatory = $false)]
  [Alias('dir', 'd', 'path')]
  [string] $InstallDir = $null,

  [Parameter(HelpMessage = 'Validate installed files', Mandatory = $false, ParameterSetName = 'Validate')]
  [Alias('v')]
  [switch] $Validate,

  [Parameter(HelpMessage = 'Clean installation', Mandatory = $false, ParameterSetName = 'Clean')]
  [Alias('c')]
  [switch] $Clean,

  [Parameter(HelpMessage = 'Branch (beta) of the application', Mandatory = $false)]
  [Alias('b')]
  [string] $Branch = $null,

  [Parameter(HelpMessage = 'Username (default = anonymous), if login is required', Mandatory = $false)]
  [Alias('u')]
  [string] $Username = 'anonymous',

  [Parameter(HelpMessage = 'Password, if login is required', Mandatory = $false)]
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
force_install_dir "%install-dir%"
login %login-string%
app_update %app-id%%branch%%validate%
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
    63 = ($false, 'STEAM GUARD REQUIRED') # not confirmed to be a thing
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
  $startup_script_path = [Path]::Combine($temp_dir, 'commands.txt')

  function Get-LoginString {
    if (!$should_login) {
      return 'anonymous'
    } else {
      return "$Username $Password"
    }
  }

  function Resolve-InstallDir {
    [string] $p = $null

    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
      $p = './app_' + $AppId
    } else {
      $p = $InstallDir
    }

    return [Path]::GetFullPath($p)
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

  function Get-ScriptText {
    param($login_string, $install_dir, $app_id, $branch_name, $need_validate)

    $builder = [StringBuilder]::new($script_template)

    $builder.Replace('%login-string%', $login_string).
    Replace('%install-dir%', $install_dir).
    Replace('%app-id%', $app_id) | Out-Null

    if ($branch_name) {
      $builder.Replace('%branch%', ' -beta ' + $branch_name) | Out-Null
    } else {
      $builder.Replace('%branch%', '') | Out-Null
    }

    if ($need_validate) {
      $builder.Replace('%validate%', ' validate') | Out-Null
    } else {
      $builder.Replace('%validate%', '') | Out-Null
    }

    return $builder.ToString()
  }

  function Get-SteamcmdDownloadUrl {
    if ($IsWindows) {
      return ('windows', $steamcmd_download_urls.windows)
    } elseif ($IsLinux) {
      return ('linux', $steamcmd_download_urls.linux)
    } elseif ($IsMacOS) {
      return ('osx', $steamcmd_download_urls.osx)
    } else {
      throw [NotSupportedException]::new('Script does not support current OS')
    }
  }

  function Get-SteamcmdExecPath {
    if ($IsWindows) {
      return Join-Path -Path $steamcmd_install_dir -ChildPath 'steamcmd.exe'
    } else {
      return Join-Path -Path $steamcmd_install_dir -ChildPath 'steamcmd.sh'
    }
  }

  function Test-SteamcmdInstalled {
    return Test-Path (Get-SteamcmdExecPath)
  }

  function Log {
    param($msg, $arguments = @())

    $logmsg = Format-LogMessage -msg $msg -arguments $arguments -color 'white'

    Write-Colorized -Message $logmsg -DefaultColor Gray
  }

  function Log-Warn {
    param($msg, $arguments = @())

    $logmsg = Format-LogMessage -msg $msg -arguments $arguments -color 'yellow'

    Write-Colorized -Message $logmsg -DefaultColor Gray
  }

  function Log-Err {
    param($msg, $arguments = @())

    $logmsg = Format-LogMessage -msg $msg -arguments $arguments -color 'red'

    Write-Colorized -Message $logmsg -DefaultColor Gray
  }

  function Log-Info {
    param($msg, $arguments = @())

    $logmsg = Format-LogMessage -msg $msg -arguments $arguments -color 'cyan'

    Write-Colorized -Message $logmsg -DefaultColor Gray
  }

  function Format-LogMessage {
    param($msg, $arguments, $color)

    $strargs = @()

    foreach ($arg in $arguments) {
      $strargs += "<$color>$($arg.ToString())</$color>"
    }

    $logmsg = [string]::Format($msg, $strargs)

    return "<$color>>>></$color> " + $logmsg
  }

  function Extract-Build {
    param($arch_path, $target_path)

    if (!(Test-Path $target_path)) {
      Log 'Created steamcmd directory at {0}' $target_path
      New-Item $target_path -ItemType Directory -Force
    }

    if ($IsWindows) {
      Log 'Extracting archive using {0}...' 'Expand-Archive'
      Expand-Archive -Path $arch_path -DestinationPath $target_path -Force
    } else {
      Log 'Extracting archive using {0}...' 'Tar'
      & tar -xzf $arch_path -C $target_path
    }

    Log-Info 'Done unpacking SteamCmd build'
  }
}

process {
  if (!(Test-SteamcmdInstalled)) {
    Log-Info 'SteamCmd is not installed, will install now'

    try {
      $dl = Get-SteamcmdDownloadUrl

      Log-Info 'Using {0} build...' $dl[0]

      $arch_path = Join-Path -Path $archives_dir -ChildPath (Split-Path -Path $dl[1] -Leaf)

      Log 'Downloading build from {0} to {1}' $dl[1], $arch_path

      if (!(Test-Path $archives_dir)) {
        New-Item $archives_dir -ItemType Directory -Force
      }

      Invoke-WebRequest -Uri $dl[1] -OutFile $arch_path

      Extract-Build -arch_path $arch_path -target_path $steamcmd_install_dir

      Log-Info 'SteamCmd was installed sucessfully at {0}' $steamcmd_install_dir
    } catch {
      Log-Err "Failed to install steamcmd:`n{0}" ($_.Exception.Message)
      exit $script_exit_codes.STEAMCMD_INSTALLATION_FAILED
    }
  } else {
    Log 'Existing SteamCmd installation found'
  }

  $scmd_exec = Get-SteamcmdExecPath

  Log 'Performing an update-run...'

  & $scmd_exec +quit

  Log 'SteamCmd update finished'

  if (-not $should_download_app) {
    Log-Warn 'No app was chosen for installation, exiting'
  } else {
    Log-Info 'Installing app {0}' $AppId

    $installation_dir = Resolve-InstallDir

    Log-Info 'Installation path is: {0}' $installation_dir

    $lstr = Get-LoginString

    $scrpt_txt = Get-ScriptText $lstr $installation_dir $AppId $Branch $Validate

    if ($Clean -and (Test-Path $installation_dir)) {
      Log-Warn 'Cleaning installation directory {0}...' $installation_dir

      $children = Get-ChildItem $installation_dir

      foreach ($child in $children) {
        Remove-Item $child.FullName -Force -Recurse
      }
    }

    Log-Warn 'Emitting startup script at {0}' $startup_script_path
    $scrpt_txt | Out-File -FilePath $startup_script_path -Force

    & $scmd_exec +runscript $startup_script_path

    $exc = $LASTEXITCODE

    Write-Host "Exit code: $exc"
  }
}

end {

}
