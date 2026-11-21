Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('workflow-sync-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$remote = Join-Path $fixture 'remote.git'
$peer = Join-Path $fixture 'peer'
$git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
function Run-Git {
    & $git @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git operation failed.' }
}
function Expect-Failure($Run, $Pattern) {
    try { & $Run; throw 'Expected failure did not occur.' }
    catch { if ($_.Exception.Message -notlike $Pattern) { throw } }
}
New-Item -ItemType Directory -Path (Join-Path $source 'tools') -Force | Out-Null
try {
    $tokens = $null; $errors = $null
    $path = Join-Path $PSScriptRoot '..\addons\github_tools\tools\github.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\dev-workflow.json') -Destination $source
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join "`n") }
    $native = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Native'}, $false)
    $mock = @'
function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    $s = $global:LandscapingSyncTest
    if ($Command -eq 'gh') {
        if ($Arguments[0] -eq 'api') { return 'fixture-user' }
        if ($Arguments[0] -eq 'pr') {
            return ('[' + (@{headRefOid=$s.head;mergeCommit=@{oid=$s.merge};url='https://example.invalid/pr/1'} | ConvertTo-Json -Compress) + ']')
        }
        throw 'Unexpected GitHub operation.'
    }
    if ($Arguments -contains 'get-url') { return 'https://github.com/evanmac03/landscaping-planner.git' }
    $output = & $s.git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture native Git failed: $LASTEXITCODE" }
    return $output
}
'@
    $original = [IO.File]::ReadAllText($path)
    $rewritten = $original.Substring(0, $native.Extent.StartOffset) + $mock + $original.Substring($native.Extent.EndOffset)
    $tool = Join-Path $source 'tools\github.ps1'
    [IO.File]::WriteAllText($tool, $rewritten)
    Run-Git init --bare -b main $remote
    Run-Git -C $source init -b main
    Run-Git -C $source config user.name 'Workflow fixture'
    Run-Git -C $source config user.email 'test@example.invalid'
    Run-Git -C $source add tools dev-workflow.json
    Run-Git -C $source commit -m Initial
    Run-Git -C $source remote add origin $remote
    Run-Git -C $source push -u origin main
    Run-Git clone $remote $peer
    Run-Git -C $peer config user.name 'Workflow fixture'
    Run-Git -C $peer config user.email 'test@example.invalid'
    Run-Git -C $source switch -c feature/test
    Set-Content -LiteralPath (Join-Path $source 'change.txt') -Value 'Feature content'
    Run-Git -C $source add change.txt
    Run-Git -C $source commit -m Feature
    Run-Git -C $source push -u origin feature/test
    $head = [string](& $git -C $source rev-parse HEAD)
    Run-Git -C $peer fetch origin
    Run-Git -C $peer merge --squash origin/feature/test
    Run-Git -C $peer commit -m 'Squashed feature'
    Run-Git -C $peer push origin main
    $merge = [string](& $git -C $peer rev-parse HEAD)
    $global:LandscapingSyncTest = @{git=$git;head=$head;merge=$merge}
    $parameters = @{Action='Synchronize';ExpectedHead=$head;ExpectedBranch='feature/test';Approve=$true}
    Set-Content -LiteralPath (Join-Path $source 'dirty.txt') -Value 'Untracked work'
    Expect-Failure { & $tool @parameters } 'Commit or deliberately move*'
    Remove-Item -LiteralPath (Join-Path $source 'dirty.txt')
    $global:LandscapingSyncTest.head = 'wrong-head'
    Expect-Failure { & $tool @parameters } 'No unique merged PR*'
    $global:LandscapingSyncTest.head = $head
    $mainBefore = [string](& $git -C $source rev-parse main)
    Run-Git -C $source update-ref refs/heads/main $head $mainBefore
    Expect-Failure { & $tool @parameters } 'Local main has commits absent*'
    if ([string](& $git -C $source branch --show-current) -ne 'feature/test') { throw 'Rejected synchronization switched branches.' }
    Run-Git -C $source update-ref refs/heads/main $mainBefore $head
    & $tool @parameters | Out-Null
    if ([string](& $git -C $source branch --show-current) -ne 'main' -or [string](& $git -C $source rev-parse HEAD) -ne $merge) {
        throw 'Exact merged main was not synchronized.'
    }
    Run-Git -C $source show-ref --verify refs/heads/feature/test
    Run-Git -C $source switch feature/test
    & $tool @parameters -CleanupBranch yes | Out-Null
    $branches = @(& $git -C $source branch --format='%(refname:short)')
    if ('feature/test' -in $branches) { throw 'Explicit squash-merged branch cleanup failed.' }
    if (@(& $git -C $source status --porcelain).Count) { throw 'Synchronization left dirty files.' }
    Write-Output 'PASS: real disposable squash-merge synchronization, exact-head/dirty guards and separately selected branch cleanup (no network).'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
    Remove-Variable -Name LandscapingSyncTest -Scope Global -ErrorAction SilentlyContinue
}
