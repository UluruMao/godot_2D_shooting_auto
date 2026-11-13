param([string]$Destination)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) {
    $Destination = Join-Path $projectRoot ('.godot/validation-' + [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
# Test the same game sources with the editor-only autoloads stripped, as in an
# exported game. Keep the working project and the user's running editor intact.
foreach ($directory in @('scene', 'scripts', 'resources', 'tests')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $Destination -Recurse
}
$editorAddon = Join-Path $projectRoot 'addons/godot_ai'
if (Test-Path -LiteralPath $editorAddon) {
    # The development workspace has this optional editor tool; source-only
    # submissions run and validate without installing it.
    $tooling = Join-Path $Destination 'addons'
    New-Item -ItemType Directory -Force -Path $tooling | Out-Null
    Copy-Item -LiteralPath $editorAddon -Destination $tooling -Recurse
}
foreach ($name in @('bin', '.godot')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Destination $name) | Out-Null
}
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'bin') -File |
    Where-Object { $_.Name -notlike '~*' -and $_.Extension -in @('.dll', '.so', '.dylib', '.gdextension', '.uid') } |
    Copy-Item -Destination (Join-Path $Destination 'bin')
Copy-Item -LiteralPath (Join-Path $projectRoot '.godot/imported') -Destination (Join-Path $Destination '.godot') -Recurse
foreach ($file in @('global_script_class_cache.cfg', 'uid_cache.bin', 'extension_list.cfg')) {
    $source = Join-Path $projectRoot ('.godot/' + $file)
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $Destination '.godot') }
}
foreach ($file in @('icon.svg', 'icon.svg.import')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $Destination
}
$configuration = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'project.godot')
$configuration = [regex]::Replace($configuration, '(?ms)^\[(autoload|editor_plugins)\]\r?\n.*?(?=^\[|\z)', '')
[System.IO.File]::WriteAllText((Join-Path $Destination 'project.godot'), $configuration)
Write-Output $Destination
