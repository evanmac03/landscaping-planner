param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dev-workflow-install-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $fixture 'unrelated-project'
$shell = (Get-Process -Id $PID).Path
function Assert-Run($Log, $Marker) {
    $text = $Log -join "`n"
    $Log | Out-Host
    if ($LASTEXITCODE -ne 0 -or $text -match '(?m)(?:SCRIPT ERROR:|ERROR:)' -or $text -notmatch $Marker) {
        throw "Addon acceptance failed: $Marker"
    }
}
try {
    New-Item -ItemType Directory -Path $project | Out-Null
    $zip = Join-Path $fixture 'addon.zip'
    & (Join-Path $PSScriptRoot '..\addons\github_tools\tools\package-addon.ps1') -Output $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $project
    $runtime = Join-Path $project 'addons\github_tools\tools'
    & git -C $project init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git init failed.' }
    & git -C $project -c user.name=Fixture -c user.email=test@example.invalid commit --allow-empty -m Initial | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git commit failed.' }
    $request = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"action":"Status"}'))
    $status = & $shell -NoProfile -File (Join-Path $runtime 'editor-git.ps1') -Request $request | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $status.branch -ne 'main') { throw 'Installed addon local Git failed.' }
    $ErrorActionPreference = 'Continue'
    $missing = @(& $shell -NoProfile -File (Join-Path $runtime 'github.ps1') -Action Plan 2>&1)
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -or ($missing -join "`n") -notmatch 'Set up dev-workflow.json') { throw 'Missing setup did not fail explicitly.' }
    '{"provider":"GitHub","repository":"example/unrelated"}' | Set-Content -LiteralPath (Join-Path $project 'dev-workflow.json')
    $plan = @(& $shell -NoProfile -File (Join-Path $runtime 'github.ps1') -Action Plan)
    if ($LASTEXITCODE -ne 0 -or ($plan -join "`n") -notmatch 'Repository: example/unrelated') { throw 'Repository configuration was ignored.' }
    $ErrorActionPreference = 'Continue'
    $missingValidation = @(& $shell -NoProfile -File (Join-Path $runtime 'github.ps1') -Action Validate 2>&1)
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -or ($missingValidation -join "`n") -notmatch 'Configure validation.script') { throw 'Missing validation setup did not fail explicitly.' }
    $ErrorActionPreference = 'Continue'
    $missingRelease = @(& $shell -NoProfile -File (Join-Path $runtime 'github.ps1') -Action Release -Version v1.0.0 -Approve 2>&1)
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -or ($missingRelease -join "`n") -notmatch 'Configure release.product') { throw 'Missing release setup did not fail explicitly.' }
    $acceptance = Join-Path $project 'addons\workflow_acceptance'
    New-Item -ItemType Directory -Path $acceptance | Out-Null
    @'
config_version=5
[application]
config/name="Unrelated addon acceptance fixture"
[editor_plugins]
enabled=PackedStringArray("res://addons/github_tools/plugin.cfg", "res://addons/workflow_acceptance/plugin.cfg")
'@ | Set-Content -LiteralPath (Join-Path $project 'project.godot')
    @'
[plugin]
name="Acceptance probe"
description="Disposable editor acceptance"
author="Test"
version="1"
script="plugin.gd"
'@ | Set-Content -LiteralPath (Join-Path $acceptance 'plugin.cfg')
    @'
@tool
extends EditorPlugin
func _enter_tree() -> void:
	call_deferred("_verify")
func _verify() -> void:
	for node in EditorInterface.get_base_control().find_children("*", "EditorDock", true, false):
		if node.title == "Godot Dev Workflow":
			print("PASS: installed Godot Dev Workflow editor dock")
			return
	push_error("Installed workflow dock not found")
'@ | Set-Content -LiteralPath (Join-Path $acceptance 'plugin.gd')
    $editor = @(& $Godot --headless --editor --path $project --quit-after 120 2>&1)
    Assert-Run $editor 'PASS: installed Godot Dev Workflow editor dock'
    Write-Output 'PASS: standalone addon archive, unrelated-project Git/configuration and real editor plugin acceptance.'
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
