[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'github.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors -join "`n") }
$native = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Native'
}, $false)
if ($null -eq $native) { throw 'Native command boundary not found.' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("landscaping-github-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') | Out-Null
$mock = @'
function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    $s = $global:LandscapingGithubTest
    $s.calls.Add("$Command $($Arguments -join ' ')")
    if ($Command -eq 'git') {
        $a = $Arguments[3..($Arguments.Count - 1)]
        $key = $a -join ' '
        switch -Wildcard ($key) {
            'branch --show-current' { return $s.branch }
            'rev-parse HEAD' { return $s.head }
            'rev-parse origin/main' { return $s.main }
            'rev-parse --absolute-git-dir' { return (Join-Path $s.root '.git') }
            'status --porcelain*' { if ($s.dirty) { return ' M project.godot' }; return }
            'status --short' { return }
            'remote get-url origin' { return 'https://github.com/evanmac03/landscaping-planner.git' }
            'fetch --prune origin' { return }
            'for-each-ref *' { return 'refs/remotes/origin/feature/test' }
            'rev-list --left-right --count *' { return "1`t$($s.behind)" }
            'rev-list --count origin/main..HEAD' { return '1' }
            'push -u origin *' { return }
            'log -1 --format=%s' { return 'Test change' }
            'log --format=- %h %s origin/main..HEAD' { return '- abc Test change' }
            'ls-remote origin refs/tags/*' {
                if ($s.tag) { return "$($s.head)`trefs/tags/v0.1.0-rc.1" }
                return
            }
            'push origin *:refs/tags/*' { $s.tag = $true; return }
            'archive --format=zip *' {
                $output = [string]($a | Where-Object { $_ -like '--output=*' } | Select-Object -First 1)
                if (-not $output) { throw "Archive output missing in arguments: $($a -join ' | ')" }
                $output = $output.Substring(9)
                if ($s.archive) {
                    Copy-Item -LiteralPath $s.archive -Destination $output
                    return
                }
                $inputDir = Join-Path $s.root 'archive-input'
                New-Item -ItemType Directory -Path $inputDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $inputDir 'project.godot') -Value 'config_version=5'
                Compress-Archive -Path (Join-Path $inputDir '*') -DestinationPath $output
                $s.archive = $output
                return
            }
        }
    }
    elseif ($Command -eq 'gh') {
        $key = $Arguments -join ' '
        switch -Wildcard ($key) {
            'api user --jq .login' {
                if ($s.offline) { throw 'Simulated GitHub network outage.' }
                return 'test-user'
            }
            'pr list *' {
                if ($s.pr) { return ('[' + (@{number=1;url='https://example.invalid/pr/1';headRefOid=$s.head} | ConvertTo-Json -Compress) + ']') }
                return '[]'
            }
            'pr create *' {
                $bodyIndex = [Array]::IndexOf($Arguments, '--body-file')
                $s.prBody = [IO.File]::ReadAllText($Arguments[$bodyIndex + 1])
                $s.pr = $true; return 'https://example.invalid/pr/1'
            }
            'pr view *' {
                return (@{headRefOid=$(if ($s.otherCiHead) {'different-head'} else {$s.head});url='https://example.invalid/pr/1';statusCheckRollup=@()} | ConvertTo-Json -Depth 5)
            }
            'api --paginate *' {
                if ($Arguments -notcontains '--jq') {
                    if ($s.assets.Count) {
                        $item = @{id=42;draft=$s.draft;tag_name=$s.lookupTag;html_url='https://example.invalid/release/42'}
                        $items = @($item)
                        if ($s.multiple) { $items += @{id=43;draft=$true;tag_name='v0.1.0-rc.2';html_url='https://example.invalid/release/43'} }
                        return ('[' + (ConvertTo-Json -InputObject $items -Compress) + ']')
                    }
                    return '[]'
                }
                return
            }
            'release create *' {
                $s.assets = @($Arguments | Where-Object { $_ -match '\.(zip|sha256)$' })
                $s.draft = $true
                return
            }
            'api repos/*/releases/tags/*' { throw 'Release-by-tag API cannot locate an unpublished draft.' }
            'release view *' { return '{"databaseId":42}' }
            'api repos/*/releases/42' {
                return (@{
                    id = 42; draft = $s.draft; tag_name = $s.lookupTag; target_commitish = $s.head; prerelease = $true; published_at='2026-10-23T16:00:00Z'
                    html_url = 'https://example.invalid/release/42'
                    assets = @($s.assets | ForEach-Object { @{ name = [IO.Path]::GetFileName($_) } })
                } | ConvertTo-Json -Depth 5)
            }
            'release download *' {
                $dir = $Arguments[$Arguments.Count - 1]
                foreach ($asset in $s.assets) { Copy-Item -LiteralPath $asset -Destination $dir }
                if ($s.tamper) {
                    Add-Content -LiteralPath (Join-Path $dir ([IO.Path]::GetFileName($s.assets[0]))) -Value 'tampered'
                }
                return
            }
            'release edit *' { $s.draft = $false; return }
        }
    }
    elseif ($Command -eq $s.editor) {
        if ($Arguments[0] -eq '--version') { return '4.7.2.stable.test' }
        if ($Arguments -contains '--import') { return }
        if ($Arguments -contains '--export-release') {
            $exe = $Arguments[$Arguments.Count - 1]
            Set-Content -LiteralPath $exe -Value 'fake executable'
            Set-Content -LiteralPath ([IO.Path]::ChangeExtension($exe, '.pck')) -Value 'fake pack'
            return
        }
    }
    throw "Unexpected mocked command: $Command $($Arguments -join ' ')"
}
'@
$text = [IO.File]::ReadAllText($scriptPath)
$text = $text.Remove($native.Extent.StartOffset, $native.Extent.EndOffset - $native.Extent.StartOffset).
    Insert($native.Extent.StartOffset, $mock)
$testScript = Join-Path $fixture 'tools\github.ps1'
[IO.File]::WriteAllText($testScript, $text)
[IO.File]::WriteAllText((Join-Path $fixture 'tools\editor-git.ps1'), 'param($Request); Write-Output ''{"head":"fixture","branch":"feature/test","index_tree":"tree","files":[],"staged":[],"hashes":{}}''')
$editor = Join-Path $fixture 'fake-godot.exe'
Set-Content -LiteralPath $editor -Value 'not executed'
$global:LandscapingGithubTest = @{
    root = $fixture; editor = $editor; branch = 'feature/test'; dirty = $false
    head = ('a' * 40); main = ('a' * 40); behind = 0; tag = $false
    draft = $true; assets = @(); tamper = $false; lookupTag = 'v0.1.0-rc.1'; archive = ''; pr = $false
    multiple = $false; otherCiHead = $false; offline = $false; prBody = ''; calls = [Collections.Generic.List[string]]::new()
}
$s = $global:LandscapingGithubTest
$passed = 0
function Expect-Failure {
    param([scriptblock]$Run, [string]$Pattern)
    try { & $Run; throw 'Expected command to fail.' }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw } }
}
try {
    & $testScript -Action Plan | Out-Null
    if (@($s.calls | Where-Object { $_ -match '^gh | fetch | push ' }).Count) { throw 'Plan performed remote operations.' }
    $passed++
    Expect-Failure { & $testScript -Action Push -ExpectedHead ('b' * 40) -ExpectedBranch 'feature/test' -Approve } 'Approved branch/commit changed*'
    Expect-Failure { & $testScript -Action Push -ExpectedHead $s.head -ExpectedBranch 'feature/other' -Approve } 'Approved branch/commit changed*'
    $passed++
    $s.dirty = $true
    Expect-Failure { & $testScript -Action Push -Approve } 'Commit or deliberately move*'
    $s.dirty = $false
    $passed++
    Expect-Failure { & $testScript -Action Push } '*requires explicit -Approve*'
    $passed++
    $s.branch = 'main'
    $discovery = (& $testScript -Action Discover) -join "`n"
    if ($discovery -notmatch '"next":"release"') { throw 'Clean main did not resume release.' }
    $passed++
    Expect-Failure { & $testScript -Action Push -Approve } 'Push requires a feature branch*'
    $passed++
    $s.branch = 'feature/test'
    $s.behind = 1
    Expect-Failure { & $testScript -Action Push -Approve } 'Remote branch has commits missing*'
    $s.behind = 0
    $passed++
    & $testScript -Action Push -Approve
    if (-not @($s.calls | Where-Object { $_ -like 'gh pr create *' }).Count) { throw 'PR was not created.' }
    if ($s.prBody -notmatch 'Local validation: not-run' -or $s.prBody -notmatch 'not a CI pass') { throw 'Missing PR validation evidence was misrepresented.' }
    $passed++
    $discovery = (& $testScript -Action Discover) -join "`n"
    if ($discovery -notmatch '"next":"merge"') { throw 'Exact-head existing PR was not detected.' }
    $passed++
    $evidenceText = (& $testScript -Action Evidence) -join "`n"
    $evidence = (($evidenceText -split 'EDITOR_RESULT:')[-1]) | ConvertFrom-Json
    if ($evidence.local.state -ne 'not-run' -or $evidence.ci.state -ne 'no-checks-reported') { throw 'Missing local/CI evidence was reported incorrectly.' }
    $passed++
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $snapshot = (& (Join-Path $fixture 'tools\editor-git.ps1') -Request unused) -join "`n"
        $fingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($snapshot)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
    $validationPath = Join-Path $fixture '.git\landscaping-editor-validation.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $validationPath) -Force | Out-Null
    @{fingerprint=$fingerprint;timestamp='2026-10-23T16:00:00Z';checks=@('Fixture suite')} |
        ConvertTo-Json | Set-Content -LiteralPath $validationPath -Encoding UTF8
    $evidenceText = (& $testScript -Action Evidence) -join "`n"
    $evidence = (($evidenceText -split 'EDITOR_RESULT:')[-1]) | ConvertFrom-Json
    if ($evidence.local.state -ne 'passed' -or ([DateTimeOffset]$evidence.local.timestamp).UtcDateTime -ne ([DateTimeOffset]'2026-10-23T16:00:00Z').UtcDateTime) { throw "Matching validation receipt lost its result/timestamp: $evidenceText" }
    $passed++
    $s.pr = $false
    & $testScript -Action Push -Approve | Out-Null
    if ($s.prBody -notmatch 'Matching local workflow validation passed' -or $s.prBody -notmatch 'Fixture suite' -or $s.prBody -notmatch '2026-10-23' -or $s.prBody -match 'C:\\') { throw "PR validation fixture mismatch: $($s.prBody)" }
    $passed++
    $s.offline = $true
    $evidenceText = (& $testScript -Action Evidence 3>$null) -join "`n"
    $evidence = (($evidenceText -split 'EDITOR_RESULT:')[-1]) | ConvertFrom-Json
    if ($evidence.local.state -ne 'passed' -or $evidence.ci.state -ne 'unavailable' -or $evidence.ci.error -notlike '*network outage*') { throw 'Remote outage hid valid local evidence.' }
    $s.offline = $false
    $passed++
    @{fingerprint='outdated';timestamp='2026-10-23T16:00:00Z';checks=@('Fixture suite')} |
        ConvertTo-Json | Set-Content -LiteralPath $validationPath -Encoding UTF8
    $s.otherCiHead = $true
    $evidenceText = (& $testScript -Action Evidence) -join "`n"
    $evidence = (($evidenceText -split 'EDITOR_RESULT:')[-1]) | ConvertFrom-Json
    if ($evidence.local.state -ne 'stale' -or $evidence.ci.state -ne 'different-head') { throw 'Stale local/different-head CI evidence was not distinguished.' }
    $s.otherCiHead = $false
    $passed++
    $s.pr = $false
    & $testScript -Action Push -Approve | Out-Null
    if ($s.prBody -notmatch 'Local validation: stale' -or $s.prBody -match 'Matching local workflow validation passed') { throw 'Stale receipt was represented as a pass in PR body.' }
    $passed++
    $s.branch = 'main'
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve } 'No local preparation receipt*'
    $passed++
    $s.main = ('b' * 40)
    $discovery = (& $testScript -Action Discover) -join "`n"
    if ($discovery -notmatch '"next":"sync"' -or $discovery -notmatch '"distance":') { throw 'Unsynchronized main was not explained.' }
    $passed++
    Expect-Failure { & $testScript -Action Release -Version v0.1.0-rc.1 -Godot $editor -Approve } '*requires clean main exactly synchronized*'
    $s.main = $s.head
    $passed++
    Expect-Failure { & $testScript -Action Release -Version '../invalid' -Godot $editor -Approve } 'Specify a version*'
    $passed++
    & $testScript -Action Release -Version v0.1.0-rc.1 -Godot $editor -Approve
    $receipt = Join-Path $fixture '.git\landscaping-releases\v0.1.0-rc.1.json'
    if (-not (Test-Path -LiteralPath $receipt)) { throw 'Verified receipt was not saved.' }
    if (-not $s.draft -or -not $s.tag) { throw 'Preparation did not retain a tagged draft.' }
    $passed++
    $downloadResult = (& $testScript -Action DownloadTest -Version v0.1.0-rc.1 -Approve) -join "`n"
    if ($downloadResult -notmatch 'EDITOR_RESULT:.*executable') { throw 'Verified test download missing.' }
    $passed++
    $downloadData = ($downloadResult -split 'EDITOR_RESULT:')[-1] | ConvertFrom-Json
    if (-not $downloadData.identity -or -not $downloadData.manifest.PSObject.Properties['landscaping-planner.exe']) { throw 'Package identity/manifest missing.' }
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -ExpectedDraft 'wrong-draft' -Approve } 'Approved draft identity changed*'
    if (-not $s.draft) { throw 'Wrong approved draft was published.' }
    $passed++
    $discovery = (& $testScript -Action Discover) -join "`n"
    if ($discovery -notmatch '"next":"publish"') { throw 'Prepared draft was not detected.' }
    $passed++
    $s.multiple = $true
    $secondReceipt = Join-Path (Split-Path -Parent $receipt) 'v0.1.0-rc.2.json'
    $secondData = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    $secondData.version = 'v0.1.0-rc.2'
    $secondData.release_id = 43
    $secondData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $secondReceipt -Encoding UTF8
    $discovery = (& $testScript -Action Discover) -join "`n"
    if ($discovery -notmatch '"next":"drafts"' -or $discovery -notmatch '"choices":\[') { throw 'Multiple drafts did not offer a chooser.' }
    $s.multiple = $false
    Remove-Item -LiteralPath $secondReceipt
    $passed++
    $s.tamper = $true
    Expect-Failure { & $testScript -Action DownloadTest -Version v0.1.0-rc.1 -Approve } 'Uploaded asset hash mismatch*'
    $s.tamper = $false
    $passed++
    $retained = Get-ChildItem -LiteralPath (Split-Path -Parent $receipt) -Directory -Filter 'build-*'
    Remove-Item -LiteralPath $receipt
    $s.dirty = $true
    $s.tamper = $true
    Expect-Failure {
        & $testScript -Action RecoverDraft -Version v0.1.0-rc.1 -BuildDirectory $retained.FullName -Approve
    } 'Uploaded asset hash mismatch*'
    if (Test-Path -LiteralPath $receipt) { throw 'Recovery saved a receipt for tampered assets.' }
    $s.tamper = $false
    $passed++
    & $testScript -Action RecoverDraft -Version v0.1.0-rc.1 -BuildDirectory $retained.FullName -Approve
    if (-not (Test-Path -LiteralPath $receipt) -or -not $s.draft) { throw 'Draft receipt recovery failed.' }
    $s.dirty = $false
    $passed++
    $s.lookupTag = 'v9.9.9'
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve } 'Release lookup returned a different*'
    $s.lookupTag = 'v0.1.0-rc.1'
    $passed++
    $s.tamper = $true
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve } 'Uploaded asset hash mismatch*'
    if (-not $s.draft) { throw 'Tampered assets were published.' }
    $s.tamper = $false
    $passed++
    $phasePath = Join-Path $fixture 'phase.txt'
    $publication = (& $testScript -Action Publish -Version v0.1.0-rc.1 -ExpectedHead $s.head -ExpectedBranch main -ExpectedDraft $downloadData.identity -PhaseFile $phasePath -Approve) -join "`n"
    $publishedResult = (($publication -split 'EDITOR_RESULT:')[-1]) | ConvertFrom-Json
    if ($publishedResult.commit -ne $s.head -or $publishedResult.assets.Count -ne 2 -or -not $publishedResult.published_at -or $publishedResult.backup -ne 'No Forgejo backup') { throw 'Publication receipt incomplete.' }
    if ((Get-Content -LiteralPath $phasePath -Raw) -ne 'Publishing verified draft') { throw 'Live phase reporting missing.' }
    $beforeRead = $s.calls.Count
    $historical = (& $testScript -Action LastPublication) -join "`n"
    $savedPublication = (($historical -split 'EDITOR_RESULT:')[-1]) | ConvertFrom-Json
    if ($savedPublication.release_id -ne $publishedResult.release_id -or $savedPublication.commit -ne $publishedResult.commit) { throw 'Publication receipt did not survive script restart.' }
    if (@($s.calls | Select-Object -Skip $beforeRead | Where-Object { $_ -like 'gh *' -or $_ -like '* fetch *' }).Count) { throw 'Reading historical receipt accessed remote.' }
    $passed++
    if ($s.draft) { throw 'Publish did not change draft state.' }
    $passed++
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve } '*already published*'
    $passed++
    Write-Output "PASS: $passed workflow checks (mocked GitHub/Godot; no network or publication)."
}
finally {
    Remove-Variable -Name LandscapingGithubTest -Scope Global
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
