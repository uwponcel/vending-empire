<#
.SYNOPSIS
    Generates the artifacts luau-lsp needs to type-check this project.

.DESCRIPTION
    Three things are required before `luau-lsp analyze` (or an editor's Luau language
    server) can understand the code, and none of them are checked into git because all
    three are generated:

      globalTypes.None.d.luau   Roblox API types. Without it, `Player`, `CFrame`,
                                `Vector3`, `task` and `warn` are all unknown. The "None"
                                variant is the game-script security level, so reaching for
                                a plugin-only API becomes a type error rather than
                                something that fails at runtime.

      sourcemap.json            Maps the Rojo tree onto the DataModel, so
                                `script.Parent.Services.DataService` resolves to a real
                                module instead of an opaque Instance.

      ~/.lune/.typedefs/        Lune's own types, for everything under tests/. The
                                `@lune/...` requires in the suites are Lune aliases, not
                                paths, so without these the analyzer looks for a literal
                                `tests/@lune/process.lua`.

    Versions are read from rokit.toml rather than hardcoded, so the definitions always
    match the pinned luau-lsp and the typedefs always match the pinned lune.

    Re-run this after changing rokit.toml, or after adding, moving or renaming any file
    (the sourcemap goes stale).

.PARAMETER SkipDownload
    Reuse an existing globalTypes file instead of fetching it. Useful offline.
#>

[CmdletBinding()]
param(
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Get-PinnedVersion {
    param([string]$ToolKey)

    $line = Select-String -Path (Join-Path $repoRoot 'rokit.toml') -Pattern "^\s*$ToolKey\s*=" |
        Select-Object -First 1
    if (-not $line) { Write-Error "No '$ToolKey' entry in rokit.toml" }

    if ($line.Line -notmatch '@([0-9]+\.[0-9]+\.[0-9]+)') {
        Write-Error "Could not parse a version out of: $($line.Line.Trim())"
    }
    return $Matches[1]
}

$luauLspVersion = Get-PinnedVersion 'luau-lsp'
$luneVersion = Get-PinnedVersion 'lune'

Write-Host "luau-lsp $luauLspVersion, lune $luneVersion (from rokit.toml)"

# 1. Roblox API type definitions, pinned to the same tag as the analyzer that reads them.
$definitions = Join-Path $repoRoot 'globalTypes.None.d.luau'
if ($SkipDownload -and (Test-Path $definitions)) {
    Write-Host 'Reusing existing globalTypes.None.d.luau'
}
else {
    $url = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$luauLspVersion/scripts/globalTypes.None.d.luau"
    Write-Host "Downloading Roblox definitions from $url"
    # Invoke-WebRequest rather than curl.exe: this script runs on Windows locally and on
    # Linux in CI, and `curl.exe` only exists on the former. CI caught that.
    Invoke-WebRequest -Uri $url -OutFile $definitions -MaximumRedirection 5
}
Write-Host "  globalTypes.None.d.luau  $((Get-Item $definitions).Length) bytes"

# 2. DataModel sourcemap. --include-non-scripts so folders and parts appear too.
Write-Host 'Generating sourcemap'
& rojo sourcemap default.project.json --output sourcemap.json --include-non-scripts
if ($LASTEXITCODE -ne 0) { Write-Error "rojo sourcemap failed with exit code $LASTEXITCODE" }

# 3. Lune typedefs. This also writes the `lune` alias into .luaurc, which is why that
#    alias is committed: it has to match the version installed here.
Write-Host 'Generating Lune type definitions'
& lune setup
if ($LASTEXITCODE -ne 0) { Write-Error "lune setup failed with exit code $LASTEXITCODE" }

$typedefs = Join-Path $HOME ".lune/.typedefs/$luneVersion"
if (-not (Test-Path $typedefs)) {
    Write-Warning "Expected typedefs at $typedefs but they are not there. Check that the lune alias in .luaurc matches the pinned version."
}

Write-Host ''
Write-Host 'Done. Type-check with:' -ForegroundColor Green
Write-Host '  ./scripts/analyze.ps1'
