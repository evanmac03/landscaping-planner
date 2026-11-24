& (Join-Path $PSScriptRoot '..\addons\github_tools\tools\github.ps1') @args
if (-not $?) { throw 'Dev workflow operation failed. Inspect output before retrying.' }
