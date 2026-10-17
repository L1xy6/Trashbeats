param([string]$Godot = "godot", [switch]$VerboseEngine)
$ErrorActionPreference = "Stop"
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$runId = [Guid]::NewGuid().ToString("N")
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot "Trashbeats-Smoke-$runId"
$oldVariables = @{}
foreach ($key in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'TRASHBEATS_TEST_RUN_ID', 'TRASHBEATS_TIANQIN_APP_ID', 'TRASHBEATS_TIANQIN_APP_KEY')) {
    $oldVariables[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    foreach ($folder in @('scripts', 'scenes', 'fonts', 'shaders', 'tests')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $folder) -Destination $testRoot -Recurse
    }
    $project = Get-Content -LiteralPath (Join-Path $sourceRoot 'project.godot') -Raw
    $project = [regex]::Replace($project, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
    $project = $project.Replace('[application]', "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"Trashbeats-SmokeTests/$runId`"")
    $project = $project.Replace('driver/enable_input=true', 'driver/enable_input=false')
    [IO.File]::WriteAllText((Join-Path $testRoot 'project.godot'), $project, [Text.UTF8Encoding]::new($false))
    $dataRoot = Join-Path $testRoot 'test-data'
    New-Item -ItemType Directory -Path $dataRoot | Out-Null
    [Environment]::SetEnvironmentVariable('APPDATA', $dataRoot, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $dataRoot, 'Process')
    [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', $dataRoot, 'Process')
    [Environment]::SetEnvironmentVariable('TRASHBEATS_TEST_RUN_ID', $runId, 'Process')
    [Environment]::SetEnvironmentVariable('TRASHBEATS_TIANQIN_APP_ID', $null, 'Process')
    [Environment]::SetEnvironmentVariable('TRASHBEATS_TIANQIN_APP_KEY', $null, 'Process')
    & $Godot --headless --path $testRoot --editor --import --quit --log-file (Join-Path $testRoot 'import.log')
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed (exit $LASTEXITCODE)." }
    $debugArguments = @()
    if ($VerboseEngine) { $debugArguments += '--verbose' }
    & $Godot --headless --path $testRoot --scene res://tests/smoke.tscn --quit-after 600 --log-file (Join-Path $testRoot 'smoke.log') @debugArguments
    $testExit = $LASTEXITCODE
    $testLog = Get-Content -LiteralPath (Join-Path $testRoot 'smoke.log') -Raw
    # Some Windows sandboxes deny access to the OS certificate store. These
    # offline tests do not use TLS; keep every other engine error fatal.
    $validationLog = $testLog.Replace('ERROR: Failed to read the root certificate store.', '')
    if ($testExit -ne 0 -or $testLog -notmatch 'SMOKE TEST: \d+ checks, 0 failures' -or $validationLog -match 'SCRIPT ERROR:|ERROR:') {
        throw "Smoke tests failed or did not complete (exit $testExit)."
    }
} finally {
    foreach ($key in $oldVariables.Keys) {
        [Environment]::SetEnvironmentVariable($key, $oldVariables[$key], 'Process')
    }
    # Delete only the unique test directory resolved beneath the OS temp folder.
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $safePrefix = $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedTestRoot.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedTestRoot -Leaf) -eq "Trashbeats-Smoke-$runId" -and (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
