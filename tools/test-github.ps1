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
                $inputDir = Join-Path $s.root 'archive-input'
                New-Item -ItemType Directory -Path $inputDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $inputDir 'project.godot') -Value 'config_version=5'
                Compress-Archive -Path (Join-Path $inputDir '*') -DestinationPath $output
                return
            }
        }
    }
    elseif ($Command -eq 'gh') {
        $key = $Arguments -join ' '
        switch -Wildcard ($key) {
            'api user --jq .login' { return 'test-user' }
            'pr list *' { return '[]' }
            'pr create *' { return 'https://example.invalid/pr/1' }
            'api --paginate *' { return }
            'release create *' {
                $s.assets = @($Arguments | Where-Object { $_ -match '\.(zip|sha256)$' })
                $s.draft = $true
                return
            }
            'api repos/*/releases/tags/*' {
                return (@{
                    id = 42; draft = $s.draft; tag_name = 'v0.1.0-rc.1'
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
            'api repos/*/releases/42' {
                return (@{ draft = $s.draft; html_url = 'https://example.invalid/release/42' } | ConvertTo-Json)
            }
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
$editor = Join-Path $fixture 'fake-godot.exe'
Set-Content -LiteralPath $editor -Value 'not executed'
$global:LandscapingGithubTest = @{
    root = $fixture; editor = $editor; branch = 'feature/test'; dirty = $false
    head = ('a' * 40); main = ('a' * 40); behind = 0; tag = $false
    draft = $true; assets = @(); tamper = $false
    calls = [Collections.Generic.List[string]]::new()
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
    $s.dirty = $true
    Expect-Failure { & $testScript -Action Push -Approve } 'Commit or deliberately move*'
    $s.dirty = $false
    $passed++
    Expect-Failure { & $testScript -Action Push } '*requires explicit -Approve*'
    $passed++
    $s.branch = 'main'
    Expect-Failure { & $testScript -Action Push -Approve } 'Push requires a feature branch*'
    $passed++
    $s.branch = 'feature/test'
    $s.behind = 1
    Expect-Failure { & $testScript -Action Push -Approve } 'Remote branch has commits missing*'
    $s.behind = 0
    $passed++
    & $testScript -Action Push -Approve
    if (-not @($s.calls | Where-Object { $_ -like 'gh pr create *' }).Count) { throw 'PR was not created.' }
    $passed++
    $s.branch = 'main'
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve } 'No local preparation receipt*'
    $passed++
    $s.main = ('b' * 40)
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
    $s.tamper = $true
    Expect-Failure { & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve } 'Uploaded asset hash mismatch*'
    if (-not $s.draft) { throw 'Tampered assets were published.' }
    $s.tamper = $false
    $passed++
    & $testScript -Action Publish -Version v0.1.0-rc.1 -Approve
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
