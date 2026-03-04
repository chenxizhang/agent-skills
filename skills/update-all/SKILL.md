---
name: update-all
description: Update all system packages and tools in parallel — winget (Windows), Windows Update (Windows), npm globals, agent skills, and apt (Linux). Each update category runs as an independent parallel task, with winget packages also upgraded in parallel internally. Use when you want to bring everything up to date quickly.
license: MIT
metadata:
  author: chenxizhang
  version: "2.0"
---

# Update All

Update all system packages and developer tools in parallel — bringing everything up to date in one command.

## Update Tasks

| Task | When to Run | Execution Mode |
|------|-------------|----------------|
| **winget upgrade** | Windows only | ✅ Each package upgraded in parallel |
| **Windows Update** | Windows only | Serial (scan → download → install → monitor) |
| **npm update -g** | If Node.js is installed | Single command |
| **npx skills update -g -y** | If Node.js is installed | Single command |
| **sudo apt update → sudo apt upgrade -y** | Linux only | ⚠️ Serial (update first, then upgrade) |

**All tasks are completely independent and MUST run in parallel. However, some tasks have internal serial steps (apt, Windows Update) — those internal steps must run in order.**

## Strict Execution Flow

**Do NOT use any scripts. Do NOT skip or merge phases. Execute each phase in order.**

⛔ **ABSOLUTELY FORBIDDEN on all platforms:**
- Do NOT create temporary script files (`.ps1`, `.sh`, `.bat`, `.cmd`, or any other script file)
- Do NOT use `Out-File`, `Set-Content`, `>`, or any file-writing mechanism to create scripts
- ALL commands must be run directly via the agent's tool calls (powershell, write_powershell, bash, etc.)
- If you find yourself wanting to create a script, STOP — run the commands directly instead

---

### Phase 1: Environment Detection (MANDATORY — must display results before proceeding)

Detect and **explicitly display** the following before doing anything else:

1. **Operating System**:
   - Windows: `[System.Environment]::OSVersion` or `$env:OS`
   - macOS/Linux: `uname -s` and `cat /etc/os-release 2>/dev/null | head -3`
2. **Shell environment**:
   - PowerShell: `$PSVersionTable.PSVersion`
   - bash/zsh: `echo $SHELL`
3. **Agent identity**: Identify which agent is running (Claude Code, GitHub Copilot CLI, Cursor, etc.)
4. **Available tools** — check which of the following are installed:
   - `winget`: `Get-Command winget -ErrorAction SilentlyContinue` (Windows)
   - `node`/`npm`: `Get-Command node -ErrorAction SilentlyContinue` or `which node`
   - `apt`: `which apt` (Linux)
   - `PSWindowsUpdate` module (Windows): `Get-Module -ListAvailable PSWindowsUpdate`
5. **sudo status** (Windows only, required for winget and Windows Update):
   - Check if sudo exists: `Get-Command sudo -ErrorAction SilentlyContinue`
   - Check sudo mode: `sudo config`
   - **If sudo is not installed or not in Inline/normal mode**: Try to auto-fix BEFORE giving up:
     1. Run `sudo sudo config --enable normal` — this may trigger a one-time UAC confirmation
     2. Re-check: `sudo config` — verify mode is now `Inline` or `normal`
     3. If auto-fix succeeded, proceed normally
     4. If auto-fix failed (e.g., user declined UAC, or command not found), THEN display a warning and skip elevated tasks (winget, Windows Update). Other tasks (npm, skills) can still proceed.
   - **Key principle: try to fix, only skip if fix fails**

**Display the detection results clearly**, for example:
```
Environment Detection:
  OS:      Windows 11 Pro (10.0.22631)
  Shell:   PowerShell 7.4
  Agent:   GitHub Copilot CLI
  winget:  ✅ available
  node:    ✅ v22.0.0
  npm:     ✅ v10.8.0
  apt:     ❌ not available (Windows)
  sudo:    ✅ v1.0.1, Inline mode
  PSWindowsUpdate: ✅ v2.2.1.5 installed

Applicable update tasks:
  1. winget upgrade (parallel per package)
  2. Windows Update (scan → install → monitor)
  3. npm update -g
  4. npx skills update -g -y
```

Another example (Linux):
```
Environment Detection:
  OS:      Ubuntu 24.04 LTS
  Shell:   bash 5.2
  Agent:   Claude Code
  winget:  ❌ not available (Linux)
  node:    ✅ v22.0.0
  npm:     ✅ v10.8.0
  apt:     ✅ available
  sudo:    ✅ available (Linux native)

Applicable update tasks:
  1. sudo apt update → sudo apt upgrade -y (serial)
  2. npm update -g
  3. npx skills update -g -y
```

**CRITICAL: If on Windows and sudo is missing or not in Inline/normal mode, first try `sudo sudo config --enable normal` to auto-fix. Only if auto-fix fails should you skip winget and Windows Update tasks. Other tasks (npm, skills) can always proceed.**

---

### Phase 2: Plan (generate environment-specific parallel execution plan)

Based on Phase 1 results, build the task list and parallel strategy.

#### Task Definitions

**Task A: winget upgrade (Windows only, requires elevation)**

1. Run `winget upgrade` (no elevation) to list all upgradable packages
2. Parse the output to extract package IDs
3. If no packages to upgrade, skip
4. Upgrade **each package individually in parallel** (see Parallel Strategy for agent-specific approach)
5. Collect results per package

⚠️ **CRITICAL — per-package parallel upgrade rules:**
- **DO**: `sudo winget upgrade --id <specific-package-id> --silent --accept-package-agreements --accept-source-agreements` for EACH package, run in parallel
- **DO NOT**: `winget upgrade --all` or `sudo winget upgrade --all` — this runs serially and defeats the purpose of parallelism
- Each package upgrade is independent — run them ALL in parallel, never sequentially

**Task B: npm update -g (if Node.js installed)**

Single command:
- Windows PowerShell: `npm update -g 2>&1`
- bash/zsh: `npm update -g 2>&1`

**Task C: npx skills update -g -y (if Node.js installed)**

Single command:
- All platforms: `npx skills update -g -y 2>&1`

**Task D: sudo apt update → sudo apt upgrade (Linux only, MUST be serial)**

⚠️ **These two commands MUST run serially, NOT combined with `&&` in a single shell call.** Run them as two separate sequential commands so the agent can observe and report each step independently.

1. Run `sudo apt update -y 2>&1` — refresh package index
   - Wait for completion, capture and display output
   - If this fails, STOP — do not proceed to upgrade
2. Run `sudo apt upgrade -y 2>&1` — upgrade all packages
   - Wait for completion, capture and display output
   - Report number of upgraded, newly installed, held back packages

This serial approach allows the agent to:
- Detect and report failures at each step
- Show the user what's being updated before upgrading
- Avoid running upgrade with a stale or broken package index

**Task E: Windows Update (Windows only, requires elevation)**

Uses PSWindowsUpdate to scan, install, and monitor Windows Update. Runs serially (scan → install → reboot check). See Parallel Strategy for how elevation is handled per agent.

**WU Steps (run inside an elevated context):**

1. Ensure PSWindowsUpdate module:
   ```powershell
   if (-not (Get-Module -ListAvailable PSWindowsUpdate)) { Install-Module -Name PSWindowsUpdate -Force }; Import-Module PSWindowsUpdate
   ```
2. Scan: `Get-WindowsUpdate` — if no updates, report "up to date" and skip
3. Install: `Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose` — **never auto-reboot**
4. Check reboot: `Get-WURebootStatus` — inform user if reboot needed

⚠️ Windows Update can take a long time (minutes to hours) — use generous timeouts and poll for progress.

#### Parallel Strategy

Windows sudo caches credentials **per console session**. This determines how many UAC prompts the user sees:

| Agent | Shell Model | sudo Behavior |
|-------|-------------|---------------|
| **GitHub Copilot CLI** | Persistent shell session | ✅ Cached — one UAC prompt for all `sudo` calls |
| **Claude Code** | New process per command | ❌ Not cached — one UAC prompt per `sudo` call |
| **Other agents** | Varies | Test with two `sudo` calls to determine behavior |

---

**Strategy for GitHub Copilot CLI: parallel tool calls (one UAC prompt total)**

sudo credential caching means all `sudo` calls share one UAC prompt. Use the agent's native parallel tool calls:

```
parallel:
  Task A: multiple parallel `sudo winget upgrade --id <pkg> ...` tool calls
  Task B: npm update -g
  Task C: npx skills update -g -y
  Task E: sequential sudo calls for WU (scan → install → reboot check)
```

All tasks run in parallel. Each `sudo` reuses the cached credential. **One UAC prompt for everything.**

---

**Strategy for Claude Code: ONE shared elevated session (one UAC prompt total)**

Since Claude Code spawns a new process per command, open **one `sudo pwsh` async session** and run ALL elevated tasks (winget + Windows Update) inside it. Non-elevated tasks (npm, skills) run in parallel outside.

```
┌─ powershell(command: "sudo pwsh -NoProfile", mode: "async") ──── ONE UAC prompt
│
│  ── winget (parallel via PowerShell Jobs) ──
│  $packages = @("<pkg1>", "<pkg2>", "<pkg3>")
│  $jobs = $packages | ForEach-Object {
│      Start-Job -ScriptBlock {
│          param($id)
│          winget upgrade --id $id --silent --accept-package-agreements --accept-source-agreements 2>&1
│      } -ArgumentList $_
│  }
│  $jobs | Wait-Job | Receive-Job
│  $jobs | Remove-Job
│
│  ── Windows Update (serial) ──
│  Import-Module PSWindowsUpdate
│  Get-WindowsUpdate
│  Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose
│  Get-WURebootStatus
│
└─ stop_powershell: close the elevated session

parallel (no elevation needed):
  Task B: npm update -g
  Task C: npx skills update -g -y
```

**Key points:**
- ONE `sudo pwsh` session = ONE UAC prompt for both winget and Windows Update
- winget packages run in parallel via `Start-Job` inside the session
- Windows Update runs serially after winget completes (both need the same elevated session)
- npm and skills updates run in parallel OUTSIDE the elevated session (they don't need elevation)
- The agent sends commands step-by-step via `write_powershell`, observing output at each step
- Use `read_powershell` with generous delays (60+ seconds) for Windows Update progress

**Display the plan before executing**, e.g. (GitHub Copilot CLI):
```
Plan: 4 parallel update tasks (one UAC prompt via sudo caching)
  Task A: winget upgrade — 5 packages (parallel sudo calls)
  Task B: npm update -g
  Task C: npx skills update -g -y
  Task E: Windows Update — scan → install → monitor
```

Or (Claude Code):
```
Plan: 3 parallel tracks (one UAC prompt via shared elevated session)
  Elevated session: winget (5 packages via Jobs) + Windows Update (serial)
  Task B: npm update -g (parallel, no elevation)
  Task C: npx skills update -g -y (parallel, no elevation)
```

---

### Phase 3: Execute (all tasks in parallel)

**Launch ALL applicable tasks simultaneously. NEVER run them sequentially.**

**GitHub Copilot CLI execution:**

For Task A (winget):
1. Run `winget upgrade` to discover packages
2. Parse package IDs from the table output (the ID column)
3. For **each** package, launch a **separate** parallel tool call: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements`
4. ⚠️ Do NOT use `winget upgrade --all` — it runs serially. Each package MUST be a separate parallel call.
5. Collect all results

For Task E (Windows Update):
1. `sudo pwsh -NoProfile -Command "Import-Module PSWindowsUpdate; Get-WindowsUpdate"` — scan
2. If updates exist: `sudo pwsh -NoProfile -Command "Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose"`
3. `sudo pwsh -NoProfile -Command "Import-Module PSWindowsUpdate; Get-WURebootStatus"` — check reboot
4. All sudo calls reuse cached credential — no additional UAC prompts
5. ⚠️ Do NOT combine scan + install into one command. Run them as separate steps so the agent can observe each result.

For Tasks B, C: run the single command and capture output.

**Claude Code execution:**

1. Start shared elevated session: `powershell(command: "sudo pwsh -NoProfile", mode: "async")` — **one UAC prompt**
2. In parallel, also launch Tasks B and C (no elevation needed)
3. Inside elevated session, send commands **one at a time** via `write_powershell` (do NOT combine into one command):
   a. Run winget Jobs (parallel package upgrades) — use `Start-Job` per package, NOT `winget upgrade --all`
   b. Wait for Jobs to complete via `Wait-Job | Receive-Job`, collect results
   c. `Import-Module PSWindowsUpdate` then `Get-WindowsUpdate` — scan for updates
   d. If updates exist, `Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose` — use `read_powershell` with 60+ second delays
   e. `Get-WURebootStatus` — check if reboot needed
4. `stop_powershell` to close elevated session
5. Collect results from all tracks

**Linux execution (all agents):**

For Task D (apt):
1. Run `sudo apt update -y 2>&1` and wait for completion
2. Check exit code — if non-zero, report failure and STOP (do not run upgrade)
3. Run `sudo apt upgrade -y 2>&1` and wait for completion
4. Parse output for summary (X upgraded, Y newly installed, Z held back)

For Tasks B, C: run in parallel alongside Task D.

---

### Phase 4: Report & Recommendations

#### Summary Report

```
================================================================================
                           UPDATE ALL — SUMMARY
================================================================================
Timestamp: <time>
System:    <OS>
Agent:     <agent>

── winget upgrade ──────────────────────────────────
  [✓] Git.Git (2.52.0 → 2.53.0)
  [✓] Microsoft.VisualStudioCode (1.95 → 1.96)
  [✗] SomeApp.Failed — installer error (exit code 1)
  Succeeded: 2 / Failed: 1

── Windows Update ──────────────────────────────────
  [✓] KB5034441 — Security Update (45 MB)
  [✓] KB5034123 — .NET Runtime Update (12 MB)
  [⚠] Reboot required to complete installation
  Succeeded: 2 / Failed: 0

── npm update -g ───────────────────────────────────
  [✓] Updated 3 packages

── npx skills update -g -y ─────────────────────────
  [✓] All skills up to date

── apt update ──────────────────────────────────────
  [✓] Package index refreshed (42 packages can be upgraded)

── apt upgrade ─────────────────────────────────────
  [✓] 42 packages upgraded, 0 newly installed, 0 held back

================================================================================
Total tasks: 5 | Succeeded: 4 | Partial: 1 (winget had 1 failure)
⚠️ Reboot required for Windows Update
================================================================================
```

#### Environment-Specific Recommendations

Provide recommendations **ONLY for the detected environment**:

**Windows:**
- If winget packages failed, suggest retrying individually: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements`
- If a package failed due to "in use", suggest closing the application first
- If sudo was not in Inline mode, remind: `sudo sudo config --enable normal`
- If Windows Update requires reboot, inform: "Please restart your computer to complete the update installation. You can do this when convenient."
- If Windows Update failed to install some updates, suggest: "Try running Windows Update again after a reboot, or check Windows Update settings in Settings → Windows Update"
- If PSWindowsUpdate module installation failed, suggest: "Run PowerShell as Administrator and try: `Install-Module -Name PSWindowsUpdate -Force`"
- Never suggest `chmod`, `apt`, or other Linux/macOS commands

**Linux:**
- If `apt update` failed, suggest checking network connectivity and sources list: `cat /etc/apt/sources.list`
- If `apt upgrade` failed, suggest `sudo apt --fix-broken install`
- If packages were held back, inform the user and suggest `sudo apt full-upgrade` if they want to force them
- If npm update failed with permission errors, suggest checking npm prefix: `npm config get prefix`
- Never suggest `winget`, `sudo config`, or other Windows commands

**macOS:**
- Note that this skill does not include Homebrew updates (yet) — user can run `brew update && brew upgrade` separately
- Never suggest `winget`, `apt`, or other Windows/Linux commands

---

## Notes

- **NEVER create script files** (`.ps1`, `.sh`, `.bat`, `.cmd`) — run all commands directly via agent tool calls
- **NEVER use `winget upgrade --all`** — always upgrade each package individually by `--id` for parallelism
- **NEVER combine Windows Update steps** (scan + install + reboot check) into a single command — run each step separately so the agent can observe and react
- The sudo requirement on Windows is specifically for winget and Windows Update — npm and skills updates typically don't need elevation
- If sudo is missing or wrong mode on Windows, try `sudo sudo config --enable normal` before giving up
- If only some tasks are applicable (e.g., no Node.js installed), run only the applicable ones
- The user may request to run only specific tasks (e.g., "just update winget") — honor that and skip others
- winget's table output format may vary by locale — the agent should parse it adaptively (look for the `Id` column header and the separator line of dashes)
- Windows Update can take a very long time — always use generous timeouts (300+ seconds) and poll for completion
- Windows Update will NEVER trigger an automatic reboot — the agent must inform the user and let them decide
- On Linux, `apt update` and `apt upgrade` are intentionally separate commands (not combined with `&&`) for better observability and error handling
- If `PSWindowsUpdate` module is not available and cannot be installed, skip Windows Update and inform the user
