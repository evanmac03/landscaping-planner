[CmdletBinding()]
param(
    [string]$Action = 'Capabilities',
    [switch]$Remote
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$response = [ordered]@{
    schema = 'guided-workflow-agent/v1'
    action = $Action
    captured_at_utc = [DateTime]::UtcNow.ToString('o')
    ok = $false
    remote_requested = [bool]$Remote
    authorization = 'none; information only'
    data = $null
    error = $null
}
function Read-WorkflowResult([string]$BackendAction) {
    $output = @(& (Join-Path $PSScriptRoot 'github.ps1') -Action $BackendAction)
    if (-not $?) { throw 'Workflow inspection failed.' }
    $lines = @($output | Where-Object { $_ -is [string] -and $_.StartsWith('EDITOR_RESULT:') })
    if ($lines.Count -ne 1) { throw 'Workflow returned no unique structured result.' }
    return ($lines[0].Substring(14) | ConvertFrom-Json)
}
function Read-Status {
    $request = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"action":"Status"}'))
    $text = @(& (Join-Path $PSScriptRoot 'editor-git.ps1') -Request $request)
    if (-not $?) { throw 'Local status failed.' }
    return (($text -join "`n") | ConvertFrom-Json)
}
try {
    if ($Action -notin @('Capabilities', 'Status', 'Evidence', 'NextStep')) {
        throw 'Unsupported action. Only Capabilities, Status, Evidence and NextStep are exposed. Execution is not supported.'
    }
    if ($Remote -and $Action -notin @('Evidence', 'NextStep')) {
        throw '-Remote is only valid for Evidence and NextStep.'
    }
    switch ($Action) {
        'Capabilities' {
            $response.data = @{
                actions = @('Capabilities', 'Status', 'Evidence', 'NextStep')
                execution = $false
                transports = @('PowerShell CLI; JSON stdout')
                local = 'Default. No AI or GitHub authentication/network required. Status hashes disk files and may write Git tree objects through the existing status helper; no index/worktree changes.'
                remote = 'Explicit -Remote only. Reads GitHub and fetches/prunes origin tracking refs; no remote writes. Existing gh login required.'
                limits = @('Not an MCP server or an AI provider', 'No live editor state or unsaved buffers', 'No CI/playtest/publication approval', 'No credentials or arbitrary command parameters accepted')
            }
        }
        'Status' {
            $response.data = Read-Status
        }
        'Evidence' {
            $response.data = Read-WorkflowResult $(if ($Remote) {'Evidence'} else {'LocalEvidence'})
        }
        'NextStep' {
            if ($Remote) {
                $response.data = @{
                    discovery = Read-WorkflowResult 'Discover'
                    advisory_only = $true
                    limits = 'Backend discovery is guidance, not authorization. Recheck exact-head CI and user approvals separately.'
                }
            } else {
                $status = Read-Status
                $next = if (@($status.files).Count) {'review_dirty_work'} elseif (@($status.staged).Count) {'review_staged_changes'} elseif (-not $status.branch) {'choose_branch'} elseif ($status.branch -eq 'main') {'inspect_main_readiness'} else {'inspect_feature_remote_state'}
                $guidance = @{
                    review_dirty_work='Review saved unstaged/untracked work and any already staged changes before selecting files. No automatic staging.'
                    review_staged_changes='Review the complete staged diff before requesting a commit; create a feature branch if needed.'
                    choose_branch='Detached HEAD: choose a branch deliberately before changing history.'
                    inspect_main_readiness='Clean main: inspect remote synchronization, exact-commit CI and existing drafts before preparing anything.'
                    inspect_feature_remote_state='Clean feature branch: inspect open/merged PRs and remote distances before choosing Push or synchronization.'
                }
                $response.data = @{
                    next = $next
                    guidance = $guidance[$next]
                    advisory_only = $true
                    commit = $status.head
                    remote_state = 'not-queried'
                    limits = 'No remote readiness, PR merge, draft or publication state inferred. Use NextStep -Remote only with permission to contact GitHub and update tracking refs.'
                }
            }
        }
    }
    $response.ok = $true
}
catch {
    $response.error = @{code='inspection_failed';message=$_.Exception.Message}
}
$response | ConvertTo-Json -Depth 20 -Compress
if (-not $response.ok) { exit 1 }
