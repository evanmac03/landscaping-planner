& (Join-Path $PSScriptRoot '..\addons\github_tools\tools\editor-git.ps1') @args
if (-not $?) { throw 'Dev workflow Git operation failed. Inspect output before retrying.' }
