Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('editor-git-test-' + [guid]::NewGuid().ToString('N'))
$git = (Get-Command git -CommandType Application).Source
$shell = (Get-Process -Id $PID).Path
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'editor-git.ps1') -Destination (Join-Path $fixture 'tools')
function Invoke-Request($data, [bool]$fail = $false) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Depth 6 -Compress)))
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $shell -NoProfile -NonInteractive -File (Join-Path $fixture 'tools\editor-git.ps1') -Request $encoded 2>&1
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if (($code -ne 0) -ne $fail) { throw "Unexpected result: $output" }
    if (-not $fail) { return $output }
}
try {
    & $git -C $fixture init -b main | Out-Null
    & $git -C $fixture config user.name 'Workflow test'
    & $git -C $fixture config user.email 'test@example.invalid'
    & $git -C $fixture add tools/editor-git.ps1
    & $git -C $fixture commit -m Initial | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture 'selected.txt') -Value 'selected'
    Set-Content -LiteralPath (Join-Path $fixture 'excluded.txt') -Value 'excluded'
    $status = ((Invoke-Request @{action='Status'}) -join "`n") | ConvertFrom-Json
    $request = @{action='Commit'; head=$status.head; branch=$status.branch; hashes=$status.hashes; index_tree=$status.index_tree; files=@('selected.txt'); message='Selected change'}
    Invoke-Request $request $true
    Invoke-Request @{action='Branch';head=$status.head;branch=$status.branch;index_tree=$status.index_tree;name='feature/test'} | Out-Null
    $request.branch = 'feature/test'
    $request.action = 'Stage'
    Add-Content -LiteralPath (Join-Path $fixture 'selected.txt') -Value 'changed'
    Invoke-Request $request $true
    $status = ((Invoke-Request @{action='Status'}) -join "`n") | ConvertFrom-Json
    $request.hashes = $status.hashes
    & $git -C $fixture add excluded.txt
    Invoke-Request $request $true
    & $git -C $fixture restore --staged excluded.txt
    Invoke-Request $request | Out-Null
    $status = ((Invoke-Request @{action='Status'}) -join "`n") | ConvertFrom-Json
    if (@($status.staged).Count -ne 1 -or $status.staged[0] -ne 'selected.txt') { throw 'Real staged list missing.' }
    $review = @{action='StagedReview';head=$status.head;branch=$status.branch;index_tree=$status.index_tree}
    $diff = (Invoke-Request $review) -join "`n"
    if ($diff -notmatch 'new file mode' -or $diff -notmatch '\+selected') { throw 'Staged review omitted new-file contents.' }
    & $git -C $fixture add excluded.txt
    Invoke-Request $review $true
    & $git -C $fixture restore --staged excluded.txt
    $stagedContents = & $git -C $fixture show ':selected.txt'
    Add-Content -LiteralPath (Join-Path $fixture 'selected.txt') -Value 'later unstaged edit'
    $request.action = 'Commit'
    $request.index_tree = $status.index_tree
    Invoke-Request $request | Out-Null
    if ((& $git -C $fixture show HEAD:selected.txt) -join "`n" -ne ($stagedContents -join "`n")) {
        throw 'Commit did not preserve staged snapshot.'
    }
    $committed = @(& $git -C $fixture diff-tree --no-commit-id --name-only -r HEAD)
    if (($committed -join '|') -ne 'selected.txt') { throw 'Commit included unselected files.' }
    if (-not (Test-Path -LiteralPath (Join-Path $fixture 'excluded.txt'))) { throw 'Unselected file lost.' }
    Invoke-Request $request $true
    $status = ((Invoke-Request @{action='Status'}) -join "`n") | ConvertFrom-Json
    $request = @{action='Stage';head=$status.head;branch=$status.branch;index_tree=$status.index_tree;hashes=$status.hashes;files=@('excluded.txt')}
    Invoke-Request $request | Out-Null
    $status = ((Invoke-Request @{action='Status'}) -join "`n") | ConvertFrom-Json
    Invoke-Request @{action='Unstage';head=$status.head;branch=$status.branch;index_tree=$status.index_tree;staged=$status.staged;files=@('excluded.txt')} | Out-Null
    if (@(& $git -C $fixture diff --cached --name-only).Count) { throw 'Unstage failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $fixture 'excluded.txt'))) { throw 'Unstage lost edits.' }
    Write-Output 'PASS: main/branch guards, real staging, changed-file/index guards, exact staged review including new files, staged-snapshot commit, stale HEAD, unstage preserving edits.'
}
finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
