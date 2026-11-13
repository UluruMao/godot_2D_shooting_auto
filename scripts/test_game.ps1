param([string]$Godot = 'godot', [switch]$SkipImport)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = $projectRoot
function Invoke-GodotCheck([string[]]$Arguments) {
    $output = & $Godot --headless --path $runtimePath @Arguments 2>&1
    $engineCode = $LASTEXITCODE
    $output | Write-Output
    # Some editor import errors still return zero. Fail on those diagnostics too.
    if ($engineCode -ne 0 -or ($output | Select-String 'SCRIPT ERROR:|ERROR:|instances were leaked|resources still in use')) {
        throw "Godot validation failed (exit $engineCode)."
    }
}
if (-not $SkipImport) { Invoke-GodotCheck @('--editor', '--quit') }
$runtimePath = & (Join-Path $PSScriptRoot 'prepare_validation.ps1')
Invoke-GodotCheck @('--script', 'res://tests/run_tests.gd')
