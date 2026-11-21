Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('package-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$exe = Join-Path $fixture 'landscaping-planner.exe'
Set-Content -LiteralPath $exe -Value 'Mock executable; never launched'
$global:LandscapingPackageTest = @{mode='passed';launched=0;killed=$false;exe=$exe;folder=$fixture}
function Start-Process {
    param($FilePath, $WorkingDirectory, $ArgumentList, [switch]$PassThru)
    $s = $global:LandscapingPackageTest
    $s.launched++
    if ($FilePath -ne $s.exe -or $WorkingDirectory -ne $s.folder -or '--path' -in $ArgumentList -or '--headless' -notin $ArgumentList) {
        throw 'Unsafe packaged process arguments.'
    }
    $log = $ArgumentList[-1].Trim('"')
    if ($s.mode -ne 'missing-log') {
        Set-Content -LiteralPath $log -Value $(if ($s.mode -eq 'error-log') {'Godot Engine; SCRIPT ERROR: fixture'} else {'Godot Engine fixture'})
    }
    if ($s.mode -eq 'changed') { Add-Content -LiteralPath $s.exe -Value 'Changed during startup' }
    $p = [pscustomobject]@{ExitCode=$(if ($s.mode -eq 'bad-exit') {1} else {0})}
    $p | Add-Member ScriptMethod WaitForExit { param($milliseconds) return ($global:LandscapingPackageTest.mode -ne 'timeout') }
    $p | Add-Member ScriptMethod Kill { $global:LandscapingPackageTest.killed = $true }
    $p | Add-Member ScriptMethod Dispose {}
    return $p
}
try {
    $data = @{folder=$fixture;executable=$exe;version='v0.0.0-test';commit='fixture';identity='draft';
        manifest=@{'landscaping-planner.exe'=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash}}
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Depth 5 -Compress)))
    $tool = Join-Path $PSScriptRoot '..\addons\github_tools\tools\test-package.ps1'
    $passed = (& $tool -Package $encoded) -join "`n"
    if ($passed -notmatch '"state":"passed"') { throw 'Clean smoke test result missing.' }
    foreach ($mode in @('bad-exit','missing-log','error-log','timeout','changed')) {
        $global:LandscapingPackageTest.mode = $mode
        $failed = $false
        try { & $tool -Package $encoded | Out-Null } catch { $failed = $true }
        if (-not $failed) { throw "Smoke check accepted $mode." }
    }
    if (-not $global:LandscapingPackageTest.killed) { throw 'Timed-out smoke process was not stopped.' }
    $before = $global:LandscapingPackageTest.launched
    $failed = $false
    try { & $tool -Package $encoded | Out-Null } catch { $failed = $true }
    if (-not $failed -or $global:LandscapingPackageTest.launched -ne $before) { throw 'Altered package was launched.' }
    $generic = Join-Path $fixture 'another-game.exe'
    Move-Item -LiteralPath $exe -Destination $generic
    $global:LandscapingPackageTest.exe = $generic
    $global:LandscapingPackageTest.mode = 'passed'
    $data.executable = $generic
    $data.executable_name = 'another-game.exe'
    $data.manifest = @{'another-game.exe'=(Get-FileHash -LiteralPath $generic -Algorithm SHA256).Hash}
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Depth 5 -Compress)))
    if (((& $tool -Package $encoded) -join "`n") -notmatch '"state":"passed"') { throw 'Configured executable smoke test failed.' }
    $data.executable_name = '..\outside.exe'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Depth 5 -Compress)))
    $failed = $false
    try { & $tool -Package $encoded | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Unsafe executable name was accepted.' }
    Write-Output 'PASS: 9 package smoke checks (mocked process; manifest, configured executable, arguments, exit, log, timeout and post-run integrity).'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
    Remove-Variable -Name LandscapingPackageTest -Scope Global
}
