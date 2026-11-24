[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Request)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ((Split-Path -Leaf $root) -eq 'github_tools') { $root = Split-Path -Parent (Split-Path -Parent $root) }
$gitExecutable = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$requestData = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Request)) | ConvertFrom-Json
function Git {
    $result = & $gitExecutable -C $root --no-pager @args
    if ($LASTEXITCODE -ne 0) { throw "Git failed ($LASTEXITCODE)." }
    return $result
}
if ($requestData.action -eq 'Status') {
    $files = @((Git ls-files --modified --others --exclude-standard) | Sort-Object -Unique)
    $hashes = [ordered]@{}
    foreach ($file in $files) {
        $path = Join-Path $root $file
        $hashes[$file] = if (Test-Path -LiteralPath $path -PathType Leaf) {
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        } else { 'DELETED' }
    }
    [ordered]@{
        branch = [string](Git branch --show-current)
        head = [string](Git rev-parse HEAD)
        files = $files
        hashes = $hashes
        staged = @(Git diff --cached --name-only)
        index_tree = [string](Git write-tree)
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
if ($requestData.action -eq 'Fetch') { Git fetch --prune origin; exit 0 }
if ($requestData.action -eq 'Diff') {
    Git diff HEAD -- | Out-Host
    Write-Output 'Untracked files are listed in Status but are not included in Git diff.'
    exit 0
}
if ($requestData.action -eq 'StagedDiff') { Git diff --cached -- | Out-Host; exit 0 }
if ($requestData.action -notin @('Branch', 'Stage', 'Unstage', 'Commit', 'StagedReview')) { throw 'Unknown editor Git action.' }
if ([string](Git rev-parse HEAD) -ne $requestData.head -or
    [string](Git branch --show-current) -ne $requestData.branch) {
    throw 'Branch/HEAD changed. Refresh Status and review again.'
}
if ([string](Git write-tree) -ne $requestData.index_tree) { throw 'Staged snapshot changed. Refresh Status and review again.' }
if ($requestData.action -eq 'StagedReview') {
    Git diff --cached --no-ext-diff --no-textconv -- | Out-Host
    Write-Output 'Binary contents are not shown. Review binary assets separately before approving.'
    exit 0
}
if ($requestData.action -eq 'Branch') {
    if ($requestData.name -notmatch '^feature/[a-z0-9][a-z0-9-]*$') { throw 'Use feature/lowercase-kebab-name.' }
    Git switch -c $requestData.name
    exit 0
}
if ($requestData.action -eq 'Commit') {
    $commitBranch = [string]$requestData.branch
    $newBranch = $requestData.PSObject.Properties['new_branch']
    if (-not $commitBranch -or $commitBranch -eq 'main') {
        if (-not $newBranch -or $newBranch.Value -notmatch '^feature/[a-z0-9][a-z0-9-]*$') {
            throw 'Create a feature branch before committing.'
        }
        $commitBranch = [string]$newBranch.Value
    } elseif ($newBranch) { throw 'Branch creation is only supported from main or detached HEAD.' }
    if (-not $requestData.message.Trim()) { throw 'Enter a commit message.' }
    if (@(Git diff --cached --name-only).Count -eq 0) { throw 'Stage changes before committing.' }
    Git diff --cached --check
    $parent = [string](Git rev-parse HEAD)
    $tree = [string](Git write-tree)
    if ($newBranch) { Git switch -c $commitBranch }
    Git commit -m $requestData.message -m 'Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
    if ([string](Git rev-parse 'HEAD^') -ne $parent -or [string](Git rev-parse 'HEAD^{tree}') -ne $tree -or
        [string](Git branch --show-current) -ne $commitBranch -or @(Git diff --cached --name-only).Count) {
        throw 'Commit was created but verification failed. Inspect Git; do not repeat automatically.'
    }
    Git status -sb
    exit 0
}
$selected = @($requestData.files)
if (-not $selected.Count) { throw 'Select files first.' }
if ($requestData.action -eq 'Unstage') {
    foreach ($file in $selected) {
        if ($file -notin @($requestData.staged)) { throw 'File was not in the reviewed staged list.' }
    }
    Git restore --staged -- @selected
    exit 0
}
foreach ($file in $selected) {
    if ($file -notin @($requestData.hashes.PSObject.Properties.Name)) { throw 'File was not in the reviewed status.' }
    $path = Join-Path $root $file
    $hash = if (Test-Path -LiteralPath $path -PathType Leaf) {
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    } else { 'DELETED' }
    if ($hash -ne $requestData.hashes.$file) { throw "File changed since Status: $file" }
    if ($hash -ne 'DELETED') {
        if ((Get-Item -LiteralPath $path).Length -ge 10MB) { throw "Review large artifacts in a terminal: $file" }
        $text = [IO.File]::ReadAllText($path)
        if ($text -match '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}') {
            throw "Potential credential detected; review in a terminal: $file"
        }
    }
}
Git add -- @selected
Write-Output 'Selected saved contents staged. Later edits remain unstaged.'
