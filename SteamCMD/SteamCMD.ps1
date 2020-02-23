#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Invokes steamcmd actions
.DESCRIPTION
    You can install steamcmd and apps using this script
.EXAMPLE
    SteamCMD.ps1 ./steamcmdfolder 258550 ./rust-ds -validate
    Install Rust dedicated server into rust-ds/ folder using steamcmd executable from steamcmdfolder/
.LINK
    https://github.com/2chevskii/Scripts/blob/master/SteamCMD.ps1
#>
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "password")]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "branchpassword")]
[CmdLetBinding(DefaultParameterSetName = 'LocalInstall', PositionalBinding)]
param (
    ## App
    [Parameter(Position = 0)]
    [Alias('id')]
    [int]$AppID,
    [Parameter(Position = 1)]
    [Alias('dir')]
    [string]$AppInstallPath,
    [switch]$Validate,

    ## Steamcmd executable
    [Parameter(ParameterSetName = 'LocalInstall', Position = 2)]
    [string]$InstallPath = "$PSScriptRoot/steamcmd",
    [Parameter(ParameterSetName = 'GlobalInstall', Mandatory = $true)]
    [Alias('g')]
    [ValidateScript( { $IsLinux }, ErrorMessage = "GlobalInstall option is only available while using Linux-based OS!")]
    [switch]$GlobalInstall,

    ## Alternative branches
    [Alias('b')]
    [string]$Branch,
    [string]$BranchPassword,

    ## Logging in
    [Parameter(Position = 3)]
    [ValidatePattern('^(?!^anonymous$).*$')]
    [Alias('username', 'user', 'l')]
    [ValidateNotNullOrEmpty()]
    [string]$Login,
    [Parameter(Position = 4)]
    [ValidateNotNullOrEmpty()]
    [Alias('p', 'pass')]
    [string]$Password,
    [Parameter(Position = 5)]
    [ValidateNotNullOrEmpty()]
    [string]$SteamGuard
)

#region WELCOME SCREEN

$script_name = 'SteamCMD helper'
$script_author = '2CHEVSKII'
$script_version = @{
    major = 2
    minor = 1
    patch = 1
}
$script_version_formatted = "v$($script_version.major).$($script_version.minor).$($script_version.patch)"
$script_license_link = 'https://www.tldrlegal.com/l/mit'
$script_repository = 'https://github.com/2chevskii/Scripts'

Write-Host "$script_name " -NoNewline
Write-Host "$script_version_formatted " -NoNewline -ForegroundColor DarkYellow
Write-Host 'by ' -NoNewline
Write-Host $script_author -ForegroundColor Magenta
Write-Host 'Licensed under the MIT License: ' -NoNewline
Write-Host $script_license_link -ForegroundColor Blue
Write-Host 'Source repository: ' -NoNewline
Write-Host $script_repository -ForegroundColor DarkBlue

#endregion

#region Constants

$steamcmd_downloadlink = @{
    windows = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    linux   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
    macos   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz'
}

$is64bit = [System.Environment]::Is64BitOperatingSystem

enum OSVer {
    WINDOWS
    MACOS
    DEBIAN_UBUNTU
    REDHAT_CENTOS
    ARCH
    NOT_SUPPORTED
}

#endregion

#region Functions

function Write-Colored {
    param(
        [string]$msg,
        [System.ConsoleColor]$color
    )

    $defcolor = $Host.UI.RawUI.ForegroundColor

    $Host.UI.RawUI.ForegroundColor = $color
    Write-Output $msg
    $Host.UI.RawUI.ForegroundColor = $defcolor
}

function Get-OsRelease {
    if ($IsWindows) {
        return [OSVer]::WINDOWS
    }

    if ($IsMacOS) {
        return [OSVer]::MACOS
    }

    $os_release = Get-Content -Path '/etc/os-release' -ErrorAction SilentlyContinue

    if (!$os_release) {
        return [OSVer]::NOT_SUPPORTED
    }

    $name = $os_release[0]

    if ($name -like '*ubuntu*') {
        return [OSVer]::DEBIAN_UBUNTU
    }

    if ($name -like '*redhat*' -or $name -like '*centos*') {
        return [OSVer]::REDHAT_CENTOS
    }

    if ($name -like '*arch*') {
        return [OSVer]::ARCH
    }

    return [OSVer]::NOT_SUPPORTED
}

function Install-Global {
    param(
        [Parameter(ValueFromPipeline)]
        [OSVer]$os
    )

    if (!$IsLinux) {
        throw 'Repository install is only available in Linux systems!'
    }

    switch ($os) {
        [OSVer]::DEBIAN_UBUNTU {
            if ($is64bit) {
                &sudo add-apt-repository multiverse
                &sudo dpkg --add-architecture i386
                &sudo apt update
                &sudo apt install lib32gcc1 steamcmd
            }
            else {
                &sudo apt install steamcmd
            }
        }
        [OSVer]::REDHAT_CENTOS {
            &yum install steamcmd
        }
        [OSVer]::ARCH {
            &git clone https://aur.archlinux.org/steamcmd.git
            Set-Location steamcmd
            &makepkg -si
            &ln -s /usr/games/steamcmd steamcmd
        }
        default {
            throw 'Your OS does not support repository installation, try another options!'
        }
    }
}

function Install-Local {
    param(
        [Parameter(ValueFromPipeline)]
        [OSVer]$os,
        [string]$path
    )

    if ($os -eq [OSVer]::NOT_SUPPORTED) {
        throw 'This OS version is not supported'
    }

    if ($os -ne [OSVer]::WINDOWS -and !(Get-Command tar.exe -ErrorAction SilentlyContinue)) {
        throw 'Tar not found'
    }

    switch ($os) {
        WINDOWS {
            $archive_path = Join-Path -Path $path -ChildPath 'steamcmd.zip'
            $dl_link = $steamcmd_downloadlink.windows
            $exec_path = Join-Path -Path $path -ChildPath 'steamcmd.exe'
        }
        MACOS {
            $archive_path = Join-Path -Path $path -ChildPath 'steamcmd.tar.gz'
            $dl_link = $steamcmd_downloadlink.macos
            $exec_path = Join-Path -Path $path -ChildPath 'steamcmd'
        }
        Default {
            $archive_path = Join-Path -Path $path -ChildPath 'steamcmd.tar.gz'
            $dl_link = $steamcmd_downloadlink.linux
            $exec_path = Join-Path -Path $path -ChildPath 'steamcmd'
        }
    }

    # Test if steamcmd exists already
    if (Test-Path $exec_path) {
        return
    }

    # Prepare installation folder 
    New-Item -Path $path -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

    try {
        Write-Output '[10%] Downloading steamcmd...'
        Invoke-WebRequest -Uri $dl_link -OutFile $archive_path
    }
    catch {
        throw 'Could not download steamcmd archive'
    }

    if (!(Test-Path $archive_path)) {
        throw 'Steamcmd archive was not downloaded for some reason'
    }

    try {
        Write-Output '[50%] Extracting archive...'
        if ($os -eq [OSVer]::WINDOWS) {
            Expand-Archive -Path $archive_path -DestinationPath $path -Force -ErrorAction Stop
        }
        else {
            &tar -C $path -xvzf $archive_path
        }
    }
    catch {
        throw 'Could not extract steamcmd archive'
    }

    try {
        Write-Output '[75%] Installing dependencies...'
        if ($os -eq [OSVer]::DEBIAN_UBUNTU -and $is64bit) {
            &sudo apt-get install lib32gcc1
        }
        elseif ($os -eq [OSVer]::REDHAT_CENTOS -and !$is64bit) {
            &yum install glibc libstdc++
        }
        elseif ($os -eq [OSVer]::REDHAT_CENTOS -and $is64bit) {
            &yum install glibc.i686 libstdc++.i686
        }
    }
    catch {
        throw 'Could not install dependencies'
    }

    try {
        Write-Output '[95%] Cleaning up...'
        Remove-Item -Path $archive_path -Force
    }
    catch {
        Write-Warning 'Error occured while cleaning up temp files'
    }

    if (!(Test-Path -Path $exec_path)) {
        throw 'Cannot find steamcmd executable'
    }

    if ($os -ne [OSVer]::WINDOWS) {
        try {
            Write-Output '[99%] Setting executable mode...'
            &sudo chmod +x $exec_path
        }
        catch {
            Write-Warning 'Could not set steamcmd as executable'
        }
    }
}

function Get-Login {
    param(
        [Parameter(Position = 0)]
        [string]$login,
        [Parameter(Position = 1)]
        [string]$password,
        [Parameter(Position = 2)]
        [string]$steamguard
    )
    $creds = '+login'

    if (!$login) {
        return $creds + ' anonymous'
    }

    $creds += " $login $password"
    
    if ($steamguard) {
        $creds += " $steamguard"
    }
    
    return $creds
}

function Install-App {

    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$id,
        [Parameter(Position = 1, Mandatory)]
        [string]$dir,
        [string]$branch,
        [string]$branchpass,
        [string]$login,
        [string]$password,
        [string]$steamguard,
        [Parameter(Position = 2)]
        [string]$steamcmdpath,
        [Parameter(Position = 3)]
        [switch]$validate
    )

    $launchargs = "$(Get-Login $login $password $steamguard) +force_install_dir $dir +app_update $id"

    if ($branch) {
        $launchargs += " -beta $branch"
    }

    if ($branchpass) {
        $launchargs += " -betapassword $branchpass"
    }

    if ($validate) {
        $launchargs += ' -validate'
    }

    $launchargs += ' +quit'
    $os = Get-OsRelease

    if ($os -eq [OSVer]::NOT_SUPPORTED) {
        throw 'OS is not supported'
    }

    $exec_path = if (!$steamcmdpath) { 'steamcmd' } elseif ($os -eq [OSVer]::WINDOWS) { Join-Path -Path $steamcmdpath -ChildPath 'steamcmd.exe' } else { Join-Path -Path $steamcmdpath -ChildPath 'steamcmd' }

    try {
        Write-Colored -msg "$([string][char]8252) Installing app $id into '$dir'" -color Yellow

        Start-Process -FilePath $exec_path -ArgumentList "$launchargs" -NoNewWindow -Wait -ErrorAction Stop -PassThru
        
        Write-Colored -msg "$([string][char]8730) App $id installed" -color Green
    }
    catch {
        Write-Colored -msg "App $id failed to install:`n$($_.Exception.Message)" -color Red
    }
}

#endregion

###################################
########### Entry point ###########
###################################

######## Check PS version #########
if ($PSVersionTable.PSEdition -ne 'Core') {
    Write-Warning 'This script might or might not work correctly on old PS editions. Consider updating to PowerShell Core if you are experiencing issues'
}

# Set steamcmd installation paths #
if ($GlobalInstall) {
    $InstallPath = $null
}
elseif (!$InstallPath) {
    $InstallPath = "$PSScriptRoot/steamcmd"

    Write-Warning "Steamcmd install path was set automatically to '$InstallPath'"
}

### Set app installation paths ###
if ($AppID -and !$AppInstallPath) {
    $AppInstallPath = "$PSScriptRoot/app-$AppID"

    Write-Warning "Application install path was set automatically to '$AppInstallPath'"
}

#region Install steamcmd

Write-Colored -msg "$([string][char]8252) Steamcmd installation check" -color Yellow

if ($GlobalInstall) {
    Get-OsRelease | Install-Global
}
else {
    Get-OsRelease | Install-Local -path $InstallPath
}

Write-Colored -msg "$([string][char]8730) Steamcmd installed" -color Green

#endregion

#region Install application

if ($AppID) {
    New-Item -Path $AppInstallPath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    $dir = Resolve-Path $AppInstallPath
    Install-App -id $AppID -dir $dir -branch $Branch -branchpass $BranchPassword -login $Login -password $Password -steamguard $SteamGuard -steamcmdpath $InstallPath $Validate
}

#endregion
