#!/usr/bin/env pwsh
#
# Upgrade all winget packages in parallel using gsudo for a single UAC elevation.
# Windows only. Requires: winget, gsudo (https://github.com/gerardog/gsudo)
#

param(
    [switch]$DryRun
)

# --- Check prerequisites ---
foreach ($tool in @('winget', 'gsudo')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "$tool not found. Install gsudo with: winget install gerardog.gsudo"
        exit 1
    }
}

# --- Step 1: List upgradable packages (no elevation needed) ---
Write-Host "Fetching upgradable packages..."
$rawLines = (winget upgrade 2>&1) -split "`r?`n"

# Locate the separator line (e.g. "---- ---- ----")
$sepIdx = -1
for ($i = 0; $i -lt $rawLines.Count; $i++) {
    if ($rawLines[$i] -match '^-') {
        $sepIdx = $i
        break
    }
}

$packageIds = @()
if ($sepIdx -ge 1) {
    $header   = $rawLines[$sepIdx - 1]
    $idStart  = $header.IndexOf('Id')
    $verStart = $header.IndexOf('Version')

    if ($idStart -ge 0 -and $verStart -gt $idStart) {
        for ($i = $sepIdx + 1; $i -lt $rawLines.Count; $i++) {
            $line = $rawLines[$i]
            # Stop at the trailing summary line ("N upgrades available") or blank line
            if ($line.Trim() -eq '' -or $line -match '^\d+ upgrade') { break }
            if ($line.Length -ge $verStart) {
                $id = $line.Substring($idStart, $verStart - $idStart).Trim()
                if ($id) { $packageIds += $id }
            }
        }
    }
}

if ($packageIds.Count -eq 0) {
    Write-Host "All packages are up to date."
    exit 0
}

Write-Host "Found $($packageIds.Count) package(s) to upgrade:"
$packageIds | ForEach-Object { Write-Host "  - $_" }

if ($DryRun) {
    Write-Host ""
    Write-Host "(Dry run - no upgrades performed)"
    exit 0
}

# --- Step 2: Cache elevated credentials (single UAC confirmation) ---
Write-Host ""
Write-Host "Requesting elevated permissions (confirm once in the UAC prompt)..."
gsudo cache on --duration 10  # cache is valid for 10 minutes

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to obtain elevated permissions."
    exit 1
}

# --- Step 3: Upgrade packages in parallel ---
# Each job calls gsudo, which reuses the cached credentials without additional prompts.
Write-Host ""
Write-Host "Upgrading $($packageIds.Count) package(s) in parallel..."

$jobs = $packageIds | ForEach-Object {
    $id = $_
    Start-Job -ScriptBlock {
        param($pkgId)
        $out = gsudo winget upgrade --id $pkgId --silent `
            --accept-package-agreements --accept-source-agreements 2>&1
        $exitCode = $LASTEXITCODE
        [PSCustomObject]@{ Id = $pkgId; Output = ($out | Out-String); ExitCode = $exitCode }
    } -ArgumentList $id
}

# --- Step 4: Wait for all jobs ---
$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

# Turn off credential cache
gsudo cache off 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not disable gsudo cache; it will expire automatically in 10 minutes."
}

# --- Step 5: Report results ---
Write-Host ""
Write-Host "========================================"
Write-Host "Upgrade Results"
Write-Host "========================================"

$succeeded = 0
$failed    = 0
$failedIds = @()

foreach ($r in $results) {
    if ($r.ExitCode -eq 0) {
        Write-Host "  [✓] $($r.Id)"
        $succeeded++
    } else {
        Write-Host "  [✗] $($r.Id)"
        $failed++
        $failedIds += $r.Id
    }
}

Write-Host ""
Write-Host "Succeeded: $succeeded"
Write-Host "Failed:    $failed"

if ($failedIds.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed packages:"
    $failedIds | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

exit 0
