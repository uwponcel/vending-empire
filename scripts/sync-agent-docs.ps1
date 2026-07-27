<#
.SYNOPSIS
    Keeps AGENTS.md byte-identical to CLAUDE.md.

.DESCRIPTION
    Different coding agents look for different filenames. Rather than maintain two
    documents that drift apart, CLAUDE.md is the source of truth and AGENTS.md is
    generated from it.

    Run with no arguments to sync. Run with -Check in CI to fail on drift.

    The script refuses to overwrite AGENTS.md when AGENTS.md is the newer file and the
    two differ, because that means edits were made to the generated copy and blindly
    syncing would throw them away. Use -From Agents to promote those edits back, or
    -Force to discard them.

.PARAMETER Check
    Compare only. Exit 0 if identical, 1 if they differ. Writes nothing.

.PARAMETER From
    Which file is the source. Defaults to Claude.

.PARAMETER Force
    Overwrite the destination even when it is newer and differs.

.EXAMPLE
    ./scripts/sync-agent-docs.ps1
    Regenerates AGENTS.md from CLAUDE.md.

.EXAMPLE
    ./scripts/sync-agent-docs.ps1 -Check
    Verifies the two are in sync. Used by CI.

.EXAMPLE
    ./scripts/sync-agent-docs.ps1 -From Agents
    Promotes edits made in AGENTS.md back into CLAUDE.md.
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [ValidateSet('Claude', 'Agents')]
    [string]$From = 'Claude',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$claudePath = Join-Path $repoRoot 'CLAUDE.md'
$agentsPath = Join-Path $repoRoot 'AGENTS.md'

function Read-Normalized {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    # Read as raw text and normalize to LF. .gitattributes pins LF in the repository,
    # but an editor can still leave CRLF behind locally, and that must not read as
    # drift when the actual content matches.
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { return '' }
    return $raw -replace "`r`n", "`n"
}

if (-not (Test-Path -LiteralPath $claudePath)) {
    Write-Error "CLAUDE.md not found at $claudePath"
}

$claudeText = Read-Normalized $claudePath
$agentsText = Read-Normalized $agentsPath
$inSync = ($null -ne $agentsText) -and ($claudeText -eq $agentsText)

if ($Check) {
    if ($inSync) {
        Write-Host 'CLAUDE.md and AGENTS.md are in sync.'
        exit 0
    }

    if ($null -eq $agentsText) {
        Write-Host 'AGENTS.md is missing.' -ForegroundColor Red
    }
    else {
        Write-Host 'CLAUDE.md and AGENTS.md have drifted.' -ForegroundColor Red
    }
    Write-Host 'Run ./scripts/sync-agent-docs.ps1 to regenerate.'
    exit 1
}

if ($inSync) {
    Write-Host 'Already in sync, nothing to do.'
    exit 0
}

if ($From -eq 'Claude') {
    $sourcePath, $sourceText = $claudePath, $claudeText
    $destPath = $agentsPath
}
else {
    if ($null -eq $agentsText) { Write-Error "Cannot sync from AGENTS.md: it does not exist." }
    $sourcePath, $sourceText = $agentsPath, $agentsText
    $destPath = $claudePath
}

# Guard against discarding edits made to the destination.
if (-not $Force -and (Test-Path -LiteralPath $destPath)) {
    $sourceTime = (Get-Item -LiteralPath $sourcePath).LastWriteTimeUtc
    $destTime = (Get-Item -LiteralPath $destPath).LastWriteTimeUtc

    if ($destTime -gt $sourceTime) {
        Write-Host ''
        Write-Host "Refusing to overwrite $(Split-Path -Leaf $destPath): it is newer than $(Split-Path -Leaf $sourcePath) and the two differ." -ForegroundColor Yellow
        Write-Host 'That usually means the generated copy was edited directly.'
        Write-Host ''
        Write-Host '  To keep those edits:     ./scripts/sync-agent-docs.ps1 -From Agents'
        Write-Host '  To discard those edits:  ./scripts/sync-agent-docs.ps1 -Force'
        Write-Host ''
        exit 1
    }
}

# Write LF explicitly. Set-Content would use the platform default and reintroduce CRLF
# on Windows, which stylua does not police for Markdown and which would show up as a
# whole-file diff on the next commit.
[System.IO.File]::WriteAllText($destPath, $sourceText, [System.Text.UTF8Encoding]::new($false))

Write-Host "Wrote $(Split-Path -Leaf $destPath) from $(Split-Path -Leaf $sourcePath)."
