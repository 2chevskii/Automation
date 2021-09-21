# Reference updater

> Script to update references for Rust plugin-dev environment

## What it does

Script function is to download latest game (RustDedicated) and (Oxide|uMod).Rust managed binaries and place them in selected location

It can optionally clean already existing files the the directory (use `-Clean` switch), useful if you dont want to mix files from different versions

## How to use

Download and place it anywhere you want (usually - in the project root folder) then invoke it.

You can also optionally specify options below:

- **Path**: folder, where files should be located. default: `<script location>/References`
- **DepotDownloaderPath**: folder where DepotDownloader will be installed if not found. default: `<TEMP>/depot-downloader`
- **ReferenceType**: `Original|Oxide|uMod` - allows to choose type of binaries you want to download. Original stands for non-patched game files, and Oxide/uMod will result in game files + respective mod files
- **Os**: `windows|linux` - allows to choose type of OS for binaries. default: current OS
- **Clean**: Removes old files from directory specified in `-Path` parameter
