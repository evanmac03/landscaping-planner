[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Discover', 'LastPublication', 'Validate', 'LocalEvidence', 'Evidence', 'DownloadTest', 'SmokeTest', 'Synchronize', 'Push', 'Release', 'RecoverDraft', 'Publish')]
    [string]$Action = 'Plan',
    [string]$Version,
    [string]$Godot,
    [string]$Title,
    [string]$BuildDirectory,
    [string]$ExpectedHead,
    [string]$ExpectedBranch,
    [string]$ExpectedDraft,
    [string]$PhaseFile,
    [string]$Package,
    [ValidateSet('yes', 'no')][string]$CleanupBranch = 'no',
    [switch]$Approve
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$repository = 'evanmac03/landscaping-planner'

function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    $executable = if ($Command -in @('git', 'gh')) {
        (Get-Command $Command -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    } else { $Command }
    $output = & $executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
    return $output
}

function Git {
    Invoke-Native 'git' (@('-C', $root, '--no-pager') + @($args | ForEach-Object { $_ }))
}

function Github {
    Invoke-Native 'gh' @($args | ForEach-Object { $_ })
}

function Write-EditorResult {
    param($Data)
    Write-Output ('EDITOR_RESULT:' + ($Data | ConvertTo-Json -Depth 8 -Compress))
}

function Set-EditorPhase {
    param([string]$Name)
    if ($PhaseFile) { [IO.File]::WriteAllText($PhaseFile, $Name) }
    Write-Host "Phase: $Name"
}

function Get-ValidationFingerprint {
    $statusRequest = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"action":"Status"}'))
    $status = (& (Join-Path $PSScriptRoot 'editor-git.ps1') -Request $statusRequest) -join "`n"
    if (-not $?) { throw 'Could not capture local validation snapshot.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($status)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-LocalValidation {
    $path = Join-Path ([string](Git @('rev-parse', '--absolute-git-dir'))) 'landscaping-editor-validation.json'
    if (-not (Test-Path -LiteralPath $path)) { return @{state='not-run';timestamp='';checks=@()} }
    $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    return @{state=$(if ($saved.fingerprint -eq (Get-ValidationFingerprint)) {'passed'} else {'stale'});timestamp=([DateTimeOffset]$saved.timestamp).UtcDateTime.ToString('o');checks=$saved.checks}
}

function Assert-Clean {
    $dirty = @(Git @('status', '--porcelain=v1', '--untracked-files=all'))
    if ($dirty.Count -gt 0) {
        throw "Commit or deliberately move uncommitted work first. Nothing was staged or stashed.`n$($dirty -join "`n")"
    }
}

function Assert-ReleaseVersion {
    if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$') {
        throw 'Specify a version such as -Version v0.1.0 or v0.1.0-rc.1.'
    }
}

function Resolve-Godot {
    if ($Godot) {
        return (Get-Item -LiteralPath $Godot -ErrorAction Stop).FullName
    }
    $command = Get-Command 'godot' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $candidates = @(Get-ChildItem -LiteralPath (Split-Path -Parent $root) -Filter 'Godot*_console.exe' -File)
    if ($candidates.Count -ne 1) {
        throw 'Specify the editor executable with -Godot PATH (or put godot on PATH).'
    }
    return $candidates[0].FullName
}

function Assert-Remote {
    $origin = [string](Git @('remote', 'get-url', 'origin'))
    if ($origin -notmatch '^https://github\.com/evanmac03/landscaping-planner(?:\.git)?/?$|^git@github\.com:evanmac03/landscaping-planner(?:\.git)?$') {
        throw "Unexpected origin: $origin. This script only publishes $repository."
    }
    Github @('api', 'user', '--jq', '.login') | Out-Null
    Git @('fetch', '--prune', 'origin') | Out-Host
}

function Get-Draft {
    $lookup = ((Github @('release', 'view', $Version, '--repo', $repository,
        '--json', 'databaseId')) -join "`n") | ConvertFrom-Json
    $raw = Github @('api', "repos/$repository/releases/$($lookup.databaseId)")
    $draft = ($raw -join "`n") | ConvertFrom-Json
    if ($draft.tag_name -ne $Version -or [string]$draft.id -ne [string]$lookup.databaseId) {
        throw 'Release lookup returned a different version or release ID.'
    }
    if (-not $draft.draft) { throw "$Version is already published; do not repeat Publish." }
    return $draft
}

function Assert-Tag {
    param([string]$Commit)
    $refs = @(Git @('ls-remote', 'origin', "refs/tags/$Version", "refs/tags/$Version^{}"))
    $peeled = @($refs | Where-Object { $_ -match '\^\{\}$' })
    $selected = @(if ($peeled.Count) { $peeled } else { $refs })
    if ($selected.Count -ne 1 -or ($selected[0] -split '\s+')[0] -ne $Commit) {
        throw "Remote tag $Version does not resolve to the prepared commit."
    }
}

function Assert-DraftAssets {
    param($Draft, $Receipt, [switch]$Retain)
    if ([string]$Draft.id -ne [string]$Receipt.release_id -or $Draft.tag_name -ne $Version) {
        throw 'Draft identity differs from the preparation receipt.'
    }
    $expected = @($Receipt.assets | ForEach-Object { $_.name } | Sort-Object)
    $actual = @($Draft.assets | ForEach-Object { $_.name } | Sort-Object)
    if (($expected -join "`n") -ne ($actual -join "`n")) {
        throw 'Draft assets differ from the prepared asset list.'
    }
    $download = Join-Path $receiptDirectory ("verify-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $download | Out-Null
    $verified = $false
    try {
        Set-EditorPhase 'Downloading assets'
        Github @('release', 'download', $Version, '--repo', $repository, '--dir', $download) | Out-Host
        Set-EditorPhase 'Verifying asset hashes'
        foreach ($asset in $Receipt.assets) {
            if ($asset.name -notmatch '^landscaping-planner-v[0-9A-Za-z.-]+-windows-x86_64\.(zip|sha256)$') {
                throw 'Receipt contains an invalid asset name.'
            }
            $path = Join-Path $download $asset.name
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $asset.sha256) {
                throw "Uploaded asset hash mismatch: $($asset.name)."
            }
        }
        $verified = $true
        if ($Retain) { return $download }
    }
    finally {
        if (-not $Retain -or -not $verified) { Remove-Item -LiteralPath $download -Recurse -Force }
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    $cli = Join-Path $env:ProgramFiles 'GitHub CLI'
    if (Test-Path -LiteralPath (Join-Path $cli 'gh.exe')) { $env:PATH = "$cli;$env:PATH" }
}

$branch = [string](Git @('branch', '--show-current'))
$head = [string](Git @('rev-parse', 'HEAD'))
if ($Action -eq 'SmokeTest') {
    if (-not $Approve) { throw 'SmokeTest requires explicit -Approve to run the downloaded executable.' }
    Set-EditorPhase 'Checking package integrity and headless startup'
    & (Join-Path $PSScriptRoot 'test-package.ps1') -Package $Package
    if (-not $?) { throw 'Packaged build smoke test failed.' }
    return
}
if ($Action -eq 'LastPublication') {
    $path = Join-Path ([string](Git @('rev-parse', '--absolute-git-dir'))) 'landscaping-releases\last-publication.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'No saved publication receipt. Older releases may predate this feature.' }
    $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($saved.repository -ne $repository) { throw 'Saved publication receipt belongs to another repository.' }
    Write-EditorResult $saved
    return
}
if (($ExpectedHead -and $ExpectedHead -ne $head) -or ($ExpectedBranch -and $ExpectedBranch -ne $branch)) {
    throw 'Approved branch/commit changed. Refresh and obtain approval again.'
}
if ($Action -eq 'Plan') {
    Write-Output "Repository: $repository"
    Write-Output "Branch: $branch"
    Write-Output "HEAD: $head"
    Git @('status', '--short') | Out-Host
    Write-Output 'Push: clean feature branch -> GitHub PR. Does not commit, rebase, merge or force-push.'
    Write-Output 'Release: clean synchronized main -> local Windows export -> verified draft.'
    Write-Output 'Publish: same clean commit + preparation receipt + exact draft assets + -Approve.'
    Write-Output 'Release needs Godot 4.7 and its matching Windows export templates. No CI or playability certification is implied.'
    return
}
if ($Action -in @('Validate', 'LocalEvidence', 'Evidence')) {
    $validationPath = Join-Path ([string](Git @('rev-parse', '--absolute-git-dir'))) 'landscaping-editor-validation.json'
    $fingerprint = Get-ValidationFingerprint
    if ($Action -eq 'Validate') {
        Set-EditorPhase 'Running local checks'
        if (Test-Path -LiteralPath $validationPath) { Remove-Item -LiteralPath $validationPath }
        $checks = @('GitHub workflow mocks', 'Read-only agent interface', 'Disposable Git integration', 'Merge synchronization integration', 'Package smoke checks', 'Godot guided workflow')
        & (Join-Path $PSScriptRoot 'test-github.ps1') | Out-Host
        if (-not $?) { throw 'Local GitHub workflow tests failed.' }
        & (Join-Path $PSScriptRoot 'test-workflow-agent.ps1') | Out-Host
        if (-not $?) { throw 'Read-only agent interface tests failed.' }
        & (Join-Path $PSScriptRoot 'test-editor-git.ps1') | Out-Host
        if (-not $?) { throw 'Local Git integration tests failed.' }
        & (Join-Path $PSScriptRoot 'test-package-tests.ps1') | Out-Host
        if (-not $?) { throw 'Package smoke tests failed.' }
        & (Join-Path $PSScriptRoot 'test-synchronize.ps1') | Out-Host
        if (-not $?) { throw 'Main synchronization integration tests failed.' }
        $editor = Resolve-Godot
        $log = @(Invoke-Native $editor @('--headless', '--path', $root, '--script', 'res://tools/check_github_dock.gd') 2>&1)
        $log | Out-Host
        if (($log -join "`n") -match '(?m)(?:SCRIPT ERROR:|ERROR:)' -or
            ($log -join "`n") -notmatch 'PASS: completion routing') { throw 'Godot guide tests did not pass cleanly.' }
        if ((Get-ValidationFingerprint) -ne $fingerprint) { throw 'Files/index/HEAD changed during checks. No validation receipt saved.' }
        @{ fingerprint=$fingerprint; head=$head; timestamp=[DateTime]::UtcNow.ToString('o'); checks=$checks } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $validationPath -Encoding UTF8
    }
    $local = @{state='not-run';timestamp='';checks=@()}
    if (Test-Path -LiteralPath $validationPath) {
        $saved = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
        $local = @{state=$(if ($saved.fingerprint -eq $fingerprint) {'passed'} else {'stale'});timestamp=$saved.timestamp;checks=$saved.checks}
    }
    $ci = @{state='not-queried';head=$head;checks=@();url=''}
    if ($Action -eq 'Evidence') {
        try {
        Assert-Remote
        $prs = @(((Github @('pr', 'list', '--repo', $repository, '--head', $branch, '--state', 'open',
            '--json', 'number,url,headRefOid')) -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
        $ci.state = 'no-open-pr'
        if ($prs.Count -eq 1) {
            $pr = ((Github @('pr', 'view', [string]$prs[0].number, '--repo', $repository,
                '--json', 'headRefOid,statusCheckRollup,url')) -join "`n") | ConvertFrom-Json
            $ci.url = $pr.url
            $ci.head = $pr.headRefOid
            $ci.checks = @($pr.statusCheckRollup)
            $ci.state = if ($pr.headRefOid -ne $head) {'different-head'} elseif ($ci.checks.Count -eq 0) {'no-checks-reported'} else {'reported'}
        } elseif ($prs.Count -gt 1) { throw 'Multiple open PRs; cannot select CI evidence automatically.' }
        else {
            $runs = @(((Github @('run', 'list', '--repo', $repository, '--commit', $head, '--limit', '100',
                '--json', 'databaseId,headSha,name,status,conclusion,url,createdAt')) -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
            $ci.state = 'no-runs-reported'
            $ci.source = 'exact-commit-runs'
            $ci.checks = @()
            # Keep the newest run of each workflow; an older pass must not hide a newer failure.
            foreach ($group in @($runs | Where-Object { $null -ne $_ -and $_.headSha -eq $head } | Group-Object name)) {
                $run = $group.Group | Sort-Object createdAt -Descending | Select-Object -First 1
                $ci.checks += @{name=$run.name;status=$run.status;conclusion=$run.conclusion;detailsUrl=$run.url;head=$run.headSha}
            }
            if ($ci.checks.Count) { $ci.state = 'reported'; $ci.url = $ci.checks[0].detailsUrl }
        }
        }
        catch {
            $ci = @{state='unavailable';head=$head;checks=@();url='';error=$_.Exception.Message}
            Write-Warning "GitHub evidence unavailable: $($_.Exception.Message)"
        }
    }
    Write-EditorResult @{local=$local;ci=$ci;commit=$head}
    return
}
if ($Action -eq 'Discover') {
    Assert-Remote
    $dirty = @(Git @('status', '--porcelain=v1', '--untracked-files=all')).Count -gt 0
    $next = 'files'
    $url = ''
    $selectedVersion = ''
    $choices = @()
    $distance = ''
    if (-not $dirty -and $branch -eq 'main' -and $head -ne [string](Git @('rev-parse', 'origin/main'))) {
        $next = 'sync'
        $distance = [string](Git @('rev-list', '--left-right', '--count', 'HEAD...origin/main'))
    }
    if (-not $dirty -and $branch -eq 'main' -and $head -eq [string](Git @('rev-parse', 'origin/main'))) {
        $next = 'release'
        $metadata = Join-Path ([string](Git @('rev-parse', '--absolute-git-dir'))) 'landscaping-releases'
        $pages = ((Github @('api', '--paginate', '--slurp', "repos/$repository/releases")) -join "`n") | ConvertFrom-Json
        $drafts = @($pages | ForEach-Object { $_ })
        $candidates = @($drafts | Where-Object {
            $null -ne $_ -and $_.draft -and $_.tag_name -match '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$' -and
            (Test-Path -LiteralPath (Join-Path $metadata "$($_.tag_name).json"))
        } | Where-Object {
            $saved = Get-Content -LiteralPath (Join-Path $metadata "$($_.tag_name).json") -Raw | ConvertFrom-Json
            $saved.commit -eq $head -and $saved.repository -eq $repository -and $saved.version -eq $_.tag_name -and [string]$saved.release_id -eq [string]$_.id
        })
        if ($candidates.Count -eq 1) {
            $next = 'publish'; $selectedVersion = $candidates[0].tag_name; $url = $candidates[0].html_url
        } elseif ($candidates.Count -gt 1) {
            $next = 'drafts'
            $choices = @($candidates | ForEach-Object { @{version=$_.tag_name;url=$_.html_url;commit=$head;id=$_.id} })
        }
    } elseif (-not $dirty -and $branch -and $branch -ne 'main') {
        $prs = @(((Github @('pr', 'list', '--repo', $repository, '--head', $branch, '--base', 'main',
            '--state', 'open', '--json', 'url,headRefOid')) -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
        if ($prs.Count -eq 1 -and $prs[0].headRefOid -eq $head) { $next = 'merge'; $url = $prs[0].url }
        elseif ($prs.Count -gt 1) { throw 'Multiple open PRs; inspect GitHub before continuing.' }
        elseif ($prs.Count -eq 1) { throw 'Open PR head differs from local HEAD. Reconcile before continuing.' }
        else {
            $merged = @(((Github @('pr', 'list', '--repo', $repository, '--head', $branch, '--base', 'main',
                '--state', 'merged', '--json', 'url,headRefOid')) -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } |
                Where-Object { $null -ne $_ -and $_.headRefOid -eq $head })
            if ($merged.Count -gt 1) { throw 'Multiple merged PRs match HEAD; inspect GitHub before continuing.' }
            if ($merged.Count -eq 1) { $next = 'sync_main'; $url = $merged[0].url }
            else { $next = 'push' }
        }
    }
    Write-EditorResult @{ next = $next; url = $url; version = $selectedVersion; commit = $head; choices = $choices; distance = $distance }
    return
}
if ($Action -ne 'RecoverDraft') { Assert-Clean }
if (-not $Approve) { throw "$Action requires explicit -Approve. Plan performs no remote operations." }
Assert-Remote

if (($ExpectedHead -and $ExpectedHead -ne [string](Git @('rev-parse', 'HEAD'))) -or
    ($ExpectedBranch -and $ExpectedBranch -ne [string](Git @('branch', '--show-current')))) {
    throw 'Approved branch/commit changed during preflight. Refresh and obtain approval again.'
}
if ($Action -eq 'Synchronize') {
    if (-not $ExpectedHead -or -not $ExpectedBranch) { throw 'Synchronize requires the reviewed branch and HEAD.' }
    if ($branch -notmatch '^feature/[a-z0-9][a-z0-9-]*$') { throw 'Synchronize requires a reviewed feature branch.' }
    $prs = @(((Github @('pr', 'list', '--repo', $repository, '--head', $branch, '--base', 'main',
        '--state', 'merged', '--json', 'headRefOid,mergeCommit,url')) -join "`n") | ConvertFrom-Json | ForEach-Object { $_ })
    $matching = @($prs | Where-Object { $null -ne $_ -and $_.headRefOid -eq $head -and $_.mergeCommit -and $_.mergeCommit.oid })
    if ($matching.Count -ne 1) { throw 'No unique merged PR matches the exact feature HEAD. Review/merge on GitHub first.' }
    $merge = [string]$matching[0].mergeCommit.oid
    if ([string](Git @('merge-base', $merge, 'origin/main')) -ne $merge) { throw 'Merged PR is not included in origin/main.' }
    if ([string](Git @('rev-list', '--count', 'origin/main..main')) -ne '0') { throw 'Local main has commits absent from origin/main. Reconcile manually; nothing switched.' }
    Assert-Clean
    Set-EditorPhase 'Fast-forwarding main after verified GitHub merge'
    Git @('switch', 'main') | Out-Host
    Git @('merge', '--ff-only', 'origin/main') | Out-Host
    if ([string](Git @('rev-parse', 'HEAD')) -ne [string](Git @('rev-parse', 'origin/main'))) { throw 'Main synchronization did not verify. Inspect before retrying.' }
    if ($CleanupBranch -eq 'yes') {
        if ([string](Git @('rev-parse', "refs/heads/$branch")) -ne $head) { throw 'Feature tip changed; main synchronized but cleanup stopped.' }
        # Squash merges do not make the feature tip an ancestor; exact PR head was verified above.
        Git @('branch', '-D', '--', $branch) | Out-Host
    }
    Write-EditorResult @{commit=[string](Git @('rev-parse', 'HEAD'));branch='main';url=$matching[0].url;cleaned=($CleanupBranch -eq 'yes')}
    return
}
if ($Action -eq 'Push') {
    if (-not $branch -or $branch -eq 'main') {
        throw 'Push requires a feature branch. Create and commit one yourself first.'
    }
    $remoteRefs = @(Git @('for-each-ref', '--format=%(refname)', "refs/remotes/origin/$branch"))
    if ($remoteRefs.Count -gt 0) {
        $counts = ([string](Git @('rev-list', '--left-right', '--count', "HEAD...origin/$branch"))) -split '\s+'
        if ([int]$counts[1] -gt 0) { throw 'Remote branch has commits missing locally. Reconcile explicitly before pushing.' }
    }
    if ([int]([string](Git @('rev-list', '--count', 'origin/main..HEAD'))) -eq 0) {
        throw 'This branch has no feature commits beyond origin/main.'
    }
    Git @('push', '-u', 'origin', $branch) | Out-Host
    $prs = ((Github @('pr', 'list', '--repo', $repository, '--head', $branch, '--base', 'main',
        '--state', 'open', '--json', 'number,url,headRefOid')) -join "`n") | ConvertFrom-Json
    if (@($prs).Count -gt 1) { throw 'Multiple matching PRs found; inspect them manually.' }
    if (@($prs).Count -eq 1) {
        if ($prs[0].headRefOid -ne $head) { throw 'PR head does not match the pushed commit; inspect before proceeding.' }
        Write-Output "Existing PR: $($prs[0].url)"
    }
    else {
        if (-not $Title) { $Title = [string](Git @('log', '-1', '--format=%s')) }
        $body = [IO.Path]::GetTempFileName()
        try {
            $commits = Git @('log', '--format=- %h %s', 'origin/main..HEAD')
            $validation = Get-LocalValidation
            $evidence = if ($validation.state -eq 'passed') {
                "Matching local workflow validation passed at $($validation.timestamp) (UTC). Suites: $($validation.checks -join ', '). This is not a full game test."
            } else {
                "Local validation: $($validation.state). No matching local pass is claimed for this commit."
            }
            $text = "## Changes`n`n$($commits -join "`n")`n`n## Verification`n`nPushed committed HEAD $head.`n`n$evidence`n`nGitHub CI: not evaluated by Push. Inspect exact-head PR checks separately; local results are not a CI pass.`n"
            [IO.File]::WriteAllText($body, $text, [Text.UTF8Encoding]::new($false))
            Github @('pr', 'create', '--repo', $repository, '--base', 'main', '--head', $branch,
                '--title', $Title, '--body-file', $body) | Out-Host
        }
        finally { Remove-Item -LiteralPath $body -Force }
    }
    Write-Output 'Stopped before merge. Review the PR and any GitHub checks separately.'
    $current = ((Github @('pr', 'list', '--repo', $repository, '--head', $branch, '--base', 'main',
        '--state', 'open', '--json', 'url,headRefOid')) -join "`n") | ConvertFrom-Json
    if (@($current).Count -ne 1 -or $current[0].headRefOid -ne $head) { throw 'Could not verify exact pushed PR.' }
    Write-EditorResult @{ url = $current[0].url }
    return
}

Assert-ReleaseVersion
if ($branch -ne 'main' -or $head -ne [string](Git @('rev-parse', 'origin/main'))) {
    throw 'Release/Publish requires clean main exactly synchronized with origin/main.'
}
$gitDirectory = [string](Git @('rev-parse', '--absolute-git-dir'))
$receiptDirectory = Join-Path $gitDirectory 'landscaping-releases'
New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
$receiptPath = Join-Path $receiptDirectory "$Version.json"

if ($Action -eq 'RecoverDraft') {
    if (Test-Path -LiteralPath $receiptPath) { throw 'Preparation receipt already exists; do not replace it.' }
    $build = (Get-Item -LiteralPath $BuildDirectory -ErrorAction Stop).FullName
    if ((Split-Path -Parent $build) -ne $receiptDirectory -or
        (Split-Path -Leaf $build) -notmatch '^build-[0-9a-f]{32}$') {
        throw 'Recovery requires a retained build directly inside this repository release metadata.'
    }
    $comparison = Join-Path $receiptDirectory ("source-check-" + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        Git @('archive', '--format=zip', "--output=$comparison", $head) | Out-Null
        if ((Get-FileHash -LiteralPath $comparison -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath (Join-Path $build 'source.zip') -Algorithm SHA256).Hash) {
            throw 'Retained source archive does not match committed HEAD.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $comparison) { Remove-Item -LiteralPath $comparison }
    }
    $stem = "landscaping-planner-$Version-windows-x86_64"
    $zip = Join-Path $build "$stem.zip"
    $checksum = Join-Path $build "$stem.sha256"
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([IO.File]::ReadAllText($checksum).Trim() -ne "$hash  $stem.zip") {
        throw 'Retained ZIP does not match its original checksum.'
    }
    $draft = Get-Draft
    if ($draft.target_commitish -ne $head) { throw 'Draft target does not match committed HEAD.' }
    Assert-Tag $head
    $receipt = [ordered]@{
        repository = $repository; version = $Version; commit = $head
        release_id = $draft.id
        assets = @(@{ name = "$stem.zip"; sha256 = $hash },
            @{ name = "$stem.sha256"; sha256 = (Get-FileHash -LiteralPath $checksum -Algorithm SHA256).Hash.ToLowerInvariant() })
    }
    Assert-DraftAssets $draft $receipt
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Output "Recovered verified draft receipt: $($draft.html_url)"
    Write-Output 'Retained build provenance is trusted locally; this checks source/archive and asset integrity, not reproducible compilation.'
    return
}

if ($Action -in @('Publish', 'DownloadTest')) {
    if (-not (Test-Path -LiteralPath $receiptPath)) { throw 'No local preparation receipt. Prepare and verify a draft first.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.commit -ne $head -or $receipt.repository -ne $repository -or $receipt.version -ne $Version) {
        throw 'Checkout or version differs from the preparation receipt.'
    }
    $draft = Get-Draft
    Assert-Tag $head
    $draftIdentity = ([string]$draft.id) + ':' + $draft.tag_name + ':' + $draft.target_commitish + ':' +
        [string]$draft.prerelease + ':' + $receipt.assets[0].sha256 + ':' + $receipt.assets[1].sha256
    if ($ExpectedDraft -and $ExpectedDraft -ne $draftIdentity) { throw 'Approved draft identity changed. Download, test and approve again.' }
    if ($Action -eq 'DownloadTest') {
        Set-EditorPhase 'Downloading and verifying assets'
        $download = Assert-DraftAssets $draft $receipt -Retain
        $stem = "landscaping-planner-$Version-windows-x86_64"
        $unpacked = Join-Path $download 'unpacked'
        Expand-Archive -LiteralPath (Join-Path $download "$stem.zip") -DestinationPath $unpacked
        $exe = Join-Path $unpacked 'landscaping-planner.exe'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Verified ZIP has no expected Windows executable.' }
        $manifest = @{}
        foreach ($file in Get-ChildItem -LiteralPath $unpacked -Recurse -File) {
            $manifest[$file.FullName.Substring($unpacked.Length + 1).Replace('\', '/')] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        Write-EditorResult @{ url = $draft.html_url; folder = $unpacked; executable = $exe; version = $Version; commit = $head; identity = $draftIdentity; manifest = $manifest; prerelease = $draft.prerelease; release_id = $draft.id }
        return
    }
    Assert-DraftAssets $draft $receipt
    $fresh = Get-Draft
    if (($fresh | ConvertTo-Json -Depth 20 -Compress) -ne ($draft | ConvertTo-Json -Depth 20 -Compress)) {
        throw 'Draft changed during verification. Inspect it and obtain fresh approval.'
    }
    Assert-Clean
    if ([string](Git @('rev-parse', 'HEAD')) -ne $head -or
        [string](Git @('branch', '--show-current')) -ne 'main') {
        throw 'Checkout changed during draft verification.'
    }
    Assert-Tag $head
    Set-EditorPhase 'Publishing verified draft'
    Github @('release', 'edit', $Version, '--repo', $repository, '--draft=false') | Out-Host
    $published = ((Github @('api', "repos/$repository/releases/$($draft.id)")) -join "`n") | ConvertFrom-Json
    if ($published.draft) { throw 'Publication did not verify; inspect GitHub before retrying.' }
    Write-Output "Published: $($published.html_url)"
    $publication = @{ repository=$repository; url = $published.html_url; version=$Version; commit=$head; release_id=$published.id;
        published_at=$published.published_at; prerelease=$published.prerelease; assets=$receipt.assets;
        verification='Uploaded assets freshly downloaded and hashes verified before publication'; backup='No Forgejo backup' }
    # Emit the verified result before local persistence; a disk failure must not imply GitHub failed.
    Write-EditorResult $publication
    $temporaryReceipt = Join-Path $receiptDirectory ('publication-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $publication | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryReceipt -Encoding UTF8
        Move-Item -LiteralPath $temporaryReceipt -Destination (Join-Path $receiptDirectory 'last-publication.json') -Force
    }
    catch {
        Write-Warning "GitHub published; local publication receipt could not be saved: $($_.Exception.Message). Do not repeat Publish."
    }
    finally {
        if (Test-Path -LiteralPath $temporaryReceipt) { Remove-Item -LiteralPath $temporaryReceipt }
    }
    return
}

if (Test-Path -LiteralPath $receiptPath) { throw 'Preparation receipt already exists. Inspect the existing draft; do not recreate it.' }
$tags = @(Git @('ls-remote', 'origin', "refs/tags/$Version"))
if ($tags.Count) { throw "Tag $Version already exists." }
$releases = ((Github @('api', '--paginate', "repos/$repository/releases", '--jq', '.[].tag_name')) -join "`n")
if (@($releases -split "`n") -contains $Version) { throw "Release $Version already exists." }
$editor = Resolve-Godot
$editorVersion = [string](Invoke-Native $editor @('--version'))
if ($editorVersion -notmatch '^4\.7\.') { throw "Expected Godot 4.7.x, found $editorVersion." }
$build = Join-Path $receiptDirectory ("build-" + [guid]::NewGuid().ToString('N'))
$source = Join-Path $build 'source'
$package = Join-Path $build 'package'
New-Item -ItemType Directory -Path $source, $package | Out-Null
# Export only committed files; never run imports or plugins against the source checkout.
$archive = Join-Path $build 'source.zip'
Git @('archive', '--format=zip', "--output=$archive", $head) | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $source
Push-Location $source
try {
    Set-EditorPhase 'Importing committed source'
    Invoke-Native $editor @('--headless', '--editor', '--path', $source, '--import') | Out-Host
    Set-EditorPhase 'Exporting Windows package'
    Invoke-Native $editor @('--headless', '--path', $source, '--export-release', 'Windows Desktop',
        (Join-Path $package 'landscaping-planner.exe')) | Out-Host
}
finally { Pop-Location }
$exe = Join-Path $package 'landscaping-planner.exe'
$pck = Join-Path $package 'landscaping-planner.pck'
foreach ($file in @($exe, $pck)) {
    if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -eq 0) {
        throw "Expected export output is missing or empty: $file. Build retained at $build."
    }
}
Assert-Clean
if ([string](Git @('rev-parse', 'HEAD')) -ne $head -or
    [string](Git @('branch', '--show-current')) -ne 'main') {
    throw 'Checkout changed during export.'
}
$stem = "landscaping-planner-$Version-windows-x86_64"
$zip = Join-Path $build "$stem.zip"
Set-EditorPhase 'Packaging Windows build'
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip
$checksum = Join-Path $build "$stem.sha256"
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($checksum, "$hash  $stem.zip`n", [Text.UTF8Encoding]::new($false))
$notes = Join-Path $build 'notes.txt'
[IO.File]::WriteAllText($notes, "Windows x86_64 export of commit $head using $editorVersion.`nExtract the ZIP and run landscaping-planner.exe with its PCK beside it.`nUnsigned build. Export success is not a GUI playtest or CI pass.`n", [Text.UTF8Encoding]::new($false))
$arguments = @('release', 'create', $Version, '--repo', $repository, '--target', $head,
    '--verify-tag', '--draft', '--title', $Version, '--notes-file', $notes, $zip, $checksum)
if ($Version.Contains('-')) { $arguments += '--prerelease' }
# Draft releases do not create their tag until publication; pin it explicitly now.
Git @('push', 'origin', "${head}:refs/tags/$Version") | Out-Host
Assert-Tag $head
Set-EditorPhase 'Uploading private draft'
Github $arguments | Out-Host
$draft = Get-Draft
$receipt = [ordered]@{
    repository = $repository; version = $Version; commit = $head
    release_id = $draft.id; godot = $editorVersion
    assets = @(@{ name = "$stem.zip"; sha256 = $hash },
        @{ name = "$stem.sha256"; sha256 = (Get-FileHash -LiteralPath $checksum -Algorithm SHA256).Hash.ToLowerInvariant() })
}
Set-EditorPhase 'Downloading and verifying assets'
Assert-DraftAssets $draft $receipt
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Output "Verified draft: $($draft.html_url)"
Write-EditorResult @{ url = $draft.html_url }
Write-Output "Build retained at $build. Test the downloaded Windows build before separately approving Publish."
