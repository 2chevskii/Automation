#!/usr/bin/env pwsh

using namespace System.IO

[CmdletBinding(PositionalBinding = $true)]
param (
  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string] $Path,
  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string] $DepotDownloaderPath,
  [Parameter(Mandatory = $false)]
  [ValidateSet('Original', 'Oxide', 'uMod')]
  [string] $ReferenceType = 'Oxide',
  [Parameter(Mandatory = $false)]
  [ValidateSet('windows', 'posix')]
  [string] $Os,
  [Parameter(Mandatory = $false)]
  [switch] $Clean
)

$temp_directory = Join-Path -Path ([Path]::GetTempPath()) -ChildPath 'automation' -AdditionalChildPath 'update-references'
$depot_downloader_directory = [string]::IsNullOrWhiteSpace($DepotDownloaderPath) ? (Join-Path $temp_directory 'depot-downloader') : [Path]::GetFullPath($DepotDownloaderPath)
$depot_downloader_executable = Join-Path $depot_downloader_directory 'DepotDownloader.dll'
$dotnet_install_path = Join-Path $temp_directory 'dotnet-install.ps1'
$depot_downloader_version = '2.4.4'
$depot_downloader_archive_path = Join-Path $temp_directory ('depot_downloader-{0}.zip' -f $depot_downloader_version)
$dotnet_install_link = 'https://gist.githubusercontent.com/2chevskii/69d93f3a753ca7e695e276d7f8b9c6ed/raw/4cfdb0f481f2d7bddb45afec8c9a940270e71463/dotnet-install.ps1'
$filelist = Join-Path $temp_directory '.references'
$oxide_releases_api = 'https://api.github.com/repos/OxideMod/Oxide.Rust/releases'
$oxide_archive_temp_path = Join-Path $temp_directory 'Oxide.Rust.zip'
$oxide_files_temp_path = Join-Path $temp_directory 'Oxide.Rust'
$umod_manifest_url = 'https://assets.umod.org/uMod.Manifest.json'
$umod_archive_temp_path = Join-Path $temp_directory 'uMod.Rust.zip'
$umod_files_temp_path = Join-Path $temp_directory 'uMod.Rust'

function Get-OxideRust-DownloadLinks {
  $releases = Invoke-WebRequest $oxide_releases_api | Select-Object -ExpandProperty Content | ConvertFrom-Json
  $last_release = $releases[0]
  $assets_url = $last_release.assets_url
  $assets = Invoke-WebRequest $assets_url | Select-Object -ExpandProperty Content | ConvertFrom-Json
  return @{
    linux   = $assets[0].browser_download_url
    windows = $assets[1].browser_download_url
  }
}

function Get-uModRust-DownloadLinks {
  $manifest = Invoke-WebRequest $umod_manifest_url | Select-Object -ExpandProperty Content | ConvertFrom-Json
  $packages = $manifest.Packages
  $umod_rust = $packages | Where-Object -Property 'FileName' -EQ 'uMod.Rust.dll'
  $artifacts = $umod_rust.Resources | Where-Object -Property 'Type' -EQ 4 | Where-Object -Property 'Version' -EQ 'develop'
  $linux = $artifacts.Artifacts | Where-Object -Property 'Platform' -EQ 'linux'
  $windows = $artifacts.Artifacts | Where-Object -Property 'Platform' -EQ 'windows'

  return @{
    linux   = $linux.Url
    windows = $windows.Url
  }
}

function Get-DepotDownloader-Release-Link {
  param (
    $version
  )

  $base_link = 'https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_{version}/depotdownloader-{version}.zip'

  return $base_link.Replace('{version}', $version)
}

function Download-File {
  param (
    $link
  )

  $bytes = (Invoke-WebRequest $link).Content

  return $bytes
}

function Truncate {
  param(
    $msg
  )

  if ($msg.Length -le 50) {
    return $msg
  }

  $p1 = $msg.Substring(0, 25)
  $p2 = $msg.Substring($msg.Length - 22)

  return $p1 + '...' + $p2
}

function Log {
  param (
    $format,
    $arguments
  )

  $message = $format -f $arguments

  Write-Colorized "<cyan>--</cyan> $message"
}

if (!(Test-Path $temp_directory)) {
  New-Item $temp_directory -ItemType Directory
}

$dotnet_installed = $false

if (Get-Command 'dotnet') {
  $version = [semver](. dotnet --version)
  $dotnet_installed = $version.Major -ge 5
}

if (!$dotnet_installed) {
  if (!(Test-Path $dotnet_install_path)) {
    Log 'Downloading dotnet-install from {0}' (Truncate $dotnet_install_link)
    Download-File $dotnet_install_link | Out-File $dotnet_install_path -Encoding utf8
  }

  Log 'Ensuring installation of .NET 5'
  . $dotnet_install_path -Channel 5.0 -Verbose
}

if (!(Test-Path $depot_downloader_executable)) {
  Log 'Installing DepotDownloader into {0}' $depot_downloader_directory

  New-Item -Path $depot_downloader_directory -ItemType Directory -Force

  if (!(Test-Path $depot_downloader_archive_path)) {
    $lnk = Get-DepotDownloader-Release-Link $depot_downloader_version
    Invoke-WebRequest $lnk -OutFile $depot_downloader_archive_path
  }

  Expand-Archive -Path $depot_downloader_archive_path -DestinationPath $depot_downloader_directory -Force
}

if (!$Path) {
  $Path = Join-Path $PSScriptRoot 'References'
  Log 'Setting path to default: {0}' $Path
} else {
  $Path = [Path]::GetFullPath($Path)
  Log 'Path was resolved to: {0}' $Path
}

if (!(Test-Path $Path)) {
  New-Item $Path -Force -ItemType Directory
} elseif ($Clean) {
  $files = Get-ChildItem -Path $Path -Force -Filter '*.dll'
  Log 'Cleaning {0} old reference files...' $files.Count
  $files | ForEach-Object { $_ | Remove-Item -Force -Recurse }
}

'regex:RustDedicated_Data\/Managed\/.*\.dll' > $filelist

if (!$Os) {
  if ($IsWindows) {
    $Os = 'windows'
  } else {
    $Os = 'posix'
  }

  Log 'OS was set to current: {0}' $Os
}

$depot = $Os -eq 'windows' ? 258551 : 258552

. dotnet $depot_downloader_executable -app 258550 -dir $Path -filelist $filelist -depot $depot

$files = Get-ChildItem -Path (Join-Path $Path 'RustDedicated_Data' 'Managed') -Filter '*.dll'
Log 'Downloaded {0} files, moving them into destination path...' $files.Count
$files | ForEach-Object { $_ | Move-Item -Destination $Path -Force }
Remove-Item -Path (Join-Path $Path 'RustDedicated_Data') -Recurse -Force

if ($LASTEXITCODE -eq 0) {
  Log 'Update successfull'

  if ($ReferenceType -eq 'Original') {
    Log 'ReferenceType set to Original, exiting now without downloading Oxide/uMod files'
    exit 0
  }
} else {
  Log 'Failed updating with code {0}' $LASTEXITCODE
  exit $LASTEXITCODE
}

if ($ReferenceType -eq 'Oxide') {
  Log 'Downloading Oxide.Rust files...'
  $links = Get-OxideRust-DownloadLinks
  [string]$link
  if ($Os -eq 'windows') {
    $link = $links.windows
    Log 'Selected Windows download link: {0}' $link
  } else {
    $link = $links.linux
    Log 'Selected Linux download link: {0}' $link
  }

  if (Test-Path $oxide_archive_temp_path) {
    Remove-Item $oxide_archive_temp_path
  }

  Invoke-WebRequest $link -OutFile $oxide_archive_temp_path

  if (!(Test-Path $oxide_files_temp_path)) {
    New-Item -Path $oxide_files_temp_path -ItemType Directory -Force
  } else {
    Get-ChildItem $oxide_files_temp_path -Recurse -Force | Remove-Item -Force -Recurse
  }

  Expand-Archive -Path $oxide_archive_temp_path -DestinationPath $oxide_files_temp_path

  $oxide_dll_files = Join-Path $oxide_files_temp_path 'RustDedicated_Data' 'Managed' | Get-ChildItem -Filter '*.dll'

  Log 'Moving {0} Oxide.Rust files to the destination folder...' $oxide_dll_files.Count
  $oxide_dll_files | ForEach-Object { $_ | Move-Item -Destination $Path -Force }
  Log 'Completed'
} else {
  Log 'Downloading uMod.Rust files...'
  $links = Get-uModRust-DownloadLinks
  [string] $link
  switch ($Os) {
    'windows' {
      $link = $links.windows
      Log 'Selected Windows download link: {0}' $link
    }
    'posix' {
      $link = $links.linux
      Log 'Selected Linux download link: {0}' $link
    }
  }

  if (Test-Path $umod_archive_temp_path) {
    Remove-Item $umod_archive_temp_path -Force
  }

  Invoke-WebRequest $link -OutFile $umod_archive_temp_path

  if (!(Test-Path $umod_files_temp_path)) {
    New-Item -Path $umod_files_temp_path -ItemType Directory -Force
  } else {
    Get-ChildItem $umod_files_temp_path -Force | Remove-Item -Recurse -Force
  }

  Expand-Archive -Path $umod_archive_temp_path -DestinationPath $umod_files_temp_path

  $umod_dll_files = Join-Path $umod_files_temp_path 'RustDedicated_Data' 'Managed' | Get-ChildItem -Filter '*.dll'

  $umod_dll_files | Move-Item -Destination $Path -Force
}
