param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$WindowsTemplate,
    [string]$Output
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Output) { $Output = Join-Path $projectRoot 'dist/ArenaShooter-Review' }
$Source = [IO.Path]::GetFullPath($Source)
$Output = [IO.Path]::GetFullPath($Output)
if ($Source -eq $projectRoot) { throw 'Export from an isolated verified source snapshot, not the open editor project.' }
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$preset = @'
[preset.0]
name="Windows Review"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="addons/*,tests/*,docs/*,native/*,scripts/*.ps1,*.md"
export_path=""
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release="TEMPLATE_PATH"
binary_format/embed_pck=true
binary_format/architecture="x86_64"
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
codesign/enable=false
application/product_name="Arena Shooter Engineering Demo"
application/file_description="Engineering portfolio review build"
'@
$preset = $preset.Replace('TEMPLATE_PATH', ([IO.Path]::GetFullPath($WindowsTemplate).Replace('\', '/')))
[IO.File]::WriteAllText((Join-Path $Source 'export_presets.cfg'), $preset)
$exe = Join-Path $Output 'ArenaShooter.exe'
$logs = & $Godot --headless --path $Source --export-release 'Windows Review' $exe 2>&1
$code = $LASTEXITCODE
$logs | Write-Output
if ($code -ne 0 -or ($logs | Select-String 'SCRIPT ERROR:|ERROR:')) { throw 'Windows export failed.' }
Push-Location $Output
try {
    $log = Join-Path $Output 'verification.log'
    $arguments = @('--headless', '--fixed-fps', '60', '--quit-after', '300', '--log-file', ('"{0}"' -f $log), '--', '--auto', '--verify-runtime')
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $Output -WindowStyle Hidden -Wait -PassThru
    $code = $process.ExitCode
    $smoke = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log } else { @() }
} finally { Pop-Location }
$smoke | Write-Output
if ($code -ne 0 -or -not ($smoke | Select-String 'RELEASE_CHECK_PASSED') -or ($smoke | Select-String 'SCRIPT ERROR:|ERROR:|instances were leaked|resources still in use')) {
    throw 'Standalone executable verification failed.'
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $Output
if (Test-Path -LiteralPath (Join-Path $projectRoot 'licenses')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses') -Destination $Output -Recurse -Force
}
@'
Arena Shooter Engineering Demo — Windows x64 review build

Run ArenaShooter.exe. T toggles Auto, I opens the inspector, C cycles planners,
P pauses, N advances a paused tick, R restarts, and Y advances the seed.
WASD moves; mouse/arrows aim; left click/Space fires.

The native library must stay next to the executable as exported.
This build does not require Godot or a compiler to be installed.

Prepared for local portfolio review. Original art/audio redistribution details
still need confirmation before public distribution. See THIRD_PARTY_NOTICES.md.
'@ | Set-Content -LiteralPath (Join-Path $Output 'README.txt') -Encoding utf8
$archive = $Output + '.zip'
Compress-Archive -Path (Join-Path $Output '*') -DestinationPath $archive -Force
Write-Output "REVIEW_BUILD_VERIFIED=$archive"
