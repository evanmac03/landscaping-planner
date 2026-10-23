[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Push', 'Release', 'Publish')]
    [string]$Action = 'Plan',
    [string]$Version,
    [string]$Godot,
    [string]$Title,
    [switch]$Approve
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$repository = 'evanmac03/landscaping-planner'

function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    $executable = if ($Command -in @('git', 'gh')) {
        (Get-Command $Command -CommandType Application -ErrorAction Stop).Source
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
    $command = Get-Command 'godot' -ErrorAction SilentlyContinue
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
    $raw = Github @('api', "repos/$repository/releases/tags/$Version")
    $draft = ($raw -join "`n") | ConvertFrom-Json
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
    param($Draft, $Receipt)
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
    try {
        Github @('release', 'download', $Version, '--repo', $repository, '--dir', $download) | Out-Host
        foreach ($asset in $Receipt.assets) {
            if ($asset.name -notmatch '^landscaping-planner-v[0-9A-Za-z.-]+-windows-x86_64\.(zip|sha256)$') {
                throw 'Receipt contains an invalid asset name.'
            }
            $path = Join-Path $download $asset.name
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $asset.sha256) {
                throw "Uploaded asset hash mismatch: $($asset.name)."
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $download -Recurse -Force
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    $cli = Join-Path $env:ProgramFiles 'GitHub CLI'
    if (Test-Path -LiteralPath (Join-Path $cli 'gh.exe')) { $env:PATH = "$cli;$env:PATH" }
}

$branch = [string](Git @('branch', '--show-current'))
$head = [string](Git @('rev-parse', 'HEAD'))
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
Assert-Clean
if (-not $Approve) { throw "$Action requires explicit -Approve. Plan performs no remote operations." }
Assert-Remote

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
            $text = "## Changes`n`n$($commits -join "`n")`n`n## Verification`n`nPublished committed HEAD $head. This script did not run tests or CI; inspect checks and test the change before merging.`n"
            [IO.File]::WriteAllText($body, $text, [Text.UTF8Encoding]::new($false))
            Github @('pr', 'create', '--repo', $repository, '--base', 'main', '--head', $branch,
                '--title', $Title, '--body-file', $body) | Out-Host
        }
        finally { Remove-Item -LiteralPath $body -Force }
    }
    Write-Output 'Stopped before merge. Review the PR and any GitHub checks separately.'
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

if ($Action -eq 'Publish') {
    if (-not (Test-Path -LiteralPath $receiptPath)) { throw 'No local preparation receipt. Prepare and verify a draft first.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.commit -ne $head -or $receipt.repository -ne $repository -or $receipt.version -ne $Version) {
        throw 'Checkout or version differs from the preparation receipt.'
    }
    $draft = Get-Draft
    Assert-Tag $head
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
    Github @('release', 'edit', $Version, '--repo', $repository, '--draft=false') | Out-Host
    $published = ((Github @('api', "repos/$repository/releases/$($draft.id)")) -join "`n") | ConvertFrom-Json
    if ($published.draft) { throw 'Publication did not verify; inspect GitHub before retrying.' }
    Write-Output "Published: $($published.html_url)"
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
    Invoke-Native $editor @('--headless', '--editor', '--path', $source, '--import') | Out-Host
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
Github $arguments | Out-Host
$draft = Get-Draft
$receipt = [ordered]@{
    repository = $repository; version = $Version; commit = $head
    release_id = $draft.id; godot = $editorVersion
    assets = @(@{ name = "$stem.zip"; sha256 = $hash },
        @{ name = "$stem.sha256"; sha256 = (Get-FileHash -LiteralPath $checksum -Algorithm SHA256).Hash.ToLowerInvariant() })
}
Assert-DraftAssets $draft $receipt
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Output "Verified draft: $($draft.html_url)"
Write-Output "Build retained at $build. Test the downloaded Windows build before separately approving Publish."
