param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = 'Stop'
foreach ($test in @('test-github.ps1', 'test-workflow-agent.ps1', 'test-editor-git.ps1', 'test-package-tests.ps1', 'test-synchronize.ps1')) {
    & (Join-Path $PSScriptRoot $test) | Out-Host
    if (-not $?) { throw "$test failed." }
}
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'test-addon.ps1') -Godot $Godot
if (-not $?) { throw 'Standalone addon acceptance failed.' }
$log = @(& $Godot --headless --path $root --script res://tools/check_github_dock.gd 2>&1)
$log | Out-Host
if ($LASTEXITCODE -ne 0 -or ($log -join "`n") -match '(?m)(?:SCRIPT ERROR:|ERROR:)' -or
    ($log -join "`n") -notmatch 'PASS: completion routing') { throw 'Godot guide tests failed.' }
