$pattern = 'namespace\s*?Oxide\.Plugins\s*?\{(?:.|\s)*?\[\s*?Info\s*?\(.*?,\s*?"(?<author>.*?)"\s*?,\s*?(?<ver>".*?"|\d+(?:.\d+)?)(?:.|\s)*?\)\s*?](?:.|\s)*?class\s*?(?<name>\w[\w\d_@]+)\s*?:'

function Get-Info {
    param (
        [string]$source_text
    )

    $match = [regex]::Match( $source_text, $pattern)

    if (!$match.Success) {
        return $null
    }

    $name = $match.Groups['name'].Value
    $author = $match.Groups['author'].Value.Replace('/', ', ').Replace('\', ', ')
    $version = $match.Groups['ver'].Value.Trim('"')

    return @{ name = $name; author = $author; version = $version }
}

$root_folder = $PSScriptRoot

$sorted_folder = Join-Path $root_folder 'sorted-plugins/'
$failed_folder = Join-Path $root_folder 'failed-plugins/'

$files = Get-ChildItem -Path $root_folder -Filter "*.cs" -Recurse -File

foreach ($file in $files) {
    try {
        $content = Get-Content $file -Raw

        $info = Get-Info $content

        $dest_folder = (Join-Path $sorted_folder "$($info.author)/$($info.name)/$($info.version)")

        New-Item -Path $dest_folder -ItemType Directory -ErrorAction SilentlyContinue

        $dest_file = Join-Path $dest_folder $file.Name

        if (Test-Path $dest_file) {
            Write-Warning "Plugin $($info.name) v$($info.version) already exists, skipping. ($($file.FullName))"
            continue
        }

        $file.CopyTo($dest_file)
        Write-Output "Plugin $($info.name) v$($info.version) was moved to $dest_file"

    } catch {
        Write-Warning "Failed to analyze file $($file.FullName)"
        New-Item -Path $failed_folder -ErrorAction SilentlyContinue -ItemType Directory
        $file.CopyTo((Join-Path $failed_folder $file.Name))
    }
}

