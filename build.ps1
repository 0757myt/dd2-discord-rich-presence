# Packs the mod. With -Zig also rebuilds plugin\bin\DiscordPresence.dll first;
# without it the already built DLL is reused (only needed after changes to plugin\DiscordPresence.cpp).
#
#   ./build.ps1                                   -> dist\Discord Rich Presence.zip (Fluffy Mod Manager archive)
#   ./build.ps1 -Install -FluffyMods <folder>     -> also copies it into Fluffy's Games\DragonsDogma2\Mods folder
#   ./build.ps1 -Release                          -> also release\ with the versioned mod archive and a source archive
#   ./build.ps1 -Zig <path to zig.exe>            -> rebuild the DLL with Zig 0.13 first
# Keep the version in plugin\DiscordPresence.rc in step with modinfo.ini.
param(
    [string] $Zig,
    [switch] $Install,
    [string] $FluffyMods,
    [switch] $Release
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$dll = Join-Path $PSScriptRoot "plugin\bin\DiscordPresence.dll"
if ($Zig) {
    New-Item -ItemType Directory -Force (Split-Path $dll) | Out-Null
    & $Zig cc -target x86_64-windows-gnu -shared -O2 -s -std=c11 -o $dll plugin\DiscordPresence.c plugin\DiscordPresence.rc
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
    Remove-Item (Join-Path (Split-Path $dll) "*") -Exclude *.dll
}
if (-not (Test-Path $dll)) { throw "No $dll yet: run with -Zig once" }

$stage = Join-Path $PSScriptRoot "dist\mod"
Remove-Item (Join-Path $PSScriptRoot "dist") -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$stage\reframework\plugins", "$stage\reframework\autorun" | Out-Null
Copy-Item $dll "$stage\reframework\plugins\"
Copy-Item DiscordPresence.lua "$stage\reframework\autorun\"
Copy-Item modinfo.ini $stage

$zip = Join-Path $PSScriptRoot "dist\Discord Rich Presence.zip"
Compress-Archive -Path "$stage\*" -DestinationPath $zip
Write-Host "Built $zip"

if ($Install) {
    if (-not $FluffyMods) { throw "-Install needs -FluffyMods <Fluffy Mod Manager\Games\DragonsDogma2\Mods>" }
    Copy-Item $zip $FluffyMods -Force
    Write-Host "Copied to $FluffyMods"
}

if ($Release) {
    $version = ((Get-Content modinfo.ini) -match '^version=' -replace '^version=', '').Trim()
    $out = Join-Path $PSScriptRoot "release"
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $out | Out-Null
    Copy-Item $zip (Join-Path $out "Discord Rich Presence $version.zip")

    $src = Join-Path $PSScriptRoot "dist\source"
    New-Item -ItemType Directory -Force "$src\plugin" | Out-Null
    Copy-Item plugin\DiscordPresence.c, plugin\DiscordPresence.rc "$src\plugin\"
    Copy-Item DiscordPresence.lua, modinfo.ini, build.ps1, README.md, CHANGELOG.md, LICENSE $src
    New-Item -ItemType Directory -Force "$src\assets\icons" | Out-Null
    Copy-Item assets\icons\*.png "$src\assets\icons\" -Exclude _preview.png
    Compress-Archive -Path "$src\*" -DestinationPath (Join-Path $out "Discord Rich Presence $version - Source.zip")
    Write-Host "Release files in $out"
}
