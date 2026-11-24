[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Output)
$ErrorActionPreference = 'Stop'
$addon = Split-Path -Parent $PSScriptRoot
$destination = [IO.Path]::GetFullPath($Output)
if ([IO.Path]::GetExtension($destination) -ne '.zip') { throw 'Output must be a ZIP path.' }
if ($destination.StartsWith($addon + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Choose output outside the addon folder.' }
if (Test-Path -LiteralPath $destination) { throw 'Output exists; choose a new archive path.' }
$staging = Join-Path ([IO.Path]::GetTempPath()) ('dev-workflow-package-' + [guid]::NewGuid().ToString('N'))
try {
    $target = Join-Path $staging 'addons\github_tools'
    New-Item -ItemType Directory -Path $target | Out-Null
    $files = @('plugin.cfg', 'plugin.gd', 'workflow_dock.gd', 'adviser_panel.gd',
        'README.md', 'dev-workflow.example.json',
        'tools\github.ps1', 'tools\editor-git.ps1', 'tools\test-package.ps1', 'tools\package-addon.ps1')
    foreach ($file in $files) {
        $path = Join-Path $target $file
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $addon $file) -Destination $path
    }
    Compress-Archive -LiteralPath (Join-Path $staging 'addons') -DestinationPath $destination
    Write-Output "Created addon archive: $destination"
    Write-Output "SHA256: $((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant())"
}
finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
