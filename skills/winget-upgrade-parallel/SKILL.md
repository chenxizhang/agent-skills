---
name: winget-upgrade-parallel
description: Upgrade all installed winget packages in parallel using gsudo for a single UAC elevation. Fetches the list of upgradable packages first, requests one UAC confirmation via gsudo cache, then upgrades all packages concurrently for faster completion. Use on Windows when you want to update everything quickly with minimal interruption.
license: MIT
compatibility: Windows only. Requires winget and gsudo (https://github.com/gerardog/gsudo). Run from PowerShell or Windows Terminal.
metadata:
  author: chenxizhang
  version: "1.0"
---

# Winget Upgrade Parallel

Upgrade all outdated winget packages in parallel with a single UAC elevation prompt, using [gsudo](https://github.com/gerardog/gsudo) to cache elevated credentials so background jobs can run silently without further confirmation.

## When to Use

- You want to update all installed packages on a Windows machine quickly
- You are tired of serial upgrades taking a long time
- You want only one UAC prompt regardless of how many packages need upgrading

## Prerequisites

- **winget** – Windows Package Manager (built into Windows 10/11)
- **gsudo** – Windows sudo equivalent that supports credential caching

Install gsudo if needed:

```powershell
winget install gerardog.gsudo
```

## Usage

```powershell
pwsh scripts/upgrade.ps1
```

## Options

- `-DryRun`: List packages that would be upgraded without performing any upgrades

Example:

```powershell
pwsh scripts/upgrade.ps1 -DryRun
```

## How It Works

1. **Discover**: Runs `winget upgrade` (no elevation needed) to list all packages with available updates.
2. **Elevate once**: Calls `gsudo cache on` which triggers a single UAC prompt and caches the credentials for 10 minutes.
3. **Upgrade in parallel**: Launches a `Start-Job` background job per package. Each job calls `gsudo winget upgrade --id <id> --silent`, reusing the cached credentials without additional prompts.
4. **Report**: Waits for all jobs to finish, turns the cache off, and prints a per-package success/failure summary.

## Example Output

```
Fetching upgradable packages...
Found 4 package(s) to upgrade:
  - Git.Git
  - Microsoft.VisualStudioCode
  - gerardog.gsudo
  - 7zip.7zip

Requesting elevated permissions (confirm once in the UAC prompt)...

Upgrading 4 package(s) in parallel...

========================================
Upgrade Results
========================================
  [✓] Git.Git
  [✓] Microsoft.VisualStudioCode
  [✓] gerardog.gsudo
  [✓] 7zip.7zip

Succeeded: 4
Failed:    0
```

## Handling Failures

If a package upgrade fails (installer error, locked file, etc.) the script will:

1. Mark it as failed in the summary
2. Continue waiting for the remaining jobs
3. Exit with code `1` and list all failed packages

Re-run the script or upgrade the failed package individually:

```powershell
gsudo winget upgrade --id <failed-id> --silent --accept-package-agreements --accept-source-agreements
```
