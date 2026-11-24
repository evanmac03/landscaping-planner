& (Join-Path $PSScriptRoot '..\addons\github_tools\tools\test-package.ps1') @args
if (-not $?) { throw 'Package verification failed.' }
