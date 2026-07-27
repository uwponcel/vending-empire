<#
.SYNOPSIS
    Type-checks the project with luau-lsp. Required gate, run before any change is done.

.DESCRIPTION
    `--!strict` at the top of a file does nothing on its own. Nothing in the build reads it
    unless an analyzer runs, and `selene` is a linter, not a type checker. This script is
    what makes the strict annotations mean anything.

    Depends on the artifacts from ./scripts/lsp-setup.ps1 and fails with a pointer to it if
    they are missing, rather than silently analyzing without Roblox types and reporting a
    flood of "unknown global" noise.

    src/server/Packages is excluded. It is vendored third-party code we are not allowed to
    modify, so its diagnostics would be permanent unfixable noise.

.PARAMETER Refresh
    Regenerate the sourcemap first. Needed after adding, moving or renaming files, since a
    stale sourcemap reports requires that resolve fine at runtime as unknown.
#>

[CmdletBinding()]
param(
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$definitions = Join-Path $repoRoot 'globalTypes.None.d.luau'
$sourcemap = Join-Path $repoRoot 'sourcemap.json'

if (-not (Test-Path $definitions)) {
    Write-Error "globalTypes.None.d.luau is missing. Run ./scripts/lsp-setup.ps1 first."
}

if ($Refresh -or -not (Test-Path $sourcemap)) {
    & rojo sourcemap default.project.json --output sourcemap.json --include-non-scripts | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "rojo sourcemap failed with exit code $LASTEXITCODE" }
}

# --platform roblox turns on DataModel-aware checking. Without it the sourcemap is ignored.
& luau-lsp analyze `
    --platform roblox `
    --definitions=$definitions `
    --sourcemap=$sourcemap `
    --ignore='**/Packages/**' `
    src/ tests/

$analyzeExit = $LASTEXITCODE

if ($analyzeExit -eq 0) {
    Write-Host 'Type check passed.' -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Host 'Type check failed.' -ForegroundColor Red
    Write-Host 'If the errors are about unknown requires on files you just added, the'
    Write-Host 'sourcemap is stale: re-run with -Refresh.'
}

exit $analyzeExit
