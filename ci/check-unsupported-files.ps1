# =============================================================================
# CD - guard stage: fail the master build if the merge contains file types the
# pipeline doesn't know how to handle (e.g. a new language like ALGOL that
# isn't in MCP_EXTENSIONS yet).
#
# Without this check, deploy.ps1 / compile-wfl.ps1 / syntaxcheck-wfl.ps1 /
# backup.ps1 all independently filter unknown extensions out of the diff and
# exit 0 ("nothing to do"), so the build reports SUCCESS even though a file
# was merged to master and never touched the MCP.
#
# Runs on the master build, BEFORE Backup, right after checkout.
# =============================================================================
$ErrorActionPreference = 'Stop'

# --- extensions the pipeline actively handles --------------------------------
$mcpExtensions = if ($env:MCP_EXTENSIONS) { $env:MCP_EXTENSIONS } else { 'c74_m c85_m das_m dat_m wfl_m' }
$knownExts = ($mcpExtensions -split '\s+' | Where-Object { $_ })

# --- paths/files that are expected to change and are NOT MCP source ---------
# Adjust this list to match whatever non-MCP files legitimately live in the
# repo (build metadata, docs, the pipeline's own scripts, etc.).
$ignorePatterns = @(
    '^Jenkinsfile$',
    '^ci/.*',
    '^\.git.*',
    '^README.*',
    '.*\.md$',
    '.*\.txt$',
    '.*\.sln$',
    '.*\.gitignore$',
    '.*\.gitattributes$'
)

# --- all files changed by this merge -----------------------------------------
# HEAD^ = previous master tip, HEAD = merge result (same convention as deploy.ps1).
$changed = & git --no-pager diff --name-only HEAD^ HEAD
if (-not $changed) {
    Write-Host "No files changed in this merge."
    exit 0
}

$unsupported = @()
foreach ($raw in $changed) {
    $f = $raw.Trim()
    if (-not $f) { continue }

    $ignored = $false
    foreach ($pat in $ignorePatterns) {
        if ($f -imatch $pat) { $ignored = $true; break }
    }
    if ($ignored) { continue }

    $ext = ($f -split '\.')[-1]
    if ($knownExts -icontains $ext) { continue }

    $unsupported += $f
}

if ($unsupported.Count -gt 0) {
    Write-Host "=================================================================="
    Write-Host " ERROR: unsupported file type(s) detected in this merge:"
    Write-Host "=================================================================="
    foreach ($f in $unsupported) { Write-Host "   $f" }
    Write-Host ""
    Write-Host "These files do not match any known MCP extension ($($knownExts -join ', '))"
    Write-Host "and are not in the ignore list. The pipeline will NOT silently skip them."
    Write-Host "Either:"
    Write-Host "  1. Add the extension to MCP_EXTENSIONS in the Jenkinsfile if it should be deployed, or"
    Write-Host "  2. Add the path/pattern to the ignore list in ci/check-unsupported-files.ps1 if it's not MCP source."
    exit 1
}

Write-Host "All changed files match a known MCP extension or the ignore list. Proceeding."