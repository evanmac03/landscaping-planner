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
# The formatter's gate, run here so that one command covers what CI checks. The workflow's own
# `formatting` job fetches and pins the tool, so where to find it is said rather than assumed: the
# environment first, then the place this machine keeps the verified copy. A run with no formatter says
# so rather than passing quietly - a verdict measured against nothing is not a clean bill of health,
# which is the same rule the instruments in this project follow.
$formatter = $env:WORKFLOW_FORMATTER
if (-not $formatter) {
    $formatter = Join-Path $env:LOCALAPPDATA 'Temp\ziva-gdfmt\gdscript-formatter-0.28.0-windows-x86_64.exe'
}
if (Test-Path -LiteralPath $formatter) {
    & $formatter --check --max-line-length 120 --verify-structure scripts tests tools
    if ($LASTEXITCODE -ne 0) { throw 'A file is not formatted. See docs/gdscript-formatting.md.' }
} else {
    Write-Host "No formatter at '$formatter', so the formatting was NOT checked."
}
