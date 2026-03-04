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
5. **sudo status** (Windows only, required for winget):
   - Check if sudo exists: `Get-Command sudo -ErrorAction SilentlyContinue`
   - Check sudo mode: `sudo config`
   - **If sudo is not installed**: ⛔ STOP winget updates. Tell user to enable sudo in **Settings → System → For Developers → Enable sudo**
   - **If sudo mode is NOT `Inline`/`normal`**: ⛔ STOP winget updates. Tell user to run: `sudo sudo config --enable normal` (this requires a one-time UAC confirmation to switch to inline mode)

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

**CRITICAL: If on Windows and sudo is missing or not in Inline/normal mode, do NOT proceed with winget updates. Display a clear warning and instructions. Other tasks (npm, skills) can still proceed.**

---

### Phase 2: Plan (generate environment-specific parallel execution plan)

Based on Phase 1 results, build the task list and parallel strategy.

#### Task Definitions

**Task A: winget upgrade (Windows only, requires sudo in Inline mode)**

1. Run `winget upgrade` (no elevation) to list all upgradable packages
2. Parse the output to extract package IDs
3. If no packages to upgrade, skip
4. Upgrade all packages **in parallel** — strategy depends on agent (see below)
5. Collect results per package

⚠️ **Internal parallelism is CRITICAL**: each package upgrade is independent — run them ALL in parallel, not sequentially.

**Agent-specific sudo strategy for winget:**

Windows sudo caches credentials **per console session**. Agents that reuse the same shell session only get one UAC prompt; agents that spawn new processes per command get prompted every time.

| Agent | Shell Model | sudo Behavior | Strategy |
|-------|-------------|---------------|----------|
| **GitHub Copilot CLI** | Persistent shell session | ✅ Cached — one UAC prompt | Use parallel tool calls: each `sudo winget upgrade --id <pkg> ...` as a separate parallel call |
| **Claude Code** | New process per command | ❌ Not cached — UAC per call | Use **one elevated session + PowerShell Jobs** (see below) |
| **Other agents** | Check behavior | Test with two `sudo` calls | Pick matching strategy |

**Strategy for GitHub Copilot CLI (parallel tool calls):**

Each package as a parallel tool call — sudo credential is cached in the shared session:
```
parallel:
  sudo winget upgrade --id <pkg1> --silent --accept-package-agreements --accept-source-agreements
  sudo winget upgrade --id <pkg2> --silent --accept-package-agreements --accept-source-agreements
  sudo winget upgrade --id <pkg3> --silent --accept-package-agreements --accept-source-agreements
```

**Strategy for Claude Code (one elevated session + PowerShell Jobs):**

Open ONE `sudo pwsh` session (one UAC prompt), then use PowerShell background jobs for parallelism:
```powershell
# Inside the elevated session:
$packages = @("<pkg1>", "<pkg2>", "<pkg3>")
$jobs = $packages | ForEach-Object {
    Start-Job -ScriptBlock {
        param($id)
        winget upgrade --id $id --silent --accept-package-agreements --accept-source-agreements 2>&1
    } -ArgumentList $_
}
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

This achieves parallelism within a single elevated session — one UAC prompt, all packages upgrade concurrently.

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

**Task E: Windows Update (Windows only, requires sudo in Inline mode)**

This task uses PSWindowsUpdate to scan, install, and monitor Windows Update. It uses a **single elevated interactive PowerShell session** — one `sudo` call, then send commands step by step via `write_powershell`. This pattern works for ALL agents (no credential caching issues).

⚠️ **Do NOT use multiple separate `sudo pwsh -Command "..."` calls** — Windows sudo does NOT cache credentials across separate process invocations (see agent-specific notes in Task A), so each one triggers a new UAC prompt.

**Execution pattern: single elevated async session**

```
┌─ powershell(command: "sudo pwsh -NoProfile", mode: "async") ──── ONE UAC prompt
│
├─ write_powershell: Install/Import PSWindowsUpdate module
├─ write_powershell: Get-WindowsUpdate (scan)
├─ write_powershell: Install-WindowsUpdate (install)
├─ write_powershell: Get-WURebootStatus (check reboot)
│
└─ stop_powershell: close the elevated session
```

**Step 0: Open an elevated interactive session (triggers UAC once)**

Use `powershell` tool with `mode: "async"`:
```
command: "sudo pwsh -NoProfile"
mode: "async"
```
This starts an elevated PowerShell session. The user confirms UAC **once**. All subsequent steps use `write_powershell` on the same `shellId`.

**Step 1: Ensure PSWindowsUpdate module is available**

Use `write_powershell` with the shellId from Step 0:
```powershell
if (-not (Get-Module -ListAvailable PSWindowsUpdate)) { Install-Module -Name PSWindowsUpdate -Force }; Import-Module PSWindowsUpdate; Write-Output 'PSWindowsUpdate ready'
```

**Step 2: Scan for available updates**

```powershell
Get-WindowsUpdate
```

- Read the output. If no updates found, report "Windows is up to date" and skip to cleanup
- If updates found, display the list with KB article IDs, titles, and sizes

**Step 3: Install all updates**

```powershell
Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose
```

- `-AcceptAll`: accept all available updates without prompting
- `-AutoReboot:$false`: do NOT reboot automatically — the user should decide when to reboot
- Use `read_powershell` with generous delays (60+ seconds) to poll for progress — Windows Update can be very slow
- Capture and display output showing progress for each update

**Step 4: Check reboot status**

```powershell
Get-WURebootStatus
```

- If reboot is required, clearly inform the user: "⚠️ A restart is required to complete Windows Update installation"
- Do NOT trigger a reboot automatically

**Step 5: Cleanup — close the elevated session**

Use `stop_powershell` with the same shellId to close the elevated session.

⚠️ **Important notes:**
- This entire flow uses ONE elevated session = ONE UAC prompt
- The agent observes output at each step and can make decisions (e.g., skip install if no updates)
- Windows Update can take a long time (minutes to hours) — use generous `delay` values when reading output
- Some updates may fail if apps are in use — report failures and suggest closing apps

#### Parallel Strategy

Based on the detected **agent identity**:

| Agent | Strategy |
|-------|----------|
| **GitHub Copilot CLI** | Launch Tasks A/B/C/D/E as parallel tool calls or sub-agents (task tool). For Task A's internal parallelism, use parallel tool calls for each winget package. Task D (apt) and Task E (Windows Update) are internally serial but run in parallel with other tasks. |
| **Claude Code** | Use Agent Teams to dispatch each task as a sub-agent. Task A's sub-agent internally parallelizes per-package upgrades. Task D and E sub-agents handle their serial steps internally. |
| **Other agents** | Use whatever parallel execution mechanism is available. |

**Display the plan before executing**, e.g.:
```
Plan: 5 parallel update tasks
  Task A: winget upgrade — 5 packages (parallel per package)
  Task B: npm update -g
  Task C: npx skills update -g -y
  Task D: apt update → apt upgrade (serial steps)
  Task E: Windows Update — scan → install → monitor (serial steps)
  Strategy: 5 parallel sub-agents, Tasks A/D/E have internal serial steps
```

---

### Phase 3: Execute (all tasks in parallel)

**Launch ALL applicable tasks simultaneously. NEVER run them sequentially.**

For Task A (winget), the execution flow within the sub-agent:
1. Run `winget upgrade` to discover packages
2. Parse package IDs from the table output (the ID column)
3. For each package, launch a parallel tool call: `sudo winget upgrade --id <pkg> --silent --accept-package-agreements --accept-source-agreements`
4. Collect all results

For Tasks B, C: run the single command and capture output.

For Task D (apt), the execution flow within the sub-agent:
1. Run `sudo apt update -y 2>&1` and wait for completion
2. Check exit code — if non-zero, report failure and STOP (do not run upgrade)
3. Run `sudo apt upgrade -y 2>&1` and wait for completion
4. Parse output for summary (X upgraded, Y newly installed, Z held back)

For Task E (Windows Update), the execution flow within the sub-agent:
1. Start elevated session: `powershell(command: "sudo pwsh -NoProfile", mode: "async")` — one UAC prompt
2. `write_powershell`: install/import PSWindowsUpdate module
3. `write_powershell`: `Get-WindowsUpdate` — scan for updates
4. If updates exist, `write_powershell`: `Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Verbose`
5. Use `read_powershell` with generous delays (60+ seconds) to poll — WU can be very slow
6. `write_powershell`: `Get-WURebootStatus` — check if reboot needed
7. `stop_powershell`: close the elevated session
8. Collect and report results

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

- The sudo requirement on Windows is specifically for winget and Windows Update — npm and skills updates typically don't need elevation
- If only some tasks are applicable (e.g., no Node.js installed), run only the applicable ones
- The user may request to run only specific tasks (e.g., "just update winget") — honor that and skip others
- winget's table output format may vary by locale — the agent should parse it adaptively (look for the `Id` column header and the separator line of dashes)
- Windows Update can take a very long time — always use generous timeouts (300+ seconds) and poll for completion
- Windows Update will NEVER trigger an automatic reboot — the agent must inform the user and let them decide
- On Linux, `apt update` and `apt upgrade` are intentionally separate commands (not combined with `&&`) for better observability and error handling
- If `PSWindowsUpdate` module is not available and cannot be installed, skip Windows Update and inform the user
