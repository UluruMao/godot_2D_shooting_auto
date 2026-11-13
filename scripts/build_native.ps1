param(
    [string]$CMake = 'cmake',
    [string]$Python = 'python',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [ValidateSet('Both', 'Debug', 'Release')][string]$Runtime = 'Both',
    [switch]$CoreOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$ctest = Join-Path (Split-Path -Parent (Get-Command $CMake).Source) 'ctest'
$targets = if ($CoreOnly) { @('core') } elseif ($Runtime -eq 'Both') { @('template_debug', 'template_release') } else { @('template_' + $Runtime.ToLowerInvariant()) }
foreach ($target in $targets) {
    $buildDirectory = Join-Path $projectRoot ".godot/native-build/$target"
    $configure = @('-S', (Join-Path $projectRoot 'native'), '-B', $buildDirectory,
        "-DBUILD_GODOT_EXTENSION=$(-not $CoreOnly)")
    if (-not $CoreOnly) {
        $pythonExecutable = (Get-Command $Python -ErrorAction Stop).Source
        $configure += "-DPython3_EXECUTABLE=$pythonExecutable"
        $configure += "-DGODOTCPP_TARGET=$target"
    }
    & $CMake @configure
    if ($LASTEXITCODE -ne 0) { throw "Native configuration failed: $target" }
    & $CMake --build $buildDirectory --config $Configuration --parallel 4
    if ($LASTEXITCODE -ne 0) { throw "Native build failed: $target" }
    & $ctest --test-dir $buildDirectory -C $Configuration --output-on-failure --no-tests=error
    if ($LASTEXITCODE -ne 0) { throw "Native tests failed: $target" }
}
