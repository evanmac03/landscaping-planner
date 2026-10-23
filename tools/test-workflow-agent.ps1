Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('workflow-agent-' + [guid]::NewGuid().ToString('N'))
$shell = (Get-Process -Id $PID).Path
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'workflow-agent.ps1') -Destination $fixture
    @'
param([string]$Action)
if ($Action -notin @('LocalEvidence','Evidence','Discover')) { throw 'Unsafe backend action.' }
if ($Action -eq 'LocalEvidence') { 'EDITOR_RESULT:{"local":{"state":"stale"},"ci":{"state":"not-queried"}}' }
elseif ($Action -eq 'Evidence') { 'EDITOR_RESULT:{"local":{"state":"passed"},"ci":{"state":"unavailable"}}' }
else { 'EDITOR_RESULT:{"next":"merge","commit":"fixture"}' }
'@ | Set-Content -LiteralPath (Join-Path $fixture 'github.ps1') -Encoding UTF8
    @'
param([string]$Request)
$r = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Request)) | ConvertFrom-Json
if ($r.action -ne 'Status') { throw 'Unsafe Git action.' }
'{"branch":"feature/test","head":"fixture","files":[],"staged":[],"hashes":{},"index_tree":"tree"}'
'@ | Set-Content -LiteralPath (Join-Path $fixture 'editor-git.ps1') -Encoding UTF8
    function Call-Agent([string[]]$Arguments, [bool]$Failure = $false) {
        $text = & $shell -NoProfile -NonInteractive -File (Join-Path $fixture 'workflow-agent.ps1') @Arguments
        if (($LASTEXITCODE -ne 0) -ne $Failure) { throw "Unexpected agent exit: $text" }
        $data = ($text -join "`n") | ConvertFrom-Json
        if ($data.schema -ne 'guided-workflow-agent/v1' -or $data.ok -eq $Failure -or $data.authorization -ne 'none; information only') { throw 'Invalid agent envelope.' }
        return $data
    }
    $cap = Call-Agent @()
    if ($cap.data.execution -or $cap.remote_requested) { throw 'Unsafe capabilities/default.' }
    $status = Call-Agent @('-Action','Status')
    if ($status.data.head -ne 'fixture') { throw 'Status lost backend fields.' }
    $local = Call-Agent @('-Action','Evidence')
    if ($local.data.local.state -ne 'stale' -or $local.data.ci.state -ne 'not-queried') { throw 'Local evidence misrepresented.' }
    $remote = Call-Agent @('-Action','Evidence','-Remote')
    if ($remote.data.ci.state -ne 'unavailable' -or -not $remote.remote_requested) { throw 'Unavailable CI concealed.' }
    $next = Call-Agent @('-Action','NextStep')
    if ($next.data.remote_state -ne 'not-queried') { throw 'Local guidance inferred remote readiness.' }
    $next = Call-Agent @('-Action','NextStep','-Remote')
    if ($next.data.discovery.next -ne 'merge' -or -not $next.data.advisory_only) { throw 'Discovery lost advisory boundary.' }
    foreach ($action in @('Push','Publish','Validate','Synchronize','Commit','execute_script')) {
        $failed = Call-Agent @('-Action',$action) $true
        if (-not $failed.error.message) { throw 'Rejected execution missing explicit error.' }
    }
    Call-Agent @('-Action','Status','-Remote') $true | Out-Null
    Remove-Item -LiteralPath (Join-Path $fixture 'github.ps1')
    $failed = Call-Agent @('-Action','Evidence') $true
    if (-not $failed.error.message) { throw 'Missing backend error concealed.' }
    Write-Output 'PASS: read-only agent contract, explicit remote opt-in, unavailable evidence, execution rejection and structured failures.'
}
finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
