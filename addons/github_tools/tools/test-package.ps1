[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Package)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Package)) | ConvertFrom-Json
$folder = [IO.Path]::GetFullPath($data.folder)
$executableName = if ($data.PSObject.Properties['executable_name']) { [string]$data.executable_name } else { 'landscaping-planner.exe' }
if ($executableName -notmatch '^[a-z0-9][a-z0-9-]*\.exe$') { throw 'Invalid package executable name.' }
$exe = Join-Path $folder $executableName
if ([IO.Path]::GetFullPath($data.executable) -ne $exe) { throw 'Unexpected package executable.' }
function Assert-Package {
    $files = @(Get-ChildItem -LiteralPath $folder -Recurse -File)
    $properties = @($data.manifest.PSObject.Properties)
    if (-not $files.Count -or $files.Count -ne $properties.Count) { throw 'Package file list changed. Download and test again.' }
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($folder.Length + 1).Replace('\', '/')
        $expected = $data.manifest.PSObject.Properties[$relative]
        if (-not $expected -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $expected.Value) {
            throw "Package integrity changed: $relative. Download and test again."
        }
    }
}
Assert-Package
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('landscaping-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$process = $null
try {
    $log = Join-Path $temporary 'startup.log'
    $process = Start-Process -FilePath $exe -WorkingDirectory $folder -ArgumentList @(
        '--headless', '--quit-after', '120', '--log-file', "`"$log`""
    ) -PassThru
    if (-not $process.WaitForExit(30000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'Headless package startup exceeded 30 seconds; only the smoke-test process was stopped.'
    }
    if ($process.ExitCode -ne 0) { throw "Packaged executable exited with code $($process.ExitCode)." }
    if (-not (Test-Path -LiteralPath $log)) { throw 'Packaged executable produced no startup log; no pass claimed.' }
    $text = Get-Content -LiteralPath $log -Raw
    if ($text -notmatch 'Godot Engine' -or $text -match '(?m)(?:SCRIPT ERROR:|ERROR:)') {
        throw "Packaged startup log did not pass cleanly:`n$text"
    }
    Assert-Package
    Write-Output ('EDITOR_RESULT:' + (@{state='passed';version=$data.version;commit=$data.commit;identity=$data.identity;
        verification='Package manifest and headless process exit/startup log verified; not an interactive playtest'} | ConvertTo-Json -Compress))
}
finally {
    if ($null -ne $process) { $process.Dispose() }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
